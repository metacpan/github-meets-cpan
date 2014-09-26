#!/usr/bin/env perl

use strict;
use warnings;

use Mojolicious::Commands;
use Plack::Builder;

use lib 'lib';

$ENV{MOJO_MODE} = 'production';
my $app = require 'script/app.pl';

builder {
    enable_if { $ENV{PLACK_ENV} eq 'development' } 'DebugLogging';
    $app;
};
