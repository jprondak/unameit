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

proc unameit_start {} {
    global argc argv argv0 env
    set argv0 [file tail $argv0]
    #
    if {[llength $argv] != 6} {
	error "Usage: $argv0 macaddress type host_units person_units start end"
    }

    lassign $argv macaddress type host_units person_units start end

    set macaddress [check_mac_addr $macaddress]

    switch -- $type prod - eval {} default {
	error "Bad license type: $type"
    }

    foreach var {start end} {
	upvar 0 $var time_var
	if {[cequal $time_var ""]} {
	    set time_var -1
	} else {
	    #
	    # Convert to seconds
	    #
	    set time_var [clock scan $time_var -gmt 1]
	    #
	    # Round to start of day
	    #
	    set time_var [clock format $time_var -format %m/%d/%Y -gmt 1]
	    #
	    # Convert back to seconds
	    #
	    set time_var [clock scan $time_var -gmt 1]
	}
    }

    set key [new_key $type $host_units $person_units $start $end $macaddress]

    foreach var {start end} {
	upvar 0 $var time_var
	if {$time_var == -1} {
	    set time_var ""
	} else {
	    set time_var [clock format $time_var -format %m/%d/%Y -gmt 1]
	}
    }
    puts "\tlicense_start\t$start"
    puts "\tlicense_end\t$end"
    puts "\tlicense_type\t$type"
    puts "\tlicense_host_units\t$host_units"
    puts "\tlicense_person_units\t$person_units"
    puts "\tlicense_key\t$key"
}

proc check_mac_addr {value} {
    set comps [split $value :]

    if {[llength $comps] != 6} {
	error "Bad MAC address: $value"
    }
    foreach comp $comps {
	if {[scan $comp "%x%s" hex junk] != 1 || $hex < 0 || 255 < $hex} {
	    error "Bad MAC address component: $comp"
	}
	append result [format "%02x" $hex]
    }
    set result
}
