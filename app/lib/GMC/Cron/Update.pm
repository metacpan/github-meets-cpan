package GMC::Cron::Update;

use strict;
use warnings;
use DateTime;
use File::Copy qw(move);
use GMC::Util qw(mongodb_config);
use JSON::Any;
use LWP::UserAgent;
use Mojo::Base -base;
use Mojo::Log;
use MongoDB;
use Pithub;
use Term::ProgressBar;

__PACKAGE__->attr( [qw(db home json log lwp mcpan pithub)] );

sub new {
    my ( $package, %args ) = @_;

    my $mongo = MongoDB::Connection->new( mongodb_config() );

    return bless {
        db     => $mongo->db,
        home   => $args{home},
        json   => JSON::Any->new,
        log    => Mojo::Log->new( path => "$args{home}/log/update.log" ),
        lwp    => LWP::UserAgent->new,
        mcpan  => 'http://api.metacpan.org/author/_search?q=profile.name:github&size=100000',
        pithub => Pithub->new( per_page => 100, auto_pagination => 1 ),
    } => $package;
}

sub run {
    my ($self) = @_;

    my $users = $self->fetch_metacpan_users;

    my $progress = Term::ProgressBar->new( { count => scalar(@$users) } );
    my $count = 0;

    foreach my $user (@$users) {
        $progress->update( ++$count );
        $self->create_or_update_user($user) or next;
        $self->update_repos($user);
    }

    my $now = sprintf '%s', DateTime->now;
    $self->db->status->remove;
    $self->db->status->insert( { last_update => $now } );

    $self->log->info('FINISHED.');

    my $src = sprintf '%s/log/update.log',        $self->home;
    my $dst = sprintf '%s/static/update.log.txt', $self->home;

    move( $src, $dst );
}

sub update_repos {
    my ( $self, $user ) = @_;

    my $repos = $self->fetch_github_repos($user);

    my $rank = $user->{github_data}{followers};

    my %languages = ();
    foreach my $repo (@$repos) {
        $repo->{_user_id} = $user->{_id};
        $languages{ $repo->{language} }++ if $repo->{language};
        $rank += $repo->{watchers};
        $rank += $repo->{forks};
    }

    my $cond   = { _id  => $user->{_id} };
    my $update = { rank => $rank };
    if (%languages) {
        $update->{languages} = \%languages;
    }

    $self->db->users->update( $cond, { '$set' => $update } );

    if (@$repos) {
        $self->db->repos->remove( { _user_id => $user->{_id} } );
        $self->db->repos->batch_insert($repos);
    }
}

sub create_or_update_user {
    my ( $self, $user ) = @_;

    $self->fetch_github_user($user) or return;
    $self->fetch_coderwall_user($user);

    my $cond = { pauseid => $user->{pauseid} };

    my $db_user = $self->db->users->find($cond);
    if ( $db_user->count ) {
        $self->db->users->update( $cond => { '$set' => $user } );
        $user->{_id} = $db_user->next->{_id};
        $self->log->info( sprintf '%-9s Updating user', $user->{pauseid} );
    }
    else {
        my $id = $self->db->users->insert($user);
        $user->{_id} = $id;
        $self->log->info( sprintf '%-9s Adding new user', $user->{pauseid} );
    }

    return 1;
}

sub fetch_github_user {
    my ( $self, $user ) = @_;

    my $github_user = $user->{github_user};
    my $result = $self->pithub->users->get( user => $github_user );

    unless ( $result->success ) {
        $self->log->error( sprintf '%-9s Could not fetch user %s from Github (RL:%d)', $user->{pauseid}, $github_user, $result->ratelimit_remaining );
        return;
    }

    $user->{github_data} = $result->content;
    $self->log->info( sprintf '%-9s Successfully fetched user %s from Github (RL:%d)', $user->{pauseid}, $github_user, $result->ratelimit_remaining );
    return 1;
}

sub fetch_github_repos {
    my ( $self, $user ) = @_;

    my $github_user = $user->{github_user};
    my $result = $self->pithub->repos->list( user => $github_user );

    unless ( $result->success ) {
        $self->log->error( sprintf '%-9s Could not fetch repos of user %s from Github (RL:%d)', $user->{pauseid}, $github_user, $result->ratelimit_remaining );
        return;
    }

    my @repos = ();
    while ( my $row = $result->next ) {
        push @repos, $row;
    }
    $self->log->info( sprintf '%-9s Successfully fetched repos of user %s from Github (RL:%d)', $user->{pauseid}, $github_user, $result->ratelimit_remaining );

    return \@repos;
}

sub fetch_coderwall_user {
    my ( $self, $user ) = @_;

    my $url = sprintf 'http://coderwall.com/%s.json', $user->{github_user};
    my $response = $self->lwp->get($url);

    unless ( $response->is_success ) {
        $self->log->warn( sprintf '%-9s Fetching data from %s failed: %s', $user->{pauseid}, $url, $response->status_line );
        return;
    }

    my $data = eval { $self->json->decode( $response->content ) };
    if ($@) {
        $self->log->warn( sprintf '%-9s Error decoding data from %s: %s', $user->{pauseid}, $url, $@ );
        return;
    }

    $self->log->info( sprintf '%-9s Successfully fetched coderwall data from %s', $user->{pauseid}, $url );

    $user->{coderwall_data} = $data;
}

sub fetch_metacpan_users {
    my ($self) = @_;

    $self->log->info('Fetching users from MetaCPAN ...');

    my $response = $self->lwp->get( $self->mcpan );
    die $response->status_line unless $response->is_success;

    my $data = $self->json->decode( $response->content );

    my @result = ();
    foreach my $row ( @{ $data->{hits}{hits} } ) {
        $row = $row->{_source};

        my $github_user;
        foreach my $profile ( @{ $row->{profile} || [] } ) {
            if ( $profile->{name} eq 'github' ) {
                $github_user = $profile->{id};
                last;
            }
        }

        push @result,
          {
            github_user  => $github_user,
            gravatar_url => $row->{gravatar_url},
            name         => $row->{name},
            pauseid      => $row->{pauseid},
            metacpan_url => 'https://metacpan.org/author/' . $row->{pauseid},
          };
    }

    $self->log->info('DONE');

    return \@result;
}

1;
