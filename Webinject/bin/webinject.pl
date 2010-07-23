#!/usr/bin/env perl

#    Copyright 2004-2006 Corey Goldberg (corey@goldb.org)
#
#    This file is part of WebInject.
#
#    WebInject is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    WebInject is distributed in the hope that it will be useful,
#    but without any warranty; without even the implied warranty of
#    merchantability or fitness for a particular purpose.  See the
#    GNU General Public License for more details.


use warnings;
use strict;
use Webinject;

my $webinject = Webinject->new();

if (($0 =~ /webinject.pl/) or ($0 =~ /webinject.exe/)) {  #set flag so we know if it is running standalone or from webinjectgui
    $webinject->engine();
}
else {
    $webinject->{'gui'} = Webinject::Gui->new();
    $webinject->engine();
    $webinject->whackoldfiles(); # delete files leftover from previous run (do this here so they are whacked on startup when running from gui)
}
