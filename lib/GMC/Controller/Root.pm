package GMC::Controller::Root;

use Mojo::Base 'Mojolicious::Controller';

sub about {
    my ($self) = @_;
    my $count = $self->db('db')->get_collection('users')
        ->find->sort( { rank => -1 } )->count;
    $self->stash(
        count     => $count,
        db_status => $self->db('db')->get_collection('status')->find->next,
    );
}

sub faq {
    my ($self) = @_;
    $self->stash(
        db_status => $self->db('db')->get_collection('status')->find->next );
}

sub list {
    my ($self) = @_;
    my $users = $self->db('db')->get_collection('users')
        ->find->sort( { rank => -1 } );

    $self->stash(
        db_status => $self->db('db')->get_collection('status')->find->next,
        users     => $users,
    );
}

sub recent {
    my ($self) = @_;
    my $users
        = $self->db('db')->get_collection('users')
        ->find( { created => { '$gt' => time - 86400 } } )
        ->sort( { rank => -1 } );

    $self->stash(
        db_status => $self->db('db')->get_collection('status')->find->next,
        users     => $users,
    );
}

sub view {
    my ($self) = @_;

    my $pauseid = $self->match->stack->[0]->{user};
    my $user    = $self->db('db')->get_collection('users')
        ->find( { pauseid => $pauseid } )->next;
    unless ($user) {
        $self->render_not_found;
        return;
    }
    my $repos = $self->db('db')->get_collection('repos')
        ->find( { _user_id => $user->{_id} } )->sort( { watchers => -1 } );
    $self->stash(
        db_status => $self->db('db')->get_collection('status')->find->next,
        repos     => $repos,
        user      => $user,
        position  => 0,
    );
}

1;
