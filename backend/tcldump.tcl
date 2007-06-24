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
# $Id: tcldump.tcl,v 1.17.10.9 1997/10/06 22:00:37 simpson Exp $

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

## Returns the oid of the mail server machine for the region passed in.
proc get_mail_server {region_oid server_alias_type} {
    global DATA_LEVEL

    switch -- $server_alias_type {
	mailhost {
	    upvar $DATA_LEVEL mailhost_regions server mailhost_cache cache
	}
	mailhub {
	    upvar $DATA_LEVEL mailhub_regions server mailhub_cache cache
	}
	default {
	    error "Bad mail server type $server_alias_type"
	}
    }

    if {[info exists cache($region_oid)]} {
	return $cache($region_oid)
    }

    upvar $DATA_LEVEL oid2owner parent

    set oid $region_oid
    while 1 {
	if {[info exists server($oid)]} {
	    set cache($region_oid) $server($oid)
	    break
	}
	switch -- [set oid $parent($oid)] "" {
	    set cache($region_oid) ""
	    break
	}
    }
    set cache($region_oid)
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
    set result {}
    for {set i 0} {[scan $hex %02x d] == 1} {incr i
    set hex [string range $hex 2 end]} {
	if {$i != 0} {
	    set result $result.
	}
	set result ${result}$d
    }
    return $result
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

### Converts an element of a mailing list into the forwarding address
### of that element on the mailing list.
proc to_forward_address {oid {user_oid {}}} {
    global DATA_LEVEL
    upvar $DATA_LEVEL addr_cache cache

    if {[info exists cache($oid)]} {
	return $cache($oid)
    }

    upvar $DATA_LEVEL\
	ISA ISA\
	oid2cname oid2cname\
	regionoid regionoid\
	oid2enabled oid2enabled\
	celloid celloid\
	oid2name oid2name

    if {![info exists ISA(mailing_list_member_object.$oid2cname($oid))]} {
	## Host, must have user_oid != ""
	## Do not cache,  only called once, and result depends on user_oid.
	switch -- $oid2name($user_oid) "" return
	return $oid2name($user_oid)@[name_of_computer $oid 1]
    }

    if {[info exists ISA(user_login.$oid2cname($oid))] ||
	    [info exists ISA(person.$oid2cname($oid))]} {
	## Allow for persons with NULL mailhandles.
	switch -- $oid2name($oid) "" {
	    return [set cache($oid) ""]
	}
	## Disabled users don't get forwarded mail.
	if {!$oid2enabled($oid)} {
	    return [set cache($oid) ""]
	}
	return [set cache($oid)\
		!$oid2name($oid)@$oid2name($celloid($regionoid($oid)))]
    }

    if {[info exists ISA(login.$oid2cname($oid))]} {
	## All other logins are included indirectly
	return [set cache($oid) $oid2name($oid)]
    }

    if {[info exists ISA(external_mail_address.$oid2cname($oid))]} {
	## External mail addresses.
	return [set cache($oid) $oid2name($oid)]
    }

    ## All others: mailing list, file/program mailbox...
    return [set cache($oid) !$oid2name($oid)@$oid2name($regionoid($oid))]
}

proc to_mailhost {oid server_alias} {
    global DATA_LEVEL
    upvar $DATA_LEVEL\
	oid2name oid2name\
	regionoid regionoid

    ## Support empty mailhandles.
    switch -- $oid2name($oid) "" return

    set mailhost\
	[name_of_computer [get_mail_server $regionoid($oid) $server_alias] 1]
    switch -- $mailhost "" {return $oid2name($oid)}
    return $oid2name($oid)@$mailhost
}

proc empty {s} {
    cequal $s ""
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
    # The next line is needed by the DHCP code.
    set regionoid($oid) $region
    set oid2netinfo($oid) [list $F(ipv4_net_start) $F(ipv4_net_end)\
	    $F(ipv4_net_mask)]
    puts $OUTPUT [format {%s %s %s %s %s} \
	    $F(name)\
	    $oid2name($region)\
	    $F(ipv4_net_start)\
	    $F(ipv4_net_end) \
	    $F(ipv4_net_mask)
	]
}
atomic_close $OUTPUT
}]

__diagnostic [unameit_time {
__diagnostic -nonewline "Hosts..."
set CANON_HOSTS_FH [atomic_open [file join $DUMPDIR canon_hosts] $MODE]
loop_subs $INPUTDIR host {
    set oid2name($oid) $F(name)
    set regionoid($oid) [set region $F(owner)]
    set oid2ifname($oid) $F(ifname)
    set oid2ifaddress($oid) $F(ifaddress)
    set oid2ip($oid) [set ip [dotted_quad $F(ipv4_address)]]
    ## Set oid2nip to the IP address on a network specific basis. oid2ip
    ## is the IP address of the primary interface.
    set oid2nip($F(ipv4_network).$oid) $ip
    ## Set oid2macaddr to the mac address for the host on a network by
    ## network basis. A host may be multi-homed, so we include the
    ## network too as an index.
    if {![empty $F(ifaddress)]} {
	set oid2macaddr($F(ipv4_network).$oid) $F(ifaddress)
    }

    ## This is needed by the DHCP code.
    if {![info exists network_host_pair($F(ipv4_network).$oid)]} {
	lappend oid2hosts($F(ipv4_network)) $oid
	set network_host_pair($F(ipv4_network).$oid) 1
	set ips_used($ip) 1
    }

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
    puts $CANON_HOSTS_FH [format {%s|%s|%s|%s|%s|%s|%s|%s} \
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

set OUTPUT [atomic_open [file join $DUMPDIR secondary_ifs] $MODE]
loop_subs $INPUTDIR ipv4_interface {
    if {[cequal $F(ipv4_address)  ""]} continue
    lappend oid2ip($F(owner)) [set ip [dotted_quad $F(ipv4_address)]]
    set regionoid($oid) [set region $regionoid($F(owner))]
    set oid2name($oid) [set hname $oid2name($F(owner))]
    set oid2ifname($oid) $F(ifname)
    set oid2ifaddress($oid) $F(ifaddress)
    ## If the mac address isn't empty and the mac address isn't already set
    ## for this host in oid2macaddr, set it. The only way that the oid2macaddr
    ## array could already be set is if this interface and the primary host
    ## interface are both on the same network (not likely).
    if {![empty $F(ifaddress)] &&
    ![info exists oid2macaddr($F(ipv4_network).$F(owner))]} {
	set oid2macaddr($F(ipv4_network).$F(owner)) $F(ifaddress)
    }
    if {![info exists oid2nip($F(ipv4_network).$F(owner))]} {
	set oid2nip($F(ipv4_network).$F(owner)) $ip
    }

    ## This is needed by the DHCP code.
    set oid2owner($oid) $F(owner)
    if {![info exists network_host_pair($F(ipv4_network).$F(owner))]} {
	lappend oid2hosts($F(ipv4_network)) $F(owner)
	set network_host_pair($F(ipv4_network).$F(owner)) 1
	set ips_used($ip) 1
    }

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
    set owner $F(owner)

    ## This is needed by the DHCP code.
    if {[info exists ISA(ipv4_interface.$oid2cname($owner))]} {
	set hostoid $oid2owner($owner)
    } else {
	set hostoid $owner
    }
    ## Set oid2macaddr for this network if it is not already set. It will
    ## already be set if there is another primary or secondary interface on the
    ## same network.
    if {![empty $oid2ifaddress($owner)] &&
    ![info exists oid2macaddr($F(ipv4_network).$hostoid)]} {
	set oid2macaddr($F(ipv4_network).$hostoid) $oid2ifaddress($owner)
    }
    if {![info exists network_host_pair($F(ipv4_network).$hostoid)]} {
	lappend oid2hosts($F(ipv4_network)) $hostoid
	set network_host_pair($F(ipv4_network).$hostoid) 1
	set ips_used($ip) 1
    }
    if {![info exists oid2nip($F(ipv4_network).$hostoid)]} {
	set oid2nip($F(ipv4_network).$hostoid) $ip
    }
    
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
}
atomic_close $OUTPUT
}]

#
# host consoles
#

__diagnostic [unameit_time {
__diagnostic -nonewline "Terminal servers..."
loop_subs $INPUTDIR terminal_server {
    set tsbase($oid) $F(base_tcp_port)
}

set OUTPUT [atomic_open [file join $DUMPDIR host_console] $MODE]
loop_subs $INPUTDIR host_console {
    set host $F(console_of_host)
    set hostr $oid2name($regionoid($host))
    set ts $F(owner)
    set tsr $oid2name($regionoid($ts))
    puts $OUTPUT [format {%s.%s %s.%s %d %d} \
	$oid2name($host)\
	$hostr\
	$oid2name($ts)\
	$tsr\
	$tsbase($ts)\
	$F(line)\
    ]
}
atomic_close $OUTPUT
}]

#
#-----------------------------------------------------
#

__diagnostic [unameit_time {
__diagnostic -nonewline "Logins..."
set oid2mpoint() ""
set oid2name() ""
loop_subs $INPUTDIR automount_map {
    set oid2name($oid) $F(name)
    set oid2mpoint($oid) $F(mount_point)
}
loop_subs $INPUTDIR person {
    set oid2fullname($oid) $F(fullname)
    set regionoid($oid) $F(owner)

    ## The following is needed by the mail aliases code
    set oid2name($oid) $F(name)
    set oid2phone($oid) $F(person_phone)
    set oid2enabled($oid)\
	[expr {[cequal $F(person_expiration) ""] ||\
	    $F(person_expiration) > $curtime}]
}

loop_subs $INPUTDIR group {
    set oid2name($oid) $F(name)
    set oid2gid($oid) $F(gid)
    set regionoid($oid) $F(owner)
}

#
# Map NULL gids of os_groups as necessary
#
loop_subs $INPUTDIR os_group {
    set oid2name($oid) $F(name)
    set regionoid($oid) $F(owner)
    if {[cequal $F(gid) ""]} {
	set F(gid) $oid2gid($F(base_group))
    }
    set oid2gid($oid) $F(gid)
}

set OUTPUT [atomic_open [file join $DUMPDIR shell_location] $MODE]
loop_subs $INPUTDIR shell_location {
    puts $OUTPUT "$oid2name($F(owner)) $F(shell_name) $F(shell_path)"
}
atomic_close $OUTPUT

#
# /etc/passwd data
# It is important that unix_pathname comes last because it can have a : in
# it (for shared automounts).
#
set OUTPUT [atomic_open [file join $DUMPDIR user_logins] $MODE]
#
# Output user login automount information in same pass as other data.
#
set USER_AUTO [atomic_open [file join $DUMPDIR user_automounts] $MODE]
set REGION_AUTO [atomic_open [file join $DUMPDIR region_automounts] $MODE]

loop_subs $INPUTDIR user_login {
    set oid2name($oid) $F(name)
    set oid2owner($oid) $F(owner)
    lappend LOGINS($F(person)) $oid
    set regionoid($oid) [set region $F(owner)]

    ## This is needed for the domain netgroups.
    lappend region2users($region) (-,$F(name),)

    ## This is needed by the mail aliases code.
    set oid2enabled($oid) $oid2enabled($F(person))

    if {![cequal $F(auto_map) ""]} {
	set ucell $celloid($F(owner))
	set umap $oid2name($F(auto_map))
	set uhost [name_of_computer $F(nfs_server)]
	puts $USER_AUTO\
	    "$F(name) $oid2name($ucell) $umap $uhost $F(unix_pathname)"
	if {![cequal $ucell $F(owner)]} {
	    puts $REGION_AUTO\
		"$F(name) $oid2name($F(owner)) $umap $uhost $F(unix_pathname)"
	}
    }

    set fullname $oid2fullname($F(person))
    if {[regexp {^([^,]*), *(.*)$} $fullname x last_name rest]} {
	## Drop any remaining commas. They break sendmail, finger etc... 
	regsub -all , $rest {} rest
	set fullname "$rest $last_name"
    }
    if {[cequal $F(gecos) ""]} {
	set gecos $fullname
	set phone $oid2phone($F(person))
	if {![cequal $phone ""]} {
	    append gecos ", $phone"
	}
    } else {
	set gecos $F(gecos)
	regsub ^& $gecos $fullname gecos
    }
    puts $OUTPUT [format {%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s} \
	$F(name) \
	$oid2name($celloid($region))\
	$oid2name($region)\
	$F(password) \
	$F(uid) \
	$oid2gid($F(primary_group))\
	$gecos\
	$F(shell)\
	$oid2mpoint($F(auto_map))\
	$oid2name($F(auto_map))\
	$oid2enabled($oid)\
	$F(unix_pathname)
    ]
}
atomic_close $OUTPUT
atomic_close $USER_AUTO

## This variable is only used by the user_login code.
catch {unset oid2phone}

set OUTPUT [atomic_open [file join $DUMPDIR logins] $MODE]
loop_subs $INPUTDIR application_login {
    set regionoid($oid) $F(owner)
    set oid2name($oid) $F(name)
    puts $OUTPUT [format {%s:%s:%s:%s:%s:%s:%s:%s} \
	$F(name)\
	$oid2name($F(owner))\
	$F(password)\
	$F(uid)\
	$oid2gid($F(primary_group))\
	$F(gecos)\
	$F(unix_pathname)\
	$F(shell)
    ]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR system_logins] $MODE]
loop_subs $INPUTDIR system_login {
    set oid2name($oid) $F(name)
    set regionoid($oid) $F(owner)
    foreach f {password uid primary_group gecos unix_pathname} {
	set oid2${f}($oid) $F($f)
    }
    puts $OUTPUT [format {%s:%s:%s:%s:%s:%s:%s:%s:%s} \
	$F(name)\
	$oid2name($F(owner))\
	$F(template_login)\
	$F(password)\
	$F(uid)\
	$oid2gid($F(primary_group))\
	$F(gecos)\
	$F(unix_pathname)\
	$F(shell)
    ]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR os] $MODE]
loop_subs $INPUTDIR os_family {
    set osname($oid) $F(os_name)
    set osrel($oid) $F(os_release_name)
    puts $OUTPUT [format "%s %s"\
	$F(os_name)\
	$F(os_release_name)\
    ]
}
loop_subs $INPUTDIR os {
    set osname($oid) $F(os_name)
    set osrel($oid) $F(os_release_name)
    set fam $F(os_family)
    puts $OUTPUT [format "%s %s %s %s"\
	$F(os_name)\
	$F(os_release_name)\
	$osname($fam)\
	$osrel($fam)\
    ]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR os_logins] $MODE]
loop_subs $INPUTDIR os_login {
    set login $F(base_login)
    set region $F(owner)
    set oid2name($oid) [set name $oid2name($login)]
    set os $F(os_spec)
    foreach f {password uid primary_group gecos unix_pathname} {
	if {[cequal $F($f) ""]} {
	    set F($f) [set oid2${f}($login)]
	}
    }
    puts $OUTPUT [format {%s:%s:%s:%s:%s:%s:%s:%s:%s:%s} \
	$name\
	$oid2name($region)\
	$osname($os)\
	$osrel($os)\
	$F(password)\
	$F(uid)\
	$oid2gid($F(primary_group))\
	$F(gecos)\
	$F(unix_pathname)\
	$F(shell)
    ]
}
atomic_close $OUTPUT
}]

#
# /etc/group data
#
__diagnostic [unameit_time {
__diagnostic -nonewline "Groups..."
loop_subs $INPUTDIR group_member {
    lappend gmembers($F(owner)) $F(gm_login)
}

set OUTPUT [atomic_open [file join $DUMPDIR user_groups] $MODE]
loop_subs $INPUTDIR user_group {
    set region $F(owner)
    set members {}
    if {[info exists gmembers($oid)]} {
	foreach moid $gmembers($oid) {
	    lappend members $oid2name($moid)
	}
    }
    puts $OUTPUT [format {%s:%s:%s:%s:%s}\
	$F(name)\
	$oid2name($celloid($region))\
	$oid2name($region)\
	$F(gid)\
	[join $members ,]
    ]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR groups] $MODE]
loop_subs $INPUTDIR application_group {
    set members {}
    if {[info exists gmembers($oid)]} {
	foreach moid $gmembers($oid) {
	    lappend members $oid2name($moid)
	}
    }
    puts $OUTPUT [format {%s:%s:%s:%s} \
	$F(name)\
	$oid2name($F(owner))\
	$F(gid)\
	[join $members ,]
    ]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR system_groups] $MODE]
loop_subs $INPUTDIR system_group {
    set members {}
    if {[info exists gmembers($oid)]} {
	foreach moid $gmembers($oid) {
	    lappend members $oid2name($moid)
	}
    }
    puts $OUTPUT [format {%s:%s:%s:%s:%s} \
	$F(name)\
	$oid2name($F(owner))\
	$F(template_group)\
	$F(gid)\
	[join $members ,]
    ]
}
atomic_close $OUTPUT

#
# *MUST* use oid2gid($oid) instead of $F(gid),  since the latter
# may be NULL,  in which case oid2gid has the base_group gid.
#
set OUTPUT [atomic_open [file join $DUMPDIR os_groups] $MODE]
loop_subs $INPUTDIR os_group {
    set region $F(owner)
    set os $F(os_spec)
    set members {}
    if {[info exists gmembers($oid)]} {
	foreach moid $gmembers($oid) {
	    lappend members $oid2name($moid)
	}
    }
    puts $OUTPUT [format {%s:%s:%s:%s:%s:%s}\
	$F(name)\
	$oid2name($region)\
	$osname($os)\
	$osrel($os)\
	$oid2gid($oid)\
	[join $members ,]
    ]
}
atomic_close $OUTPUT
}]

#
# /etc/services data.
#

__diagnostic [unameit_time {
__diagnostic -nonewline "Services..."
set OUTPUT [atomic_open [file join $DUMPDIR services] $MODE]
foreach proto {tcp udp} {
    loop_subs $INPUTDIR ${proto}_service_alias {
	lappend aliases($F(owner)) $F(ip_service_name)
    }
    loop_subs $INPUTDIR ${proto}_service {
	set cell $celloid($F(owner))
	if {![info exists aliases($oid)]} {
	    set al ""
	} else {
	    set al $aliases($oid)
	}
	puts $OUTPUT\
	    [format "%s:%s:%s/$proto:%s"\
		$F(ip_service_name)\
		$oid2name($cell)\
		$F(${proto}_port)\
		$al]
    }
    catch {unset aliases}
}
atomic_close $OUTPUT
}]

#
# /etc/netgroup data
#

__diagnostic [unameit_time {
__diagnostic -nonewline "Netgroups..."

foreach class {host_netgroup_member_object user_netgroup_member_object
netgroup} {
    loop_subs $INPUTDIR $class {
	set oid2name($oid) $F(name)
	set regionoid($oid) $F(owner)
    }
}

loop_subs $INPUTDIR netgroup_member {
    set ng_host $F(ng_host)
    set ng_user $F(ng_user)
    set ng_ng $F(ng_ng)

    ## Netgroups
    if {![empty $ng_ng]} {
	lappend ng($F(owner)) $oid2name($ng_ng)@$oid2name($regionoid($ng_ng))
	continue
    }
    
    ## Host regions
    if {![empty $ng_host] && [info exists ISA(region.$oid2cname($ng_host))]} {
	lvarcat ng($F(owner)) $region2hosts($ng_host)
	continue
    }

    ## User regions
    if {![empty $ng_user] && [info exists ISA(region.$oid2cname($ng_user))]} {
	lvarcat ng($F(owner)) $region2users($ng_user)
	continue
    }

    ## Rest
    set tuple "("
    if {![empty $ng_host]} {
	## Use the real host name if it is computed twice so it will be
	## deleted by the lrmdups below.
	append tuple "[name_of_computer $ng_host 1],"
    } else {
	append tuple "-,"
    }
    if {![empty $ng_user]} {
	append tuple "$oid2name($ng_user),)"
    } else {
	append tuple "-,)"
    }
    lappend ng($F(owner)) $tuple
}

set OUTPUT [atomic_open [file join $DUMPDIR netgroups] $MODE]
set ROUTPUT [atomic_open [file join $DUMPDIR region_netgroups] $MODE]

loop_subs $INPUTDIR netgroup {
    puts $ROUTPUT "$oid2name($oid) $oid2name($F(owner))"
    set members ""
    if {[info exists ng($oid)]} {
	set members [lrmdups $ng($oid)]
    }
    puts $OUTPUT [format {%s %s} $F(name)@$oid2name($F(owner)) $members]
}

atomic_close $ROUTPUT
atomic_close $OUTPUT

catch {unset region2hosts}
catch {unset region2users}
catch {unset ROUTPUT}
catch {unset ng}
}]

### Mailing lists

__diagnostic [unameit_time {
__diagnostic -nonewline {Mailing lists...}

set OUTPUT [atomic_open [file join $DUMPDIR mailing_lists] $MODE]
set ROUTPUT [atomic_open [file join $DUMPDIR region_mailing_lists] $MODE]
set COUTPUT [atomic_open [file join $DUMPDIR cell_mailing_lists] $MODE]
set DOUTPUT [atomic_open [file join $DUMPDIR drops] $MODE]
set POUTPUT [atomic_open [file join $DUMPDIR postmaster_lists] $MODE]

loop_subs $INPUTDIR external_mail_address {
    set oid2name($oid) $F(name)
}

foreach class {file_mailbox program_mailbox} {
    if {[cequal $class file_mailbox]} {
	set replacement {\1"\2"}
    } else {
	set replacement {"|\2"}
    }
    loop_subs $INPUTDIR $class {
	set oid2name($oid) $F(name)
	set regionoid($oid) $F(owner)

	regsub -all {\\} $F(unix_pathname) {\\\\} quoted_pathname
	regsub -all {"} $quoted_pathname {\\"} quoted_pathname
	regsub {^(:include:)?(.*)} $quoted_pathname $replacement\
		quoted_pathname

	# Output the drop with list structure so pull will extract it with
	# list structure.
	puts $DOUTPUT "$F(name) $oid2name($F(owner))\
		[name_of_computer $F(mailbox_route) 1]\
		[list $quoted_pathname]"
	puts $ROUTPUT "$F(name) $oid2name($F(owner))"
	puts $OUTPUT "$F(name)@$oid2name($F(owner)):\
		$F(name)@[name_of_computer $F(mailbox_route) 1]"
    }
}
atomic_close $DOUTPUT

## We don't know the contents of the mailing lists until we read 
## mailing_list_members. Keep a record of the mailing lists until
## mailing_list_members is read.
loop_subs $INPUTDIR mailing_list {
    set oid2name($oid) $F(name)
    set regionoid($oid) $F(owner)
    puts $ROUTPUT "$F(name) $oid2name($F(owner))"
}

loop_subs $INPUTDIR mailing_list_member {
    set addr [to_forward_address $F(ml_member)]
    if {![cequal $addr ""]} {
	lappend ml_lines($F(owner)) $addr
    }
}

#
# Try never to send Postmaster mail to /dev/null
#
loop_subs $INPUTDIR mailing_list {
    puts -nonewline $OUTPUT "$F(name)@$oid2name($F(owner)): "
    if {[info exists ml_lines($oid)]} {
	puts $OUTPUT $ml_lines($oid)
    } else {
	puts $OUTPUT /dev/null
    }
    if {![cequal $F(name) postmaster]} continue
    puts -nonewline $POUTPUT "postmaster $oid2name($regionoid($oid)) "
    if {[info exists ml_lines($oid)]} {
	puts $POUTPUT $ml_lines($oid)
	continue
    }
    puts $POUTPUT root
}
atomic_close $POUTPUT

loop_subs $INPUTDIR user_login {
    ## Always output the mailing list so it gets put in the right region file.
    puts $COUTPUT "$oid2name($oid) $oid2name($celloid($regionoid($oid)))"
    
    puts -nonewline $OUTPUT\
	    "$oid2name($oid)@$oid2name($celloid($regionoid($oid))): "

    if {[cequal $F(preferred_mailbox) Person]} {
	set person $F(person)

	switch -- $oid2name($person) "" {
	    ## Empty mailhandle.
	    puts $OUTPUT /dev/null
	    continue
	}
	## Redirect to mailhandle.
	puts $OUTPUT\
	    !$oid2name($person)@$oid2name($celloid($regionoid($person)))
	continue
    }

    set route $F(mailbox_route)

    if {$oid2enabled($oid)} {
	lappend person2uls($F(person)) $oid
	switch -- $route "" {
	    ## Send to default mailhost.
	    puts $OUTPUT [to_mailhost $oid mailhost]
	    continue
	}
	## Send to mailbox_route address.
	# to_forward_address can return the empty string if
	# mailbox_route points to a person with an empty mailhandle.
	switch -- [set addr [to_forward_address $route $oid]] "" {
	    puts $OUTPUT /dev/null
	    continue
	}
	puts $OUTPUT $addr
	continue
    }

    switch -- $route "" {
	## Disabled with default mailhost
	puts $OUTPUT /dev/null
	continue
    }
    set cname $oid2cname($route)
    if {![info exists ISA(mailing_list_member_object.$cname)]} {
	## Disabled with explicit mailhost
	puts $OUTPUT /dev/null
	continue
    }
    lappend person2uls($F(person)) $oid
    if {![info exists ISA(external_mail_address.$cname)]} {
	## Disabled. Set to something besides external address.
	puts $OUTPUT [to_forward_address $route $oid]
	continue
    }
    ## Disabled. mailbox_route is external address.
    ## Sendmail version 8 sends nice message when you
    ## tack .redirect on the end.
    puts $OUTPUT [to_forward_address $route $oid].redirect
}

loop_subs $INPUTDIR person {
    if {[cequal $oid2name($oid) ""]} continue

    ## Always output the mailing list so it gets put in the right region file.
    puts $COUTPUT "$oid2name($oid) $oid2name($celloid($regionoid($oid)))"

    puts -nonewline $OUTPUT\
	    "$oid2name($oid)@$oid2name($celloid($regionoid($oid))): "
    if {[cequal $F(preferred_mailbox) Person]} {
	set route $F(mailbox_route)
	
	if {$oid2enabled($oid)} {
	    ## Enabled and set to "Person". Send mail to mailbox_route.

	    if {[cequal $route ""]} {
		puts $OUTPUT [to_mailhost $oid mailhub]
	    } else {
		# to_forward_address can return an empty string if
		# mailbox_route points to a person with an empty mailhandle.
		set addr [to_forward_address $route $oid]
		if {[cequal $addr ""]} {
		    set addr /dev/null
		}
		puts $OUTPUT $addr
	    }
	} else {
	    if {![cequal $route ""]} {
		if {[info exists\
			ISA(mailing_list_member_object.$oid2cname($route))]} {
		    if {[info exists\
			    ISA(external_mail_address.$oid2cname($route))]} {
			## Disabled. mailbox_route is external address.
			## Sendmail version 8 sends nice message when you
			## tack .redirect on the end.
			puts $OUTPUT [to_forward_address $route $oid].redirect
		    } else {
			## Disabled. Set to something besides external address.
			puts $OUTPUT [to_forward_address $route $oid]
		    }
		} else {
		    ## Disabled. mailbox_route not member object.
		    puts $OUTPUT /dev/null
		}
	    } else {
		## Disabled. mailbox_route not external address.
		puts $OUTPUT /dev/null
	    }
	}
    } else {
	if {[info exists person2uls($oid)]} {
	    set space 0
	    foreach ul_oid $person2uls($oid) {
		if {$space} {
		    puts -nonewline $OUTPUT " "
		}
		puts -nonewline $OUTPUT\
		!$oid2name($ul_oid)@$oid2name($celloid($regionoid($ul_oid)))
		set space 1
	    }
	    puts $OUTPUT ""
	} else {
	    puts $OUTPUT /dev/null
	}
    }
}

loop_subs $INPUTDIR mailbox_alias {
    set owner $F(owner)

    # Skip person's with empty mailhandles
    if {[cequal $oid2name($owner) ""]} continue

    puts $COUTPUT "$F(name) $oid2name($celloid($regionoid($owner)))"

    puts $OUTPUT "$F(name)@$oid2name($celloid($regionoid($owner))):\
	    !$oid2name($owner)@$oid2name($celloid($regionoid($owner)))"
}

atomic_close $OUTPUT
atomic_close $COUTPUT
atomic_close $ROUTPUT

#
# Separate line for each var behaves better for CVS merge.
#
catch {unset ml_lines}
catch {unset person2uls}
catch {unset oid2enabled}
catch {unset DOUTPUT}
catch {unset COUTPUT}
catch {unset ROUTPUT}
catch {unset addr_cache}
catch {unset postmaster_oids}
catch {unset mailing_list_oids}
catch {unset POUTPUT}
}]

### Automounts

__diagnostic [unameit_time {
__diagnostic -nonewline "Automounts..."
set OUTPUT [atomic_open [file join $DUMPDIR automount_map] $MODE]
loop_subs $INPUTDIR automount_map {
    puts $OUTPUT "$F(name) $oid2name($F(owner)) $F(mount_point) $F(mount_opts)"
}
atomic_close $OUTPUT
    
set HOST_AUTO [atomic_open [file join $DUMPDIR host_automounts] $MODE]

loop_subs $INPUTDIR secondary_automount {
    append sec_am($F(owner))\
	" [name_of_computer $F(nfs_server)] $F(unix_pathname)"
}

loop_subs $INPUTDIR automount {
    if {[info exists oid2ip($F(owner))]} {
	set OUTPUT $HOST_AUTO
	set owner [name_of_computer $F(owner)]
    } else {
	set OUTPUT $REGION_AUTO
	set owner $oid2name($F(owner))
    }
    append sec_am($oid) ""
    puts $OUTPUT\
	"$F(name) $owner $oid2name($F(auto_map))\
	    [name_of_computer $F(nfs_server)]\
	    $F(unix_pathname)$sec_am($oid)"
}

atomic_close $HOST_AUTO
atomic_close $REGION_AUTO

catch {unset sec_am}
}]

### Printers
__diagnostic [unameit_time {
__diagnostic -nonewline "Printers..."

set OUTPUT [atomic_open [file join $DUMPDIR printer_type] $MODE]
loop_subs $INPUTDIR bsd_printcap {
    set oid2name($oid) $F(name)
}

loop_subs $INPUTDIR bsd_printer_type {
    set pcap "sd=$F(bsd_printcap_sd):$F(bsd_printcap1)"
    append pcap ":$F(bsd_printcap2):$F(bsd_printcap3)"
    #
    switch -- $F(bsd_printcap_tc) "" {} default {
	append pcap ":tc=$oid2name($F(bsd_printcap_tc))"
    }
    puts $OUTPUT [format {%s:%s:%s}\
	$F(name)\
	$oid2name($celloid($F(owner)))\
	$pcap]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR printers] $MODE]
loop_subs $INPUTDIR bsd_printer {
    set rm [name_of_computer $F(bsd_printer_rm)]
    set rp $oid2name($F(bsd_printer_rp))
    set pcap "sd=$F(bsd_printcap_sd)"
    puts $OUTPUT [format {%s:%s:%s:%s:%s}\
	$F(name)\
	$oid2name($celloid($F(owner)))\
	$rm\
	$rp\
	$pcap]
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR printer_alias] $MODE]
loop_subs $INPUTDIR bsd_printer_alias {
    if {[info exists ISA(host.$oid2cname($F(owner)))]} {
	set type host
	set owner [name_of_computer $F(owner)]
    } else {
	set type region
	set owner $oid2name($F(owner))
    }
    puts $OUTPUT [format {%s:%s:%s:%s}\
	$F(name)\
	$owner\
	$type\
	$oid2name($F(bsd_printer))]
}
atomic_close $OUTPUT
}]

### Pagers
__diagnostic [unameit_time {
__diagnostic -nonewline "Pagers..."
set OUTPUT [atomic_open [file join $DUMPDIR providers] $MODE]
loop_subs $INPUTDIR paging_provider {
    set oid2name($oid) $F(name)
    set oid2owner($oid) $F(owner)
    puts $OUTPUT "$F(name)|$oid2name($F(owner))|$F(provider_data_number)|$F(provider_operator_number)|$F(provider_support_number)"
}
atomic_close $OUTPUT

set OUTPUT [atomic_open [file join $DUMPDIR pagers] $MODE]
loop_subs $INPUTDIR pager {
    if {![cequal $F(pager_person) ""]} {
	if {[cequal $F(pager_pin) ""]} {
	    set pin none
	} else {
	    set pin $F(pager_pin)
	}
	## If a person exists but does not have any logins, LOGINS won't exist.
	if {[info exists LOGINS($F(pager_person))]} {
	    foreach login $LOGINS($F(pager_person)) {
		puts $OUTPUT [format "%s %s %s@%s %s"\
		    $oid2name($login)\
		    $pin\
		    $oid2name($F(pager_provider))\
		    $oid2name($oid2owner($F(pager_provider)))\
		    $F(pager_phone)]
	    }
	}
    }
}
atomic_close $OUTPUT
}]

### Sybase interfaces
__diagnostic [unameit_time {
__diagnostic -nonewline "Sybase interfaces..."
set OUTPUT [atomic_open [file join $DUMPDIR sybase_interface] $MODE]
loop_subs $INPUTDIR sybase_interface {
    ## Get host oid
    if {[info exists ISA(host.$oid2cname($F(sybase_host)))]} {
	set host_oid $F(sybase_host)
    } elseif {[info exists ISA(host_alias.$oid2cname($F(sybase_host)))]} {
	set host_oid $oid2owner($F(sybase_host))
    } else {
	set host_oid $oid2primary_server($F(sybase_host))
    }

    puts $OUTPUT "$F(sybase_name) $oid2name($celloid($F(owner)))\
	    $oid2name($F(owner)) [name_of_computer\
	    $F(sybase_host)]@$oid2hexip($host_oid) $F(tcp_port)"
}
atomic_close $OUTPUT
}]
catch {unset oid2primary_server}

### DHCP ranges
catch {unset network_host_pair}

__diagnostic [unameit_time {
__diagnostic -nonewline "DHCP hosts..."
set NETWORK_FH [atomic_open [file join $DUMPDIR dhcp_networks] $MODE]
set SERVER_ID_FH [atomic_open [file join $DUMPDIR dhcp_server_identifier]\
	$MODE]
set DYNAMIC_FH [atomic_open [file join $DUMPDIR dhcp_dynamic_hosts] $MODE]
set STATIC_FH [atomic_open [file join $DUMPDIR dhcp_static_hosts] $MODE]

#
# To make fake UUIDs for DHCP range elements pad out with 14 leading zeros
# (14 + 8 == 22 == length of radix64 coded UUID).
#
set pad [replicate . 14]

loop_subs $INPUTDIR ipv4_range {
    set dhcp_server [name_of_computer $F(ipv4_range_server)]

    ## Put network in dhcp_networks file if not already there.
    if {![info exists\
	    dhcphost_network_seen($F(ipv4_range_server).$F(owner))]} {
	set dhcphost_network_seen($F(ipv4_range_server).$F(owner)) 1

	lassign $oid2netinfo($F(owner)) start end mask
	puts $NETWORK_FH "$dhcp_server [dotted_quad $start] [dotted_quad $end]\
		[dotted_quad $mask] $oid2name($regionoid($F(owner)))"
    }

    ## Put DHCP server mapping in server id file if not already there.
    if {![info exists host_seen($F(ipv4_range_server))]} {
	puts $SERVER_ID_FH "$dhcp_server $oid2ip($F(ipv4_range_server))"
	set host_seen($F(ipv4_range_server)) 1
    }

    if {[cequal $F(ipv4_range_type) Static]} {
	if {![info exists static_range($F(ipv4_range_server).$F(owner))]} {
	    set static_range($F(ipv4_range_server).$F(owner)) 1
	    
	    ## When processing a static range, put all the hosts on the
	    ## subnet in the DHCP file regardless of whether the host in
	    ## is the range or not. This is easier than seeing if the host
	    ## is in the range and is more efficient. Some hosts will be
	    ## superfluous in the DHCP configuration file, but that is OK.
	    ## They just won't ever ask for their IP address.
	    if {![info exists oid2hosts($F(owner))]} continue
	    foreach host_oid $oid2hosts($F(owner)) {
		if {[info exists oid2macaddr($F(owner).$host_oid)]} {
		    puts $STATIC_FH "$dhcp_server $oid2name($host_oid)\
			    $oid2name($regionoid($host_oid))\
			    $oid2nip($F(owner).$host_oid)\
			    [eval format %s%s:%s%s:%s%s:%s%s:%s%s:%s%s\
			    [split $oid2macaddr($F(owner).$host_oid) {}]]"
		}
	    }
	}
    } else {
	## Output range to dhcp_dynamic_ranges file.
	lassign $oid2netinfo($F(owner)) start end mask
	puts $DYNAMIC_FH "$dhcp_server [dotted_quad $start]\
		[dotted_quad $mask] [dotted_quad $F(ipv4_range_start)]\
		[dotted_quad $F(ipv4_range_end)] $F(ipv4_lease_length)"
	
	## Foreach address in the dynamic range, make up a host name and add it
	## to the canon_hosts file.
	if {[empty $F(ipv4_range_prefix)]} {
	    set prefix dhcp
	} else {
	    set prefix $F(ipv4_range_prefix)
	}
	set addr $F(ipv4_range_start)
	while {[string compare $addr $F(ipv4_range_end)] <= 0} {
	    set ip [dotted_quad $addr]
	    if {![info exists ips_used($ip)]} {
		regsub -all {\.} $ip - dash_addr
		puts $CANON_HOSTS_FH [format {%s|%s|%s|%s|%s|%s|%s|%s} \
			"$pad$ip"\
			$ip\
			$prefix-$dash_addr\
			$oid2name($celloid($regionoid($F(owner))))\
			$oid2name($regionoid($F(owner)))\
			""\
			""\
			No
		]
	    }
	    set addr [unameit_address_increment $addr]
	}
    }
}	    
atomic_close $STATIC_FH
atomic_close $DYNAMIC_FH
atomic_close $CANON_HOSTS_FH
atomic_close $NETWORK_FH
atomic_close $SERVER_ID_FH

foreach var {dhcp_server dhcphost_network_seen oid2netinfo oid2hosts
oid2macaddr dash_addr ips_used oid2nip oid2ifaddress host_seen static_range} {
    catch {unset $var}
}
}]
