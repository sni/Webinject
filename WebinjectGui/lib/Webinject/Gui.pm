package Webinject::Gui;

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

use 5.006;
use strict;
use warnings;
use Tk;
use Tk::Stderr;
use Tk::ROText;
use Tk::Compound;
use Tk::ProgressBar::Mac;
use Tk::NoteBook;
use Tk::PNG;
use base qw/Webinject/;

our $VERSION = '1.56';

=head1 NAME

Webinject::Gui - Gui part of Webinject

=head1 SYNOPSIS

    use Webinject::Gui;
    my $webinjectgui = Webinject::Gui->new();

=head1 DESCRIPTION

WebInject is a free tool for automated testing of web applications and web
services. It can be used to test individual system components that have HTTP
interfaces (JSP, ASP, CGI, PHP, AJAX, Servlets, HTML Forms, XML/SOAP Web
Services, REST, etc), and can be used as a test harness to create a suite of
[HTTP level] automated functional, acceptance, and regression tests. A test
harness allows you to run many test cases and collect/report your results.
WebInject offers real-time results display and may also be used for monitoring
system response times.

=head1 CONSTRUCTOR

=head2 new ( [ARGS] )

Creates an C<Webinject::Gui> object.

=cut

sub new {
    my $class = shift;
    my (%options) = @_;
    $| = 1;    # don't buffer output to STDOUT

    my $self = {
        'mainloop'        => 1,
        'stderrwindow'    => 1,
    };

    for my $opt_key ( keys %options ) {
        if ( exists $self->{$opt_key} ) {
            $self->{$opt_key} = $options{$opt_key};
        }
        else {
            croak("unknown option: $opt_key");
        }
    }

    bless $self, $class;

    # save command line for later restarts
    $self->{'command_line'} = $0." ".join(" ", @ARGV);
    $self->{'gui'}          = 1;

    $self->_set_defaults();
    $self->_whackoldfiles();
    $self->_init_main_window();

    return $self;
}

########################################

=head1 METHODS

=cut

sub _init_main_window {
    my $self = shift;

    $self->{'mainwindow'} = MainWindow->new(
        -title => 'WebInject - HTTP Test Tool    (version '. $Webinject::Gui::VERSION . ')',
        -bg        => '#666699',
        -takefocus => '1',         #start on top
    );

    $self->{'mainwindow'}->geometry("750x650+0+0");                     # size and screen placement
    if($self->{'stderrwindow'}) {
        $self->{'mainwindow'}->InitStderr;                              # redirect all STDERR to a window
    }
    $self->{'mainwindow'}->raise;                                       # put application in front at startup
    $self->{'mainwindow'}->bind( '<F5>' => sub { $self->engine(); } );  # F5 key makes it run

    if ( -e "icon.gif" ) {                                              # if icon graphic exists, use it
        $self->{'mainwindow'}->update();
        my $icon = $self->{'mainwindow'}->Photo( -file => 'icon.gif' );
        $self->{'mainwindow'}->iconimage($icon);
    }

    if ( -e "logo.gif" ) {                                              # if logo graphic exists, use it
        $self->{'mainwindow'}->Photo( 'logogif', -file => "logo.gif" );
        $self->{'mainwindow'}->Label(
            -image => 'logogif',
            -bg    => '#666699',
        )->place(qw/-x 305 -y 12/);
        $self->{'mainwindow'}->update();
    }

    my $menubar = $self->{'mainwindow'}->Frame(qw/-relief flat -borderwidth 2/);
    $menubar->place(qw/-x 0 -y 0/);
    $menubar->configure( -background => '#666699' );                    # menu outline

    my $filemenu = $menubar->Menubutton(
        -text             => 'File',
        -foreground       => 'white',
        -background       => '#666699',
        -activebackground => '#666699',
        -activeforeground => 'black',
        -tearoff          => '0',
    )->pack(qw/-side left/);

    $filemenu->command(
        -label            => 'Restart',
        -background       => '#666699',
        -activebackground => '#EFEFEF',
        -foreground       => 'white',
        -activeforeground => 'black',
        -command          => sub { $self->_gui_restart(); },
    );

    $filemenu->command(
        -label            => 'Exit',
        -background       => '#666699',
        -activebackground => '#EFEFEF',
        -foreground       => 'white',
        -activeforeground => 'black',
        -command          => sub { exit; }
    );

    my $viewmenu = $menubar->Menubutton(
        -text             => 'View',
        -foreground       => 'white',
        -background       => '#666699',
        -activebackground => '#666699',
        -activeforeground => 'black',
        -tearoff          => '0',
    )->pack(qw/-side left/);

    $viewmenu->command(
        -label            => 'config.xml',
        -background       => '#666699',
        -activebackground => '#EFEFEF',
        -foreground       => 'white',
        -activeforeground => 'black',
        -command          => sub { $self->_viewconfig(); },
    );

    my $aboutmenu = $menubar->Menubutton(
        -text             => 'About',
        -foreground       => 'white',
        -background       => '#666699',
        -activebackground => '#666699',
        -activeforeground => 'black',
        -tearoff          => '0',
    )->pack(qw/-side left/);

    $aboutmenu->command(
        -label            => 'About WebInject',
        -background       => '#666699',
        -activebackground => '#EFEFEF',
        -foreground       => 'white',
        -activeforeground => 'black',
        -command          => sub { $self->_about() },
    );

    $self->{'mainwindow'}->Label(
        -text => 'Engine Status:',
        -bg   => '#666699',
        -fg   => '#FFFFFF',
    )->place(qw/-x 12 -y 100/);
    $self->{'mainwindow'}->update();

    $self->{'out_window'} = $self->{'mainwindow'}->Scrolled(
        'ROText',    # engine status window
        -scrollbars => 'e',
        -background => '#EFEFEF',
        -width      => '103',
        -height     => '7',
    )->place(qw/-x 12 -y 118/);
    $self->{'mainwindow'}->update();

    $self->{'tabs'} = $self->{'mainwindow'}->NoteBook(
        -backpagecolor      => '#666699',
        -background         => '#EFEFEF',    # color for active tab
        -foreground         => 'black',      # text color for active tab
        -inactivebackground => '#BFBFBF',    # color for inactive tabs
    )->place(qw/-x 12 -y 240/);              # outer notebook object

    my $status_tab = $self->{'tabs'}->add( 'statustab', -label => 'Status' );
    $self->{'mainwindow'}->update();

    my $statustab_canvas = $status_tab->Canvas(
        -width          => '719',
        -height         => '365',
        -highlightcolor => '#CCCCCC',
        -background     => '#EFEFEF',
    )->pack();
    $self->{'mainwindow'}->update();        # canvas to fill tab (to place widgets into)

    my $statustab_buttoncanvas = $statustab_canvas->Canvas(
        -width      => '700',
        -height     => '24',
        -background => '#666699',
    )->place(qw/-x 10 -y 334/);
    $self->{'mainwindow'}->update();        # canvas to place buttons into

    $self->{'minimalcheckbx'} = 'minimal_off';    # give it a default value
    $statustab_buttoncanvas->Label(
        -text => 'Minimal Output',
        -bg   => '#666699',
        -fg   => 'white',
    )->place(qw/-x 49 -y 4/);
    $self->{'mainwindow'}->update();
    $statustab_buttoncanvas->Checkbutton(
        -text       => '',                  # using a text widget instead
        -onvalue    => 'minimal_on',
        -offvalue   => 'minimal_off',
        -variable   => \$self->{'minimalcheckbx'},
        -background => '#666699',
        -activebackground    => '#666699',
        -highlightbackground => '#666699',
    )->place(qw/-x 20 -y 2/);
    $self->{'mainwindow'}->update();

    $self->{'timercheckbx'} = 'timer_off';      # give it a default value
    $statustab_buttoncanvas->Label(
        -text => 'Response Timer Output',
        -bg   => '#666699',
        -fg   => 'white',
    )->place(qw/-x 199 -y 4/);
    $self->{'mainwindow'}->update();
    $statustab_buttoncanvas->Checkbutton(
        -text       => '',                      # using a text widget instead
        -onvalue    => 'timer_on',
        -offvalue   => 'timer_off',
        -variable   => \$self->{'timercheckbx'},
        -background => '#666699',
        -activebackground    => '#666699',
        -highlightbackground => '#666699',
    )->place(qw/-x 170 -y 2/);
    $self->{'mainwindow'}->update();

    $self->{'status_window'} = $statustab_canvas->Scrolled(
        'ROText',                               # test case status monitor window
        -scrollbars => 'e',
        -background => '#EFEFEF',
        -width      => '102',
        -height     => '23',
    )->place(qw/-x 0 -y 0/);
    $self->{'mainwindow'}->update();
    $self->{'status_window'}->tagConfigure( 'red', -foreground => '#FF3333' )
      ;              #define tag for font color
    $self->{'status_window'}->tagConfigure( 'green', -foreground => '#009900' )
      ;              #define tag for font color

    $self->{'monitorenabledchkbx'} = 'monitor_on';    #give it a default value
    $self->{'mainwindow'}->Label(
        -text => 'Disable Monitor',
        -bg   => '#666699',
        -fg   => 'white',
    )->place(qw/-x 189 -y 242/);
    $self->{'mainwindow'}->update();
    $self->{'monitor_enabledchkbx'} = $self->{'mainwindow'}->Checkbutton(
        -text     => '',              #using a text widget instead
        -onvalue  => 'monitor_off',
        -offvalue => 'monitor_on',
        -variable            => \$self->{'monitorenabledchkbx'},
        -background          => '#666699',
        -activebackground    => '#666699',
        -highlightbackground => '#666699',
        -command             => sub { $self->_monitor_enable_disable(); },
    )->place(qw/-x 160 -y 240/);
    $self->{'mainwindow'}->update();
    $self->_monitor_enable_disable();    #call sub to enable and create monitor

    $self->{'stop_button'} = $self->{'mainwindow'}->Button->Compound;
    $self->{'stop_button'}->Text( -text => "Stop" );
    $self->{'stop_button'} = $self->{'mainwindow'}->Button(
        -width            => '50',
        -height           => '13',
        -background       => '#EFEFEF',
        -activebackground => '#666699',
        -foreground       => '#000000',
        -activeforeground => '#FFFFFF',
        -borderwidth      => '3',
        -image            => $self->{'stop_button'},
        -command          => sub { $self->{'stop'} = 'yes'; },
    )->place;
    $self->{'mainwindow'}->update();  #create this button but don't place it yet

    $self->{'rtc_button'} = $self->{'mainwindow'}->Button->Compound;
    $self->{'rtc_button'}->Text( -text => "Run" );
    $self->{'rtc_button'} = $self->{'mainwindow'}->Button(
        -width            => '50',
        -height           => '13',
        -background       => '#EFEFEF',
        -activebackground => '#666699',
        -foreground       => '#000000',
        -activeforeground => '#FFFFFF',
        -borderwidth      => '3',
        -image            => $self->{'rtc_button'},
        -command          => sub { $self->engine(); },
    )->place(qw/-x 110 -y 65/);
    $self->{'mainwindow'}->update();
    $self->{'rtc_button'}->focus();

    $self->{'progressbar'} = $self->{'mainwindow'}->ProgressBar(
        -width => '420',
        -bg    => '#666699'
    )->place(qw/-x 176 -y 65/);
    $self->{'mainwindow'}->update();

    $self->{'status_ind'} = $self->{'mainwindow'}->Canvas(
        -width      => '28',        #engine status indicator
        -height     => '9',
        -background => '#666699',
    )->place(qw/-x 621 -y 69/);
    $self->{'mainwindow'}->update();

    if($self->{'mainloop'}) {
        MainLoop;
    }
    return;
}

########################################
sub _gui_initial {                   #this runs when engine is first loaded
    my $self = shift;

    $self->{'out_window'}->delete( '0.0', 'end' );    # clear window before starting
    $self->{'status_window'}->delete( '0.0', 'end' ); # clear window before starting

    # change status color amber while running
    $self->{'status_ind'}->configure( -background => '#FF9900' );

    $self->{'rtc_button'}->placeForget;                 # remove the run button
    $self->{'stop_button'}->place(qw/-x 110 -y 65/);    # place the stop button

    # disable button while running
    $self->{'monitor_enabledchkbx'}->configure( -state => 'disabled' );

    $self->{'out_window'}->insert( "end", "Starting Webinject Engine... \n\n" );
    $self->{'out_window'}->see("end");

    return;
}

########################################
sub _gui_restart {    #kill the entire app and restart it
    my $self = shift;
    return exec $self->{'command_line'};
}

########################################
sub _gui_processing_msg {
    my $self = shift;
    my $file = shift;
    $self->{'out_window'}->insert( "end", "processing test case file:\n".$file."\n\n", 'bold' );
    $self->{'out_window'}->see("end");
    return;
}

########################################
sub _gui_statusbar {
    my $self            = shift;
    my $percentcomplete = ( $self->{'result'}->{'runcount'} / $self->{'result'}->{'casecount'} ) * 100;
    # update progressbar with current status
    $self->{'progressbar'}->set($percentcomplete);
    return;
}

########################################
sub _gui_tc_descript {
    my $self = shift;
    my $case = shift;
    unless ( $self->{'minimalcheckbx'} eq "minimal_on" ) {
        $self->{'status_window'}->insert( "end", "- " . $case->{description1} . "\n" );
        $self->{'status_window'}->see("end");
    }
    return;
}

########################################
sub _gui_status_passed {
    my $self = shift;
    $self->{'status_window'}->insert( "end", "PASSED\n", 'green' );
    $self->{'status_window'}->see("end");
    return;
}

########################################
sub _gui_status_failed {
    my $self = shift;
    if ( $1 and $2 ) {
        $self->{'status_window'}->insert( "end", "FAILED ($1$2)\n", 'red' );
        $self->{'status_window'}->see("end");
    }
    else {
        $self->{'status_window'}->insert( "end", "FAILED\n", 'red' );
        $self->{'status_window'}->see("end");
    }
    return;
}

########################################
sub _gui_timer_output {
    my $self    = shift;
    my $latency = shift;
    if ( $self->{'timercheckbx'} eq "timer_on" ) {
        $self->{'status_window'}->insert( "end", $latency." s\n" );
        $self->{'status_window'}->see("end");
    }
    return;
}

########################################
sub _gui_final {
    my $self = shift;

    $self->{'out_window'}->insert( "end", "Execution Finished... see results.html file for detailed output report");
    $self->{'out_window'}->see("end");

    $self->{'status_window'}->insert( "end", "\n\n------------------------------\nTotal Run Time: $self->{'result'}->{'totalruntime'} seconds\n");
    $self->{'status_window'}->insert( "end", "\nTest Cases Run: $self->{'result'}->{'totalruncount'}\nTest Cases Passed: $self->{'result'}->{'totalcasespassedcount'}\nTest Cases Failed: $self->{'result'}->{'totalcasesfailedcount'}\nVerifications Passed: $self->{'result'}->{'totalpassedcount'}\nVerifications Failed: $self->{'result'}->{'totalfailedcount'}\n" );
    $self->{'status_window'}->see("end");

    # change status color to reflect failure or all tests passed
    if( $self->{'result'}->{'totalfailedcount'} > 0 ) {
        # red
        $self->{'status_ind'}->configure( -background => '#FF3333' );
    }
    else {
        # green
        $self->{'status_ind'}->configure( -background => '#009900' );
    }

    # re-enable button after finish
    $self->{'monitor_enabledchkbx'}->configure( -state => 'normal' );

    return;
}

########################################
sub _gui_updatemontab {
    my $self = shift;

    # don't try to update if monitor is disabled in gui
    if ( $self->{'monitorenabledchkbx'} ne 'monitor_off' ) {
        if (
            ( -e $self->{'config'}->{'output_dir'}."plot.png" )
            and (  ( $self->{'config'}->{'graphtype'} ne 'nograph' )
                or ( $self->{'switches'}->{'plotclear'} ne 'yes' ) )
          )
        {
            # if plot graphic exists, put it in canvas
            $self->{'montab_plotcanvas'}->Photo( 'plotgraph', -file => $self->{'config'}->{'output_dir'}."plot.png" );
            $self->{'montab_plotcanvas'}->Label( -image => 'plotgraph' )->place(qw/-x 7 -y 0/);
        }
    }
    return;
}

########################################
sub _gui_updatemonstats {    #update timers and counts in monitor tab
    my $self = shift;

    #don't try to update if monitor is disabled in gui
    if( $self->{'monitorenabledchkbx'} ne 'monitor_off' ) {

        $self->{'mintime_text'}->configure( -text => "Min:  $self->{'result'}->{'minresponse'} sec" );
        $self->{'maxtime_text'}->configure( -text => "Max:  $self->{'result'}->{'maxresponse'} sec" );
        $self->{'avgtime_text'}->configure( -text => "Avg:  $self->{'result'}->{'avgresponse'} sec" );
        $self->{'runcounttotal_text'}->configure( -text => "Total:  $self->{'result'}->{'totalruncount'}" );
        $self->{'runcountcasespassed_text'}->configure( -text => "Passed:  $self->{'result'}->{'totalcasespassedcount'}" );
        $self->{'runcountcasespfailed_text'}->configure( -text => "Failed:  $self->{'result'}->{'totalcasesfailedcount'}" );
    }
    return;
}

########################################
# flip button and do cleanup when user clicks Stop
sub _gui_stop {
    my $self = shift;

    $self->{'stop_button'}->placeForget;               #remove the stop botton
    $self->{'rtc_button'}->place(qw/-x 110 -y 65/);    #place the stop button

    $self->{'progressbar'}->set(-1);    #update progressbar back to zero

    $self->{'mainwindow'}->update();

    $self->_gui_final();
    return;
}

########################################
# remove graph
sub _gui_cleargraph {
    my $self = shift;

    $self->_reset_result();

    # delete a plot file if it exists so an old one is never rendered
    if ( -e $self->{'config'}->{'output_dir'}."plot.png" ) {
        unlink $self->{'config'}->{'output_dir'}."plot.png";
    }

    $self->{'montab_plotcanvas'}->destroy;    # destroy the canvas

    $self->{'montab_plotcanvas'} = $self->{'montab_canvas'}->Canvas(
        -width      => '718',
        -height     => '240',
        -background => '#EFEFEF',
    )->place(qw/-x 0 -y 0/);
    # canvas to place graph into
    $self->{'mainwindow'}->update();
    return;
}

########################################
# remove graph then set value to truncate log
sub _gui_cleargraph_button {
    my $self = shift;

    $self->_gui_cleargraph();

    # set value so engine knows to truncate plot log
    $self->{'switches'}->{'plotclear'} = 'yes';
    return;
}

########################################
sub _about {
    my $self = shift;

    $self->{'about'} = MainWindow->new(
        -title     => 'About WebInject',
        -bg        => '#666699',
        -takefocus => '1',                 #start on top
    );
    $self->{'about'}->raise;                          #put in front
    $self->{'about'}->geometry("320x200+200+200");    #size and screen placement
    if ( -e "icon.gif" ) {    #if icon graphic exists, use it
        $self->{'about'}->update();
        my $icon = $self->{'about'}->Photo( -file => 'icon.gif' );
        $self->{'about'}->iconimage($icon);
    }

    my $about_text = $self->{'about'}->ROText(
        -width =>
          '100', #make these big.  window size is controlled by geometry instead
        -height     => '100',
        -background => '#666699',
        -foreground => 'white',
    )->pack;

    $about_text->insert(
        "end", qq|
WebInject
©2004-2006 Corey Goldberg

Please visit www.webinject.org
for information and documentation.

WebInject is Free and Open Source.
Licensed under the terms of the GNU GPL.
    |
    );

    return;
}

########################################
sub _viewconfig {
    my $self = shift;

    $self->{'viewconfig'} = MainWindow->new(
        -title     => 'config.xml',
        -bg        => '#666699',
        -takefocus => '1',            #start on top
    );
    $self->{'viewconfig'}->raise;     #put in front
    $self->{'viewconfig'}->geometry("500x400+200+200")
      ;                               #size and screen placement
    if ( -e "logo.gif" ) {            #if icon graphic exists, use it
        $self->{'viewconfig'}->update();
        my $icon = $self->{'viewconfig'}->Photo( -file => 'icon.gif' );
        $self->{'viewconfig'}->iconimage($icon);
    }

    my $config_text = $self->{'viewconfig'}->ROText(
        -width =>
          '100', #make these big.  window size is controlled by geometry instead
        -height     => '100',
        -background => '#666699',
        -foreground => 'white',
    )->pack;

    my $file;
    if($self->{'opt_configfile'} ) {
        $file = $self->{'opt_configfile'};
    } elsif(-e "config.xml") {
        $file = "config.xml";
    }
    if(defined $file) {
        # open file handle
        open( my $config, '<', $file )
          or die "\nERROR: Failed to open ".$file." file: $!\n\n";
        # read the file into an array
        my @configfile = <$config>;
        $config_text->insert( "end", @configfile );
        close($config);
    } else {
        $config_text->insert( "end", "couldn't open default config file" );
    }

    return;
}

########################################
sub _monitor_enable_disable {
    my $self = shift;

    my $mon_tab;
    if ( !defined $self->{'monitorenabledchkbx'}
        or $self->{'monitorenabledchkbx'} eq 'monitor_on' )
    {    #create the monitor tab and all it's widgets

        $mon_tab = $self->{'tabs'}->add( 'montab', -label => 'Monitor' );
        $self->{'mainwindow'}->update();    #add the notebook tab

        $self->{'montab_canvas'} = $mon_tab->Canvas(
            -width      => '719',
            -height     => '365',
            -background => '#EFEFEF',
        )->place(qw/-x 0 -y 0/);
        $self->{'mainwindow'}->update()
          ;    #canvas to fill tab (to place widgets into)

        $self->{'montab_plotcanvas'} = $self->{'montab_canvas'}->Canvas(
            -width      => '718',
            -height     => '240',
            -background => '#EFEFEF',
        )->place(qw/-x 0 -y 0/);
        $self->{'mainwindow'}->update();    #canvas to place graph into

        my $clear_graph = $mon_tab->Button->Compound;
        $clear_graph->Text( -text => "Clear Graph" );
        $clear_graph = $mon_tab->Button(
            -width            => '70',
            -height           => '13',
            -background       => '#EFEFEF',
            -activebackground => '#666699',
            -foreground       => '#000000',
            -activeforeground => '#FFFFFF',
            -borderwidth      => '3',
            -image            => $clear_graph,
            -command          => sub { $self->_gui_cleargraph_button(); },
        )->place(qw/-x 630 -y 310/);
        $self->{'mainwindow'}->update();

        $self->{'montab_buttoncanvas'} = $self->{'montab_canvas'}->Canvas(
            -width      => '700',
            -height     => '26',
            -background => '#666699',
        )->place(qw/-x 10 -y 334/);
        $self->{'mainwindow'}->update();    #canvas to place buttons into

        $self->{'montab_buttoncanvas'}->Label(
            -text => 'Line Graph',
            -bg   => '#666699',
            -fg   => 'white',
        )->place(qw/-x 49 -y 4/);
        $self->{'mainwindow'}->update();
        my $radiolinegraph = $self->{'montab_buttoncanvas'}->Radiobutton(
            -value               => 'lines',
            -variable            => \$self->{'graphtype'},
            -indicatoron         => 'true',
            -background          => '#666699',
            -activebackground    => '#666699',
            -highlightbackground => '#666699',
        )->place(qw/-x 20 -y 2/);
        $self->{'mainwindow'}->update();

        $radiolinegraph->select;    #select as default

        $self->{'montab_buttoncanvas'}->Label(
            -text => 'Impulse Graph',
            -bg   => '#666699',
            -fg   => 'white',
        )->place(qw/-x 199 -y 4/);
        $self->{'mainwindow'}->update();
        $self->{'montab_buttoncanvas'}->Radiobutton(
            -value               => 'impulses',
            -variable            => \$self->{'graphtype'},
            -background          => '#666699',
            -activebackground    => '#666699',
            -highlightbackground => '#666699',
        )->place(qw/-x 170 -y 2/);
        $self->{'mainwindow'}->update();

        $self->{'montab_buttoncanvas'}->Label(
            -text => 'No Graph',
            -bg   => '#666699',
            -fg   => 'white',
        )->place(qw/-x 349 -y 4/);
        $self->{'mainwindow'}->update();
        $self->{'montab_buttoncanvas'}->Radiobutton(
            -value               => 'nograph',
            -variable            => \$self->{'graphtype'},
            -background          => '#666699',
            -activebackground    => '#666699',
            -highlightbackground => '#666699',
            -command             => sub { $self->_gui_cleargraph(); }
            ,    #remove graph from view
        )->place(qw/-x 320 -y 2/);
        $self->{'mainwindow'}->update();

        my $resptime_label = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 12 -y 245/);
        $self->{'mainwindow'}->update();
        $resptime_label->configure( -text => 'Response Times:' );

        $self->{'minresponse'} = 'N/A';    #set initial value for timer display
        $self->{'mintime_text'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 32 -y 265/);
        $self->{'mainwindow'}->update();
        $self->{'mintime_text'}
          ->configure( -text => "Min:  $self->{'minresponse'} sec" );

        $self->{'maxresponse'} = 'N/A';    #set initial value for timer display
        $self->{'maxtime_text'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 32 -y 285/);
        $self->{'mainwindow'}->update();
        $self->{'maxtime_text'}
          ->configure( -text => "Max:  $self->{'maxresponse'} sec" );

        $self->{'avgresponse'} = 'N/A';    #set initial value for timer display
        $self->{'avgtime_text'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 32 -y 305/);
        $self->{'mainwindow'}->update();
        $self->{'avgtime_text'}
          ->configure( -text => "Avg:  $self->{'avgresponse'} sec" );

        $self->{'runcount_label'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 250 -y 245/);
        $self->{'mainwindow'}->update();
        $self->{'runcount_label'}->configure( -text => 'Runtime Counts:' );

        $self->{'totalruncount'} = 'N/A';   #set initial value for count display
        $self->{'runcounttotal_text'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 270 -y 265/);
        $self->{'mainwindow'}->update();
        $self->{'runcounttotal_text'}
          ->configure( -text => "Total:  $self->{'totalruncount'}" );

        $self->{'casepassedcount'} = 'N/A'; #set initial value for count display
        $self->{'runcountcasespassed_text'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 270 -y 285/);
        $self->{'mainwindow'}->update();
        $self->{'runcountcasespassed_text'}
          ->configure( -text => "Passed:  $self->{'casepassedcount'}" );

        $self->{'casefailedcount'} = 'N/A'; #set initial value for count display
        $self->{'runcountcasespfailed_text'} = $self->{'montab_canvas'}->Label(
            -width      => '25',
            -height     => '1',
            -background => '#EFEFEF',
            -foreground => 'black',
            -relief     => 'flat',
            -anchor     => 'w',
        )->place(qw/-x 270 -y 305/);
        $self->{'mainwindow'}->update();
        $self->{'runcountcasespfailed_text'}
          ->configure( -text => "Failed:  $self->{'casefailedcount'}" );

    }    #end monitor create

    if ( defined $self->{'monitorenabledchkbx'}
        and $self->{'monitorenabledchkbx'} eq 'monitor_off' )
    {    #delete the tab when disabled
        $mon_tab = $self->{'tabs'}->delete( 'montab', -label => 'Monitor' );
        $self->{'mainwindow'}->update();
    }

    return;
}

########################################
sub _gui_no_plotter_found {    #if gnuplot not specified, notify on gui
    my $self = shift;

    $self->{'montab_plotcanvas'}->Label(
        -text =>
"Sorry, I can't display the graph.\nMake sure you have gnuplot on your system and it's location is specified in config.xml. ",
        -bg => '#EFEFEF',
        -fg => 'black',
    )->place(qw/-x 95 -y 100/);
    $self->{'mainwindow'}->update();
    return;
}


=head1 SEE ALSO

For more information about webinject visit http://www.webinject.org

=head1 AUTHOR

Corey Goldberg, E<lt>corey@goldb.orgE<gt>

Sven Nierlein, E<lt>nierlein@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Sven Nierlein

Copyright (C) 2004-2006 by Corey Goldberg

This library is free software; you can redistribute it under the GPL2 license.

=cut

1;
__END__
