#
# Copyright (c) 1995, 1997 Enterprise Systems Management Corp.
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
# $Id: voltest.tcl,v 1.10.58.1 1997/10/04 23:12:29 viktor Exp $
#

set tcn $env(UNAMEIT_CELL)

set top_cell\
    [unameit_decode_items -result\
	[unameit_qbe cell [list name = $tcn]]]

if {[info exists env(FIRST_REGION)]} {
   set first_region $env(FIRST_REGION)
} else {
   set first_region 1
}
if {[info exists env(LAST_REGION)]} {
   set last_region $env(LAST_REGION)
} else {
   set last_region 254
}

set salist\
    [unameit_decode_items -result\
	[unameit_qbe server_type name server_type_name]]

set machinelist\
    [unameit_decode_items -result [unameit_qbe machine]]

set oslist\
    [unameit_decode_items -result [unameit_qbe os]]

foreach sa $salist {
    upvar 0 $sa sa_item
    set sa_type($sa_item(server_type_name)) $sa
}

set type 0
foreach machine $machinelist {
    foreach os $oslist {
	set mos($type) [list $machine $os]
	incr type
    }
}

set top_net\
    [unameit_decode_items -result\
	[unameit_qbe ipv4_network {ipv4_net_start = 80700000}]]

set cell_# [expr ($first_region - 1)/16]

if {[expr $first_region % 16] != 1} {
    incr cell_#
    set cell\
	[unameit_decode_items -result\
	    [unameit_qbe cell [list name = "acmecell${cell_#}.$tcn"]]]
    set cn "acmecell${cell_#}.$tcn"
    set amap\
	[unameit_decode_items -result\
	    [unameit_qbe automount_map {name = auto_home} [list owner = $cell]]]
}

for {set i $first_region} {$i <= $last_region} {incr i} {
    puts "[lindex [time {
	puts -nonewline "Starting region: $i..."
	flush stdout
	if {[expr $i % 16] == 1} {
	    set cn "acmecell[incr cell_#].$tcn"
	    unameit_create cell [set cell [uuidgen]] name $cn
	    unameit_create automount_map [set amap [uuidgen]] \
		name auto_home\
		owner $cell\
		mount_point /home\
		mount_opts "-rw,hard,intr"
	}
	set rn "acmeregion$i.$cn"
	unameit_create region [set region [uuidgen]] name $rn
	unameit_create ipv4_network [set net [uuidgen]] \
	    name "acmesubnet$i" \
	    owner $region\
	    ipv4_net_start 128.112.$i.0 \
	    ipv4_net_bits 24\
	    ipv4_net_mask 255.255.255.0\
	    ipv4_net_type Fixed
	unameit_create user_group [set group [uuidgen]] \
	    name "grp$i" \
	    gid ""\
	    owner $region
	for {set h 1} {$h < 40} {incr h} {
	    lassign $mos([expr $h % $type]) machine os
	    unameit_create computer [set host [uuidgen]] \
		name "host$i-$h" \
		owner $region \
		machine $machine\
		os $os\
		ifname ""\
		ifaddress "8:0:20:1:[format %x $i]:[format %x $h]"\
		ipv4_network $net\
		ipv4_address "128.112.$i.$h"\
		receives_mail No
	    if {$h == 1} {
		if {$i % 16 == 1} {
		    if {$i == 1} {set owner $top_cell} else {set owner $cell}
		    unameit_create server_alias [set mh [uuidgen]] \
			server_type $sa_type(mailhost) \
			owner $owner \
			primary_server $host
		} elseif {$i % 2 == 0} {
		    unameit_create server_alias [set mh [uuidgen]] \
			server_type $sa_type(mailhost) \
			owner $region \
			primary_server $host
		}
	    } elseif {$h == 2} {
		if {$i % 32 == 1} {
		    if {$i == 1} {set owner $top_cell} else {set owner $cell}
		    unameit_create server_alias [set ns [uuidgen]] \
			server_type $sa_type(dnsserver) \
			owner $owner \
			primary_server $host
		} elseif {$i % 8 == 0} {
		    unameit_create server_alias [set ns [uuidgen]] \
			server_type $sa_type(dnsserver) \
			owner $region \
			primary_server $host
		}
	    } elseif {$h == 3} {
		if {$i == 1} {
		    unameit_create server_alias [set ph [uuidgen]] \
			server_type $sa_type(pullserver) \
			owner $top_cell \
			primary_server $host
		}
		if {$i % 16 == 1} {
		    unameit_create server_alias [set ph [uuidgen]] \
			server_type $sa_type(pullserver) \
			owner $cell \
			primary_server $host
		}
		unameit_create server_alias [set yp [uuidgen]] \
		    server_type $sa_type(nisserver) \
		    owner $region \
		    primary_server $host
		unameit_create server_alias [set ph [uuidgen]] \
		    server_type $sa_type(pullserver) \
		    owner $region \
		    primary_server $host
	    }
	    set uniq_alpha [translit 0-9 a-j [expr $i * 40 + $h]]
	    unameit_create person [set person [uuidgen]] \
		fullname "$uniq_alpha" \
		name "p$uniq_alpha"\
		owner $region\
		preferred_mailbox Account
	    unameit_create user_login [set ulogin [uuidgen]] \
		name "[format {u%03d%02d} $i $h]"  \
		owner $region \
		password "[unameit_crypt [format {p%03d%02d} $i $h]]" \
		uid ""\
		primary_group $group \
		person $person \
		unix_pathname "/local/0/home/[format {u%03d%02d} $i $h]" \
		shell sh\
		auto_map $amap\
		nfs_server $host\
		preferred_mailbox Account
	    unameit_create mailing_list [set mlist [uuidgen]] \
		name "[format {m%03d%02d} $i $h]" \
		owner $region
	}
	#
	# Commit the transaction
	#
	set commit_time [time {
	    if {[catch unameit_commit commit_result]} {
		puts $errorInfo
		puts $errorCode
		puts $commit_result
		commandloop
	    }
	    if {$i % 16 == 0} {
		unameit_relogin
	    }
	}]
    }] 0] ([lindex $commit_time 0])"
    unameit_abort
}
