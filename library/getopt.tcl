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
#
# $Id: getopt.tcl,v 1.4 1997/03/18 23:48:41 ccpowell Exp $
#

#
# Getopt argc argv {c var val} ...
#
# If option $char is present in argv,  set var to $val
# if $val is {$optarg} the value is taken from next command line
# argument.
#
proc getopt {argc argv args} {
    set optind 0
    foreach opt $args {
	set var([lindex $opt 0]) [lindex $opt 1]
	set val([lindex $opt 0]) [lindex $opt 2]
    }
    while {$optind < $argc} {
	set arg [lindex $argv $optind]
	if {[string compare [string index $arg 0] -] != 0} {
	    return $optind
	}
	if {[string compare $arg --] == 0} {
	    return [incr optind]
	}
	set len [string length $arg]
	for {set i 1} {$i < $len} {incr i} {
	    set c [string index $arg $i]
	    if {![info exists var($c)]} {
		return -code error "Invalid option $c"
	    }
	    if {[string compare $val($c) {$optarg}] == 0} {
		if {$len > $i+1} {
		    uplevel set [list $var($c)] \
			    [list [string range $arg [expr $i+1] end]]
		    break
		} else {
		    if {$optind+1 == $argc} {
			return -code error "No value given to option $c"
		    } else {
			uplevel set [list $var($c)] \
				[list [lindex $argv [incr optind]]]
		    }
		}
	    } else {
		uplevel set [list $var($c)] [list $val($c)]
	    }
	}
	incr optind
    }
    return $optind
}


