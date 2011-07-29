package GMC::Controller::Root;

use Mojo::Base 'Mojolicious::Controller';

sub about {
    my ($self) = @_;
    my $count = $self->db->users->find->sort( { rank => -1 } )->count;
    $self->stash(
        count     => $count,
        db_status => $self->db->status->find->next,
    );
}

sub faq {
    my ($self) = @_;
    $self->stash( db_status => $self->db->status->find->next );
}

sub list {
    my ($self) = @_;
    my $users = $self->db->users->find->sort( { rank => -1 } );
    $self->stash(
        db_status => $self->db->status->find->next,
        users     => $users,
    );
}

sub view {
    my ($self) = @_;
    my $pauseid = $self->match->captures->{user};
    my $user = $self->db->users->find( { pauseid => $pauseid } )->next;
    unless ($user) {
        $self->render_not_found;
        return;
    }
    my $repos = $self->db->repos->find( { _user_id => $user->{_id} } )->sort( { watchers => -1 } );
    $self->stash(
        db_status => $self->db->status->find->next,
        repos     => $repos,
        user      => $user,
    );
}

1;
