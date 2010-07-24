#!/usr/bin/env perl

##################################################

use strict;
use Test::More tests => 2;
use Data::Dumper;

use_ok('Webinject::Gui');

my $webinjectgui = Webinject::Gui->new('noloop' => 1, 'nostderrwindow' => 1);
isa_ok($webinjectgui, "Webinject::Gui", 'Object is a Webinject::Gui');
