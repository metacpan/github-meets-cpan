package GMC;

use Mojo::Base 'Mojolicious';
use GMC::Util qw(mongodb_config);

# Required by Mojolicious::Plugin::Mongodb
use MongoDB::Connection (); ## no perlimports

# This method will run once at server start
sub startup {
    my $self = shift;

    $self->static->paths( [ $self->home->rel_file('static') ] );

    $self->plugin(
        mongodb => {
            mongodb_config(),
            database => 'db',
            helper   => 'db',
        }
    );

    # setup routes
    my $r = $self->routes;
    $r->namespaces( ['GMC::Controller'] );
    $r->route('/')->to('root#list');
    $r->route('/about')->to('root#about');
    $r->route('/faq')->to('root#faq');
    $r->route('/recent')->to('root#recent');
    $r->route('/user/:user')->to('root#view');
}

1;
