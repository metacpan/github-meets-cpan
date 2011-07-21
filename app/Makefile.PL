#!/usr/bin/env perl
use ExtUtils::MakeMaker;

WriteMakefile(
    PREREQ_PM => {
        'LWP::UserAgent'               => '6.02',
        'Mojolicious'                  => '1.64',
        'Mojolicious::Plugin::Mongodb' => '1.07',
        'MongoDB'                      => '0.43',
        'Pithub'                       => '0.01005',
    }
);
