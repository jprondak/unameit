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
# $Id: unameit_mode.tcl,v 1.15.8.1 1997/08/28 18:29:46 viktor Exp $
#

#
# Mode Maintenance Utility
#
# TBD - check for euid of 0 or non-zero. This is debatable.
#
# start this as tcl \
exec tcl -n $0 "$@"

package require Config

proc usage {} {
    puts stderr "usage: unameit_mode command \[mode\]"
    puts stderr "\tvalid commands are 'create', 'check', 'delete', 'edit', and 'list'"
    exit 1
}

proc unameit_mode_check {} {
    global unameitMode env

    read_config_file config site $unameitMode(SiteFile) 
    read_config_file config user $unameitMode(RootFile) 

    set config(class) ""
    set config(application) ""
    set okay 1
    foreach app [list unameitd upulld] {
	foreach param [list server_host service databases \
		data dblogs dbname] {
	    if {[catch {unameit_config_ne config $param unisqlx $app} msg]} {
		set okay 0
		puts $msg
	    }
	}
    }
    if {$okay} {
	puts "\nConfiguration for mode '$unameitMode(Mode)' looks okay."
    } else {
	puts "\nERROR: Configuration for mode '$unameitMode(Mode)' is bad."
	exit 1
    }
}

proc unameit_mode_delete {} {
    global unameitMode
    foreach f [list $unameitMode(SiteFile) $unameitMode(RootFile)] {
	if {[file exists $f]} {
	    puts "deleting $f"
	    file delete $f
	}
    }
}

proc unameit_mode_list {} {
    global unameitMode
    foreach f [glob -nocomplain [unameit_filename UNAMEIT_CONFIG *.conf]] {
	set config [file tail $f]
	set mode [file rootname $config]
	puts "$mode"
    }
}

proc unameit_mode_edit {} {
    global unameitMode env

    set editor vi
    if {[info exists env(EDITOR)]} {
	set editor $env(EDITOR)
    }
    if {[info exists env(VISUAL)]} {
	set editor $env(VISUAL)
    }
    catch {
	exec $editor $unameitMode(SiteFile) $unameitMode(RootFile) >@stdout 2>@stderr <@stdin 
    } msg
    puts $msg
    unameit_mode_check
}

#
# This uses wishx for a gui.
#
proc unameit_mode_create {} {
    global unameitMode unameitConf

    set already_done 0
    set files [list $unameitMode(SiteFile) $unameitMode(RootFile)]
    foreach f $files {
	if {[file exists $f]} {
	    puts stderr "$f already exists"
	    set already_done 1
	}
    }
    if $already_done {
	exit 1
    }

    if {! [file isdirectory $unameitMode(RootDir)]} {
	puts "creating $unameitMode(RootDir)"
	file mkdir $unameitMode(RootDir)
    }
    foreach f $files {
	write_file $f ""
    }

    unameit_mode_defaults
    puts "modify defaults in dialog box, then push Okay"
    unameit_mode_dialog
    vwait unameitMode(Dialog)

    switch -- $unameitMode(Dialog) {
	Okay {
	    puts "creating $unameitMode(SiteFile)"
	    set conf [read_file $unameitMode(SiteSourceFile)]
	    set conf [subst -nocommands -nobackslash $conf]
	    write_file $unameitMode(SiteFile) $conf

	    puts "creating $unameitMode(RootFile)"
	    set conf [read_file $unameitMode(RootSourceFile)] 
	    set conf [subst -nocommands -nobackslash $conf]
	    write_file $unameitMode(RootFile) $conf
	}
	default {
	    puts "aborted at user request"
	    exit 1
	}
    }
    unameit_mode_check
    exit 0
}

proc add_default {name {default ""}} {
    global unameitConf unameitConfOrder
    set unameitConf($name) $default
    lappend unameitConfOrder $name
}

#
# Set default configuration values based on the mode.
# Some values have no defaults - set them to blank.
#
proc unameit_mode_defaults {} {
    global unameitConf unameitMode unameitConfOrder
    set unameitConfOrder {}
    set mode $unameitMode(Mode)

    set default_domain ""
    catch {set default_domain [exec domainname]}

    set fqdn [set host [host_info official_name [info hostname]]]

    if {![regexp {\.} $fqdn] && [regexp {\.} $default_domain]} {
	set fqdn $host.$default_domain
    }

    add_default NIS/DNS_Domain 			$default_domain
    add_default Local_FQDN			$fqdn
    add_default Unameit_Data_Directory		/var/unameit-$mode
    add_default Unameit_Service 		unameit-$mode
    add_default Unameit_Server			$host
    add_default Unameit_Server_FQDN		$fqdn
    add_default Upull_Service			upull-$mode
    add_default Upull_Server			$host
    add_default Upull_Server_FQDN		$fqdn

    add_default Unisqlx_Database_Name 		$mode
    add_default Unisqlx_Database_Size_Kb 	32000
    add_default Unisqlx_Database_Directory	/var/unameit-$mode/dbdata
    add_default Unisqlx_Database_Logs		/var/unameit-$mode/dblogs
    add_default Unisqlx_Num_Data_Buffers_Kb	32000
    add_default Unisqlx_Num_Log_Buffers_Kb	2000
    add_default Unisqlx_Checkpoint_Interval_Kb	4000

    set unameitConf(Srvtab)		/etc/unameit/$mode.srvtab
    set unameitConf(Keytab)		/etc/unameit/$mode.keytab
}


#
# Display a dialog suitable for changing values in unameitConf
#
proc unameit_mode_dialog {} {
    global unameitConf unameitMode unameitConfOrder
    toplevel .d
    pack [frame .d.sep -bg black -height 2] -fill x
    pack [frame .d.file_entries] -fill x    
    pack [frame .d.buttons] -fill x
    pack [button .d.buttons.okay -text "Okay" \
	    -command "set unameitMode(Dialog) Okay"] \
	    -side left
    pack [button .d.buttons.defaults -text "Restore Defaults" \
	    -command unameit_mode_defaults] \
	    -side left
    pack [button .d.buttons.abort -text "Abort" \
	    -command "set unameitMode(Dialog) Abort"] \
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
    wm title .d "Setup Unameit - $unameitMode(Mode)"
    wm withdraw .
}


###########################################################################
#
# Main
#
lassign $argv command unameitMode(Mode)

set unameitMode(SiteSourceFile) \
	[unameit_filename UNAMEIT_INSTALL unameit.conf]

set unameitMode(SiteFile) \
	[unameit_filename UNAMEIT_CONFIG $unameitMode(Mode).conf]

set unameitMode(RootDir) \
	[unameit_filename UNAMEIT_ETC]

set unameitMode(RootSourceFile) \
	[unameit_filename UNAMEIT_INSTALL unameit_root.conf]

set unameitMode(RootFile) \
	[file join $unameitMode(RootDir) $unameitMode(Mode).conf]

#
# List command does not require a mode argument.
#
switch -- $command list {unameit_mode_list; exit 0}

#
# All other commands want a mode to operate on.
#
if {[cequal "" $unameitMode(Mode)]} {
    usage
}

switch -- $command {
    create {
	# Create uses Tk.
	if {[lempty [info commands winfo]]} {
	    lvarcat argv0 -- $argv
	    execl wishx $argv0
	}
	unameit_mode_create
    }
    check - delete - edit unameit_mode_$command
    default usage
}
