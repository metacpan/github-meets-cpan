package GMC::Cron::Update;

use strict;
use warnings;

use DateTime ();
use File::Copy qw(move);
use GMC::Util qw(github_config mongodb_config);
use Cpanel::JSON::XS qw( decode_json );
use LWP::UserAgent ();
use Mojo::Base -base;
use Mojo::Log;
use MongoDB ();
use Pithub 0.01030; # encoding fix

__PACKAGE__->attr( [qw(db home log lwp mcpan pithub)] );

sub new {
    my ( $package, %args ) = @_;

    my $mongo  = MongoDB::Connection->new( mongodb_config() );
    my $github = github_config();
    my $gh_ua  = LWP::UserAgent->new;
    $gh_ua->default_header( 'Accept-Encoding' => 'identity' );

    return bless {
        db   => $mongo->get_database('db'),
        home => $args{home},
        log  => Mojo::Log->new( path => "$args{home}/log/update.log" ),
        lwp  => LWP::UserAgent->new,
        mcpan =>
            'https://fastapi.metacpan.org/v1/author/_search?q=profile.name:github&size=1000',
        pithub => Pithub->new(
            auto_pagination => 1,
            per_page        => 100,
            $github->{TOKEN} ? ( token => $github->{TOKEN} ) : (),
            ua              => $gh_ua,
        ),
    } => $package;
}

sub run {
    my ($self) = @_;

    my $users = $self->fetch_metacpan_users;

    foreach my $user (@$users) {
        $self->create_or_update_user($user) or next;
        $self->update_repos($user);
    }

    my $now = sprintf '%s', DateTime->now;
    $self->db->get_collection('status')->remove;
    $self->db->get_collection('status')->insert( { last_update => $now } );

    $self->log->info('FINISHED.');

    my $src = sprintf '%s/log/update.log',        $self->home;
    my $dst = sprintf '%s/static/update.log.txt', $self->home;

    move( $src, $dst );
}

sub update_repos {
    my ( $self, $user ) = @_;

    my $repos = $self->fetch_github_repos($user);

    my $rank = $user->{github_data}{followers};

    my %languages;
    foreach my $repo (@$repos) {
        $repo->{_user_id} = $user->{_id};
        next unless $repo->{language};
        $languages{ $repo->{language} }++;

        # Count only Perl projects
        next unless $repo->{language} eq 'Perl';
        $rank++;
        $rank += $repo->{watchers};
        $rank += $repo->{forks};
    }

    my $cond   = { _id  => $user->{_id} };
    my $update = { rank => $rank };
    if (%languages) {
        $update->{languages} = \%languages;
    }

    $self->db->get_collection('users')
        ->update( $cond, { '$set' => $update } );

    if (@$repos) {
        $self->db->get_collection('repos')
            ->remove( { _user_id => $user->{_id} } );
        $self->db->get_collection('repos')->batch_insert($repos);
    }
}

sub create_or_update_user {
    my ( $self, $user ) = @_;

    $self->fetch_github_user($user) or return;
    $self->fetch_coderwall_user($user);

    my $cond = { pauseid => $user->{pauseid} };

    my $db_user = $self->db->get_collection('users')->find($cond);
    if ( $db_user->count ) {
        $self->db->get_collection('users')
            ->update( $cond => { '$set' => $user } );
        $user->{_id} = $db_user->next->{_id};
        $self->log->info( sprintf '%-9s Updating user', $user->{pauseid} );
    }
    else {
        $user->{created} = time;
        my $id = $self->db->get_collection('users')->insert($user);
        $user->{_id} = $id;
        $self->log->info( sprintf '%-9s Adding new user', $user->{pauseid} );
    }

    return 1;
}

sub fetch_github_user {
    my ( $self, $user ) = @_;

    my $github_user = $user->{github_user};
    unless ($github_user) {
        $self->log->error( sprintf '%-9s Invalid GitHub user: %s',
            $user->{pauseid}, $github_user );
        return;
    }

    my $result = $self->pithub->users->get( user => $github_user );

    unless ( $result->success ) {
        $self->log->error(
            sprintf '%-9s Could not fetch user %s from GitHub (RL:%d)',
            $user->{pauseid}, $github_user, $result->ratelimit_remaining );
        return;
    }

    $user->{github_data} = $result->content;
    $self->log->info(
        sprintf '%-9s Successfully fetched user %s from GitHub (RL:%d)',
        $user->{pauseid}, $github_user, $result->ratelimit_remaining );
    return 1;
}

sub fetch_github_repos {
    my ( $self, $user ) = @_;

    my $github_user = $user->{github_user};
    my $result = $self->pithub->repos->list( user => $github_user );

    unless ( $result->success ) {
        $self->log->error(
            sprintf
                '%-9s Could not fetch repos of user %s from GitHub (RL:%d)',
            $user->{pauseid}, $github_user, $result->ratelimit_remaining );
        return;
    }

    my @repos = ();
    while ( my $row = $result->next ) {
        push @repos, $row;
    }
    $self->log->info(
        sprintf
            '%-9s Successfully fetched repos of user %s from GitHub (RL:%d)',
        $user->{pauseid}, $github_user, $result->ratelimit_remaining );

    return \@repos;
}

sub fetch_coderwall_user {
    my ( $self, $user ) = @_;

    my $url = sprintf 'http://coderwall.com/%s.json', $user->{coderwall_user};
    my $response = $self->lwp->get($url);

    unless ( $response->is_success ) {
        $self->log->warn( sprintf '%-9s Fetching data from %s failed: %s',
            $user->{pauseid}, $url, $response->status_line );
        return;
    }

    my $data = eval { decode_json( $response->content ) };
    if ($@) {
        $self->log->warn( sprintf '%-9s Error decoding data from %s: %s',
            $user->{pauseid}, $url, $@ );
        return;
    }

    $self->log->info(
        sprintf '%-9s Successfully fetched coderwall data from %s',
        $user->{pauseid}, $url );

    $user->{coderwall_data} = $data;
}

sub fetch_metacpan_users {
    my ($self) = @_;

    $self->log->info('Fetching users from MetaCPAN ...');

    my $response = $self->lwp->get( $self->mcpan );
    die $response->status_line unless $response->is_success;

    my $data = decode_json( $response->content );

    my @result = ();
    foreach my $row ( @{ $data->{hits}{hits} } ) {
        $row = $row->{_source};

        my $coderwall_user;
        my $github_user;
        foreach my $profile ( @{ $row->{profile} || [] } ) {
            $github_user = $profile->{id} if $profile->{name} eq 'github';
            $coderwall_user = $profile->{id}
                if $profile->{name} eq 'coderwall';
        }

        push @result,
            {
            github_user    => $github_user,
            coderwall_user => $coderwall_user || $github_user,
            gravatar_url   => $row->{gravatar_url},
            name           => $row->{name},
            pauseid        => $row->{pauseid},
            metacpan_url => 'https://metacpan.org/author/' . $row->{pauseid},
            };
    }

    $self->log->info('DONE');

    return \@result;
}

1;
