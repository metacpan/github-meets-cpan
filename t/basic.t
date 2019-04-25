#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo ();

my $t = Test::Mojo->new('GMC');
$t->get_ok('/about')->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_like(qr/GitHub Meets CPAN/i);

done_testing();
