#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use GMC::Cron::Update;
GMC::Cron::Update->new( home => "$FindBin::Bin/../" )->run;
