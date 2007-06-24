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
# $Id: tcldump_dns.tcl,v 1.2.14.1 1997/08/28 18:25:30 viktor Exp $
#

set curtime [clock seconds]

uplevel #0 {set tcl_interactive [fstat stdout tty]}

proc loop_subs {inputdir class code} {
    global DATA_LEVEL
    upvar $DATA_LEVEL\
	ISA ISA unrestored unrestored subclasses subclasses fields fields\
	oid oid uuid uuid oid2uuid oid2uuid oid2cname oid2cname F F

    set fmt {unset F; lassign $line oid uuid DATA; }
    append fmt {set oid2uuid($oid) $uuid; set oid2cname($oid) $cname; }
    append fmt {lassign $DATA %s; %s}
    set code [list uplevel 1 $code]
    #
    foreach cname [concat $class $subclasses($class)] {
	if {![info exists unrestored($cname)]} continue
	set fh [open [file join $inputdir $unrestored($cname)] r]
	#
	set F() {}
	set vars ""
	foreach f $fields($cname) {lappend vars F($f)}
	#
	while {[lgets $fh line] != -1} [format $fmt $vars $code]
	close $fh
    }
}

proc name_of_computer {oid {real_host 0}} {
    global DATA_LEVEL
    upvar $DATA_LEVEL cname_cache cache

    switch -- $oid "" return

    if {[info exists cache($oid.$real_host)]} {
	return $cache($oid.$real_host)
    }

    upvar $DATA_LEVEL\
	ISA ISA oid2cname oid2cname oid2name oid2name regionoid regionoid

    if {$real_host} {
	if {[info exists ISA(host.$oid2cname($oid))]} {
	    # Host.
	    set name $oid2name($oid)
	    set region $oid2name($regionoid($oid))
	} elseif {[info exists ISA(host_alias.$oid2cname($oid))]} {
	    # Host of host alias.
	    upvar $DATA_LEVEL oid2owner hostof
	    set name $oid2name($hostof($oid))
	    set region $oid2name($regionoid($hostof($oid)))
	} else {
	    # Host of server alias.
	    upvar $DATA_LEVEL oid2primary_server primary
	    set name $oid2name($primary($oid))
	    set region $oid2name($regionoid($primary($oid)))
	}
    } else {
	if {[info exists ISA(host.$oid2cname($oid))]} {
	    # Host
	    set name $oid2name($oid)
	    set region $oid2name($regionoid($oid))
	} elseif {[info exists ISA(host_alias.$oid2cname($oid))]} {
	    # Host alias.
	    upvar $DATA_LEVEL oid2owner hostof
	    set name $oid2name($oid)
	    set region $oid2name($regionoid($hostof($oid)))
	} else {
	    # Server alias.
	    upvar $DATA_LEVEL oid2server_type stype
	    set name $oid2name($stype($oid))
	    set region $oid2name($regionoid($oid))
	}
    }

    switch -- $region {
	. {
	    return [set computer_cache($oid.$real_host) $name]
	}
	default {
	    return [set computer_cache($oid.$real_host) $name.$region]
	}
    }
}

proc dotted_quad {hex} {
    scan $hex %02x%02x%02x%02x q1 q2 q3 q4
    return $q1.$q2.$q3.$q4
}

proc host_ip_list {oids} {
    global DATA_LEVEL
    upvar $DATA_LEVEL\
	oid2name oid2name\
	celloid celloid\
	regionoid regionoid\
	oid2ip oid2ip

    set result {}
    foreach oid $oids {
	set region $regionoid($oid)
	lappend result\
	    [format "%s@%s@%s@%s"\
		$oid2name($oid)\
		$oid2name($celloid($region))\
		$oid2name($region)\
		[join $oid2ip($oid) ,]]
    }
    return $result
}

#
#-----------------------------------------------------
#
# Load database image
#
global DATA_LEVEL
set DATA_LEVEL "#[info level]"

package require Config
unameit_getconfig config uparsedb
set data_dir [file join [unameit_config config data] data]
set INPUTDIR [file join $data_dir data.$VERSION]
set DUMPDIR [file join $data_dir dump.$VERSION]

source [file join $INPUTDIR Info.tcl]
foreach cname [array names subclasses] {
    set ISA($cname.$cname) 1
    foreach subname $subclasses($cname) {
	set ISA($cname.$subname) 1
    }
}

#
# Create output directory
#
file mkdir $DUMPDIR
set MODE 0444

#
# Region data for pull
#
## For empty Organizations, just output the cell oid since the
## cell is its own "color". For regions, don't output any oid
## so we can differentiate cells from regions.
#
__diagnostic [unameit_time {
__diagnostic -nonewline "Regions..."
set OUTPUT [atomic_open [file join $DUMPDIR regions] $MODE]
loop_subs $INPUTDIR region {
    set oid2name($oid) $F(name)
    set oid2owner($oid) $F(owner)
    #
    # Initialize domain netgroups to empty values
    #
    set region2hosts($oid) ""
    set region2users($oid) ""

    if {[info exists ISA(cell.$oid2cname($oid))]} {
	if {[cequal $F(cellorg) ""]} {
	    set org_oid $oid
	} else {
	    set org_oid $F(cellorg)
	}
	puts $OUTPUT [list $oid $F(name) $F(owner) $F(wildcard_mx) $org_oid]
    } else {
	puts $OUTPUT [list $oid $F(name) $F(owner) $F(wildcard_mx)]
    }
}
atomic_close $OUTPUT

#
# Compute cell oid of every cell and region
#
foreach oid [array names oid2name] {
    if {[info exists celloid($oid)]} continue
    set hier $oid
    set owner $oid
    while {![info exists ISA(cell.$oid2cname($owner))]} {
	set owner $oid2owner($owner)
	lappend hier $owner
    }
    foreach oid $hier {
	set celloid($oid) $owner
    }
}
}]

#
# /etc/networks data
#
__diagnostic [unameit_time {
__diagnostic -nonewline "Networks..."
set OUTPUT [atomic_open [file join $DUMPDIR networks] $MODE]
loop_subs $INPUTDIR ipv4_network {
    set region $F(owner)
    puts $OUTPUT [format {%s %s %s %s %s} \
	    $F(name)\
	    $oid2name($region)\
	    $F(ipv4_address)\
	    $F(ipv4_last_address) \
	    $F(ipv4_mask)
	]
}
atomic_close $OUTPUT
}]

__diagnostic [unameit_time {
__diagnostic -nonewline "Hosts..."
set OUTPUT [atomic_open [file join $DUMPDIR canon_hosts] $MODE]
loop_subs $INPUTDIR host {
    set oid2name($oid) $F(name)
    set regionoid($oid) [set region $F(owner)]
    set oid2ifname($oid) $F(ifname)
    set oid2ip($oid) [set ip [dotted_quad $F(ipv4_address)]]

    ## Save a list of computers per region for netgroups
    if {[info exists ISA(computer.$oid2cname($oid))]} {
	lappend region2hosts($region) ([name_of_computer $oid 1],-,)
    }

    ## This is used by Sybase interfaces
    set oid2hexip($oid) $F(ipv4_address)

    if {[info exists F(receives_mail)]} {
	set recmail $F(receives_mail)
    } else {
	set recmail No
    }
    puts $OUTPUT [format {%s|%s|%s|%s|%s|%s|%s|%s} \
	$uuid\
	$ip\
	$F(name)\
	$oid2name($celloid($region))\
	$oid2name($region)\
	$F(ifname) \
	$F(ifaddress)\
	$recmail
    ] 
}
atomic_close $OUTPUT


set OUTPUT [atomic_open [file join $DUMPDIR secondary_ifs] $MODE]
loop_subs $INPUTDIR ipv4_interface {
    if {[cequal $F(ipv4_address)  ""]} continue
    lappend oid2ip($F(owner)) [set ip [dotted_quad $F(ipv4_address)]]
    set regionoid($oid) [set region $regionoid($F(owner))]
    set oid2name($oid) [set hname $oid2name($F(owner))]
    set oid2ifname($oid) $F(ifname)
    puts $OUTPUT [format {%s|%s|%s|%s|%s|%s|%s}\
	$F(ifname) \
	$ip\
	$F(ifaddress) \
	$hname\
	$oid2name($celloid($region))\
	$oid2name($region)\
	$oid2uuid($F(owner))\
    ]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR secondary_ip] $MODE]
loop_subs $INPUTDIR ipv4_secondary_address {
    set ip [dotted_quad $F(ipv4_address)]
    set ifname $oid2ifname($F(owner))
    set hname $oid2name($F(owner))
    set region $regionoid($F(owner))
    puts $OUTPUT [format {%s|%s|%s|%s|%s} \
	    $ip\
	    $ifname\
	    $hname\
	    $oid2name($celloid($region))\
	    $oid2name($region)
	]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR host_aliases] $MODE]
loop_subs $INPUTDIR host_alias {
    set host $F(owner)
    set oid2owner($oid) $F(owner)
    set oid2name($oid) $F(name)
    set region $regionoid($host)
    set regionoid($oid) $region
    puts $OUTPUT [format {%s %s %s %s %s} \
	$F(name)\
	$oid2name($celloid($region))\
	$oid2name($host)\
	$oid2name($celloid($region))\
	$oid2name($region)
    ]
}
atomic_close $OUTPUT
}]

__diagnostic [unameit_time {
__diagnostic -nonewline "Server aliases..."
set OUTPUT [atomic_open [file join $DUMPDIR server_type] $MODE]
loop_subs $INPUTDIR server_type {
    puts $OUTPUT [format {%s %s} \
	[set oid2name($oid) $F(name)]\
	[set oid2typename($oid) $F(server_type_name)]
    ]
}
atomic_close $OUTPUT

#
# This file is read by the pull daemon on the client side too.
# This code must come after the secondary_ifs code because the 
# host_ip_list routine uses the oid2ip array
# variable which is finished by the secondary_ifs code.
#
set OUTPUT [atomic_open [file join $DUMPDIR server_aliases] $MODE]
loop_subs $INPUTDIR server_alias {
    set hlist $F(primary_server)
    lvarcat hlist $F(secondary_servers)
    set typename $oid2typename($F(server_type))
    set oid2name($oid) [set name $oid2name($F(server_type))]
    set region $F(owner)
    set regionoid($oid) $region
    puts $OUTPUT [format {%s %s %s %s} \
	$name\
	$oid2name($region)\
	$typename\
	[host_ip_list $hlist]
    ]

    ## This code is needed by the mail alias code.
    switch -- $typename {
	mailhost {
	    set mailhost_regions($region) $oid
	}
	mailhub {
	    set mailhub_regions($region) $oid
	}
    }

    ## This code is needed by mail aliases, automounts and sybase interfaces.
    set oid2primary_server($oid) $F(primary_server)
    set oid2server_type($oid) $F(server_type)

    ## This code is needed by the netgroup code.
    foreach o $hlist {
	lappend server_alias2hosts($oid) ([name_of_computer $o 1],-,)
    }
}
atomic_close $OUTPUT
}]
