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
  
require('webinject.pl');

$| = 1; #don't buffer output to STDOUT


 
$mw = MainWindow->new(-title  => 'WebInject - HTTP Test Tool',
                      -width  => '650', 
                      -height => '650', 
                      -bg     => '#666699',
                      );
$mw->InitStderr; #redirect all STDERR to a window
$mw->raise; #put application in front at startup
$mw->bind('<F5>' => \&engine);

 
$mw->update();
$icon = $mw->Photo(-file => 'icon.gif');
$mw->iconimage($icon);


$mw->Photo('logogif', -file => "logo.gif");    
$mw->Label(-image => 'logogif', 
            -bg    => '#666699'
            )->place(qw/-x 235 -y 12/); $mw->update();


$mw->Label(-text  => 'Engine Status:',
            -bg    => '#666699'
            )->place(qw/-x 25 -y 110/); $mw->update();


$out_window = $mw->Scrolled(ROText,  #engine status window 
                   -scrollbars  => 'e',
                   -background  => '#EFEFEF',
                   -width       => '85',
                   -height      => '7',
                  )->place(qw/-x 25 -y 128/); $mw->update(); 


$mw->Label(-text  => 'Test Case Status:',
           -bg    => '#666699'
           )->place(qw/-x 25 -y 238/); $mw->update(); 


$status_window = $mw->Scrolled(ROText,  #test case status window 
                   -scrollbars  => 'e',
                   -background  => '#EFEFEF',
                   -width       => '85',
                   -height      => '26',
                  )->place(qw/-x 25 -y 256/); $mw->update();


$rtc_button = $mw->Button->Compound;
$rtc_button->Text(-text => "Run Test Cases");
$rtc_button = $mw->Button(-width              => '85',
                          -height             => '13',
                          -background         => '#EFEFEF',
                          -activebackground   => '#666699',
                          -foreground         => '#000000',
                          -activeforeground   => '#FFFFFF',
                          -borderwidth        => '3',
                          -image              => $rtc_button,
                          -command            => sub{engine();}
                          )->place(qw/-x 25 -y 75/); $mw->update();
$rtc_button->focus();


$exit_button = $mw->Button->Compound;
$exit_button->Text(-text => "Exit");
$exit_button = $mw->Button(-width              => '40',
                           -height             => '13',
                           -background         => '#EFEFEF',
                           -activebackground   => '#666699',
                           -foreground         => '#000000',
                           -activeforeground   => '#FFFFFF',
                           -borderwidth        => '3',
                           -image              => $exit_button,
                           -command            => sub{exit;}
                           )->place(qw/-x 596 -y 5/); $mw->update();


$progressbar = $mw->ProgressBar(-width  => '420', 
                                -bg     => '#666699'
                                )->place(qw/-x 150 -y 75/); $mw->update();



MainLoop;




#------------------------------------------------------------------
sub gui_initial {
    
    #vars set in test engine
    $currentcasefile = '';
    $testnum = '';
    $casecount = '';
    $description1 = '';
    $totalruncount = '';
    $failedcount = '';
    $passedcount = '';
    $totalruntime = '';

    $out_window->delete('0.0','end');    #clear window before starting
    
    $status_window->delete('0.0','end'); #clear window before starting
    
    $rtc_button->configure(-state       => 'disabled',  #disable button while running
                           -background  => '#666699',
                           );
    
    $out_window->insert("end", "Starting Webinject Engine... \n\n"); $out_window->see("end");
}
#------------------------------------------------------------------
sub gui_processing_msg {
    $out_window->insert("end", "processing test case file:\n$currentcasefile\n\n"); $out_window->see("end");
}
#------------------------------------------------------------------
sub gui_statusbar {
    $percentcomplete = ($testnum/$casecount)*100;  
    $progressbar->set($percentcomplete);  #update progressbar with current status
}
#------------------------------------------------------------------
sub gui_tc_descript {
    $status_window->insert("end", "- $description1\n"); $status_window->see("end");
}
#------------------------------------------------------------------
sub gui_status_passed {
    $status_window->insert("end", "PASSED\n"); $status_window->see("end");
} 
#------------------------------------------------------------------
sub gui_status_failed {
    $status_window->insert("end", "FAILED ($1$2)\n"); $status_window->see("end");
}
#------------------------------------------------------------------
sub gui_final {
    $out_window->insert("end", "Execution Finished... see results.html file for detailed output"); $out_window->see("end");
    
    $status_window->insert("end", "\n\n------------------------------\nTotal Run Time: $totalruntime  seconds\n");
    $status_window->insert("end", "\nTest Cases Run: $totalruncount\nVerifications Passed: $passedcount\nVerifications Failed: $failedcount\n"); 
    $status_window->see("end");
       
    $rtc_button->configure(-state       => 'normal',  #re-enable button after finish
                           -background  => '#EFEFEF',
                           );
}
#------------------------------------------------------------------

