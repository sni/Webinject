#!/usr/bin/env perl

##################################################

use strict;
use Test::More tests => 2;
use Data::Dumper;

use_ok('Webinject::Gui');

my $webinjectgui = Webinject::Gui->new('mainloop' => 0, 'stderrwindow' => 0);
isa_ok($webinjectgui, "Webinject::Gui", 'Object is a Webinject::Gui');
