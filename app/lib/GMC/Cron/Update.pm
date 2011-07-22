package GMC::Cron::Update;

use strict;
use warnings;
use GMC::Util qw(mongodb_config);
use JSON::Any;
use LWP::UserAgent;
use Mojo::Base -base;
use Mojo::Log;
use MongoDB;
use Pithub;

__PACKAGE__->attr( [qw(db json log lwp mcpan pithub)] );

sub new {
    my ( $package, %args ) = @_;

    my $mongo = MongoDB::Connection->new( mongodb_config() );

    return bless {
        db     => $mongo->db,
        json   => JSON::Any->new,
        log    => Mojo::Log->new,
        lwp    => LWP::UserAgent->new,
        pithub => Pithub->new( per_page => 100, auto_pagination => 1 ),
        mcpan  => 'http://api.metacpan.org/author/_search?q=profile.name:github&size=100000',
    } => $package;
}

sub run {
    my ($self) = @_;

    my $users = $self->fetch_metacpan_users;

    foreach my $user (@$users) {
        $self->create_or_update_user($user) or next;
        $self->update_repos($user);
    }

    $self->log->info("FINISHED.");
}

sub update_repos {
    my ( $self, $user ) = @_;

    my $repos = $self->fetch_github_repos( $user->{github_user} );

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

    $user->{github_data} = $self->fetch_github_user( $user->{github_user} );

    return unless $user->{github_data};

    my $cond = { pauseid => $user->{pauseid} };

    my $db_user = $self->db->users->find($cond);
    if ( $db_user->count ) {
        $self->db->users->update( $cond => { '$set' => $user } );
        $user->{_id} = $db_user->next->{_id};
        $self->log->info("Updating user $user->{pauseid}");
    }
    else {
        my $id = $self->db->users->insert($user);
        $user->{_id} = $id;
        $self->log->info("Adding new user $user->{pauseid}");
    }

    return 1;
}

sub fetch_github_user {
    my ( $self, $github_user ) = @_;

    my $result = $self->pithub->users->get( user => $github_user );
    my $github_data;

    if ( $result->success ) {
        $github_data = $result->content;
        $self->log->info("Successfully fetched user ${github_user} from Github");
    }
    else {
        $self->log->warn("Could not fetch user ${github_user} from Github");
    }

    return $github_data;
}

sub fetch_github_repos {
    my ( $self, $github_user ) = @_;

    my $result = $self->pithub->repos->list( user => $github_user );
    my $repos = [];

    if ( $result->success ) {
        while ( my $row = $result->next ) {
            push @$repos, $row;
        }
        $self->log->info("Successfully fetched repos of user ${github_user} from Github");
    }
    else {
        $self->log->warn("Could not fetch repos of user ${github_user} from Github");
    }

    return $repos;
}

sub fetch_metacpan_users {
    my ($self) = @_;

    $self->log->info("Fetching users from MetaCPAN ...");

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
            metacpan_url => "https://metacpan.org/author/" . $row->{pauseid},
          };
    }

    $self->log->info("DONE");

    return \@result;
}

1;
