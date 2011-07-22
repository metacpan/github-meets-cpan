#!/usr/bin/env perl
use ExtUtils::MakeMaker;

WriteMakefile(
    PREREQ_PM => {
        'App::Cronjob'                 => '1.102311',
        'DateTime'                     => '0.70',
        'LWP::UserAgent'               => '6.02',
        'Mojolicious'                  => '1.64',
        'Mojolicious::Plugin::Mongodb' => '1.07',
        'MongoDB'                      => '0.43',
        'Pithub'                       => '0.01005',
        'Term::ProgressBar'            => '2.09',
    }
);
