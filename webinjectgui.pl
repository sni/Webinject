#!/usr/bin/perl

#    Copyright 2004 Corey Goldberg (corey@test-tools.net)
#
#    This file is part of WebInject.
#
#    WebInject is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    WebInject is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with WebInject; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use Tk;
use Tk::Stderr;
use Tk::ROText;
use Tk::Compound;
use Tk::ProgressBar::Mac;
use Tk::NoteBook;





$| = 1; #don't buffer output to STDOUT


 
$mw = MainWindow->new(-title            => 'WebInject - HTTP Test Tool    (version 1.20)',
                      -bg               => '#666699',
                      -takefocus        => '1'  #start on top
                      );
$mw->geometry("750x650+0+0");  #size and screen placement
$mw->InitStderr; #redirect all STDERR to a window
$mw->raise; #put application in front at startup
$mw->bind('<F5>' => \&engine);  #F5 key makes it run


if (-e "logo.gif") {  #if icon graphic exists, use it
    $mw->update();
    $icon = $mw->Photo(-file => 'icon.gif');
    $mw->iconimage($icon);
}


if (-e "logo.gif") {  #if logo graphic exists, use it
    $mw->Photo('logogif', -file => "logo.gif");    
    $mw->Label(-image => 'logogif', 
               -bg    => '#666699'
              )->place(qw/-x 305 -y 12/); $mw->update();
}


$mw->Label(-text  => 'Engine Status:',
           -bg    => '#666699',
           -fg    => '#FFFFFF'
          )->place(qw/-x 12 -y 100/); $mw->update();


$out_window = $mw->Scrolled(ROText,  #engine status window 
                   -scrollbars  => 'e',
                   -background  => '#EFEFEF',
                   -width       => '103',
                   -height      => '7',
                  )->place(qw/-x 12 -y 118/); $mw->update();













$tabs = $mw->NoteBook(-backpagecolor       => '#666699',
                     -background          => '#EFEFEF', #color for active tab
                     -foreground          => 'black', #text color for active tab
                     -inactivebackground  => '#BFBFBF', #color for inactive tabs
                    )->place(qw/-x 12 -y 240/);  #outer notebook object

$status_tab = $tabs->add('statustab', -label => 'Status'); $mw->update();
$mon_tab = $tabs->add('montab', -label => 'Monitor'); $mw->update();



$status_window = $status_tab->Scrolled(ROText,  #test case status monitor window 
                   -scrollbars  => 'e',
                   -background  => '#EFEFEF',
                   -width       => '100',
                   -height      => '24',
                  )->pack(); $mw->update();
$status_window->tagConfigure('red', -foreground => '#FF3333');  #define tag for font color
$status_window->tagConfigure('green', -foreground => '#009900'); #define tag for font color




$montab_canvas = $mon_tab->Canvas(-width        => '719',
                                      -height       => '340',                   
                                      -background  => '#EFEFEF'
                                     )->pack(); $mw->update();  #canvas to fill tab to place widgets into


if (-e "plot.gif") {  #if plot graphic exists, put it in canvas
    $montab_canvas->Photo('plotgraph', -file => "plot.gif");    
    $montab_canvas->Label(-image => 'plotgraph', )->place(qw/-x 1 -y 1/);
}


$restart_button = $mw->Button->Compound;
$restart_button->Text(-text => "Restart");
$restart_button = $mw->Button(-width          => '50',
                          -height             => '13',
                          -background         => '#EFEFEF',
                          -activebackground   => '#666699',
                          -foreground         => '#000000',
                          -activeforeground   => '#FFFFFF',
                          -borderwidth        => '3',
                          -image              => $restart_button,
                          -command            => sub{gui_restart();}
                          )->place(qw/-x 5 -y 5/); $mw->update();



$exit_button = $mw->Button->Compound;
$exit_button->Text(-text => "Exit");
$exit_button = $mw->Button(-width              => '50',
                           -height             => '13',
                           -background         => '#EFEFEF',
                           -activebackground   => '#666699',
                           -foreground         => '#000000',
                           -activeforeground   => '#FFFFFF',
                           -borderwidth        => '3',
                           -image              => $exit_button,
                           -command            => sub{exit;}
                           )->place(qw/-x 687 -y 5/); $mw->update();




$stop_button = $mw->Button->Compound;
$stop_button->Text(-text => "Stop");
$stop_button = $mw->Button(-width              => '50',
                           -height             => '13',
                           -background         => '#EFEFEF',
                           -activebackground   => '#666699',
                           -foreground         => '#000000',
                           -activeforeground   => '#FFFFFF',
                           -borderwidth        => '3',
                           -image              => $stop_button,
                           -command            => sub {$STOP = 'YES';}
                           )->place; $mw->update();  #create this button but don't place it yet
                           
                           
                           


$rtc_button = $mw->Button->Compound;
$rtc_button->Text(-text => "Run");
$rtc_button = $mw->Button(-width              => '50',
                          -height             => '13',
                          -background         => '#EFEFEF',
                          -activebackground   => '#666699',
                          -foreground         => '#000000',
                          -activeforeground   => '#FFFFFF',
                          -borderwidth        => '3',
                          -image              => $rtc_button,
                          -command            => sub{engine();}
                          )->place(qw/-x 110 -y 65/); $mw->update();
$rtc_button->focus();



$progressbar = $mw->ProgressBar(-width  => '420', 
                                -bg     => '#666699'
                                )->place(qw/-x 176 -y 65/); $mw->update();


$status_ind = $mw->Canvas(-width       => '28',  #engine status indicator 
                          -height      => '9',                   
                          -background  => '#666699',
                          )->place(qw/-x 621 -y 69/); $mw->update();


$minimalcheckbx = 'minimal_off';  #give it a default value
$mw->Label(-text  => 'Minimal Output',
           -bg    => '#666699',
           -fg    => '#FFFFFF'
          )->place(qw/-x 49 -y 629/); $mw->update();
$minimal_checkbx = $mw->Checkbutton(-text       => '',  #using a text widget instead 
                        -onvalue                => 'minimal_on',
                        -offvalue               => 'minimal_off',
                        -variable               => \$minimalcheckbx,
                        -background             => '#666699',
                        -activebackground       => '#666699',
                        -highlightbackground    => '#666699'
                        )->place(qw/-x 20 -y 627/); $mw->update();


$timercheckbx = 'timer_off';  #give it a default value
$mw->Label(-text  => 'Response Timer Output',
           -bg    => '#666699',
           -fg    => '#FFFFFF'
          )->place(qw/-x 199 -y 629/); $mw->update();
$timers_checkbx = $mw->Checkbutton(-text        => '',  #using a text widget instead 
                        -onvalue                => 'timer_on',
                        -offvalue               => 'timer_off',
                        -variable               => \$timercheckbx,
                        -background             => '#666699',
                        -activebackground       => '#666699',
                        -highlightbackground    => '#666699'
                        )->place(qw/-x 170 -y 627/); $mw->update();




#load the Engine
if (-e "./webinject.pl") {
    do "./webinject.pl"   
} 
#test if the Engine was loaded
unless (defined &engine){
        print STDERR "Error: I can not load the test engine (webinject.pl)!\n\n";
        print STDERR "Check to make sure webinject.pl exists.\n";
        print STDERR "If it is not missing, you are most likely missing some Perl modules it requires.\n";
        print STDERR "Try running the engine by itself and see what modules it complains about.\n\n";
}




MainLoop;




#------------------------------------------------------------------
sub gui_initial {   #this runs when engine is first loaded
    
    #vars set in test engine
    $currentcasefile = ''; 
    $testnum = '';
    $latency = '';    
    $casecount = '';
    $description1 = '';
    $totalruncount = '';
    $failedcount = '';
    $passedcount = '';
    $casefailedcount = '';
    $casepassedcount = '';
    $totalruntime = '';
    $STOP = 'NO';


    $out_window->delete('0.0','end');  #clear window before starting
    
    $status_window->delete('0.0','end');  #clear window before starting
    
    $status_ind->configure(-background  => '#FF9900');  #change status color amber while running


    $rtc_button->placeForget;  #remove the run botton
    $stop_button->place(qw/-x 110 -y 65/);  #place the stop button


    $out_window->insert("end", "Starting Webinject Engine... \n\n"); $out_window->see("end");
}
#------------------------------------------------------------------
sub gui_restart {  #kill the entire app and restart it
    if ($0 =~ /webinjectgui.pl/) {
        exec 'perl ./webinjectgui.pl';
    }
    if ($0 =~ /webinjectgui.exe/) {
        exec './webinjectgui.exe';
    }
}
#------------------------------------------------------------------
sub gui_processing_msg {
    $out_window->insert("end", "processing test case file:\n$currentcasefile\n\n", 'bold'); $out_window->see("end");
}
#------------------------------------------------------------------
sub gui_statusbar {
    $percentcomplete = ($testnum/$casecount)*100;  
    $progressbar->set($percentcomplete);  #update progressbar with current status
}
#------------------------------------------------------------------
sub gui_tc_descript {
    unless ($minimalcheckbx  eq "minimal_on") {
        $status_window->insert("end", "- $description1\n"); $status_window->see("end");
    }
}
#------------------------------------------------------------------
sub gui_status_passed {
    $status_window->insert("end", "PASSED\n", 'green'); $status_window->see("end");
} 
#------------------------------------------------------------------
sub gui_status_failed {
    if ($1 and $2) {
        $status_window->insert("end", "FAILED ($1$2)\n", 'red'); $status_window->see("end");
    } 
    else {
        $status_window->insert("end", "FAILED\n", 'red'); $status_window->see("end");
    }
}
#------------------------------------------------------------------
sub gui_timer_output {
    if ($timercheckbx  eq "timer_on") {
        $status_window->insert("end", "$latency s\n"); $status_window->see("end");
    }
}    
#------------------------------------------------------------------
sub gui_final {
    $out_window->insert("end", "Execution Finished... see results.html file for detailed output"); $out_window->see("end");
    
    $status_window->insert("end", "\n\n------------------------------\nTotal Run Time: $totalruntime  seconds\n");
    $status_window->insert("end", "\nTest Cases Run: $totalruncount\nTest Cases Passed: $casepassedcount\nTest Cases Failed: $casefailedcount\nVerifications Passed: $passedcount\nVerifications Failed: $failedcount\n"); 
    $status_window->see("end");

    if ($failedcount > 0) {  #change status color to reflect failure or all tests passed
        $status_ind->configure(-background  => '#FF3333');  #red
    } 
    else {
        $status_ind->configure(-background  => '#009900');  #green
    }
     
        
    $minimal_checkbx->configure(-state  => 'normal');  #re-enable button after finish

    $timers_checkbx->configure(-state  => 'normal');  #re-enable button after finish
}
#------------------------------------------------------------------
sub gui_updatemontab {
    if (-e "plot.gif") {  #if plot graphic exists, put it in canvas
        $montab_canvas->Photo('plotgraph', -file => "plot.gif");    
        $montab_canvas->Label(-image => 'plotgraph', )->place(qw/-x 1 -y 1/);
    }
}    
#------------------------------------------------------------------
sub gui_stop {  #flip button and do cleanup when user clicks Stop

    $stop_button->placeForget;  #remove the stop botton
    $rtc_button->place(qw/-x 110 -y 65/);  #place the stop button
    
    $progressbar->set(-1);  #update progressbar back to zero
    
    gui_final();
}
