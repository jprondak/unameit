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
# $Id: pull_main_dns.tcl,v 1.3.4.1 1997/08/28 18:25:29 viktor Exp $

set DBM_MAX 850		;# Should be somewhat less than DBM's 1024

proc is_global_pull_server {} {
    global UNAMEIT_DATA VERSION

    #
    # Local path list for this checkpoint.  May not (yet) exist.
    #
    set path_list [file join $UNAMEIT_DATA data gen.$VERSION path_list]

    #
    # If exists and is empty,  we are the global pull server.
    #
    cequal "[catch {file size $path_list} size].$size" 0.0
}

proc over_threshold {new old percentage} {
    #
    if {![file exists $old]} {
	return 0
    }
    #
    set lines1 0
    set chars1 0
    for_file line $new {
	incr lines1
	incr chars1 [clength $line]
    }
    #
    set lines2 0
    set chars2 0
    for_file line $old {
	incr lines2
	incr chars2 [clength $line]
    }
    #
    # Protect against files shrinking.
    # Growth is too common to be fussy about.
    #
    expr {
	($lines2 - $lines1) / double($lines2 + 1) * 100 > $percentage ||
	($chars2 - $chars1) / double($chars2 + 1) * 100 > $percentage
    }
}

# This routine does some post system installation cleanup. It may delete
# old versions of files, etc.
proc post_process_move {type {region ""}} {
    global CONFIG MOVE_LIST VERSION INSTALL_DIRS DELAYED_DELETE_DIRS

    switch -exact $CONFIG(${type}_install_type) {
	safe {
	    if {[cequal $region ""]} {
		set dir [file dirname $INSTALL_DIRS($type)]
	    } else {
		set dir [file dirname $INSTALL_DIRS(nis.$region)]
	    }
	    file delete -force -- [file join $dir old]
	    if {[file exists [file join $dir current]]} {
		file rename [file join $dir current] [file join $dir old]
	    }
	    file rename [file join $dir new] [file join $dir current]
	}
	unsafe {
	    foreach entry $MOVE_LIST {
		file delete -- $entry.old
		catch {link $entry $entry.old}
	    }
	    foreach entry $MOVE_LIST {
		set tail [file tail $entry]

		file rename -force -- $entry.new $entry
	    }
	}
    }
}

proc etc_file_to_dir {file} {
    global INET_DIR

    switch -exact $file {
	hosts -
	netmasks -
	networks {
	    return $INET_DIR
	}
	default {
	    return /etc
	}
    }
}

proc move_file_to_system {type file {region ""} {copied_from_etc 0}} {
    global MOVE_LIST INSTALL_DIRS CONFIG OLD_VERSION USE_PLUSES

    if {![file exists $file]} {
	return
    }
    set tail [file tail $file]
    if {[cequal $region ""]} {
	if {[cequal $type etc]} {
	    set new_file [etc_file_to_dir $tail]/$tail
	} else {
	    set new_file $INSTALL_DIRS($type)/$tail
	}
    } else {
	set new_file $INSTALL_DIRS($type.$region)/$tail
    }
    set threshold $CONFIG(${type}_threshold)
    if {!$copied_from_etc && $threshold != -1} {
	switch -exact $CONFIG(${type}_install_type) {
	    safe {
		set push [list current $tail]
	    }
	    unsafe {
		set push {}
	    }
	}
	if {![lempty $push]} {
	    set elems [file split $new_file]
	    set nelems [llength $elems]
	    set chop [expr {[llength $elems] - [llength $push]}]
	    set old_file [eval file join [lreplace $elems $chop end] $push]
	} else {
	    set old_file $new_file
	}
	if {[over_threshold $file $old_file $threshold]} {
	    error "Cannot install $file because it shrank > $threshold%"
	}
    }
    lappend MOVE_LIST $new_file
    if {[cequal $CONFIG(${type}_install_type) unsafe]} {
	set new_file $new_file.new
    }
    set var_fd [open $file r]
    set mode 0444
    set system_fd [atomic_open $new_file $mode]
    if {[cequal $type dns] && [cequal $tail named.boot]} {
	while {[gets $var_fd line] != -1} {
	    if {[regexp {^directory +[^ ]+$} $line]} {
		if {[cequal $CONFIG(dns_install_type) safe]} {
		    puts $system_fd "directory\
			    [file dirname [file dirname $new_file]]/current"
		} else {
		    puts $system_fd "directory [file dirname $new_file]"
		}
	    } else {
		puts $system_fd $line
	    }
	}
    } else {
	copyfile $var_fd $system_fd
    }
    close $var_fd
    atomic_close $system_fd
}

proc install_files_to_system {install_which_files} {
    global CONFIG FILE_LIST MOVE_LIST INSTALL_DIRS
    global UNAMEIT_DATA VERSION

    if {[cequal $install_which_files none]} return
    set list dns
    if {[cequal $install_which_files all]} {
	lappend list etc
    }
    foreach type $list {
	if {[cequal $CONFIG(${type}_install_type) none]} {
	    continue
	}
	switch -- $type {
	    etc {
		if {![info exists INSTALL_DIRS(etc)]} {
		    continue
		}
		# MOVE_LIST is used to move "a.new" to "a" when we are all
		# done installing the files to the system.
		set MOVE_LIST {}
		foreach entry $FILE_LIST($type) {
		    if {![info exists CONFIG(install_etc_files)] ||
			    [lsearch -exact $CONFIG(install_etc_files) \
				[file tail $entry]] > -1} {
			move_file_to_system $type $entry
		    }
		}
		# The post_process_move routine moves a.new to a, or
		# "current" to "old" and "new" to "current", etc.
		post_process_move $type
		continue
	    }
	    dns {
		if {![info exists INSTALL_DIRS($type)]} {
		    continue
		}
		set MOVE_LIST {}
		foreach entry $FILE_LIST($type) {
		    move_file_to_system $type $entry
		}
		post_process_move $type
		continue
	    }
	}
    }
}

proc convert_to_boolean {val} {
    set val [string tolower $val]
    switch -exact $val {
	true -
	yes -
	on -
	t -
	y -
	1 {
	    return 1
	}
	false -
	no -
	off -
	f -
	n -
	0 {
	    return 0
	}
	default {
	    error "Invalid boolean $val"
	}
    }
}

proc process_configuration {} {
    global CONFIG UNAMEIT_DATA

    # Any settings here are not canonicalized by the code below so they are
    # canonicalized manually here.
    set CONFIG(dns_dir) /var/named
    set CONFIG(dns_install_type) none
    set CONFIG(dns_threshold) -1

    set CONFIG(etc_dir) /etc			;# Can't change
    set CONFIG(etc_install_type) none
    set CONFIG(etc_threshold) -1

    set CONFIG(full_host_first)	0

    unameit_getconfig c upull
    unameit_configure_app c appConfig

    # Process the parameters that we know about, ignoring the others.
    foreach {key value} [array get appConfig] {
	switch -- $key {
	    etc_install_type {
		switch -- $value {
		    unsafe -
		    none {
		    }
		    default {
			error "Illegal value $value for $key in configuration\
				file"
		    }
		}
		set CONFIG($key) $value
	    }

	    dns_install_type {
		switch -- $value {
		    safe -
		    unsafe -
		    none {
		    }
		    default {
			error "Illegal value $value for $key in configuration\
				file"
		    }
		}
		set CONFIG($key) $value
	    }

	    full_host_first {
		if {[catch {convert_to_boolean $value} msg]} {
		    error "Illegal boolean value \"$value\" for $key in\
			    configuration file"
		} else {
		    set value $msg
		}
		set CONFIG($key) $value
	    }

	    dns_threshold {
		if {![regexp {[0-9]+%?} $value] && ![cequal $value -1]} {
		    error "Invalid percentile \"$value\" for $key in\
			    configuration file"
		}
		regsub % $value "" value
		set CONFIG($key) $value
	    }
	    
	    dns_dir -
	    install_etc_files {
		set CONFIG($key) $value
	    }
	}
    }
}

proc create_system_directories {install_which_files} {
    global NIS_REGIONS DNS_REGIONS UNAMEIT_DATA VERSION CONFIG INSTALL_DIRS

    if {[cequal $install_which_files none]} return
    set list dns
    if {[cequal $install_which_files all]} {
	lappend list etc
    }
    foreach type $list {
	if {[cequal $type dns] && [array size DNS_REGIONS] == 0} {
	    continue
	}
	set install_type $CONFIG(${type}_install_type)
	switch -exact $install_type {
	    safe {
		set INSTALL_DIRS($type) $CONFIG(${type}_dir)/new
		make_directories $INSTALL_DIRS($type)
	    }
	    unsafe {
		set INSTALL_DIRS($type) $CONFIG(${type}_dir)
		make_directories $INSTALL_DIRS($type)
	    }
	    none {
		set INSTALL_DIRS($type) $UNAMEIT_DATA/$VERSION/$type
		make_directories $INSTALL_DIRS($type)
	    }
	}
    }
}

proc check_version_info {} {
    global VERSION UNAMEIT_DATA OLD_VERSION

    if {$VERSION == -1} {
	error "Pull server hasn't any pull data files yet."
    }
    if {[catch {open $UNAMEIT_DATA/version r} fd] == 0} {
	if {[gets $fd line] == -1} {
	    error "$UNAMEIT_DATA/version file is empty"
	}
	scan $line "%s" OLD_VERSION
	close $fd
    } else {
	set OLD_VERSION ""
    }
    if {![cequal $OLD_VERSION ""] &&
    [compare_versions $VERSION $OLD_VERSION] >= 0} {
	if {[compare_versions $VERSION $OLD_VERSION] > 0} {
	    error "Pull server version\
		is $VERSION and local version is $OLD_VERSION"
	}
	puts done.
	exit 0
    }
}

proc compare_versions {a b} {
    set split_a [split $a .]
    set split_b [split $b .]
    lassign $split_a a_major a_minor a_trans
    lassign $split_b b_major b_minor b_trans
    if {$a_major > $b_major} {
	return -1
    } elseif {$a_major < $b_major} {
	return 1
    }
    if {$a_minor > $b_minor} {
	return -1
    } elseif {$a_minor < $b_minor} {
	return 1
    }
    if {$a_trans > $b_trans} {
	return -1
    } elseif {$a_trans < $b_trans} {
	return 1
    }
    return 0
}

proc verify_host_and_ip {host ip} {
    global INSTALL_FILES HOST_NAME

    set error 0
    if {[info exists HOST_NAME]} {
	set h $HOST_NAME
    } else {
	set h [id host]
    }
    if {[string match *.* $h]} {
	if {![cequal $h $host]} {
	    puts stderr "UName*It thinks this host is $host but host\
		    name is $h"
	    set error 1
	}
    } else {
	lassign [split $host .] short_host
	if {![cequal $h $short_host]} {
	    puts stderr "UName*It thinks this host is $short_host but\
		    host name is $h"
	    set error 1
	}
    }
    if {[lsearch -exact [get_ip_addrs] $ip] == -1} {
	puts stderr "Host IP returned by UName*It ($ip) doesn't match\
		any of this host's IP addresses ([get_ip_addrs])"
	set error 1
    }
    if {$error} {
	set INSTALL_FILES none
	puts stderr "Not installing files to system"
    }
}

proc truncate_path_element {region} {
    regsub {^[^.]*\.} $region "" region
    if {![regexp {\.} $region]} {
	return .
    } else {
	return $region
    }
}

proc read_regions_file {} {
    global VERSION UNAMEIT_DATA ORG_OID ORG_OID_2_CELLS TREE PARENT

    unameit_cp gen.$VERSION/regions $UNAMEIT_DATA/tmp/regions
    for_file line $UNAMEIT_DATA/tmp/regions {
	set count [scan $line {%s %s %s %s %s} oid region parent_oid\
		wildcard_mx org_oid]
	set regions($region) 1
	set oid2region($oid) $region
	set region2parentoid($region) $parent_oid
	if {4 < $count} {
	    set ORG_OID($region) $org_oid
	    lappend ORG_OID_2_CELLS($org_oid) $region
	}
    }

    ## Build in memory tree.
    foreach region [lsort -command breadth_first [array names regions]] {
	## Initialize variable. Since we are processing in breadth first
	## order, it won't exist.
	set TREE($region) ""

	## Compute the parent of the node. The root is its own parent.
	if {[cequal $region .]} {
	    set PARENT(.) .
	    continue		;# Skip adding to child list below.
	} else {
	    set PARENT($region) $oid2region($region2parentoid($region))
	}

	## Append to parent's child list
	lappend TREE($PARENT($region)) $region
    }

    file delete -- [file join $UNAMEIT_DATA tmp regions]
}

proc process_server_aliases {} {
    global VERSION UNAMEIT_DATA MY_CNAME MY_NAME
    global DNS_SERVERS PULL_SERVERS
    global DNS_REGIONS PULL_REGIONS
    global REGION

    unameit_cp gen.$VERSION/server_aliases $UNAMEIT_DATA/tmp/server_aliases

    for_file line $UNAMEIT_DATA/tmp/server_aliases {
	set replicas [lassign $line alias alias_scope stype]
	set i 0
	foreach chunk $replicas {
	    lassign [split $chunk @] host scope owner ips
	    switch -exact $stype {
		dnsserver {
		    lappend DNS_SERVERS($alias_scope) [split $ips ,]
		}
		pullserver {lappend PULL_SERVERS($alias_scope) $host.$owner}
	    }
	    if {[cequal $host.$owner $MY_CNAME]} {
		if {$i == 0} {
		    set MY_NAME($alias.$alias_scope) 1
		}
		switch -- $stype {
		    dnsserver {
			if {$i == 0 || [cequal $alias_scope .]} {
			    set DNS_REGIONS(primary@$alias_scope) 1
			} else {
			    set DNS_REGIONS(secondary@$alias_scope) 1
			}
		    }
		    pullserver {
			if {$i == 0} {
			    set PULL_REGIONS(primary@$alias_scope) 1
			} else {
			    set PULL_REGIONS(secondary@$alias_scope) 1
			}
		    }
		}
	    }
	    incr i
	}
    }
    file delete -- [file join $UNAMEIT_DATA tmp server_aliases]
}

proc region_compare {a b} {
    global SORT_REGION

    if {![info exists SORT_REGION]} {
	error "SORT_REGION does not exist"
    }
    if {[cequal $a $b]} {
	return 0
    }
    set a_in_path [regexp [esc_str $a]\$ $SORT_REGION]
    set b_in_path [regexp [esc_str $b]\$ $SORT_REGION]
    if {$a_in_path != $b_in_path} {
	return [expr $a_in_path ? -1 : 1]
    } else {
	set a_split [split $a .]
	set b_split [split $b .]
	while {1} {
	    set a_last [expr [llength $a_split] - 1]
	    set b_last [expr [llength $b_split] - 1]
	    set a_str [lindex $a_split $a_last]
	    set b_str [lindex $b_split $b_last]
	    if {[string compare $a_str $b_str] != 0} {
		return [string compare $b_str $a_str]
	    }
	    set a_split [lreplace $a_split $a_last $a_last]
	    set b_split [lreplace $b_split $b_last $b_last]
	}
    }
}

### Breadth first region comparison function.
proc breadth_first {a b} {
    if {[cequal $a .]} {
	return -1
    }
    if {[cequal $b .]} {
	return 1
    }

    set a_split [split $a .]
    set b_split [split $b .]

    set a_len [llength $a_split]
    set b_len [llength $b_split]

    if {$a_len != $b_len} {
	if {$a_len > $b_len} {
	    return 1
	} else {
	    return -1
	}
    }

    set a_part [lindex $a_split 0]
    set b_part [lindex $b_split 0]
    if {![cequal $a_part $b_part]} {
	return [string compare $a_part $b_part]
    } else {
	return [breadth_first [join [lrange $a_split 1 end] .]\
		[join [lrange $b_split 1 end] .]]
    }
}

### Given a region, this routine returns the cell and the organization
### oid for that region.
proc get_cell_and_oid {region} {
    global ORG_OID PARENT REGION2CELL_OID_CACHE

    if {[info exists REGION2CELL_OID_CACHE($region)]} {
	return $REGION2CELL_OID_CACHE($region)
    }

    while {![info exists ORG_OID($region)]} {
	set region $PARENT($region)
    }

    return [set REGION2CELL_OID_CACHE($region)\
	    [list $region $ORG_OID($region)]]
}

### This routine returns a list of regions up the tree. If "type" is a region
### name, then all the regions up to but not including "type" are returned.
### This is useful for /etc files. If type is "cell", then all the regions
### up to and including the cell are returned. This is useful for certain
### types of NIS files. If type is "all", then all the regions up to the
### cell and any regions below the cell that are not cells themselves are
### returned. This is useful for NIS files also.
proc get_up_regions {start type {prefix ""}} {
    global GEN_FILES REGIONS ORG_OID TREE PARENT

    ## Grab all regions up to the termination point.
    if {[cequal $type all] || [cequal $type cell]} {
	set up_to_cell 1
    } else {
	set up_to_cell 0
    }
    set result {}
    for {set current $start}\
	    {$up_to_cell ? ![info exists ORG_OID($current)] :\
	    ![cequal $current $type]}\
	    {set current $PARENT($current)} {
	lappend result $current
	set seen($current) 1
    }
    ## If we are going up to the cell, we include it. If the user passed
    ## in a region, we don't include it.
    if {$up_to_cell} {
	lappend result $current
	set seen($current) 1
	set cell $current
    }
	
    ## Grab regions on side of tree
    if {[cequal $type all]} {
	set working_set $TREE($cell)
	while {![lempty [set region [lvarpop working_set]]]} {
	    ## Skip over cells
	    if {[info exists ORG_OID($region)]} continue

	    ## Skip over the subtree we just went up.
	    if {[info exists seen($region)]} continue

	    lappend result $region
	    lvarcat working_set $TREE($region)
	}
    }
    
    ## Elide results if the user doesn't want them all.
    if {[cequal $prefix ""]} {
	return $result
    } else {
	set l {}
	foreach region $result {
	    if {[info exists GEN_FILES($prefix.region.$region)]} {
		lappend l $region
	    }
	}
	return $l
    }
}

### This routine gets all the regions within an organization. It calls
### get_up_regions multiple times.
proc get_org_regions {start {prefix ""}} {
    global ORG_OID_2_CELLS

    lassign [get_cell_and_oid $start] cell org_oid
    set result [get_up_regions $start all $prefix]

    foreach c $ORG_OID_2_CELLS($org_oid) {
	if {[cequal $cell $c]} continue
	lvarcat result [get_up_regions $c all $prefix]
    }

    set result
}

#
# This routine gets all the regions below and including a specific region,
# somewhat breadth first.
#
proc get_down_regions {start {prefix ""}} {
    global TREE GEN_FILES

    set result {}
    set working_set $start
    while {![lempty [set region [lvarpop working_set]]]} {
	lappend result $region
	lvarcat working_set $TREE($region)
    }

    ## Elide results if the user doesn't want them all.
    if {[cequal $prefix ""]} {
	return $result
    } else {
	set l {}
	foreach region $result {
	    if {[info exists GEN_FILES($prefix.region.$region)]} {
		lappend l $region
	    }
	}
	return $l
    }
}

proc esc_str {str} {
    set result ""
    set count 0
    set str_length [string length $str]
    while {$count < $str_length} {
	set c [csubstr $str $count 1]
	if {[ctype alnum $c]} {
	    set result $result$c
	} else {
	    set result $result\\$c
	}
	incr count
    }
    return $result
}

proc make_directories {args} {
    eval file mkdir $args
}

proc interpret_domain_name {} {
    global DOMAIN_NAME INSTALL_FILES REGION

    switch -- $DOMAIN_NAME {
	"" -
	noname {
	    unset DOMAIN_NAME
	    return
	}
    }
    if {![cequal $DOMAIN_NAME $REGION]} {
	puts stderr "Domain name and region returned by pull\
		server ($REGION) are not equal"
	puts stderr "Not installing files to system"
	set DOMAIN_NAME $REGION
	set INSTALL_FILES none
    }
}


proc get_pull_files {} {
    global PULL_REGIONS GEN_FILES VERSION UNAMEIT_DATA

    puts "Transferring pull server files..."

    set gv_fd [atomic_open [file join $UNAMEIT_DATA data gen.version] 0444]
    puts $gv_fd $VERSION

    make_directories [file join $UNAMEIT_DATA data gen.$VERSION]

    unameit_cp pull_main.tcl [file join $UNAMEIT_DATA data pull_main.tcl] 1

    foreach file [array names GEN_FILES] {
	unameit_cp gen.$VERSION/$file $UNAMEIT_DATA/data/gen.$VERSION/$file 1
    }

    set pl_r_fd [open $UNAMEIT_DATA/data/gen.$VERSION/path_list r]
    set pl_w_fd [atomic_open $UNAMEIT_DATA/data/gen.$VERSION/path_list 0444]

    while {[gets $pl_r_fd line] != -1} {
	puts $pl_w_fd $line
    }
    puts $pl_w_fd [unameit_send unameit_get_uuid]

    close $pl_r_fd
    atomic_close $pl_w_fd
    atomic_close $gv_fd
}

proc set_mapping_array {file {delimiter :}} {
    global UNAMEIT_DATA VERSION
    upvar seen seen mapping mapping

    unameit_cp [file join gen.$VERSION $file]\
	    [set local_file [file join $UNAMEIT_DATA tmp $file]]

    set fh [open $local_file r]
    while {[gets $fh line] != -1} {
	set fullname [ctoken line $delimiter]
	lassign [split $fullname @] name ext
	if {![info exists seen($name)]} {
	    set seen($name) 1
	    set mapping($fullname) 1
	}
    }
    close $fh

    file delete -- $local_file
}

proc get_dns_server_region {region} {
    global DNS_SERVERS PARENT

    set r $region
    while 1 {
	if {[info exists DNS_SERVERS($r)]} {
	    return $r
	}
	set r $PARENT($r)
	if {[cequal $r .]} break
    }
    if {[info exists DNS_SERVERS(.)]} {
	return .
    } else {
	error "No DNS server for $region"
    }
}

proc get_network_dns_region {network} {
    upvar net_dns_region net_dns_region

    set saved_network $network
    while {![cequal $network ""]} {
	if {[info exists net_dns_region($network)]} {
	    return $net_dns_region($network)
	}
	regsub {\.?[^.]*$} $network {} network
    }
    error "Cannot find region for network $saved_network"
}

proc reverse_ip {ip} {
    set split_ip [split $ip .]
    set len [llength $split_ip]
    set result {}
    for {set i [expr $len - 1]} {$i >= 0} {incr i -1} {
	lappend result [lindex $split_ip $i]
    }
    return [join $result .]
}

proc hex_to_dotted {addr} {
    for {set i 0; set result ""} \
	    {[regexp {^[0-9a-fA-F][0-9a-fA-F]} $addr hex_byte]} \
	    {incr i; set addr [string range $addr 2 end]} {
	if {$i} {
	    append result .
	}
	append result [format "%u" 0x$hex_byte]
    }
    set result
}

array set COMMON_BIT_TABLE {
0f 0
07 1 8f 1
03 2 47 2 8b 2 cf 2
01 3 23 3 45 3 67 3 89 3 ab 3 cd 3 ef 3}

# Takes a start and end address and returns the number of common bits
# in the network. The starting and ending addresses must be hex.
proc count_matching_bits {start end} {
    global COMMON_BIT_TABLE

    set start [string tolower $start]
    set end [string tolower $end]
    for {set bits 0; set i 0} {$i < 8} {incr i} {
	set s_char [string index $start $i]
	set e_char [string index $end $i]
	if {![cequal $s_char $e_char]} {
	    return [expr $bits+$COMMON_BIT_TABLE($s_char$e_char)]
	}
	incr bits 4
    }
    return $bits
}

# Takes a network in dotted quad and trims it according the number of common
# bits.
proc trim_net_via_common_bits {net common_bits} {
    set list [split $net .]
    set last_index [expr int(($common_bits-1)/8)]
    return [join [lrange $list 0 $last_index] .]
}

proc read_networks {} {
    global VERSION UNAMEIT_DATA
    upvar net_dns_region net_dns_region

    set net_dns_region() 1; unset net_dns_region()
    unameit_cp gen.$VERSION/dump_networks $UNAMEIT_DATA/tmp/networks
    set fd [open $UNAMEIT_DATA/tmp/networks r]
    while {[gets $fd line] != -1} {
	lassign $line name owner start end
	switch -- $name {
	    multicast -
	    universe -
	    loopback continue
	}
	set dotted_start [hex_to_dotted $start]
	set dotted_end [hex_to_dotted $end]
	set canon_net [trim_net_via_common_bits $dotted_start \
		[count_matching_bits $start $end]]
	set net_dns_region($canon_net) [get_dns_server_region $owner]
    }
    close $fd
    file delete -- [file join $UNAMEIT_DATA tmp networks]
}

proc process_inaddr {} {
    global DNS_REGIONS GEN_FILES BOOT_FD VERSION IS_PULL_SERVER
    global UNAMEIT_DATA DNS_SERVERS FILE_LIST

    if {[array size DNS_REGIONS] == 0} {
	return
    }

    puts "Processing inaddr..."

    set glue_recs() 1; unset glue_recs()

    if {[info exists DNS_REGIONS(primary@.)]} {
	lappend FILE_LIST(dns) $UNAMEIT_DATA/$VERSION/dns/db.in-addr.arpa
	unameit_cp gen.$VERSION/inaddr.arpa\
		$UNAMEIT_DATA/$VERSION/dns/db.in-addr.arpa
	puts $BOOT_FD "primary\tin-addr.arpa\tdb.in-addr.arpa"

	lappend FILE_LIST(dns) $UNAMEIT_DATA/$VERSION/dns/db.127
	unameit_cp gen.$VERSION/inaddr.127 $UNAMEIT_DATA/$VERSION/dns/db.127
	puts $BOOT_FD "primary\t127.in-addr.arpa\tdb.127"
    }

    read_networks

    foreach prefixed_dns_region [array names DNS_REGIONS primary@*] {
	regsub primary@ $prefixed_dns_region "" dns_region

	foreach net_file [array names GEN_FILES inaddr*] {
	    regsub {inaddr\.} $net_file "" ip
	    
	    # net_dns_regions doesn't get set for loopback and universe
	    if {[info exists net_dns_region($ip)] &&
	    [cequal $net_dns_region($ip) $dns_region]} {
		puts $BOOT_FD \
	        "primary\t[reverse_ip $ip].in-addr.arpa\tdb.$ip"

		set fd [atomic_open $UNAMEIT_DATA/$VERSION/dns/db.$ip 0444]
		lappend FILE_LIST(dns) $UNAMEIT_DATA/$VERSION/dns/db.$ip

		if {$IS_PULL_SERVER} {
		    set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
			    $net_file] r]
		    copyfile $rfh $fd
		    close $rfh
		} else {
		    unameit_send $fd [list unameit_pull_read_file [file join\
			    gen.$VERSION $net_file]]
		}
		
		set glue_networks {}
		# The '.' in the expression $net_file.* is necessary and
		# sufficient to get all the correct subnets. You don't need
		# to take out the '.' because any networks that were subnetted
		# on non-octet boundaries are already in the same inaddr.<addr>
		# file. The Perl scripts took care of this.
		# 	You also don't want to leave '.' out or you will 
		# inspect the network we are already processing in the 
		# outer loop.
		foreach subnet_file [array names GEN_FILES $net_file.*] {
		    regsub {inaddr\.} $subnet_file "" subnet

		    # The algorithm for finding subnets we need glue records
		    # from is as follows. Suppose you have the following
		    # hierarchy
		    #	126		esm.com		has dns server alias
		    #	126.5		west.esm.com
		    #	126.5.20	east.esm.com	has dns server alias
		    #	126.5.20.8	north.esm.com	has dns server alias
		    # If you are processing network 126, then you want to grab
		    # the glue records for network 126.5.20 but not network
		    # 126.5.20.8. To do this, you need to check the parent
		    # network of the subnet you are processing and check to
		    # see if its DNS server is the same as the DNS server you
		    # are processing in the outer loop. If it is, grab the
		    # records, otherwise don't.
		    set subnet_dns_region $net_dns_region($subnet)
		    regsub {\.?[^.]*$} $subnet {} shortened_subnet
		    set subnet_parent_dns_region\
			    [get_network_dns_region $shortened_subnet]
		    if {[get_dns_server_region $subnet_parent_dns_region] ==
		    $dns_region} {
			grab_glue_recs $subnet inaddr
			lappend glue_networks $subnet
		    }
		}
		if {![lempty $glue_networks]} {
		    puts $fd \
	    ";--------------------------- Glue Records -----------------"
		    foreach network $glue_networks {
			puts -nonewline $fd $glue_recs($network)
		    }
		}
		atomic_close $fd
	    }
	}
    }
    foreach prefixed_dns_region [array names DNS_REGIONS secondary@*] {
	regsub secondary@ $prefixed_dns_region "" dns_region
	foreach net_file [array names GEN_FILES inaddr*] {
	    regsub {inaddr\.} $net_file "" ip

	    # Skip loopback and arpa by checking "info exists"
	    if {[info exists net_dns_region($ip)] &&
	    [cequal $net_dns_region($ip) $dns_region]} {
		set line "secondary\t[reverse_ip $ip].in-addr.arpa "
		set ip_list [lindex $DNS_SERVERS($dns_region) 0]
		for {set i 0} \
			{$i < 10 && [llength $ip_list] > $i} \
			{incr i} {
		    append line " [lindex $ip_list $i]"
		}
		append line " db.$ip"
		puts $BOOT_FD $line
	    }
	}
    }
    atomic_close $BOOT_FD
    catch {unset BOOT_FD}
}

proc get_dns_server_region {region} {
    global DNS_SERVERS

    set split_region [split $region .]
    while {[llength $split_region] > 0} {
	set cur_region [join $split_region .]
	if {[info exists DNS_SERVERS($cur_region)]} {
	    return $cur_region
	}
	set split_region [lrange $split_region 1 end]
    }
    return .
}

proc grab_glue_recs {region prefix} {
    global VERSION UNAMEIT_DATA
    upvar glue_recs glue_recs

    unameit_cp gen.$VERSION/$prefix.$region $UNAMEIT_DATA/tmp/$prefix.$region
    set fd [open $UNAMEIT_DATA/tmp/$prefix.$region r]
    set reading_glue_lines 0
    while {[gets $fd line] != -1} {
	if {[regexp {^;} $line]} {
	    if {$reading_glue_lines} {
		close $fd
		file delete -- [file join $UNAMEIT_DATA tmp $prefix.$region]
		return
	    } else {
		set reading_glue_lines 1
		set glue_recs($region) ""
	    }
	} else {
	    if {$reading_glue_lines} {
		append glue_recs($region) "$line\n"
	    }
	}
    }
    # The following should not be reached.
    close $fd
    file delete -- [file join $UNAMEIT_DATA tmp $prefix.$region]
}

# Algorithm:
# Put "directory $UNAMEIT_DATA/dns" and "cache . db.cache" in named.boot
# foreach each "dns_region" that host is primary for {
#     Record "primary <region> db.<region>" in named.boot
#     Create db.<region> file
#     for each region below or including "dns_region" {
#         if region's dns server is not dns_region {
#             if region's parent's DNS server is dns_region {
#   	          grab glue records from region and put in GLUE_RECS
#	          Add region to glue_regions
#             }
#	      continue
#         }
#         Append region data to dns_region file
#     }
#     for each region in glue_regions {
#         Append that region's glue records to dns_region file
#     }
#     close dns_region file
# }
# for each DNS region that host is secondary for {
#     output secondary line to named.boot file
# }
proc process_named {} {
    global DNS_REGIONS UNAMEIT_DATA VERSION DNS_SERVERS BOOT_FD
    global FILE_LIST PARENT IS_PULL_SERVER

    if {[array size DNS_REGIONS] == 0} {
	return
    }

    puts "Processing named..."

    set BOOT_FD [atomic_open $UNAMEIT_DATA/$VERSION/dns/named.boot 0444]
    lappend FILE_LIST(dns) $UNAMEIT_DATA/$VERSION/dns/named.boot

    puts $BOOT_FD "directory $UNAMEIT_DATA/dns\n"

    # Root name servers don't need a db.cache line to tell it where roots are.
    # It already knows where the roots are. It is a root name server!
    if {![info exists DNS_REGIONS(primary@.)]} {
	puts $BOOT_FD "cache\t.\tdb.cache"
    }

    unameit_cp gen.$VERSION/db.cache $UNAMEIT_DATA/$VERSION/dns/db.cache
    lappend FILE_LIST(dns) $UNAMEIT_DATA/$VERSION/dns/db.cache

    foreach prefixed_dns_region [array names DNS_REGIONS primary@*] {
	regsub primary@ $prefixed_dns_region "" dns_region
	puts $BOOT_FD "primary\t$dns_region\tdb.$dns_region"

	set dns_region_fd \
		[atomic_open $UNAMEIT_DATA/$VERSION/dns/db.$dns_region 0444]
	lappend FILE_LIST(dns) $UNAMEIT_DATA/$VERSION/dns/db.$dns_region

	set glue_regions {}
	foreach region [get_down_regions $dns_region named] {
	    if {![cequal [get_dns_server_region $region] $dns_region]} {
		set parent_region $PARENT($region)

		if {[cequal [get_dns_server_region $parent_region]\
			$dns_region]} {
		    grab_glue_recs $region named.region
		    lappend glue_regions $region
		}
		continue
	    }

	    # Can't use unameit_cp here because we are appending, not
	    # clobbering the file.
	    if {$IS_PULL_SERVER} {
		set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
			named.region.$region] r]
		copyfile $rfh $dns_region_fd
		close $rfh
	    } else {
		unameit_send $dns_region_fd [list unameit_pull_read_file [file\
			join gen.$VERSION named.region.$region]]
	    }
	}

	if {![lempty $glue_regions]} {
	    puts $dns_region_fd \
	    ";--------------------------- Glue Records -----------------"
	    foreach region $glue_regions {
		puts -nonewline $dns_region_fd $glue_recs($region)
	    }
	}

	atomic_close $dns_region_fd
    }
    foreach prefixed_dns_region [array names DNS_REGIONS secondary@*] {
	regsub secondary@ $prefixed_dns_region "" dns_region

	puts -nonewline $BOOT_FD "secondary\t$dns_region"

	set ip_list [lindex $DNS_SERVERS($dns_region) 0]
	for {set i 0} \
		{$i < 10 && [llength $ip_list] > $i} \
		{incr i} {
	    puts -nonewline $BOOT_FD \
		    " [lindex $ip_list $i]"
	}
	puts $BOOT_FD "\tdb.$dns_region"
    }
}

proc process_resolv_conf {} {
    global DOMAIN_NAME DNS_SERVERS UNAMEIT_DATA VERSION FILE_LIST REGION

    puts "Processing resolv.conf..."
    if {[info exists DOMAIN_NAME]} {
	set domain_name $DOMAIN_NAME
    } else {
	set domain_name $REGION
    }
    set split_domain [split $domain_name .]
    while {[llength $split_domain] > 0} {
	set d [join $split_domain .]
	if {[info exists DNS_SERVERS($d)]} {
	    set fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/resolv.conf 0444]
	    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/resolv.conf
	    puts $fh "domain\t$domain_name"
	    for {set i 0} {$i < 3 && $i < [llength $DNS_SERVERS($d)]} \
		    {incr i} {
		puts $fh "nameserver\t[lindex [lindex $DNS_SERVERS($d) $i] 0]"
	    }
	    atomic_close $fh
	    return
	}
	set split_domain [lrange $split_domain 1 end]
    }
}

proc main {} {
    global tcl_platform pullPriv
    global UNAMEIT_DATA HOST_UUID MY_CNAME VERSION GEN_FILES PULL_HOST
    global DNS_REGIONS MY_IP VERSION
    global FILE_LIST DELAYED_DELETE_DIRS SECONDARY_IFS
    global INSTALL_FILES REGION IS_PULL_SERVER
    global OS RELEASE SHORT_HOST MY_NAME INET_DIR USE_PLUSES

    puts "Initializing..."

    set UNAMEIT_DATA [unameit_config pullPriv data]
    set INSTALL_FILES all

    check_version_info
    
    #
    # Get hostname and latest version data
    #
    array set whoami_results [unameit_send "unameit_pull_whoami $HOST_UUID"]
    #
    # MY_CNAME is qualified by region
    #
    set MY_CNAME $whoami_results(host)
    #
    # MY_NAME array is indexed with CNAME and any server aliases.
    #
    set MY_NAME($MY_CNAME) 1
    #
    # Split MY_CNAME to recover short name and region.
    #
    regexp {^([^.]*)\.(.*)$} $MY_CNAME junk SHORT_HOST REGION
    #
    # Decode IP info
    #
    set MY_IP $whoami_results(ip)
    set SECONDARY_IFS $whoami_results(secondary_ifs)

    make_directories $UNAMEIT_DATA/tmp $UNAMEIT_DATA/$VERSION/etc

    read_regions_file

    lassign [get_cell_and_oid $REGION] cell org_oid
    if {[info exists GEN_FILES(sybase_interfaces.cell.$cell)]} {
    	set HAS_SYBASE_FILES 1
    	make_directories $UNAMEIT_DATA/$VERSION/sybase
    } else {
    	set HAS_SYBASE_FILES 0
    }

    process_configuration

    interpret_domain_name

    verify_host_and_ip $MY_CNAME $MY_IP

    set OS $tcl_platform(os)
    set RELEASE $tcl_platform(osVersion)

    set version_fd [atomic_open $UNAMEIT_DATA/version 0444]
    puts $version_fd $VERSION

    process_server_aliases

    if {[array size NIS_REGIONS] != 0} {
	make_directories $UNAMEIT_DATA/$VERSION/nis
	foreach nis_region [array names NIS_REGIONS] {
	    make_directories $UNAMEIT_DATA/$VERSION/nis/$nis_region
	}
    }
    if {[array size DNS_REGIONS] != 0} {
	make_directories $UNAMEIT_DATA/$VERSION/dns
    }

    if {[array size PULL_REGIONS] != 0 && ![is_global_pull_server]} {
	set IS_PULL_SERVER 1
	make_directories $UNAMEIT_DATA/data
	get_pull_files
    } else {
	set IS_PULL_SERVER 0
    }

    if {[file isdirectory /etc/inet]} {
	set INET_DIR /etc/inet
    } else {
	set INET_DIR /etc
    }
    switch -glob -- $OS.$RELEASE {
	SunOS.4* {
	    set USE_PLUSES 1
	}
	SunOS.5* {
	    set USE_PLUSES 0
	}
	HP-UX.* {
	    set USE_PLUSES 1
	}
    }

    foreach v {dns etc} {
	set FILE_LIST($v) {}
    }

    # Process all the files
    process_named
    # process_inaddr must come after process_named. They share a file handle.
    process_inaddr
    process_resolv_conf

    set DELAYED_DELETE_DIRS {}
    if {![cequal $INSTALL_FILES none]} {
	create_system_directories $INSTALL_FILES
	install_files_to_system $INSTALL_FILES
    }

    atomic_close $version_fd

    if {[array size DNS_REGIONS] > 0} {
	if {[catch {open /etc/named.pid r} fd] == 0} {
	    gets $fd line
	    if {![regexp {[0-9]+} $line]} {
		puts stderr "/etc/named.pid file doesn't contain a pid"
	    } else {
		catch {kill HUP $line}
	    }
	    close $fd
	}
    }
    foreach dir $DELAYED_DELETE_DIRS {
	file delete -force -- $dir
    }

    lassign [split $VERSION .] major minor trans
    foreach file [readdir $UNAMEIT_DATA] {
	if {[regexp {^([0-9]+)\.([0-9]+)\.([0-9]+)$} $file junk cur_major\
		cur_minor cur_trans]} {
	    if {$cur_major < $major ||
	    $cur_major == $major && $cur_minor < $minor ||
	    $cur_major == $major && $cur_minor == $minor && $cur_trans <\
		    $trans} {
		## Catch in case someone is cd'ed to the directory. If they
		## are, the delete will fail.
		catch {file delete -force -- [file join $UNAMEIT_DATA $file]}
	    }
	}
    }
    # Only delete old gen directories if we are a pull server and we are not
    # the global pull server (the check in parentheses).
    if {[llength [array names PULL_REGIONS]] > 0 && ![is_global_pull_server]} {
	cd [file join $UNAMEIT_DATA data]
	foreach gen_dir [glob -nocomplain -- {gen.[0-9]*}] {
	    if {[scan $gen_dir "gen.%d.%d.%d%s" v1 v2 v3 tail] == 3} {
		if {$v1 < $major || $v1 == $major && $v2 < $minor - 3} {
		    catch {file delete -force -- $gen_dir}
		}
	    }
	}
    }
    puts "done."
}
