#
# Copyright (c) 1997 Enterprise Systems Management Corp.
#
# This file is part of UName*It.
#
# UName*It is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2, or (at your option) any later
# version.
#
# UName*It is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with UName*It; see the file COPYING.  If not, write to the Free
# Software Foundation, 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA.
#
# $Id: load_gui.tcl,v 1.10.10.1 1997/08/28 18:29:08 viktor Exp $

# this is a wishx script to run the loading scripts.
# It is executed by unameit_load.
# The user needs his own kerboros tickets -
# run kinit to get them.

package require Config

source [unameit_filename UNAMEIT_LOADLIB load_commands.tcl]
source [unameit_filename UNAMEIT_LOADLIB load_setup.tcl]

#
# Start a test.
# Put up the message and log it in the logfile.
# Returns true if okay, false if another test was running.
#
proc start_test {message} {
    global logfile running

    if {![info exists running]} {
	puts $logfile [concat [clock format [clock seconds]] " - " $message]
	flush $logfile
	set running $message
	.msg.message configure -text $running
	update
	return 1
    }
    return 0
}

#
# The finish procedure does an update to process (i.e. log_reject) all of
# the events that occurred during the test. Then the mutex is removed
# and the message area is updated.
#
proc finish_test {{message finished}} {
    global logfile running

    update
    if {[info exists running]} {
	puts $logfile [concat [clock format [clock seconds]] " - " $message]
	flush $logfile
	unset running
	.msg.message configure -text ""
	update
	return 1
    }
    return 0
}

proc init_frame {} {
    global LoadSetup LoadConfig
    set uport [unameit_config LoadConfig service]
    wm title . "LoadRunner"
    pack [button .exit -text exit -command exit] -side bottom 
    pack [frame .msg -borderwidth 2 -relief groove] -side bottom -fill x 
    pack [label .msg.label -text "Operation In Progress:"] -side left
    pack [label .msg.message] -anchor w 

    pack [frame .bb -borderwidth 6 -relief ridge] -pady 5 -padx 5 -fill x -side right 
    pack [frame .lr -borderwidth 6 -relief ridge] -pady 5 -padx 5 -fill x
    pack [frame .sp -borderwidth 6 -relief ridge] -pady 5 -padx 5 -fill x
    pack [frame .ds -borderwidth 6 -relief ridge] -pady 5 -padx 5 -fill x
    pack [frame .lo -borderwidth 6 -relief ridge] -pady 5 -padx 5 -fill x

    pack [label .lr.dir -text "Directory: [pwd]"] -anchor w
    add_button .lr.setup 	"Input File Setup" 	load_setup_dialog
    add_button .lr.snlf  	"Start New Log File" 	start_log

    pack [label .sp.label -text "Unameit Server Commands"] -anchor w
    pack [label .sp.port -text "Unameit Server Port: $uport"] -anchor w
    add_subprocess .sp.start 	"Start Server $uport"	server_start
    add_subprocess .sp.lnd   	"Load Cache Data Into Server" 	server_load
    add_subprocess .sp.stop	"Stop Server $uport"	server_stop
    add_test .sp.ccp  		"Copy Checkpoint From Server" 	copy_checkpoint
    #add_test .sp.dh 		"Dump Cache Into HTML"		dump_heap

    #
    # Command Execution Options
    #
    pack [label .ds.label -text "Load Command Execution Options"] -anchor w
    pack [radiobutton .ds.doit -text "Execute Command" \
	    -variable doit -value execute] -side left
    pack [radiobutton .ds.showit -text "Show Command" \
	    -variable doit -value show] -side left

    #
    # Logging Options
    #
    pack [label .lo.label -text "Load Command Logging Options"] -anchor w
    pack [frame .lo.tb] -fill x
    pack [checkbutton .lo.tb.warning -text Warning -variable verbosity(W)] -side left
    pack [checkbutton .lo.tb.reject -text Reject -variable verbosity(R)] -side left
    pack [checkbutton .lo.tb.create -text Create -variable verbosity(C)] -side left
    pack [checkbutton .lo.tb.ignore -text Ignore -variable verbosity(I)] -side left
    pack [checkbutton .lo.tb.debug -text Debug -variable verbosity(D)] -side left
    pack [checkbutton .lo.tb.trace -text StackTrace -variable verbosity(T)] -side left

    pack [label .bb.label -text "Load Commands"] -anchor w
    set buttons 0
    add_test .bb.b01 "Load Domains" load_domains
    add_test .bb.b02 "Load Networks" load_networks
    add_test .bb.b03 "Load Routers" load_routers
    add_test .bb.b04 "Load Hubs" load_hubs
    add_test .bb.b05 "Load Computers" load_hosts
    add_test .bb.b06 "Load DNS Hosts" load_dns
    add_test .bb.b07 "Load Persons" load_persons
    add_test .bb.b08 "Load User Groups" load_user_groups
    add_test .bb.b09 "Load Application Groups" load_application_groups
    add_test .bb.b10 "Load User Logins and Automounts" load_user_logins
    add_test .bb.b11 "Load Application Logins" load_application_logins
    add_test .bb.b12 "Load User Group Members" load_user_group_members
    add_test .bb.b13 "Load Application Group Members" load_application_group_members
    add_test .bb.b14 "Load Aliases" load_aliases
    add_test .bb.b15 "Load Netgroups" load_netgroups
    add_test .bb.b16 "Load Services" load_services
    add_test .bb.b17 "Generate Load Script" load_generate
}

proc do_test {label command_proc} {
    global verbosity logfile doit

    if {[cequal execute $doit] && ![start_test $label]} {
	    return
    }

    if {! [$command_proc command]} {
	.msg.message configure -text "bad news..."
	return
    }

    foreach type [array names verbosity] {
	if {$verbosity($type)} {
	    lappend command -$type
	}
    }
    
    if {[cequal execute $doit]} {
	lvarpush command exec 
	lappend command >@ $logfile 2>@$logfile
    
	set result [catch $command msg]
	if {$result != 0} {
	    tk_dialog .warning "LoadRunner ERROR" \
		    "$label - failed. See logfile." \
		    "" 0 okay

	}
	finish_test 

    } else {
	show_command $command
    }
    return
}


proc do_subprocess {label command_proc} {
    global verbosity logfile doit

    if {[cequal execute $doit] && ![start_test $label]} {
	    return
    }

    if {! [$command_proc command]} {
	.msg.message configure -text "bad news..."
	return
    }

    if {[cequal execute $doit]} {
	lvarpush command exec 
	lappend command >@ $logfile 2>@$logfile
    
	set result [catch $command]
	if {$result != 0} {
	    tk_dialog .warning "LoadRunner ERROR" \
		    "$label - failed. See logfile." \
		    "" 0 okay

	}
	finish_test 

    } else {
	show_command $command
    }
    return
}

# Add a button
proc add_button {button_name label command} {
    pack [button $button_name -text $label -command $command] -fill x
}

# Add a test button. The command will get wrapped.
proc add_test {button_name label command} {
    set full_command [list do_test $label $command]
    pack [button $button_name -text $label -command $full_command] -fill x
}

# Add a subprocess button. The command will get wrapped.
proc add_subprocess {button_name label command} {
    set full_command [list do_subprocess $label $command]
    pack [button $button_name -text $label -command $full_command] -fill x
}

###########################################################################

proc unimp {c} {
    return 0
}

proc show_command {command} {

    if {! [winfo exists .sc]} {

    toplevel .sc
    pack [label .sc.title -text "Load Command"]
    pack [frame .sc.cf] -fill x    
    pack [text .sc.cf.command -wrap word -width 60 -height 4] -fill x
    pack [frame .sc.buttons] -fill x
    pack [button .sc.buttons.dismiss -text Dismiss -command "wm withdraw .sc"] \
	    -side left
#    pack [button .sc.buttons.save -text "Execute" -command "wm withdraw .sc"] \
	    -side left

    wm title .sc "Load Command"
    wm group .sc .
    } else {
	.sc.cf.command delete 1.0 end
    }
    .sc.cf.command insert end $command
    wm deiconify .sc
    raise .sc
    return
}

proc warn_not_root {} {
    if {[id userid] != 0} {
	tk_dialog .warning "LoadRunner WARNING" \
		"You are not root. You will not be able to start or stop the server." \
		"" 0 okay
    }
}


proc start_log {} {
    global logfile

    if {![start_test "Truncating Logfile"]} {
	return
    }

    catch {
	seek $logfile 0
	ftruncate -fileid $logfile 0
    }

    finish_test "Started New Logfile"
}

###########################################################################

proc do_gui {} {
    global env logfile verbosity doit LoadSetup LoadConfig

    unameit_getconfig LoadConfig loadrunner
    warn_not_root
    catch {unset LoadSetup}
    catch {unset LoadEnv}

    # Default Command Options
    set doit show
    set verbosity(W) 1
    set verbosity(R) 1
    
    init_frame
    load_setup_defaults
    load_setup_get
    set logfile [open $LoadSetup(Logfile) a 0666]
}

