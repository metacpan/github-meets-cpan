# Fix linter complaints via strict and warnings
use strict;
use warnings;

requires 'Cpanel::JSON::XS';
requires 'LWP::UserAgent';
requires 'LWP::Protocol::https';
requires 'Mojolicious', '<= 8.14';
requires 'Mojolicious::Plugin::Mongodb';
requires 'Path::Tiny';
requires 'Pithub', '0.01030';
