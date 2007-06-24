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
# $Id: networks.tcl,v 1.2.46.1 1997/09/23 21:59:42 simpson Exp $

proc make_netkey {p_item} {
    upvar 1 $p_item item

    set netkey $item(ipv4_net_start)
    append netkey . [unameit_address_xor ffffffff $item(ipv4_net_end)]
    return $netkey
}

proc get_top_net {hexip p_ip p_lastip p_mask} {

    upvar 1 $p_ip ip \
	    $p_lastip lastip \
	    $p_mask mask
    
    #
    # Skip special addresses.
    #
    switch -- $hexip {
	00000000 - 
	7f000001 {
	    log_reject "$hexip is a reserved address"
	    return 0
	}
    }

    switch -glob -- $hexip {
	[0-7]* {
	    regsub {^(..)......$} $hexip {\1000000} ip
	    regsub {^(..)......$} $hexip {\1ffffff} lastip
	    set mask ff000000
	}
	[8-9a-b]* {
	    regsub {^(....)....$} $hexip {\10000} ip
	    regsub {^(....)....$} $hexip {\1ffff} lastip
	    set mask ffff0000
	}
	[c-d]* {
	    regsub {^(......)..$} $hexip {\100} ip
	    regsub {^(......)..$} $hexip {\1ff} lastip
	    set mask ffffff00
	}
	e* {
	    log_reject "$hexip is a multicast address"
	    return 0
	}
	f* {
	    log_reject "$hexip is a reserved address"
	    return 0
	}
    }
    return 1
}

proc auto_net {first_ip_address} {
    scan $first_ip_address "%02x%02x%02x%02x" q1 q2 q3 q4
    set name "auto-$q1-$q2-$q3-$q4"
    return $name
}
