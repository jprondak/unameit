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
# $Id: load.tcl,v 1.32.10.1 1997/08/28 18:29:02 viktor Exp $
#

#
# This is a sort of wrapper for load operations. It is a wishx script
# which is executed by unameit_load. Most options will cause unameitcl
# to be run with the appropriate script (see LoadScripts below).

package require Config

#
# Find a unameit executable and return the complete pathname.
#
proc find_exe {exe} {
    foreach place [list UNAMEIT_BIN UNAMEIT_SBIN] {
	set f [unameit_filename $place $exe]
	if {[file executable $f]} {
	    return $f
	}
    }
    error "$exe cannot be found"
}

#
# Print a usage message.
#
proc usage {} {
    global LoadScripts

    puts "Usage: unameit_load operation options"
    puts "Operations are:"
    foreach op [lsort [array names LoadScripts]] {
	puts "\t$op"
    }

    puts "\nTo start the Graphical Interface use 'unameit_load gui'"
}

proc printenv {} {
    global env
    foreach {var value} [array get env] {
	puts "$var='$value';"
	puts "export $var;"
    }
}

unameit_getconfig loadConfig unameit_load

array set LoadScripts [list \
aliases		[unameit_filename UNAMEIT_LOADLIB load_aliases.tcl] \
copy_checkpoint	[unameit_filename UNAMEIT_LOADLIB dat_to_heap.tcl] \
domains 	[unameit_filename UNAMEIT_LOADLIB load_domains.tcl] \
generate 	[unameit_filename UNAMEIT_LOADLIB load_generate.tcl] \
groups_users 	[unameit_filename UNAMEIT_LOADLIB load_group_users.tcl] \
groups 		[unameit_filename UNAMEIT_LOADLIB load_groups.tcl] \
hosts 		[unameit_filename UNAMEIT_LOADLIB load_hosts.tcl] \
netgroups 	[unameit_filename UNAMEIT_LOADLIB load_netgroups.tcl] \
networks 	[unameit_filename UNAMEIT_LOADLIB load_networks.tcl] \
persons 	[unameit_filename UNAMEIT_LOADLIB load_persons.tcl] \
services 	[unameit_filename UNAMEIT_LOADLIB load_services.tcl] \
users 		[unameit_filename UNAMEIT_LOADLIB load_users.tcl] \
; # dump_html 	[unameit_filename UNAMEIT_LOADLIB heap_to_html.tcl]
]
	
if {$argc == 0} {
    usage
    exit 1
} 

set options [lassign $argv op]
switch -exact -- $op {
    env {
	printenv
	exit 0
    }

    gui	{
	# GUI uses Tk.
	if {[lempty [info commands winfo]]} {
	    lvarcat argv0 -- $argv
	    execl wishx $argv0
	}
	source [unameit_filename UNAMEIT_LOADLIB load_gui.tcl]
	do_gui
    }

    default {
	if {[info exists LoadScripts($op)]} {
	    linsert options 0 $LoadScripts($op) 
	    set result [catch {execl unameitcl $options} msg]
	    #
	    # The execl command does a real execl, unlike the normal tcl exec.
	    # if execl fails, we may need to 'kill [id process]'
	    puts $msg
	    exit $result
	}
	puts "No such operation $op"
	usage
	exit 1
    }
}


