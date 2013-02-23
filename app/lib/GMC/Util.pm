package GMC::Util;

use Mojo::Base 'Exporter';
use JSON::XS;
use File::Slurp qw(read_file);

our @EXPORT_OK = qw/environment github_config mongodb_config/;
my $ENVIRONMENT;

sub mongodb_config {
    my ($self) = @_;

    my %config = (
        host => environment()->{DOTCLOUD_DATA_MONGODB_HOST},
        port => environment()->{DOTCLOUD_DATA_MONGODB_PORT},
    );

    my ( $user, $pass ) = @{ environment() }{qw(DOTCLOUD_DATA_MONGODB_LOGIN DOTCLOUD_DATA_MONGODB_PASSWORD)};

    $config{password} = $pass if defined $pass;
    $config{username} = $user if defined $user;

    return %config;
}

sub github_config {
    my ($self) = @_;

    my $env = environment();

    return {
        CLIENT_ID     => $env->{GITHUB_CLIENT_ID},
        CLIENT_SECRET => $env->{GITHUB_CLIENT_SECRET},
    };
}

sub environment {
    my ($self) = @_;

    return $ENVIRONMENT if $ENVIRONMENT;

    my $file = "$ENV{HOME}/environment.json";

    if ( -f $file ) {
        my $env = read_file($file);
        $ENVIRONMENT = JSON::XS->new->decode($env);
        return $ENVIRONMENT;
    }

    $ENVIRONMENT = {
        DOTCLOUD_DATA_MONGODB_HOST => 'localhost',
        DOTCLOUD_DATA_MONGODB_PORT => 27017,
    };

    return $ENVIRONMENT;
}

1;
