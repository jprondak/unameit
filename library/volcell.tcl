#
# Copyright (c) 1995, 1996 Enterprise Systems Management Corp.
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
# $Id: volcell.tcl,v 1.5 1996/05/20 19:19:20 viktor Exp $
#

proc create_item {class args} {
    global SYSCALLS
    eval $SYSCALLS(${class}_create) $args
}

set top_cell [unameit_top_cell]

if {[string compare $top_cell ""] == 0} {
    error "Database not initialized"
}

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
	[unameit_qbe server_type name stype_name]]

foreach savar $salist {
    upvar 0 $savar sa
    set sa_type($sa(stype_name)) $sa(uuid)
}

set proto_# 0
foreach proto [unameit_decode_items -result [unameit_qbe host_prototype]] {
    set acmehost([set proto_#]) $proto
    incr proto_#
}

set top_net\
    [unameit_decode_items -result\
	[unameit_qbe inet_net {ipv4_address = 80700000}]]

foreach c [info commands] {
    set __CMDS($c) {}
}

set amap\
    [unameit_decode_items -result\
	[unameit_qbe automount_map\
	    {name = auto_home} [list owner  = $top_cell]]]

for {set i $first_region} {$i <= $last_region} {incr i} {
    puts [time {
	puts -nonewline "Starting region: $i..."
	flush stdout
	create_item region [set region [uuidgen]] \
	    "name acmeregion$i" \
	    "owner $top_cell"
	create_item inet_net [set net [uuidgen]] \
	    "name acmesubnet$i" \
	    "owner $region" \
	    "address 128.112.$i.0" \
	    "last_address 128.112.$i.255" \
	    {mask 255.255.255.0} \
	    "parent $top_net"
	create_item user_group [set group [uuidgen]] \
	    "name grp$i" \
	    gid \
	    "owner $region"
	for {set h 1} {$h < 40} {incr h} {
	    create_item host [set host [uuidgen]] \
		"name host$i-$h" \
		"owner $region" \
		"prototype $acmehost([expr $h % [set proto_#]])" \
		"ifname le0" \
		"macaddr 8:0:20:1:[format %x $i]:[format %x $h]" \
		"parent $net" \
		"address 128.112.$i.$h" \
		{receives_mail 0}
	    if {$h == 1} {
		if {$i == 1} {
		    create_item server_alias [set mh [uuidgen]] \
			[list stype $sa_type(mailhost)] \
			[list owner $top_cell] \
			[list server_host $host]
		    catch {rename $mh {}}
		} elseif {$i % 2 == 0} {
		    create_item server_alias [set mh [uuidgen]] \
			[list stype $sa_type(mailhost)] \
			[list owner $region] \
			[list server_host $host]
		    catch {rename $mh {}}
		}
	    }
	    if {$h == 2} {
		if {$i == 1} {
		    create_item server_alias [set ns [uuidgen]] \
			[list stype $sa_type(dnsserver)] \
			[list owner $top_cell] \
			[list server_host $host]
		    catch {rename $ns {}}
		} elseif {$i % 8 == 0} {
		    create_item server_alias [set ns [uuidgen]] \
			[list stype $sa_type(dnsserver)] \
			[list owner $region] \
			[list server_host $host]
		    catch {rename $ns {}}
		}
	    }
	    if {$h == 3} {
		if {$i == 1} {
		    create_item server_alias [set ph [uuidgen]] \
			[list stype $sa_type(pullserver)] \
			[list owner $top_cell] \
			[list server_host $host]
		    catch {rename $ph {}}
		}
		create_item server_alias [set yp [uuidgen]] \
		    [list stype $sa_type(nisserver)] \
		    [list owner $region] \
		    [list server_host $host]
		    catch {rename $yp {}}
		create_item server_alias [set ph [uuidgen]] \
		    [list stype $sa_type(pullserver)] \
		    [list owner $region] \
		    [list server_host $host]
		catch {rename $ph {}}
	    }
	    set uniq_alpha [translit 0-9 a-j [expr $i * 40 + $h]]
	    create_item person [set person [uuidgen]] \
		"fullname $uniq_alpha" \
		"owner $region"
	    create_item user_login [set ulogin [uuidgen]] \
		"name [format {u%03d%02d} $i $h]"  \
		"owner $region" \
		"password [unameit_crypt [format {p%03d%02d} $i $h]]" \
		uid \
		"primary_group $group" \
		"person $person" \
		"remote_dir /local/0/home/[format {u%03d%02d} $i $h]" \
		{shell /bin/sh} \
		"auto_map $amap" \
		"remote_host $host" \
		{enabled 1} \
		mailhost
	    create_item mailing_list [set mlist [uuidgen]] \
		"name [format {m%03d%02d} $i $h]" \
		"owner $region"
	    unameit_add_members mailing_list ml_login $mlist $ulogin
	    catch {rename $ulogin {}}
	    catch {rename $person {}}
	    catch {rename $host {}}
	    catch {rename $mlist {}}
	}
	catch {rename $region {}}
	catch {rename $net {}}
	catch {rename $group {}}
	#
	# Commit the transaction
	#
	set code [catch unameit_commit commit_result]
	if {$code != 0} {
	    puts $errorInfo
	    puts $errorCode
	    commandloop
	} else {
	    set new_commands_found 0
	    foreach c [info commands] {
		if {[info exists __CMDS($c)]} continue
		set __CMDS($c) {}
		rename $c {}
	    }
	}
    }]
}
