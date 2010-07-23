#!/usr/bin/env perl

##################################################

use strict;
use Test::More tests => 4;
use Data::Dumper;

use_ok('Webinject');

my $webinject = Webinject->new();
isa_ok($webinject, "Webinject", 'Object is a Webinject');

##################################################
# test some internal functions
my $teststring = '<äöüß>';
my $verify     = '%3C%C3%A4%C3%B6%C3%BC%C3%9F%3E';
is($webinject->_url_escape($teststring), $verify, '_url_escape() in scalar context');

my @test   = $webinject->_url_escape(qw'< ä ö ü ß >');
my @verify = qw'%3C %C3%A4 %C3%B6 %C3%BC %C3%9F %3E';
is_deeply(\@test, \@verify, '_url_escape() in list context');