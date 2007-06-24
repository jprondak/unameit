#! /bin/sh 
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
# $Id: upull_mode.tcl,v 1.10.8.1 1997/08/28 18:29:54 viktor Exp $
#

#
# Mode Maintenance Utility for Upull clients
# Affects only the hosts config file for the given mode.
#
# start this as tcl \
exec tcl -n $0 "$@"

package require Config

proc usage {} {
    puts stderr "usage: upull_mode command \[mode\]"
    puts stderr "\tvalid commands are 'create', 'check', 'delete', 'edit', and 'list'"
    exit 1
}

proc upull_mode_check {} {
    global upullMode env

    read_config_file config site $upullMode(SiteFile) 
    read_config_file config user $upullMode(RootFile) 

    set config(class) ""
    set config(application) ""
    set okay 1
    foreach app [list upull upulld] {
	foreach param [list server_host] {
	    if {[catch {unameit_config_ne config $param "" $app} msg]} {
		set okay 0
		puts $msg
	    }
	}
    }
    if {$okay} {
	puts "\nConfiguration for mode '$upullMode(Mode)' looks okay."
    } else {
	puts "\nERROR: Configuration for mode '$upullMode(Mode)' is bad."
	exit 1
    }
}

proc upull_mode_delete {} {
    global upullMode
    foreach f [list $upullMode(RootFile)] {
	if {[file exists $f]} {
	    puts "deleting $f"
	    file delete $f
	}
    }
}

proc upull_mode_list {} {
    global upullMode
    foreach f [glob -nocomplain [unameit_filename UNAMEIT_CONFIG *.conf]] {
	set config [file tail $f]
	set mode [file rootname $config]
	puts "$mode"
    }
}

proc upull_mode_edit {} {
    global upullMode env

    set editor vi
    if {[info exists env(EDITOR)]} {
	set editor $env(EDITOR)
    }
    if {[info exists env(VISUAL)]} {
	set editor $env(VISUAL)
    }
    catch {
	exec $editor $upullMode(RootFile) >@stdout 2>@stderr <@stdin 
    } msg
    puts $msg
    upull_mode_check
}

proc upull_mode_create {} {
    global upullMode unameitConf upullConf

    if {[file exists $upullMode(RootFile)]} {
	error "$upullMode(RootFile) already exists"
    }
    if {! [file exists $upullMode(SiteFile)]} {
	error "$upullMode(Mode) is not a valid unameit mode"
    }
    if {! [file isdirectory $upullMode(RootDir)]} {
	puts "creating $upullMode(RootDir)"
	file mkdir $upullMode(RootDir)
    }
    write_file $upullMode(RootFile) ""

    upull_mode_defaults
    puts "modify defaults in dialog box, then push Okay"
    upull_mode_dialog
    vwait upullMode(Dialog)

    switch -- $upullMode(Dialog) {
	Okay {
	    puts "creating $upullMode(RootFile)"
	    set conf [read_file $upullMode(RootSourceFile)] 
	    set conf [subst -nocommands -nobackslash $conf]
	    write_file $upullMode(RootFile) $conf
	}
	default {
	    puts "aborted at user request"
	    exit 1
	}
    }
    upull_mode_check
    exit 0
}

proc add_default {name {default ""}} {
    global unameitConf unameitConfOrder
    set unameitConf($name) $default
    lappend unameitConfOrder $name
}

#
# Substitutions on the template require the following parameters to be
# set even though they are not used on a pull server.
#
proc add_unused {} {
    global unameitConf
    foreach p [list \
	    Unisqlx_Database_Name \
	    Unisqlx_Database_Logs \
	    Unisqlx_Database_Size_Kb \
	    Unisqlx_Database_Directory \
	    Unisqlx_Num_Data_Buffers_Kb \
	    Unisqlx_Num_Log_Buffers_Kb \
	    Unisqlx_Checkpoint_Interval_Kb \
	    License_Key \
	    License_Type \
	    License_Host_Units \
	    License_User_Units \
	    License_Begin_Date \
	    License_End_Date] {
	set unameitConf($p) "NOT USED ON THIS HOST "
    }
}


#
# Set default configuration values based on the mode.
# Some values have no defaults - set them to blank.
#
proc upull_mode_defaults {} {
    global unameitConf upullMode unameitConfOrder
    set unameitConfOrder {}
  
    read_config_file upullConfig site $upullMode(SiteFile) 
    set upullConfig(application) upull

    set mode $upullMode(Mode)

    set default_domain ""
    catch {set default_domain [exec domainname]}

    set fqdn [set host [host_info official_name [info hostname]]]

    if {![regexp {\.} $fqdn] && [regexp {\.} $default_domain]} {
	set fqdn $host.$default_domain
    }
    
    add_unused

    add_default NIS/DNS_Domain 			$default_domain
    add_default Local_FQDN			$fqdn
    add_default Unameit_Data_Directory		/var/unameit-$mode
    add_default Upull_Server			$host
    add_default Upull_Server_FQDN		$fqdn
}


#
# Display a dialog suitable for changing values in unameitConf
#
proc upull_mode_dialog {} {
    global unameitConf upullMode unameitConfOrder
    toplevel .d
    pack [frame .d.sep -bg black -height 2] -fill x
    pack [frame .d.file_entries] -fill x    
    pack [frame .d.buttons] -fill x
    pack [button .d.buttons.okay -text "Okay" \
	    -command "set upullMode(Dialog) Okay"] \
	    -side left
    pack [button .d.buttons.defaults -text "Restore Defaults" \
	    -command upull_mode_defaults] \
	    -side left
    pack [button .d.buttons.abort -text "Abort" \
	    -command "set upullMode(Dialog) Abort"] \
	    -side left

    set fnum 0
    foreach f $unameitConfOrder {
	incr fnum
	set fe .d.file_entries.f$fnum
	pack [frame $fe] -fill x
	set label [translit _ " " $f]
	pack [label $fe.label -text $label -width 30 -anchor w] -side left
	pack [entry $fe.entry -textvariable unameitConf($f) -width 45] \
		-side right -fill x -expand 1
    }
    wm title .d "Setup Upull - $upullMode(Mode)"
    wm withdraw .
}

    
###########################################################################
#
# Main
#
lassign $argv command upullMode(Mode)

set upullMode(SiteFile) \
	[unameit_filename UNAMEIT_CONFIG $upullMode(Mode).conf]

set upullMode(RootDir) \
	[unameit_filename UNAMEIT_ETC]

set upullMode(RootSourceFile) \
	[unameit_filename UNAMEIT_INSTALL unameit_root.conf]

set upullMode(RootFile) \
	[file join $upullMode(RootDir) $upullMode(Mode).conf]

#
# List command does not require a mode argument.
#
switch -- $command list {upull_mode_list; exit 0}

#
# All other commands want a mode to operate on.
#
if {[cequal "" $upullMode(Mode)]} {
    usage
}

switch -- $command {
    create {
	# Create uses Tk.
	if {[lempty [info commands winfo]]} {
	    lvarcat argv0 -- $argv
	    execl wishx $argv0
	}
	upull_mode_create
    }
    check - delete - edit upull_mode_$command
    default usage
}
