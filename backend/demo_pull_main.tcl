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
# $Id: demo_pull_main.tcl,v 1.2.12.1 1997/08/28 18:25:27 viktor Exp $
#
# Global variables used by this file
# VERSION		Version of backend files. Usually something like
#			0.51
# OLD_VERSION		Previous version of backend files. The empty string
#			if there is no previous version.
#
# HOST_UUID		The uuid of the current host.
#
# HOST_NAME		The name of the host given on the command line.
#			This is the overridden name.
#
# UNAMEIT_DATA		The parent directory on this machine where all the
#			files we are generating go.
#
# MY_CNAME		The host name that the server thinks this machine is,
#			fully qualified.
#
# MY_NAME		Associative array of names for this machine.  Currently
#			includes $MY_CNAME and any (primary) server_aliases.
#
# REGION		The region UName*It thinks this host is in.
#			Extracted from MY_CNAME
#
# MY_IP			The ip address of this host (dotted quad).
#
# MAILHOSTS		These three arrays are indexed by a region. They
# DNS_SERVERS		contain the regions which have a mailhost, DNS server,
# NIS_SERVERS		NIS server or pull server. The value of each array
# PULL_SERVERS		element is the list of hosts that serve that region. 
# PAGER_SERVERS		DNS_SERVERS is treated somewhat specially. See code
# 			below.
#
# MAILHOST_REGIONS	These four arrays are indexed by all the regions
# DNS_REGIONS		that this host is a mailhost, DNS server, NIS
# NIS_REGIONS		server or pull server for. Most of the time, these 
# PULL_REGIONS		arrays will be empty but a host may be a NIS server 
# PAGER_REGIONS		for a couple of regions in which case NIS_REGIONS 
#			will have two entries. DNS_REGIONS and PULL_REGIONS
#			are treated somewhat specially. See code below.
#
# SECONDARY_IFS		A list of secondary interfaces for this host as
#			returned by the upulld(1m) "whoami" request.
#			The interfaces are of the form "le0@192.9.200.101".
#
# GEN_FILES		An array whose indices are all the files in the
#			gen.$VERSION directory. The value is the file type
#			"file" or "directory".
#
# DOMAIN_NAME		The NIS domain name that this host is in. If the
#			variable is not set, then there is no NIS server
#			for this host.
#
# PULL_HOST		The host we are pulling from.
#
# USE_PLUSES		Whether to put pluses in /etc files for NIS.
#
# INET_DIR, MAIL_DIR	Where to install inet, mail files.
#
# CONFIG		This variable holds the configuration options selected
#			in the upull.conf file. The defaults are put in this
#			array too before upull.conf is read.
#
# INSTALL_DIRS		This array contains the installation directories for
#			each type of file. It is indexed by "nis", "etc" and
#			"dns". If nis_relative is set in upull.conf, then
#			it will also be indexed by "nis.<region>" where 
#			<region> is a region that this machine is a NIS
#			server for.
#
# FILE_LIST		This array is indexed by "etc", "nis.<region>"
#			or "dns". Each entry contains the full path name of a
#			file that has been created in UNAMEIT_DATA and needs
#			to be copied to the system directories.
#
# HAS_SYBASE_FILES	This is a boolean that is true if there are Sybase
#			files to install.
#
# INSTALL_FILES		This is a global variable that tells which files to
#			install. Normally, all etc, dns, nis and sybase files
#			are installed according to the install_type in the
#			upull.conf file. If there is a host name mismatch,
#			an IP address mismatch or a region/NIS domain mismatch,
#			then the /var/unameit files are created but nothing
#			is installed. In this case, this variable will be
#			set to "none". If there is a prototype mismatch,
#			then the /etc files are not installed and this variable
#			is set to "not_etc" and everything but the etc
#			files are installed.
#
# REGIONS		An array containing the name of all the regions and 
#			cells in the database.
#
# ORG_OID		This array lists the oid for each cell. Regions
#			don't have an index in this array.
# ORG_OID_2_CELLS	This array contains all the cells in org_oid.
#
# OS_TO_FAMILY		A mapping from an OS to the family the OS is in.
#			The value will be empty if the index is an OS
#			family rather than a regular os.
#
# IS_PULL_SERVER	Boolean telling whether this machine is a pull
#			server or not. If it is, we can get the pull data
#			directly from the local file system after pulling it.

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

		if {([cequal $tail passwd] || [cequal $tail shadow]) &&
		[cequal $type etc]} {
		    #lock_pw_file /etc
		}
		# yppasswdd under NIS locks the file passwd.ptmp
		if {[cequal $tail passwd] && [cequal $type nis]} {
		    lock_pw_file [file dirname $entry]
		}

		file rename -force -- $entry.new $entry

		if {([cequal $tail passwd] || [cequal $tail shadow]) &&
		[cequal $type etc]} {
		    #unlock_pw_file /etc
		}
		if {[cequal $tail passwd] && [cequal $type nis]} {
		    unlock_pw_file [file dirname $entry]
		}
	    }
	}
    }
}

proc etc_file_to_dir {file} {
    global MAIL_DIR INET_DIR UNAMEIT_DATA SHORT_HOST

    return $UNAMEIT_DATA/$SHORT_HOST/etc
    switch -exact $file {
	aliases {
	    return $MAIL_DIR
	}
	hosts -
	netmasks -
	networks -
	protocols -
	services {
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
    if {[cequal $tail shadow]} {
	set mode 0400
    } else {
	if {[cequal $type nis] && [cequal $tail passwd]} {
	    # The yppasswdd daemon may want to write nis passwd files
	    set mode 0644
	} else {
	    set mode 0444
	}
    }
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
    } elseif {([cequal $type etc] || [cequal $type nis]) &&
	[cequal $tail auto_master]} {
	while {[gets $var_fd line] != -1} {
	    lassign $line dir map options
	    if {$USE_PLUSES} {
		puts $system_fd "$dir /etc/$map $options"
	    } else {
		puts $system_fd "$dir $map $options"
	    }
	}
    } else {
	copyfile $var_fd $system_fd
    }
    close $var_fd
    atomic_close $system_fd
}

proc install_files_to_system {install_which_files} {
    global CONFIG FILE_LIST MOVE_LIST INSTALL_DIRS HAS_SYBASE_FILES
    global UNAMEIT_DATA VERSION

    if {[cequal $install_which_files none]} return
    set list {dns nis}
    if {[cequal $install_which_files all]} {
	lappend list etc
    }
    if {$HAS_SYBASE_FILES} {
	lappend list sybase
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
	    dns -
	    sybase {
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
	if {!$CONFIG(nis_relative)} {
	    if {![info exists INSTALL_DIRS($type)]} {
		continue
	    }
	    set MOVE_LIST {}
	    set index [array names FILE_LIST nis.*]
	    if {[llength $index] > 1} {
		error "nis_relative is turned off but host is NIS server\
			for multiple regions.\nThis\
			would overwrite files in the NIS directory."
	    }
	    foreach entry $FILE_LIST($index) {
		if {[info exists CONFIG(install_nis_maps)]} {
		    set tail [file tail $entry]
		    if {[lsearch -exact $CONFIG(install_nis_maps) $tail]
		    > -1} {
			move_file_to_system $type $entry
		    }
		} else {
		    move_file_to_system $type $entry
		}
	    }
	    foreach etc_file $CONFIG(unhandled_nis_files) {
		set dir [etc_file_to_dir $etc_file]
		if {![file exists $dir/$etc_file]} {
		    close [open\
			[file join $UNAMEIT_DATA $VERSION etc $etc_file] w]
		    move_file_to_system $type\
			[file join $UNAMEIT_DATA $VERSION etc $etc_file] "" 1
		} else {
		    move_file_to_system $type\
			[file join $dir $etc_file] "" 1
		}
	    }
	    post_process_move $type
	} else {
	    foreach index [array names FILE_LIST nis.*] {
		if {![info exists INSTALL_DIRS($index)]} {
		    continue
		}
		set MOVE_LIST {}
		regsub {^nis\.} $index "" region
		foreach entry $FILE_LIST($index) {
		    if {[info exists CONFIG(install_nis_maps)]} {
			set tail [file tail $entry]
			if {[lsearch -exact $CONFIG(install_nis_maps) $tail]
			> -1} {
			    move_file_to_system $type $entry $region
			}
		    } else {
			move_file_to_system $type $entry $region
		    }
		}
		foreach etc_file $CONFIG(unhandled_nis_files) {
		    set dir [etc_file_to_dir $etc_file]
		    if {![file exists $dir/$etc_file]} {
			close [open\
			    [file join $UNAMEIT_DATA $VERSION etc $etc_file] w]
			move_file_to_system $type\
			    [file join $UNAMEIT_DATA $VERSION etc $etc_file]\
				$region 1
		    } else {
			move_file_to_system $type [file join $dir $etc_file]\
			    $region 1
		    }
		}
		post_process_move $type $region
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
    global CONFIG UNAMEIT_DATA HAS_SYBASE_FILES

    # Any settings here are not canonicalized by the code below so they are
    # canonicalized manually here.
    set CONFIG(dns_dir) /var/named
    set CONFIG(dns_install_type) none
    set CONFIG(dns_threshold) -1

    set CONFIG(nis_dir) /var/yp/src
    set CONFIG(nis_install_type) none
    set CONFIG(nis_relative) 0
    set CONFIG(nis_threshold) -1

    set CONFIG(etc_dir) /etc			;# Can't change
    set CONFIG(etc_install_type) none
    set CONFIG(etc_threshold) -1

    if {[catch {file isdirectory ~sybase}] == 0} {
	set CONFIG(sybase_dir) ~sybase
    }
    set CONFIG(sybase_install_type) none
    set CONFIG(sybase_threshold) -1
    set CONFIG(sybase_nullhost) 1

    set CONFIG(unhandled_nis_files) {rpc protocols bootparams publickey netid\
	    timezone}
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
			error "Illegal value $value for $key in configuration file"
		    }
		}
		set CONFIG($key) $value
	    }

	    dns_install_type -
	    nis_install_type -
	    sybase_install_type {
		switch -- $value {
		    safe -
		    unsafe -
		    none {
		    }
		    default {
			error "Illegal value $value for $key in configuration file"
		    }
		}
		set CONFIG($key) $value
	    }

	    full_host_first -
	    nis_relative -
	    sybase_nullhost {
		if {[catch {convert_to_boolean $value} msg]} {
		    error "Illegal boolean value \"$value\" for $key in configuration file"
		} else {
		    set value $msg
		}
		set CONFIG($key) $value
	    }

	    dns_threshold -
	    nis_threshold -
	    etc_threshold -
	    sybase_threshold {
		if {![regexp {[0-9]+%?} $value] && ![cequal $value -1]} {
		    error "Invalid percentile \"$value\" for $key in configuration file"
		}
		regsub % $value "" value
		set CONFIG($key) $value
	    }
	    
	    dns_dir -
	    sybase_dir -
	    nis_dir -
	    unhandled_nis_files -
	    install_nis_maps -
	    install_etc_files {
		set CONFIG($key) $value
	    }
	}
    }
    if {$HAS_SYBASE_FILES && ![info exists CONFIG(sybase_dir)] &&
    ![cequal $CONFIG(sybase_install_type) none]} {
	error "Directory ~sybase not found. Cannot install sybase\
		interfaces file."
    }
}

proc create_system_directories {install_which_files} {
    global NIS_REGIONS DNS_REGIONS UNAMEIT_DATA VERSION CONFIG INSTALL_DIRS
    global HAS_SYBASE_FILES

    if {[cequal $install_which_files none]} return
    set list {nis dns}
    if {[cequal $install_which_files all]} {
	lappend list etc
    }
    if {$HAS_SYBASE_FILES} {
	lappend list sybase
    }
    foreach type $list {
	if {[cequal $type nis] && [array size NIS_REGIONS] == 0} {
	    continue
	}
	if {[cequal $type dns] && [array size DNS_REGIONS] == 0} {
	    continue
	}
	set install_type $CONFIG(${type}_install_type)
	switch -exact $install_type {
	    safe {
		set INSTALL_DIRS($type) $CONFIG(${type}_dir)/new
		if {[cequal $type nis] && $CONFIG(nis_relative)} {
		    foreach region [array names NIS_REGIONS] {
			set INSTALL_DIRS(nis.$region) \
				$CONFIG(${type}_dir)/$region/new
			make_directories $INSTALL_DIRS(nis.$region)
		    }
		} else {
		    make_directories $INSTALL_DIRS($type)
		}
	    }
	    unsafe {
		set INSTALL_DIRS($type) $CONFIG(${type}_dir)
		make_directories $INSTALL_DIRS($type)
		if {[cequal $type nis] && $CONFIG(nis_relative)} {
		    foreach region [array names NIS_REGIONS] {
			set INSTALL_DIRS(nis.$region) \
				$INSTALL_DIRS(nis)/$region
			make_directories $INSTALL_DIRS(nis.$region)
		    }
		}
	    }
	    none {
		set INSTALL_DIRS($type) $UNAMEIT_DATA/$VERSION/$type
		make_directories $INSTALL_DIRS($type)
		if {[cequal $type nis] && $CONFIG(nis_relative)} {
		    foreach region [array names NIS_REGIONS] {
			set INSTALL_DIRS(nis.$region) \
				$INSTALL_DIRS($type)/$region
			make_directories $INSTALL_DIRS(nis.$region)
		    }
		}
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

proc read_os_file {} {
    global VERSION UNAMEIT_DATA OS_TO_FAMILY

    unameit_cp gen.$VERSION/os [file join $UNAMEIT_DATA tmp os]

    for_file line [file join $UNAMEIT_DATA tmp os] {
	# lassign will clear the fam_os and fam_release variables if only
	# two fields exist.
	lassign $line os release fam_os fam_release

	if {![cequal $fam_os ""] || ![cequal $fam_release ""]} {
	    set OS_TO_FAMILY($os.$release) [list $fam_os $fam_release]
	} else {
	    set OS_TO_FAMILY($os.$release) ""
	}
    }

    file delete -- [file join $UNAMEIT_DATA tmp os]
}

proc process_server_aliases {} {
    global VERSION UNAMEIT_DATA MY_CNAME MY_NAME
    global MAILHOSTS DNS_SERVERS NIS_SERVERS PULL_SERVERS
    global MAILHOST_REGIONS DNS_REGIONS NIS_REGIONS PULL_REGIONS
    global PAGER_SERVERS PAGER_REGIONS REGION

    unameit_cp gen.$VERSION/server_aliases $UNAMEIT_DATA/tmp/server_aliases

    for_file line $UNAMEIT_DATA/tmp/server_aliases {
	set replicas [lassign $line alias alias_scope stype]
	set i 0
	foreach chunk $replicas {
	    lassign [split $chunk @] host scope owner ips
	    switch -exact $stype {
		mailhost {lappend MAILHOSTS($alias_scope) $host.$owner}
		dnsserver {
		    lappend DNS_SERVERS($alias_scope) [split $ips ,]
		}
		nisserver {lappend NIS_SERVERS($alias_scope) $chunk@$alias}
		pullserver {lappend PULL_SERVERS($alias_scope) $host.$owner}
		pagerserver {lappend PAGER_SERVERS($alias_scope) $host.$owner}
	    }
	    if {[cequal $host.$owner $MY_CNAME]} {
		if {$i == 0} {
		    set MY_NAME($alias.$alias_scope) 1
		}
		switch -- $stype {
		    mailhost {set MAILHOST_REGIONS($alias_scope) 1}
		    dnsserver {
			if {$i == 0 || [cequal $alias_scope .]} {
			    set DNS_REGIONS(primary@$alias_scope) 1
			} else {
			    set DNS_REGIONS(secondary@$alias_scope) 1
			}
		    }
		    nisserver {set NIS_REGIONS($alias_scope) 1}
		    pullserver {
			if {$i == 0} {
			    set PULL_REGIONS(primary@$alias_scope) 1
			} else {
			    set PULL_REGIONS(secondary@$alias_scope) 1
			}
		    }
		    pagerserver {set PAGER_REGIONS($alias_scope) 1}
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
	#puts stderr "Domain name and region returned by pull\
		server ($REGION) are not equal"
	#puts stderr "Not installing files to system"
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

proc grab_single_file {file_name} {
    global DOMAIN_NAME UNAMEIT_DATA NIS_REGIONS VERSION FILE_LIST

    if {[info exists DOMAIN_NAME]} {
	foreach region [array names NIS_REGIONS] {
	    unameit_cp gen.$VERSION/$file_name \
		    $UNAMEIT_DATA/$VERSION/nis/$region/$file_name
	    lappend FILE_LIST(nis.$region) \
		    $UNAMEIT_DATA/$VERSION/nis/$region/$file_name
	}
    } else {
	unameit_cp gen.$VERSION/$file_name\
		$UNAMEIT_DATA/$VERSION/etc/$file_name
	lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/$file_name
    }
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

proc process_alias_file {fh file_name {record_in_output 0}} {
    global UNAMEIT_DATA VERSION DBM_MAX
    upvar mapping mapping output output
    
    unameit_cp [file join gen.$VERSION $file_name]\
	    [set local_file [file join $UNAMEIT_DATA tmp $file_name]]
    set local_fh [open $local_file r]
    
    while {[gets $local_fh line] != -1} {
	regexp {([^:]*):(.*)} $line x key line
    
	## If the following is true, then we found a file or program drop
	## in the main mailing list file and we have already output it in
	## the /etc file. There is no NIS server.
	if {[info exists output($key)]} continue

	if {$record_in_output} {
	    set output($key) 1
	}
	
	if {[info exists mapping($key)]} {
	    lassign [split $key @] key region
	} else {
	    regsub @ $key .. key
	}
	puts -nonewline $fh $key:

	set ccount [clength $key:]
	set split_count 0
	set comma ""
	foreach token $line {
	    if {$ccount > $DBM_MAX} {
		set new_key "$key--$split_count"
		puts -nonewline $fh ", $new_key\n$new_key:"
		set ccount [clength $new_key:]
		set comma ""
		incr split_count
	    }
	    if {[regexp {^!} $token]} {
		set token [string range $token 1 end]
		if {[info exists mapping($token)]} {
		    lassign [split $token @] name region
		    set out "$comma $name"
		} else {
		    regsub @ $token .. token
		    set out "$comma $token"
		}
	    } else {
		set out "$comma $token"
	    }
	    set comma ,
	    puts -nonewline $fh $out
	    incr ccount [clength $out]
	}
	puts $fh ""
    }

    close $local_fh
    file delete -- $local_file
}

proc compute_local_aliases {processing_type start_region} {
    global DOMAIN_NAME GEN_FILES MY_CNAME ORG_OID_2_CELLS
    upvar mapping mapping postmaster_file postmaster_file

    if {[cequal $processing_type /etc]} {
	## This alias is hardcoded. Record it so it doesn't get picked up
	## later.
	set seen(mailer-daemon) 1
	
	## Process entries in host drop file.
	if {[info exists GEN_FILES(maildrop.host.$MY_CNAME)]} {
	    set_mapping_array maildrop.host.$MY_CNAME
	}

	## See if we can find a postmaster region. If so, use it, otherwise
	## just hardcode that we have seen "postmaster".
	set postmaster_regions [get_up_regions $start_region cell postmaster]
	if {![cequal $postmaster_regions ""]} {
	    set region [lindex $postmaster_regions 0]
	    set mapping(postmaster@$region) 1
	    
	    set postmaster_file postmaster.region.$region
	}
	set seen(postmaster) 1
    }

    ## Whether we are processing /etc or NIS, we need to look all the way up
    ## the tree to the cell and look at user logins in the cell for shortening.
    ## Even if we are processing /etc and we have a NIS server, we may need
    ## to shorten names in the /etc file because the names in the /etc file
    ## may reference a mailing list in the NIS database and the NIS database
    ## will contain the shortened name.
    foreach region [get_up_regions $start_region cell mailing_list] {
	set_mapping_array mailing_list.region.$region
    }

    lassign [get_cell_and_oid $start_region] cell org_oid
    foreach c $ORG_OID_2_CELLS($org_oid) {
	if {[info exists GEN_FILES(mailing_list.cell.$c)]} {
	    set_mapping_array mailing_list.cell.$c
	}
    }

    if {[info exists GEN_FILES(mailing_list.region..)]} {
	set_mapping_array mailing_list.region..
    }
}

proc process_aliases {} {
    global UNAMEIT_DATA MY_CNAME GEN_FILES VERSION DOMAIN_NAME NIS_REGIONS
    global FILE_LIST REGION

    puts {Processing aliases...}

    ## Create local aliases file
    set local_fh [atomic_open [file join $UNAMEIT_DATA $VERSION etc aliases]\
	    0444]
    lappend FILE_LIST(etc) [file join $UNAMEIT_DATA $VERSION etc aliases]

    ## Compute local aliases so we can shorten them
    compute_local_aliases /etc $REGION

    ## Output all entries in drop file with short name. Record each entry
    ## in the variable "output" so it won't get re-output later.
    if {[info exists GEN_FILES(maildrop.host.$MY_CNAME)]} {
	process_alias_file $local_fh maildrop.host.$MY_CNAME 1
    }

    ## If we found a postmaster file, process its contents, else output
    ## "postmaster: root".
    if {[info exists postmaster_file]} {
	process_alias_file $local_fh $postmaster_file 1
    } else {
	puts $local_fh "postmaster: root"
    }

    ## Always output a "mailer-daemon" line in the /etc file.
    puts $local_fh "mailer-daemon: postmaster"

    if {![info exists DOMAIN_NAME]} {
	process_alias_file $local_fh mailing_lists
    }

    atomic_close $local_fh

    # Create nis files
    foreach nis_region [array names NIS_REGIONS] {
	set nis_fh \
	    [atomic_open $UNAMEIT_DATA/$VERSION/nis/$nis_region/aliases 0444]
	lappend FILE_LIST(nis.$nis_region) \
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/aliases

	catch {unset output}; catch {unset mapping}

	compute_local_aliases NIS $nis_region

	process_alias_file $nis_fh mailing_lists

	atomic_close $nis_fh
    }
}

proc process_automount_file {file_name} {
    global VERSION UNAMEIT_DATA MAP_TO_DIR
    upvar dups dups data data

    unameit_cp gen.$VERSION/$file_name $UNAMEIT_DATA/tmp/$file_name
    set local_fh [open $UNAMEIT_DATA/tmp/$file_name r]

    while {[gets $local_fh line] != -1} {
	scan $line %s map
	set line [string trim [string range $line [clength $map] end]]
	if {![info exists MAP_TO_DIR($map)]} continue

	scan $line %s name
	if {[info exists dups($name)]} continue
	set dups($name) 1

	append data($map) $line\n
    }

    close $local_fh
    file delete -- [file join $UNAMEIT_DATA tmp $file_name]
}

# The global variable MAP_TO_DIR maps automount_map names to directories.
# It is needed by the passwd code so it is not garbage collected.
proc process_automounts {} {
    global VERSION UNAMEIT_DATA DOMAIN_NAME MY_CNAME GEN_FILES
    global NIS_REGIONS MAP_TO_DIR REGION FILE_LIST ORG_OID_2_CELLS
    global USE_PLUSES

    puts "Processing automounts..."

    ## Process auto_master
    set am_fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/auto_master 0444]
    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/auto_master

    # The /etc prefix is put on during installation if needed.
    ## Always put out auto_direct for direct automounts.
    puts $am_fh "/- auto_direct -rw,intr,hard"

    lassign [get_cell_and_oid $REGION] cell org_oid
    if {[info exists GEN_FILES(automount_map.cell.$cell)]} {
	unameit_cp gen.$VERSION/automount_map.cell.$cell\
		$UNAMEIT_DATA/tmp/automount_map.cell.$cell

	set local_fh [open $UNAMEIT_DATA/tmp/automount_map.cell.$cell r]
	while {[gets $local_fh line] != -1} {
	    scan $line "%s %s" dir map
	    set MAP_TO_DIR($map) $dir
	    puts $am_fh $line
	}
	close $local_fh

	file delete -- [file join $UNAMEIT_DATA tmp automount_map.cell.$cell]
    }
    atomic_close $am_fh
    
    ## Process local host automounts
    if {[info exists GEN_FILES(automount.host.$MY_CNAME)]} {
	process_automount_file automount.host.$MY_CNAME
    }

    ## If no domain name, process regular autos up to cell, user automounts
    ## for current cell, and foreign cell automounts for maps that we know.
    if {![info exists DOMAIN_NAME]} {
	foreach region [get_up_regions $REGION cell automount] {
	    process_automount_file automount.region.$region
	}
	if {[info exists GEN_FILES(automount.cell.$cell)]} {
	    process_automount_file automount.cell.$cell
	}
	foreach c $ORG_OID_2_CELLS($org_oid) {
	    if {[cequal $c $cell]} continue

	    if {[info exists GEN_FILES(automount.cell.$c)]} {
		process_automount_file automount.cell.$c
	    }
	}
    }

    ## Dump all /etc automount map data.
    foreach map [array names data] {
	set fd [atomic_open $UNAMEIT_DATA/$VERSION/etc/$map 0444]
	lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/$map

	puts -nonewline $fd $data($map)
	if {[info exists DOMAIN_NAME] && $USE_PLUSES} {
	    puts $fd +$map
	}

	atomic_close $fd
    }
    
    # Now create empty automount files for those maps referenced in
    # auto_master but not written.
    foreach map [array names MAP_TO_DIR] {
	if {![info exists data($map)]} {
	    set fd [atomic_open $UNAMEIT_DATA/$VERSION/etc/$map 0444]
	    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/$map
	    if {[info exists DOMAIN_NAME] && $USE_PLUSES} {
		puts $fd +$map
	    }
	    atomic_close $fd
	}
    }

    foreach nis_region [array names NIS_REGIONS] {
	catch {unset data}; catch {unset dups}

	lassign [get_cell_and_oid $nis_region] cell org_oid

	foreach region [get_up_regions $nis_region cell automount] {
	    process_automount_file automount.region.$region
	}
	if {[info exists GEN_FILES(automount.cell.$cell)]} {
	    process_automount_file automount.cell.$cell
	}
	foreach c $ORG_OID_2_CELLS($org_oid) {
	    if {[cequal $c $cell]} continue

	    if {[info exists GEN_FILES(automount.cell.$c)]} {
		process_automount_file automount.cell.$c
	    }
	}

	foreach map [array names data] {
	    set fd [atomic_open $UNAMEIT_DATA/$VERSION/nis/$nis_region/$map\
		    0444]
	    lappend FILE_LIST(nis.$nis_region)\
		    $UNAMEIT_DATA/$VERSION/nis/$nis_region/$map

	    puts -nonewline $fd $data($map)

	    atomic_close $fd
	}
    }
}

proc process_ethers {} {
    puts "Processing ethers..."
    grab_single_file ethers
}

proc process_group_line {fh line} {
    global DBM_MAX
    upvar groups_seen groups_seen overflow_count overflow_count

    set line_len [clength $line]
    lassign [split $line :] name password gid logins

    if {[info exists groups_seen($name)]} {
	return
    }
    set groups_seen($name) 1

    if {$line_len < $DBM_MAX} {
	puts $fh $line
	return
    }
    set begin_part $name:$password:$gid:
    puts -nonewline $fh $begin_part
    set ccount [clength $begin_part]
    set comma ""
    foreach token [split $logins ,] {
	if {$ccount > $DBM_MAX} {
	    set begin_part [format "g%07u:%s:%d:" $overflow_count \
		    $password $gid]
	    incr overflow_count
	    set ccount [clength $begin_part]
	    puts -nonewline $fh "\n$begin_part"
	    set comma ""
	}
	puts -nonewline $fh [set token "$comma$token"]
	incr ccount [clength $token]
	set comma ,
    }
    puts $fh ""
}

proc process_group_file {fh file_name} {
    global VERSION UNAMEIT_DATA
    upvar groups_seen groups_seen overflow_count overflow_count

    unameit_cp gen.$VERSION/$file_name $UNAMEIT_DATA/tmp/$file_name
    set local_fh [open $UNAMEIT_DATA/tmp/$file_name r]
    while {[gets $local_fh line] != -1} {
	process_group_line $fh $line
    }
    close $local_fh
    file delete -- [file join $UNAMEIT_DATA tmp $file_name]
}

proc process_system_groups {fh regions} {
    global VERSION UNAMEIT_DATA GEN_FILES OS RELEASE OS_TO_FAMILY
    upvar groups_seen groups_seen overflow_count overflow_count

    foreach region $regions {
	unameit_cp gen.$VERSION/system_groups.region.$region\
		$UNAMEIT_DATA/tmp/system_groups.region.$region

	## Suck in OS override data for this region
	catch {unset os_overrides}
	if {[info exists GEN_FILES(os_groups.region.$region)]} {
	    unameit_cp gen.$VERSION/os_groups.region.$region\
		    $UNAMEIT_DATA/tmp/os_groups.region.$region

	    for_file line $UNAMEIT_DATA/tmp/os_groups.region.$region {
		lassign [split $line :] name os release gid logins
		set os_overrides($os.$release.$name) [list $gid $logins]
	    }

	    file delete --\
		[file join $UNAMEIT_DATA tmp os_groups.region.$region]
	}

	for_file line $UNAMEIT_DATA/tmp/system_groups.region.$region {
	    lassign [split $line :] name template gid logins
	    if {[info exists os_overrides($OS.$RELEASE.$name)]} {
		lassign $os_overrides($OS.$RELEASE.$name) gid os_logins
		if {[cequal $logins ""]} {
		    set logins $os_logins
		} elseif {![cequal $os_logins ""]} {
		    set logins "$logins,$os_logins"
		}
	    } else {
		if {[info exists OS_TO_FAMILY($OS.$RELEASE)]} {
		    lassign $OS_TO_FAMILY($OS.$RELEASE) os_fam\
			    release_fam
		    if {[info exists\
			    os_overrides($os_fam.$release_fam.$name)]} {
			lassign $os_overrides($os_fam.$release_fam.$name)\
				gid os_logins
			if {[cequal $logins ""]} {
			    set logins $os_logins
			} elseif {![cequal $os_logins ""]} {
			    set logins "$logins,$os_logins"
			}
		    } else {
			if {[cequal $template Yes]} {
			    set groups_seen($name) 1
			    continue
			}
		    }
		} else {
		    if {[cequal $template Yes]} {
			set groups_seen($name) 1
			continue
		    }
		}
	    }
	    process_group_line $fh [join [list $name * $gid $logins] :]
	}
	file delete --\
	    [file join $UNAMEIT_DATA tmp system_groups.region.$region]
    }
}

proc process_groups {} {
    global GEN_FILES UNAMEIT_DATA DOMAIN_NAME REGION
    global NIS_REGIONS VERSION USE_PLUSES FILE_LIST

    puts "Processing groups..."

    set local_fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/group 0444]
    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/group

    set groups_seen() 1; unset groups_seen()
    set overflow_count 0

    ## Process group logins in /etc
    process_system_groups $local_fh [get_up_regions $REGION\
	    cell system_groups]
    if {[info exists DOMAIN_NAME]} {
	set stopping_point $DOMAIN_NAME
    } else {
	set stopping_point cell
    }
    foreach region [get_up_regions $REGION $stopping_point groups] {
	process_group_file $local_fh groups.region.$region
    }

    ## Process group logins in /etc
    lassign [get_cell_and_oid $REGION] cell org_oid

    foreach region [get_up_regions $REGION $stopping_point user_groups] {
	process_group_file $local_fh user_groups.region.$region
    }
    if {[info exists DOMAIN_NAME] && $USE_PLUSES} {
	puts $local_fh +:::
    }
    atomic_close $local_fh

    foreach nis_region [array names NIS_REGIONS] {
	set nis_fh [atomic_open $UNAMEIT_DATA/$VERSION/nis/$nis_region/group\
		0444]
	lappend FILE_LIST(nis.$nis_region) \
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/group

	catch {unset groups_seen}
	catch {unset overflow_count}
	set groups_seen() 1; unset groups_seen()
	set overflow_count 0

	lassign [get_cell_and_oid $nis_region] cell org_oid

	foreach region [get_up_regions $nis_region cell groups] {
	    process_group_file $nis_fh groups.region.$region
	}
	if {[info exists GEN_FILES(user_groups.region.$cell)]} {
	    process_group_file $nis_fh user_groups.region.$cell
	}

	atomic_close $nis_fh
    }
}

proc process_hosts_file {fh file_name is_etc_file} {
    global VERSION UNAMEIT_DATA CONFIG OS RELEASE
    upvar 1 ips_seen ips_seen hosts_seen hosts_seen canon_name canon_name

    unameit_cp gen.$VERSION/$file_name $UNAMEIT_DATA/tmp/$file_name
    set local_fh [open $UNAMEIT_DATA/tmp/$file_name r]

    ## Solaris 2.4 doesn't preserve the ordering in the hosts file. Therefore,
    ## if you have an secondary ifs or ips, you must output the primary host
    ## line twice first.
    if {$is_etc_file && [cequal $OS SunOS] && [cequal $RELEASE 5.4]} {
	set bug 1
    } else {
	set bug 0
    }
    while {[gets $local_fh line] != -1} {
	lassign $line one two three four five six seven
	set ip $one
	set cname $two
	set len [llength $line]
	if {![info exists hosts_seen($cname)]} {
	    set hosts_seen($cname) 1
	    set ips_seen($ip) 1
	    if {$CONFIG(full_host_first)} {
		switch [llength $line] {
		    3 {
			puts $fh [set out_line "$one $three $two"]
		    }
		    4 {
			puts $fh [set out_line "$one $three $two $four"]
		    }
		    5 {
			puts $fh [set out_line "$one $three $two $five $four"]
		    }
		    7 {
			puts $fh [set out_line\
				"$one $three $two $four $six $five $seven"]
		    }
		}
		set canon_name($cname) $three
	    } else {
		puts $fh [set out_line $line]
		set canon_name($cname) $cname
	    }
	    if {$bug} {
		# Any secondary ifs or ips will be in the same file so we
		# can make the variable host_to_line local to this routine.
		set host_to_line($cname) $out_line
	    }
	} elseif {[info exists ips_seen($ip)]} {
	    # Host alias
	    puts $fh "$ip $canon_name($cname) [lrange $line 2 end]"
	} elseif {$len == 2 || [info exists hosts_seen($three)]} {
	    # Secondary IP
	    if {$bug} {
		# host_to_line better be set or this is a bug.
		puts $fh "$host_to_line($cname) # Solaris 2.4 read bug"
	    }
	    if {$len == 2 || !$CONFIG(full_host_first)} {
		puts $fh "$ip $canon_name($cname) [lrange $line 2 end]"
	    } else {
		puts $fh "$ip $canon_name($cname) $four $three\
			[lrange $line 4 end]"
	    }
	    set ips_seen($ip) 1
	} else {
	    # Secondary interfaces
	    set ips_seen($ip) 1
	    set hosts_seen($three) 1
	    if {$bug} {
		# host_to_line better be set or this is a bug.
		puts $fh "$host_to_line($cname) # Solaris 2.4 read bug"
	    }
	    if {$CONFIG(full_host_first)} {
		puts $fh "$ip $canon_name($cname) $four $three\
			[lrange $line 4 end]"
	    } else {
		puts $fh "$ip $canon_name($cname) [lrange $line 2 end]"
	    }
	}
    }

    close $local_fh
    file delete -- [file join $UNAMEIT_DATA tmp $file_name]
}

proc process_server_aliases_hosts {fh file_name shorten org_oid} {
    global VERSION UNAMEIT_DATA CONFIG
    upvar aliases_seen aliases_seen

    unameit_cp [file join gen.$VERSION $file_name]\
	    [file join $UNAMEIT_DATA tmp $file_name]
    set local_fh [open [file join $UNAMEIT_DATA tmp $file_name] r]

    while {[gets $local_fh line] != -1} {
	lassign $line ip cname alias
	if {!$CONFIG(full_host_first)} {
	    if {[regexp {^([^.]*)\.(.*)$} $cname x cshort cdomain]} {
		lassign [get_cell_and_oid $cdomain] ccell corg_oid
		if {[cequal $org_oid $corg_oid]} {
		    set cname $cshort
		}
	    }
	}
	if {$shorten} {
	    regsub {^([^.]*).*} $alias {\1} short_alias
	    if {[info exists aliases_seen($short_alias)]} {
		puts $fh "$ip $cname $alias"
	    } else {
		puts $fh "$ip $cname $alias $short_alias"
		set aliases_seen($short_alias) 1
	    }
	} else {
	    puts $fh "$ip $cname $alias"
	}
    }

    close $local_fh
    file delete -- [file join $UNAMEIT_DATA tmp $file_name]
}

proc process_hosts {} {
    global DOMAIN_NAME NIS_REGIONS UNAMEIT_DATA MY_IP GEN_FILES
    global MY_CNAME VERSION NIS_SERVERS FILE_LIST SECONDARY_IFS CONFIG
    global OS RELEASE REGION SHORT_HOST

    puts "Processing hosts..."

    set local_fh [atomic_open [file join $UNAMEIT_DATA $VERSION etc hosts]\
	    0444]
    lappend FILE_LIST(etc) [file join $UNAMEIT_DATA $VERSION etc hosts]
    
    lassign [get_cell_and_oid $REGION] cell org_oid

    puts $local_fh "0.0.0.0\tnullhost\t# for Sybase"

    ## /etc and nis files always get . hosts
    if {[info exists GEN_FILES(hosts.region..)]} {
	process_hosts_file $local_fh hosts.region.. 1
    }
    if {[info exists DOMAIN_NAME]} {
	set regions [get_up_regions $REGION $DOMAIN_NAME hosts]
    } else {
	set regions [get_org_regions $REGION hosts]
    }
    foreach region $regions {
	process_hosts_file $local_fh hosts.region.$region 1
    }

    if {![info exists canon_name($SHORT_HOST)]} {
	if {$CONFIG(full_host_first)} {
	    puts $local_fh [set host_line "$MY_IP\t$MY_CNAME $SHORT_HOST"]
	} else {
	    puts $local_fh [set host_line "$MY_IP\t$SHORT_HOST $MY_CNAME"]
	}
	set count 0
	foreach val $SECONDARY_IFS {
	    lassign [split $val @] if ip
	    if {[cequal $OS SunOS] && [cequal $RELEASE 5.4] &&
	    [incr count] == 1} {
		puts $local_fh "$host_line # Solaris 2.4 read bug"
	    }
	    if {$CONFIG(full_host_first)} {
		puts $local_fh\
		"$ip\t$MY_CNAME $SHORT_HOST-$if.$REGION $SHORT_HOST-$if"
	    } else {
		puts $local_fh\
		"$ip\t$SHORT_HOST $SHORT_HOST-$if $SHORT_HOST-$if.$REGION"
	    }
	}
    }

    # Grab all the regions because we need to know when we get to the cell
    # so we can reset the shorten_aliases variable.
    if {[info exists DOMAIN_NAME]} {
	set regions [get_up_regions $REGION $DOMAIN_NAME]
    } else {
	set regions [get_org_regions $REGION]
    }
    set shorten_aliases 1
    foreach region $regions {
	if {[info exists GEN_FILES(server_aliases.region.$region)]} {
	    process_server_aliases_hosts $local_fh\
		    server_aliases.region.$region $shorten_aliases $org_oid
	}

	if {[cequal $region $cell]} {
	    set shorten_aliases 0
	}
    }

    ## Output the NIS server addresses in the hosts file.
    if {[info exists DOMAIN_NAME] &&
    [info exists NIS_SERVERS($DOMAIN_NAME)]} {
	foreach chunk $NIS_SERVERS($DOMAIN_NAME) {
	    lassign [split $chunk @] host scope owner ips alias
	    set ip_list [split $ips ,]
	    if {$CONFIG(full_host_first)} {
		puts $local_fh "[lindex $ip_list 0]\t$host.$owner\
			$host $alias $alias.$DOMAIN_NAME"
	    } else {
		puts $local_fh "[lindex $ip_list 0]\t$host\
			$host.$owner $alias $alias.$DOMAIN_NAME"
	    }
	}
    }

    atomic_close $local_fh

    foreach nis_region [array names NIS_REGIONS] {
	set nis_fh [atomic_open [file join $UNAMEIT_DATA $VERSION nis\
		$nis_region hosts] 0444]
	lappend FILE_LIST(nis.$nis_region) \
		[file join $UNAMEIT_DATA $VERSION nis $nis_region hosts]

	puts $nis_fh "0.0.0.0\tnullhost\t# for Sybase"

	foreach var {ips_seen hosts_seen canon_name aliases_seen} {
	    catch "unset $var"
	}

	lassign [get_cell_and_oid $nis_region] cell org_oid

	if {[info exists GEN_FILES(hosts.region..)]} {
	    process_hosts_file $nis_fh hosts.region.. 0
	}
	foreach region [get_org_regions $nis_region hosts] {
	    process_hosts_file $nis_fh hosts.region.$region 0
	}

	set shorten_aliases 1
	foreach region [get_org_regions $nis_region] {
	    if {[info exists GEN_FILES(server_aliases.region.$region)]} {
		process_server_aliases_hosts $nis_fh\
			server_aliases.region.$region $shorten_aliases $org_oid
	    }

	    if {[cequal $region $cell]} {
		set shorten_aliases 0
	    }
	}

	atomic_close $nis_fh
    }
}

proc process_host_console {} {
    puts "Processing host console..."
    grab_single_file host_console
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

proc process_netgroup_file {fh file_name cell} {
    global UNAMEIT_DATA VERSION DBM_MAX
    upvar mapping mapping

    unameit_cp gen.$VERSION/$file_name $UNAMEIT_DATA/tmp/$file_name
    set local_fh [open $UNAMEIT_DATA/tmp/$file_name r]

    while {[gets $local_fh line] != -1} {
 	set key [ctoken line { }]
	
	if {[info exists mapping($key)]} {
	    lassign [split $key @] short_key region
	    set print_key $short_key
	} else {
	    set print_key $key
	}

 	puts -nonewline $fh $print_key
 	set ccount [clength $print_key]
	
  	set split_count 0

	set line [string trimleft $line]
	foreach token [split $line { }] {
  	    if {$ccount > $DBM_MAX} {
 		set new_key $print_key--$split_count
  		puts -nonewline $fh " $new_key\n$new_key"
 		set ccount [clength $new_key]
  		incr split_count
  	    }

 	    puts -nonewline $fh " "
 	    incr ccount

	    switch -glob -- $token {
		"(-,*" {
		    # User. Do nothing
		}
		"(*" {
		    ## Found hostname. Output short name in addition to long
		    ## name if in same cell.
		    if {[regexp {^\(([^,.]*)\.([^,]+),-,\)$}\
			    $token x short_host host_region] &&
			    [region_is_in_cells_org $host_region $cell]} {
			set out_str "($short_host,-,) "
			puts -nonewline $fh $out_str
			incr ccount [clength $out_str]
		    }
		}
		default {
		    ## Found reference to subnetgroup.
		    if {[info exists mapping($token)]} {
			lassign [split $token @] short_name region
			set token $short_name
		    }
		}
	    }
		
  	    puts -nonewline $fh $token
 	    incr ccount [clength $token]
  	}
  	puts $fh ""
    }
    close $local_fh
    file delete -- [file join $UNAMEIT_DATA tmp $file_name]
}

proc region_is_in_cells_org {region cell} {
    global ORG_OID_2_CELLS REGION_IN_CELL_ORG_CACHE

    if {[info exists REGION_IN_CELL_ORG_CACHE($region.$cell)]} {
	return $REGION_IN_CELL_ORG_CACHE($region.$cell)
    }

    lassign [get_cell_and_oid $region] region_cell region_org_oid

    foreach c $ORG_OID_2_CELLS($region_org_oid) {
	if {[cequal $cell $c]} {
	    return [set REGION_IN_CELL_ORG_CACHE($region.$cell) 1]
	}
    }

    return [set REGION_IN_CELL_ORG_CACHE($region.$cell) 0]
}
    
proc process_netgroup {} {
    global DOMAIN_NAME NIS_REGIONS UNAMEIT_DATA VERSION REGION FILE_LIST

    puts "Processing netgroups..."

    foreach nis_region [array names NIS_REGIONS] {
	set nis_fh [atomic_open\
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/netgroup 0444]
	lappend FILE_LIST(nis.$nis_region) \
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/netgroup

	set mapping() 0; unset mapping
	foreach region [get_up_regions $nis_region cell netgroup] {
	    set_mapping_array netgroup.region.$region { }
	}
	set seen() 0; unset seen

	lassign [get_cell_and_oid $nis_region] nis_cell nis_org_oid

	process_netgroup_file $nis_fh netgroups $nis_cell

	atomic_close $nis_fh
    }
}

proc process_netmasks {} {
    puts "Processing netmasks..."
    grab_single_file netmasks
}

proc process_networks {} {
    puts "Processing networks..."
    grab_single_file networks
}

proc process_pagers {} {
    global UNAMEIT_DATA VERSION FILE_LIST PAGER_REGIONS NIS_REGIONS
    global GEN_FILES IS_PULL_SERVER

    puts "Processing pagers..."
    if {[array size PAGER_REGIONS] > 0} {
	set local_fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/providers 0444]
	foreach region [array names PAGER_REGIONS] {
	    if {[info exists GEN_FILES(providers.region.$region)]} {
		if {$IS_PULL_SERVER} {
		    set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
			    providers.region.$region] r]
		    copyfile $rfh $local_fh
		    close $rfh
		} else {
		    unameit_send $local_fh [list unameit_pull_read_file \
			    [file join gen.$VERSION providers.region.$region]]
		}
	    }
	}
	atomic_close $local_fh
	# Don't put providers file on FILE_LIST. It is not installed.
    }
    
    foreach nis_region [array names NIS_REGIONS] {
	unameit_cp gen.$VERSION/pagers \
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/pagers
	lappend FILE_LIST(nis.$nis_region) \
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/pagers
    }
}

proc read_shadow_passwords {} {
    upvar shadow_passwds shadow_passwds

    set shadow_passwds() 1; unset shadow_passwds()
    set fd [open /etc/shadow r]
    while {[gets $fd line] != -1} {
	set list [split $line :]
	set shadow_passwds([lindex $list 0]) [lrange $list 1 end]
    }
    close $fd
}

proc process_passwd_line {fh line shadow_fd {sort_var ""}} {
    global MAP_TO_DIR
    upvar logins_seen logins_seen shadow_passwds shadow_passwds\
	    shell_mapping shell_mapping login_count login_count

    if {![cequal $sort_var ""]} {
	upvar 1 $sort_var sort
    }

    set split_line [split $line :]
    set login [lindex $split_line 0]
    set uid [lindex $split_line 2]

    if {[info exists logins_seen($login)]} {
	return
    }

    set logins_seen($login) 1
    incr login_count

    ## Replace automount path
    if {[scan [lindex $split_line 5] {$%s} map] == 1} {
	if {[info exists MAP_TO_DIR($map)]} {
	    set split_line [lreplace $split_line 5 5 $MAP_TO_DIR($map)/$login]
	} else {
	    set split_line [lreplace $split_line 5 5 /]
	}
    }

    ## Do shell path processing
    set shell [lindex $split_line 6]
    if {![regexp {^/} $shell]} {
	if {[info exists shell_mapping($shell)]} {
	    set shell $shell_mapping($shell)
	} else {
	    set shell /bin/$shell
	}
    }
    set split_line [lreplace $split_line 6 6 $shell]

    if {![cequal $shadow_fd ""]} {
	if {[info exists shadow_passwds($login)]} {
	    set shadow_splice [lrange $shadow_passwds($login) 1 end]
	} else {
	    set shadow_splice [list {} {} {} {} {} {} {}]
	}
	set password [lindex $split_line 1]
	set split_line [lreplace $split_line 1 1 x]
	if {[cequal $password *]} {
	    set password *LK*
	}
	puts $shadow_fd [join [concat $login $password $shadow_splice] :]
    }
    set line [join $split_line :]
    if {![lempty $sort_var]} {
	set sort($uid,$login) $line
    } else {
	puts $fh $line
    }
}

proc process_passwd_file {fh file_name shadow_fd {sort_var ""}} {
    global UNAMEIT_DATA VERSION
    upvar logins_seen logins_seen shadow_passwds shadow_passwds\
	    shell_mapping shell_mapping login_count login_count

    set pass_var ""
    if {![cequal $sort_var ""]} {
	upvar 1 $sort_var [set pass_var sort]
    }

    unameit_cp gen.$VERSION/$file_name $UNAMEIT_DATA/tmp/$file_name
    set local_fh [open $UNAMEIT_DATA/tmp/$file_name r]

    while {[gets $local_fh line] != -1} {
	process_passwd_line $fh $line $shadow_fd $pass_var
    }
    close $local_fh
    file delete -- [file join $UNAMEIT_DATA tmp $file_name]
}

proc process_system_logins {fh shadow_fd regions {sort_var ""}} {
    global VERSION UNAMEIT_DATA GEN_FILES OS RELEASE OS_TO_FAMILY
    upvar logins_seen logins_seen shadow_passwds shadow_passwds\
	    shell_mapping shell_mapping login_count login_count

    set pass_var ""
    if {![cequal $sort_var ""]} {
	upvar 1 $sort_var [set pass_var sort]
    }

    foreach region $regions {
	unameit_cp gen.$VERSION/system_logins.region.$region\
		$UNAMEIT_DATA/tmp/system_logins.region.$region

	## Suck in OS override data for this region
	catch {unset os_overrides}
	if {[info exists GEN_FILES(os_logins.region.$region)]} {
	    unameit_cp gen.$VERSION/os_logins.region.$region\
		    $UNAMEIT_DATA/tmp/os_logins.region.$region

	    for_file line $UNAMEIT_DATA/tmp/os_logins.region.$region {
		lassign [split $line :] name os release password uid gid\
			gecos path shell
		set os_overrides($os.$release.$name) [list $password $uid\
			$gid $gecos $path $shell]
	    }

	    file delete --\
		[file join $UNAMEIT_DATA tmp os_logins.region.$region]
	}

	for_file line $UNAMEIT_DATA/tmp/system_logins.region.$region {
	    lassign [split $line :] name template password uid gid gecos path\
		    shell
	    if {[info exists os_overrides($OS.$RELEASE.$name)]} {
		lassign $os_overrides($OS.$RELEASE.$name) password uid gid\
			gecos path shell
	    } else {
		if {[info exists OS_TO_FAMILY($OS.$RELEASE)]} {
		    lassign $OS_TO_FAMILY($OS.$RELEASE) os_fam\
			    release_fam
		    if {[info exists\
			    os_overrides($os_fam.$release_fam.$name)]} {
			lassign $os_overrides($os_fam.$release_fam.$name)\
				password uid gid gecos path shell
		    } else {
			if {[cequal $template Yes]} {
			    set logins_seen($name) 1
			    continue
			}
		    }
		} else {
		    if {[cequal $template Yes]} {
			set logins_seen($name) 1
			continue
		    }
		}
	    }
	    process_passwd_line $fh [join [list $name $password $uid $gid\
		    $gecos $path $shell] :] $shadow_fd $pass_var
	}
	file delete --\
	    [file join $UNAMEIT_DATA tmp system_logins.region.$region]
    }
}

proc read_shell_locations {file} {
    global VERSION UNAMEIT_DATA
    upvar shell_mapping shell_mapping

    unameit_cp gen.$VERSION/$file $UNAMEIT_DATA/tmp/$file
    for_file line $UNAMEIT_DATA/tmp/$file {
	scan $line "%s %s" shell path
	if {![info exists shell_mapping($shell)]} {
	    set shell_mapping($shell) $path
	}
    }
    file delete -- [file join $UNAMEIT_DATA tmp $file]
}

proc root_first {a b} {
    if {[regexp {,root$} $a]} {
	return -1
    }
    if {[regexp {,root$} $b]} {
	return 1
    }
    lassign [split $a ,] a_uid a_login
    lassign [split $b ,] b_uid b_login
    if {[expr $a_uid < $b_uid]} {
	return -1
    } elseif {[expr $b_uid < $a_uid]} {
	return 1
    } else {
	return [string compare $a_login $b_login]
    }
}

proc process_passwd {} {
    global GEN_FILES UNAMEIT_DATA DOMAIN_NAME REGION
    global NIS_REGIONS VERSION USE_PLUSES FILE_LIST ORG_OID_2_CELLS
    global MAP_TO_DIR CONFIG

    puts "Processing passwd..."

    ## Process user logins in /etc.
    lassign [get_cell_and_oid $REGION] cell org_oid

    ## Read shell_location file
    if {[info exists GEN_FILES(shell_location.region.$REGION)]} {
	read_shell_locations shell_location.region.$REGION
    }
    if {![cequal $REGION $cell] &&
    [info exists GEN_FILES(shell_location.region.$cell)]} {
	read_shell_locations shell_location.region.$cell
    }

    ## Suck in old shadow contents
    if {[file exists /etc/shadow]} {
	read_shadow_passwords
	set shadow_fd [atomic_open $UNAMEIT_DATA/$VERSION/etc/shadow 0400]
	lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/shadow
    } else {
	set shadow_fd ""
    }
    
    set local_fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/passwd 0444]
    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/passwd

    set logins_seen() 1; unset logins_seen()
    set login_count 0

    ## Process system logins in /etc
    process_system_logins $local_fh $shadow_fd [get_up_regions $REGION\
	    cell system_logins] lines
    if {[info exists DOMAIN_NAME]} {
	set stopping_point $DOMAIN_NAME
    } else {
	set stopping_point cell
    }
    foreach type {logins user_logins} {
	foreach region [get_up_regions $REGION $stopping_point $type] {
	    process_passwd_file $local_fh $type.region.$region $shadow_fd lines
	}
    }

    ## Never leave the /etc/passwd file empty!
    if {![info exists lines(0,root)]} {
	puts stderr "No root account in /etc/passwd"
	puts stderr "Not installing /etc files to system"
	set CONFIG(etc_install_type) none
    }

    ## Dump out memory data.
    foreach index [lsort -command root_first [array names lines]] {
	puts $local_fh $lines($index)
    }

    if {[info exists DOMAIN_NAME] && $USE_PLUSES} {
	puts $local_fh +::::::
    }
    atomic_close $local_fh
    if {![cequal $shadow_fd ""]} {
	atomic_close $shadow_fd
    }

    foreach nis_region [array names NIS_REGIONS] {
	set nis_fh [atomic_open $UNAMEIT_DATA/$VERSION/nis/$nis_region/passwd\
		0444]
	lappend FILE_LIST(nis.$nis_region) \
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/passwd

	## Read shell_location file
	catch {unset shell_mapping}
	lassign [get_cell_and_oid $nis_region] cell org_oid
	if {[info exists GEN_FILES(shell_location.region.$nis_region)]} {
	    read_shell_locations shell_location.region.$nis_region
	}
	if {![cequal $REGION $cell] &&
	[info exists GEN_FILES(shell_location.region.$cell)]} {
	    read_shell_locations shell_location.region.$cell
	}

	foreach region [get_up_regions $nis_region cell logins] {
	    process_passwd_file $nis_fh logins.region.$region ""
	}

	foreach c $ORG_OID_2_CELLS($org_oid) {
	    catch {unset logins_seen}; set logins_seen() 1; unset logins_seen()

	    if {[cequal $c $cell]} {
		if {[info exists GEN_FILES(user_logins.region.$cell)]} {
		    process_passwd_file $nis_fh user_logins.region.$cell ""
		}
	    } else {
		set alt_fh [atomic_open\
			$UNAMEIT_DATA/$VERSION/nis/$nis_region/passwd.$c 0444]
		lappend FILE_LIST(nis.$nis_region)\
			$UNAMEIT_DATA/$VERSION/nis/$nis_region/passwd.$c

		if {[info exists GEN_FILES(user_logins.region.$c)]} {
		    process_passwd_file $alt_fh user_logins.region.$c ""
		}

		atomic_close $alt_fh
	    }
	}
	atomic_close $nis_fh
    }

    catch {unset MAP_TO_DIR}
}

## Suck in the printer types so we can look up and output there values
## when needed. We don't output a printer type unless a printer on the
## local machine uses that printer type (for security reasons).
proc read_printer_types {cell} {
    global VERSION UNAMEIT_DATA GEN_FILES
    upvar printer_type printer_type

    if {[info exists GEN_FILES(printer_type.cell.$cell)]} {
	unameit_cp gen.$VERSION/printer_type.cell.$cell\
		$UNAMEIT_DATA/tmp/printer_type.cell.$cell
	for_file line $UNAMEIT_DATA/tmp/printer_type.cell.$cell {
	    regexp {^[^:]*} $line key
	    set printer_type($key) $line
	}
	file delete -- [file join $UNAMEIT_DATA tmp printer_type.cell.$cell]
    }
}

proc read_printer_file {fh cell} {
    global VERSION UNAMEIT_DATA GEN_FILES MY_NAME
    upvar printer_type printer_type aliases aliases

    if {[info exists GEN_FILES(printer.cell.$cell)]} {
	unameit_cp gen.$VERSION/printer.cell.$cell\
		$UNAMEIT_DATA/tmp/printer.cell.$cell
	for_file line $UNAMEIT_DATA/tmp/printer.cell.$cell {
	    set host [ctoken line { }]
	    set template [ctoken line { }]
	    set printer_name [ctoken line { }]
	    set line [string range $line 1 end]	;# Trash leading space

	    if {[info exists MY_NAME($host)] &&
		    ![info exists template_output($template)] &&
		    [info exists printer_type($template)]} {
		puts $fh $printer_type($template)
		set template_output($template) 1
	    }

	    set printer_list $printer_name
	    if {[info exists aliases($printer_name)]} {
		foreach alias $aliases($printer_name) {
		    append printer_list |$alias
		}
	    }
	    puts $fh $printer_list:$line
	}
	file delete -- [file join $UNAMEIT_DATA tmp printer.cell.$cell]
    }
}

proc read_printer_alias_file {file} {
    global VERSION UNAMEIT_DATA
    upvar aliases aliases

    unameit_cp gen.$VERSION/$file [file join $UNAMEIT_DATA tmp $file]
    for_file line [file join $UNAMEIT_DATA tmp $file] {
	scan $line {%s %s} alias printer
	lappend aliases($printer) $alias
    }
    file delete -- [file join $UNAMEIT_DATA tmp $file]
}

proc process_printcap {} {
    global VERSION UNAMEIT_DATA GEN_FILES FILE_LIST REGION MY_CNAME
    
    puts "Processing printcap..."

    lassign [get_cell_and_oid $REGION] cell org_oid

    set fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/printcap 0444]
    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/printcap

    read_printer_types $cell

    if {[info exists GEN_FILES(printer_alias.host.$MY_CNAME)]} {
	read_printer_alias_file printer_alias.host.$MY_CNAME
    }

    foreach region [get_up_regions $REGION cell printer_alias] {
	read_printer_alias_file printer_alias.region.$region
    }

    read_printer_file $fh $cell

    atomic_close $fh
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

proc process_services {} {
    global UNAMEIT_DATA VERSION REGION GEN_FILES NIS_REGIONS FILE_LIST
    global IS_PULL_SERVER

    puts "Processing services..."

    set local_fh [atomic_open $UNAMEIT_DATA/$VERSION/etc/services 0444]
    lappend FILE_LIST(etc) $UNAMEIT_DATA/$VERSION/etc/services

    lassign [get_cell_and_oid $REGION] cell

    if {[info exists GEN_FILES(services.cell.$cell)]} {
	if {$IS_PULL_SERVER} {
	    set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
		    services.cell.$cell] r]
	    copyfile $rfh $local_fh
	    close $rfh
	} else {
	    unameit_send $local_fh [list unameit_pull_read_file\
		    [file join gen.$VERSION services.cell.$cell]]
	}
    }
    if {[info exists GEN_FILES(services.cell..)] && ![cequal $cell .]} {
	if {$IS_PULL_SERVER} {
	    set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
		    services.cell..] r]
	    copyfile $rfh $local_fh
	    close $rfh
	} else {
	    unameit_send $local_fh [list unameit_pull_read_file\
		    [file join gen.$VERSION services.cell..]]
	}
    }

    atomic_close $local_fh

    foreach nis_region [array names NIS_REGIONS] {
	set nis_fh [atomic_open\
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/services 0444]
	lappend FILE_LIST(nis.$nis_region)\
		$UNAMEIT_DATA/$VERSION/nis/$nis_region/services

	lassign [get_cell_and_oid $nis_region] cell

	if {[info exists GEN_FILES(services.cell.$cell)]} {
	    if {$IS_PULL_SERVER} {
		set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
			services.cell.$cell] r]
		copyfile $rfh $nis_fh
		close $rfh
	    } else {
		unameit_send $nis_fh [list unameit_pull_read_file\
			[file join gen.$VERSION services.cell.$cell]]
	    }
	}
	if {[info exists GEN_FILES(services.cell..)] && ![cequal $cell .]} {
	    if {$IS_PULL_SERVER} {
		set rfh [open [file join $UNAMEIT_DATA data gen.$VERSION\
			services.cell..] r]
		copyfile $rfh $nis_fh
		close $rfh
	    } else {
		unameit_send $nis_fh [list unameit_pull_read_file\
			[file join gen.$VERSION services.cell..]]
	    }
	}

	atomic_close $nis_fh
    }
}

proc format_sybase_interface {name host ip port usenullhost} {
    set result [format "%s\n" $name]
    #
    # Machines that use TLI have /etc/netconfig
    #
    if [file exists /etc/netconfig] {
	#
	# The TLI format of the Sybase Interfaces file
	# is the most brain-dead idea I have seen thus far.
	#
	# XXX: ideally should pick the "nearest" from all the addresses
	# of master host,  otherwise,   multihomed hosts will accept
	# connections on all ports,  but no one will come to the party!
	#
	if {$usenullhost} {
	    set master_ip 00000000
	} else {
	    set master_ip $ip
	}
	append result \
	    [format "\tquery tli tcp /dev/tcp \\x0002%04x%s%08x%08x\n" \
		$port $ip 0 0]
	append result \
	    [format "\tmaster tli tcp /dev/tcp \\x0002%04x%s%08x%08x\n" \
		$port $master_ip 0 0]
	#
	# XXX: Do we need console, debug and trace in this case also?
	#
    } else {
	if {$usenullhost} {
	    set master_host nullhost
	} else {
	    set master_host $host
	}
	append result "\tquery tcp sun-ether $host $port\n"
	append result "\tmaster tcp sun-ether $master_host $port\n"
	append result "\tconsole tcp sun-ether $host [expr $port + 1]\n"
	append result "\tdebug tcp sun-ether $host [expr $port + 2]\n"
	append result "\ttrace tcp sun-ether $host [expr $port + 3]\n"
    }
    set result
}

proc process_sybase_interfaces {} {
    global UNAMEIT_DATA VERSION FILE_LIST HAS_SYBASE_FILES REGION GEN_FILES
    global CONFIG

    puts "Processing sybase interfaces..."

    if {!$HAS_SYBASE_FILES} {
	return
    }

    lassign [get_cell_and_oid $REGION] cell org_oid
    set local_fh [atomic_open $UNAMEIT_DATA/$VERSION/sybase/interfaces 0444]
    set FILE_LIST(sybase) $UNAMEIT_DATA/$VERSION/sybase/interfaces

    unameit_cp gen.$VERSION/sybase_interfaces.cell.$cell\
	    $UNAMEIT_DATA/tmp/sybase_interfaces.cell.$cell
    for_file line $UNAMEIT_DATA/tmp/sybase_interfaces.cell.$cell {
	scan $line {%s %s %s %s %s} name cell region host_ip port
	lassign [split $host_ip @] host ip
	puts -nonewline $local_fh [format_sybase_interface $name $host $ip\
		$port $CONFIG(sybase_nullhost)]
    }
    file delete -- [file join $UNAMEIT_DATA tmp sybase_interfaces.cell.$cell]

    atomic_close $local_fh
}

proc main {} {
    global tcl_platform pullPriv
    global UNAMEIT_DATA HOST_UUID MY_CNAME VERSION GEN_FILES PULL_HOST
    global NIS_REGIONS DNS_REGIONS PULL_REGIONS MY_IP VERSION
    global FILE_LIST DELAYED_DELETE_DIRS SECONDARY_IFS
    global HAS_SYBASE_FILES INSTALL_FILES REGION IS_PULL_SERVER
    global OS RELEASE SHORT_HOST MY_NAME INET_DIR MAIL_DIR USE_PLUSES CONFIG

    puts "Initializing..."

    set UNAMEIT_DATA $pullPriv(data)
    set INSTALL_FILES all

    set HOST_UUID [unameit_send [list unameit_pull_get_host_uuid $SHORT_HOST]]
    CheckPathList $HOST_UUID
    file delete -- $UNAMEIT_DATA/version

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

    read_os_file

    process_configuration

    interpret_domain_name

    #verify_host_and_ip $MY_CNAME $MY_IP

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
    if {[file isdirectory /etc/mail]} {
	set MAIL_DIR /etc/mail
    } else {
	set MAIL_DIR /etc
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
	Linux.* {
	    set USE_PLUSES 0
	}
    }

    foreach v {dns etc} {
	set FILE_LIST($v) {}
    }

    # Process all the files
    process_aliases
    process_automounts
    process_ethers
    process_groups
    process_hosts
    process_host_console
    process_named
    # process_inaddr must come after process_named. They share a file handle.
    process_inaddr
    process_netgroup
    process_netmasks
    process_networks
    process_pagers
    process_passwd
    process_printcap
    process_resolv_conf
    process_services
    process_sybase_interfaces

    set INSTALL_FILES all
    file delete -force -- $UNAMEIT_DATA/$SHORT_HOST
    set CONFIG(nis_relative) 1
    foreach type {dns nis etc sybase} {
	set CONFIG(${type}_dir) $UNAMEIT_DATA/$SHORT_HOST/$type
	set CONFIG(${type}_install_type) unsafe
    }

    set DELAYED_DELETE_DIRS {}
    if {![cequal $INSTALL_FILES none]} {
	make_directories $UNAMEIT_DATA/$SHORT_HOST
	create_system_directories $INSTALL_FILES
	install_files_to_system $INSTALL_FILES
    }

    atomic_close $version_fd

    #if {[array size DNS_REGIONS] > 0} {
    #	if {[catch {open /etc/named.pid r} fd] == 0} {
    #	    gets $fd line
    #	    if {![regexp {[0-9]+} $line]} {
    #		puts stderr "/etc/named.pid file doesn't contain a pid"
    #	    } else {
    #		catch {kill HUP $line}
    #	    }
    #	    close $fd
    #	}
    #}
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
