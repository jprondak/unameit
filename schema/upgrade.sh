#!/bin/sh
#
# $Id: $
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

# Tcl ignores the next line\
: shell ignores lines through << 'END_TCL_CODE'

#
# Data dump file management routines
#

proc old_file {cname} {
    global IDIR old_file
    file join $IDIR $old_file($cname)
}

proc class_file {cname} {
    global ODIR unrestored
    file join $ODIR $unrestored($cname)
}

proc old_init {} {
    global IDIR old_file old_fields oid2classname root_oid
    source [file join $IDIR Info.tcl]
    array set old_file [array get unrestored]
    array set old_fields [array get fields]
}

proc load_info {} {
    global FD ODIR
    #
    set path [file join $ODIR Info.tcl]
    if {[file exists $path]} {
	uplevel #0 source $path
    }
    set FD(Info) [atomic_open $path 0644]
}

proc dump_info {} {
    global FD fields instances unrestored oid2classname root_oid
    #
    set fd $FD(Info)
    if {[catch {
		foreach cname [lsort [array names fields]] {
		    if {$instances($cname) == 0} continue
		    puts $fd [list set fields($cname) $fields($cname)]
		    puts $fd [list set instances($cname) $instances($cname)]
		    puts $fd [list set unrestored($cname) $unrestored($cname)]
		}
		foreach oid [lsort [array names oid2classname]] {
		    puts $fd [list set oid2classname($oid)\
			    $oid2classname($oid)]
		}
		foreach oid [lsort [array names root_oid]] {
		    puts $fd [list set root_oid($oid) $root_oid($oid)]
		}
		foreach cname [unameit_get_subclasses unameit_data_item] {
		    puts $fd [list set subclasses($cname)\
			    [unameit_get_subclasses $cname]]
		}
	    } error] == 0} {
	atomic_close $fd
    } else {
	global errorCode errorInfo
	set ec $errorCode
	set ei $errorInfo
	atomic_abort $fd
	return -code error -errorinfo $ei -errorcode $ec $error
    }
}

proc get_fields {cname} {
    set result {}
    foreach attr [unameit_get_attributes $cname] {
	switch -- $attr uuid - deleted continue
	lappend result $attr
    }
    return $result
}

proc load_class {cname code} {
    global fields unrestored
    upvar 1 oid oid uuid uuid F F
    #
    if {![info exists unrestored($cname)]} return
    set in [open [class_file $cname] r]
    #
    set cmd {lassign $DATA}
    foreach f $fields($cname) {
	lappend cmd F($f)
    }
    #
    catch {unset F}
    while {[lgets $in line] != -1} {
	lassign $line oid uuid DATA	
	eval $cmd
	uplevel 1 $code
    }
    close $in
}

proc edit_class {cname {code ""}} {
    global FD fields unrestored instances
    upvar 1 oid oid uuid uuid F F
    #
    if {[info exists unrestored($cname)]} {
 	if {[cequal $code ""]} {
 	    error "Class $cname already exists in data directory"
 	}
 	set in [open [class_file $cname] r]
 	set cmd {lassign $DATA}
 	foreach f $fields($cname) {
 	    lappend cmd F($f)
 	}
 	catch {unset F}
	set FD($cname) [atomic_open [class_file $cname] 0644]
 	while {[lgets $in line] != -1} {
 	    lassign $line oid uuid DATA
 	    eval $cmd
 	    uplevel 1 $code
 	}
 	close $in
    } else {
 	set unrestored($cname) $cname.dat
 	set fields($cname) [get_fields $cname]
 	set instances($cname) 0
	set FD($cname) [atomic_open [class_file $cname] 0644]
    }
}

proc finish_class {cname} {
    global FD
    #
    if {[catch {atomic_close $FD($cname)} error]} {
	global errorCode errorInfo
	set ec $errorCode
	set ei $errorInfo
	atomic_abort $FD($cname)
	return -code error -errorinfo $ei -errorcode $ec $error
    }
}

proc dump_instance {oid uuid} {
    global FD fields instances
    upvar #0 $oid item $oid $oid
    #
    set cname $item(Class)
    incr instances($cname)
    set DATA {}
    #
    foreach f $fields($cname) {
	if {[info exists item($f)]} {
	    lappend DATA $item($f)
	} else {
	    lappend DATA {}
	}
    }
    #
    puts $FD($cname) [list $oid $uuid $DATA]
}

proc edit_protected {} {
    global FD ODIR
    set FD(Protected) [atomic_open [file join $ODIR Protected.dat] 0644]
}

proc dump_protected {oid uuid} {
    global FD
    puts $FD(Protected) [list $oid $uuid]
}

proc finish_protected {} {
    global FD
    #
    if {[catch {atomic_close $FD(Protected)} error]} {
	global errorCode errorInfo
	set ec $errorCode
	set ei $errorInfo
	atomic_abort $FD(Protected)
	return -code error -errorinfo $ei -errorcode $ec $error
    }
}

proc load_old_class {cname code} {
    global old_fields old_file
    upvar 1 uuid uuid F F oid oid
    #
    if {![info exists old_file($cname)]} return
    #
    set in [open [old_file $cname] r]
    #
    set cmd {lassign $DATA}
    foreach f $old_fields($cname) {
	lappend cmd F($f)
    }
    #
    catch {unset F}
    while {[lgets $in line] != -1} {
	lassign $line oid uuid DATA
	eval $cmd
	uplevel 1 $code
    }
    close $in
}

proc load_old_protected {code} {
    global IDIR
    upvar 1 oid oid uuid uuid
    #
    set in [open [file join $IDIR Protected.dat] r]
    #
    while {[lgets $in line] != -1} {
	lassign $line oid uuid
	uplevel 1 $code
    }
    close $in
}

proc convert_unchanged {} {
    global old_file unrestored unprotect old_fields fields
    #
    foreach cname [array names old_file] {
	if {[info exists unrestored($cname)]} continue
	edit_class $cname
	set fields($cname) $old_fields($cname)
	load_old_class $cname {
	    upvar #0 $oid object
	    set object(Class) $cname
	    array set object [array get F]
	    dump_instance $oid $uuid
	    unset object
	}
	finish_class $cname
    }
    #
    # Fix up protected objects
    #
    edit_protected
    load_old_protected {
	if {![info exists unprotect($oid)]} {
	    dump_protected $oid $uuid
	}
    }
    finish_protected
}

proc safe_incr {var} {
    upvar 1 $var val
    if {[info exists val]} {incr val} {set val 1}
}

#
# (Possibly) Create an external address object to add to mailing list.
#
proc v4_create_address {owner elem} {
    global addr_cache filenum prognum
    upvar #0 $elem elem_object
    set key "$elem_object(ml_address).$owner"
    if {[info exists addr_cache($key)]} {
	return $addr_cache($key)
    }
    switch -regexp -- $key {
	{^ *(:include:)? */.*} {
	    # File
	    upvar #0 [set uuid [uuidgen]] new_object
	    set new_object(Class) file_mailbox
	    set new_object(name)\
		[format "filembox%d" [safe_incr filenum($owner)]]
	    set new_object(owner) $owner
	    #
	    # XXX: reject empty ml_host
	    #
	    set new_object(mailbox_route) $elem_object(ml_host)
	    regsub {^ *(:include:)? *(.*)} $elem_object(ml_address)\
		{\1\2} new_object(unix_pathname)
	}
	{^\|} {
	    # Program
	    upvar #0 [set uuid [uuidgen]] new_object
	    set new_object(Class) program_mailbox
	    set new_object(name)\
		[format "progmbox%d" [safe_incr prognum($owner)]]
	    set new_object(owner) $owner
	    #
	    # XXX: reject empty ml_host
	    #
	    set new_object(mailbox_route) $elem_object(ml_host)
	    set new_object(unix_pathname)\
		[string range $elem_object(ml_address) 1 end]
	}
	default {
	    # external address
	    upvar #0 [set uuid [uuidgen]] new_object
	    set new_object(Class) external_mail_address
	    set new_object(name) $elem_object(ml_address)
	    set new_object(owner) $owner
	}
    }
    set new_object(mtime) $elem_object(mtime)
    set new_object(mtran) $elem_object(mtran)
    set new_object(modby) $elem_object(modby)
    dump_instance $uuid $uuid
    unset new_object
    return [set addr_cache($key) $uuid]
}

proc v4_create_forward_list {user_oid} {
    upvar #0 $user_oid user_object
    upvar #0 [set uuid [uuidgen]] object
    set object(Class) mailing_list
    set object(owner) $user_object(owner)
    set object(name) "$user_object(name)-forward"
    set object(comment) "Mail forwarding list for '$user_object(name)'"
    set object(mtime) $user_object(mtime)
    set object(mtran) $user_object(mtran)
    set object(modby) "UName*It 2.5 Conversion"
    dump_instance $uuid $uuid
    unset object
    return $uuid
}

proc v4_add_objects {list elems} {
    foreach elem $elems {
	upvar #0 $elem elem_object
	set elem_object(owner) $list
	dump_instance $elem $elem_object(uuid)
	unset elem_object
    }
}

proc v4_add_addresses {owner list elems} {
    foreach elem $elems {
	upvar #0 $elem elem_object
	set elem_object(owner) $list
	set elem_object(ml_member) [v4_create_address $owner $elem]
	dump_instance $elem $elem_object(uuid)
	unset elem_object
    }
}

proc v4_convert_mail {} {
    global old_file oid2classname
    #
    set now [clock seconds]
    #
    foreach cname {
	    mailing_list mailing_list_member person user_login
	    file_mailbox program_mailbox external_mail_address
	} {
	edit_class $cname
	lappend clist $cname
    }
    #
    # Hash user_login oids.
    #
    load_old_class user_login {
	set isuser($oid) 1
	switch -- $F(login_enabled) "" - Yes {
	    set is_active($F(person)) 1
	}
	set has_accounts($F(person)) 1
    }
    #
    # Dump person records
    #
    load_old_class person {
	upvar #0 $oid object
	array set object [array get F]
	set object(Class) person
	if {[info exists has_accounts($oid)] &&
		![info exists is_active($oid)]} {
	    set object(person_expiration) $now
	}
	dump_instance $oid $uuid
	unset object
    }
    catch {unset has_accounts}
    #
    # Load mailing lists name, owner etc into memory
    # and dump into new mailing_list file
    #
    load_old_class mailing_list {
	upvar #0 $oid object
	array set object [array get F]
	set object(Class) mailing_list
	dump_instance $oid $uuid
    }
    #
    # Dump mailing_list_member objects,  but defer those that
    # redirect a user's mail.
    #
    foreach cname {mailing_list_login mailing_list_sublist} {
	load_old_class $cname {
	    upvar #0 $oid object
	    array set object [array get F]
	    set object(Class) mailing_list_member
	    #
	    if {[info exists isuser($F(owner))]} {
		set object(uuid) $uuid
		lappend forward_objects($F(owner)) $oid
	    } else {
		dump_instance $oid $uuid
		unset object
	    }
	}
    }
    #
    # Dump external address and program file objects.
    # Again defer dealing with user_login objects.
    #
    load_old_class mailing_list_address {
	upvar #0 $oid object
	array set object [array get F]
	set object(Class) mailing_list_member
	#
	if {[info exists isuser($F(owner))]} {
	    set object(uuid) $uuid
	    lappend forward_addresses($F(owner)) $oid
	} else {
	    upvar #0 $object(owner) list_object
	    set object(ml_member) [v4_create_address $list_object(owner) $oid]
	    dump_instance $oid $uuid
	    unset object
	}
    }
    #
    # Process user_logins,  also deal with deferred mail forwarding
    #
    load_old_class user_login {
	upvar #0 $oid object
	set oid2uuid($oid) $uuid
	array set object [array get F]
	#
	set object(Class) user_login
	#
	# Deal with mail routing
	#
	if {[info exists forward_objects($oid)]} {
	    if {![info exists forward_addresses($oid)] &&
		    [llength $forward_objects($oid)] == 1} {
		set object(mailbox_route) $forward_objects($oid)
	    } else {
		set object(mailbox_route) [v4_create_forward_list $oid]
		v4_add_objects $object(mailbox_route) $forward_objects($oid)
		if {[info exists forward_addresses($oid)]} {
		    v4_add_addresses $object(owner) $object(mailbox_route)\
			$forward_addresses($oid)
		}
	    }
	} elseif {[info exists forward_addresses($oid)]} {
	    if {[llength $forward_addresses($oid)] == 1} {
		set object(mailbox_route)\
		    [v4_create_address $object(owner) $forward_addresses($oid)]
	    } else {
		set object(mailbox_route) [v4_create_forward_list $oid]
		v4_add_addresses $object(owner) $object(mailbox_route)\
		    $forward_addresses($oid)
	    }
	}
	#
	switch -- $F(login_enabled) {
	    No {
		if {[info exists is_active($object(person))]} {
		    regsub {^\**} $object(password) {*} object(password)
		    set object(shell) "/bin/true"
		}
		if {![info exists object(mailbox_route)]} {
		    set object(preferred_mailbox) Person
		    set object(maibox_route) ""
		}
	    }
	}
	#
	if {![info exists object(mailbox_route)]} {
	    set object(maibox_route) $F(mailhost)
	}
	dump_instance $oid $uuid
	unset object
    }
    catch {unset old_file(person)}
    catch {unset old_file(user_login)}
    catch {unset old_file(mailing_list)}
    catch {unset old_file(mailing_list_sublist)}
    catch {unset old_file(mailing_list_login)}
    catch {unset old_file(mailing_list_address)}
    #
    # Purge dropped classes from oid2class map.
    #
    foreach oid [array names oid2classname] {
	switch -- $oid2classname($oid)\
	    mailing_list_sublist - mailing_list_login - mailing_list_address {
		unset oid2classname($oid)
	}
    }
    #
    foreach cname $clist {
	finish_class $cname
    }
}

#
# Netgroup conversion code
#

proc v4_create_members {group elems} {
    upvar #0 $group group_object
    #
    foreach elem $elems {
	upvar #0 [set uuid [uuidgen]] object
	set object(Class) $group_object(Class)_member
	set object(owner) $group
	set object(ng_member) $elem
	#
	set object(mtime) $group_object(mtime)
	set object(mtran) $group_object(mtran)
	set object(modby) $group_object(modby)
	dump_instance $uuid $uuid
	unset object
    }
}

proc v4_convert_netgroups {} {
    global old_file unprotect unrestored fields instances
    upvar ODIR ODIR
    #
    foreach type {user_netgroup host_netgroup} {
	set unrestored($type) $type.dat
	set unrestored(${type}_member) ${type}_member.dat
	set fields($type) {name owner comment mtime modby mtran}
	set fields(${type}_member) {owner ng_member comment mtime modby mtran}
	set instances($type) 0
	set instances(${type}_member) 0
    }
    foreach type {host_netgroup user_netgroup} {
	close [open [file join $ODIR $type.dat] w]
	close [open [file join $ODIR ${type}_member.dat] w]
    }
    foreach cname {
	    host_netgroup host_netgroup_member
	    user_netgroup user_netgroup_member
	} {
	edit_class $cname {
	    error "Unexpected instance of $cname"
	}
	lappend clist $cname
    }
    #
    foreach cname {host_netgroup user_netgroup} {
	load_old_class $cname {
	    upvar #0 $oid object
	    #
	    # The recursive netgroups are not converted.
	    #
	    switch -- $F(name) allhosts - allusers {
		set unprotect($oid) 1
		continue
	    }
	    array set object [array get F]
	    set object(Class) $cname
	    #
	    # Make subnetgroups into member objects
	    #
	    v4_create_members $oid $F(subnetgroups)
	    #
	    # The domain netgroups are converted with the domain as the
	    # sole member.
	    #
	    switch -- $F(name) hosts - users {
		v4_create_members $oid $F(owner)
		set unprotect($oid) 1
	    }
	    dump_instance $oid $uuid
	    unset object
	}
    }
    #
    foreach cname {host_netgroup_member user_netgroup_member} {
	load_old_class $cname {
	    upvar #0 $oid object
	    set object(owner) $F(owner)
	    array set object [array get F]
	    if {[info exists F(ng_login)]} {
		set object(ng_member) $F(ng_login)
	    } else {
		set object(ng_member) $F(ng_host)
	    }
	    set object(Class) $cname
	    dump_instance $oid $uuid
	    unset object
	}
    }
    #
    foreach cname $clist {
	finish_class $cname
	catch {unset old_file($cname)}
    }
}

proc v4_convert_roles {} {
    global old_file oid2classname cname2oid
    #
    # Synthesize oids for new classes
    #
    foreach cname {
	    external_mail_address program_mailbox file_mailbox} {
	set oid2classname($cname) $cname
    }
    #
    # Invert oid2classname map
    #
    foreach oid [array names oid2classname] {
	set cname2oid($oid2classname($oid)) $oid
    }
    edit_class role
    #
    foreach op {create update delete} {
	set f($op) unameit_role_${op}_classes
    }
    load_old_class role {
	upvar #0 $oid object
	array set object [array get F]
	set object(Class) role
	#
	foreach op {create update delete} {
	    if {[lsearch -exact $F($f($op)) $cname2oid(mailing_list)] < 0} {
		continue
	    }
	    foreach cname {
		    external_mail_address program_mailbox file_mailbox} {
		lappend object($f($op)) $cname2oid($cname)
	    }
	}
	dump_instance $oid $uuid
	unset object
    }
    #
    finish_class role
    unset old_file(role)
}

proc banner {version} {
    puts -nonewline "\nUpgrading to Schema version $version..."
    flush stdout
}

proc convert_schema {dir} {
    set ipath [file join $dir Info.tcl]
    set dcpath [file join $dir unameit_data_class.dat]
    set ncpath [file join $dir unameit_network_class.dat]

    set fd [open $ipath r]
    regsub -all {bytesize} [read $fd [file size $ipath]] {octets} code
    close $fd
    eval $code

    set in [open $ncpath r]
    set out [open $dcpath a]

    while {[lgets $in line] != -1} {
	lassign $line oid uuid DATA
	eval lassign [list $DATA] $fields(unameit_network_class)
	set DATA {}
	foreach var $fields(unameit_data_class) {
	    lappend DATA [set $var]
	}
	puts $out [list $oid $uuid $DATA]
    }
    close $in
    close $out

    file delete $ncpath

    set infofd [open $ipath w]
    foreach var {oid2uuid unrestored fields instances} {
	if [array exists $var] {
	    upvar 0 $var a
	    catch {unset a(unameit_network_class)}
	    foreach elem [lsort [array names a]] {
		puts $infofd [list set ${var}($elem) $a($elem)]
	    }
	}
    }
    close $infofd
}

proc write_version_file {data version} {
    file delete -- [file join $data data data.version]
    set fd [open [file join $data data data.version] w]
    puts $fd $version
    close $fd
}

proc v7_convert_roles {} {
    global oid2classname

    foreach oid [array names oid2classname] {
	set cname2oid($oid2classname($oid)) $oid
    }
    foreach op {create update delete} {
	set f($op) unameit_role_${op}_classes
    }

    if {![info exists cname2oid(host_netgroup)] ||
    ![info exists cname2oid(user_netgroup)]} return

    ## Synthesize oid for new class.
    set oid2classname(mixed_netgroup) mixed_netgroup
    set cname2oid(mixed_netgroup) mixed_netgroup

    edit_class role {
	upvar #0 $oid object
	array set object [array get F]
	set object(Class) role
	#
	foreach op {create update delete} {
	    if {[lsearch -exact $F($f($op)) $cname2oid(host_netgroup)] >= 0 ||
	    [lsearch -exact $F($f($op)) $cname2oid(user_netgroup)] >= 0} {
		lappend object($f($op)) $cname2oid(mixed_netgroup)
	    }
	}
	dump_instance $oid $uuid
	unset object
    }
    finish_class role
}

proc v8_convert_networks {} {
    global fields old_fields

    edit_class ipv4_range
    set fields(ipv4_network) $old_fields(ipv4_network)
    edit_class ipv4_network {
	set fields(ipv4_network) {name owner ipv4_net_netof ipv4_net_start\
		ipv4_net_end ipv4_net_bits ipv4_net_mask ipv4_net_type\
		comment modby mtran mtime}
	upvar #0 $oid item
	set item(Class) ipv4_network
	array set item [array get F]
	foreach tuple {{ipv4_network ipv4_net_netof}\
		{ipv4_address ipv4_net_start}\
		{ipv4_last_address ipv4_net_end}\
		{ipv4_mask ipv4_net_mask}\
		{ipv4_mask_type ipv4_net_type}} {
	    lassign $tuple old_attr new_attr
	    set item($new_attr) $F($old_attr)
	}
	#
	# Add comments to universe, loopback and multicast networks.
	#
	switch -- $uuid {
	    oHvXD3702R073kU.65b.VU {
		set item(comment) {Container for all IP networks}
	    }
	    oIQbi3702R073kU.65b.VU {
		set item(comment) {Local loopback network (IANA)}
	    }
	    oInJ.3702R073kU.65b.VU {
		set item(comment) {IP multicast addresses (IANA)}
	    }
	}
	#
	# Compute network prefix.
	#
	set item(ipv4_net_bits) [unameit_address_common_bits $F(ipv4_address)\
		$F(ipv4_last_address)]
	#
	# Adjust net mask to at least include the network prefix
	#
	set item(ipv4_net_mask)\
	    [unameit_address_or\
		[unameit_address_make_mask 4 $item(ipv4_net_bits)]\
		[unameit_address_make_mask 4\
		    [unameit_address_mask_bits $item(ipv4_net_mask)]]]
	dump_instance $oid $uuid
    }
    foreach {uuid data} [list\
	koWfJY.U2R4HakU.65b.VU [list\
	    Class ipv4_network\
	    name class-a\
	    owner oG.IIZ702R073kU.65b.VU\
	    ipv4_net_netof oHvXD3702R073kU.65b.VU\
	    ipv4_net_start 00000000\
	    ipv4_net_bits 1\
	    ipv4_net_mask ff000000\
	    ipv4_net_type Fixed\
	    ipv4_net_end 7fffffff\
	    comment {Container for all Class A networks}]\
	koWgr2.U2R4HakU.65b.VU [list\
	    Class ipv4_network\
	    name class-b\
	    owner oG.IIZ702R073kU.65b.VU\
	    ipv4_net_netof oHvXD3702R073kU.65b.VU\
	    ipv4_net_start 80000000\
	    ipv4_net_bits 2\
	    ipv4_net_mask ffff0000\
	    ipv4_net_type Fixed\
	    ipv4_net_end bfffffff\
	    comment {Container for all Class B networks}]\
	koWi2Y.U2R4HakU.65b.VU [list\
	    Class ipv4_network\
	    name class-c\
	    owner oG.IIZ702R073kU.65b.VU\
	    ipv4_net_netof oHvXD3702R073kU.65b.VU\
	    ipv4_net_start c0000000\
	    ipv4_net_bits 3\
	    ipv4_net_mask ffffff00\
	    ipv4_net_type Fixed\
	    ipv4_net_end dfffffff\
	    comment {Container for all Class C networks}]\
	koWjG2.U2R4HakU.65b.VU [list\
	    Class ipv4_network\
	    name experimental\
	    owner oG.IIZ702R073kU.65b.VU\
	    ipv4_net_netof oHvXD3702R073kU.65b.VU\
	    ipv4_net_start f0000000\
	    ipv4_net_bits 5\
	    ipv4_net_mask f8000000\
	    ipv4_net_type Fixed\
	    ipv4_net_end f7ffffff\
	    comment {Experimental addressses (IANA)}]\
	koWkTY.U2R4HakU.65b.VU [list\
	    Class ipv4_network\
	    name reserved\
	    owner oG.IIZ702R073kU.65b.VU\
	    ipv4_net_netof oHvXD3702R073kU.65b.VU\
	    ipv4_net_start f8000000\
	    ipv4_net_bits 5\
	    ipv4_net_mask f8000000\
	    ipv4_net_type Fixed\
	    ipv4_net_end ffffffff\
	    comment {Reserved addressses (IANA)}]\
	iTz4K2.X2R4ybEU.65b.VU [list\
	    Class ipv4_range\
	    owner koWjG2.U2R4HakU.65b.VU\
	    ipv4_range_start f0000000\
	    ipv4_range_end f7ffffff\
	    ipv4_range_type Static\
	    ipv4_range_devices {}\
	    ipv4_range_server {}\
	    ipv4_range_prefix {}\
	    ipv4_lease_length {}\
	    comment {Reserve all addresses}]\
	iTz5u2.X2R4ybEU.65b.VU [list\
	    Class ipv4_range\
	    owner koWkTY.U2R4HakU.65b.VU\
	    ipv4_range_start f8000000\
	    ipv4_range_end ffffffff\
	    ipv4_range_type Static\
	    ipv4_range_devices {}\
	    ipv4_range_server {}\
	    ipv4_range_prefix {}\
	    ipv4_lease_length {}\
	    comment {Reserve all addresses}]] {
	#
	global $uuid
	lappend data mtime 876513001 mtran 0.0.0 modby UName*It
	array set $uuid $data
	dump_instance $uuid $uuid
    }
    finish_class ipv4_network
    finish_class ipv4_range
}

proc v8_convert_roles {} {
    global oid2classname

    foreach oid [array names oid2classname] {
	set cname2oid($oid2classname($oid)) $oid
    }
    foreach op {create update delete} {
	set f($op) unameit_role_${op}_classes
    }

    if {![info exists cname2oid(host_netgroup)] ||
    ![info exists cname2oid(user_netgroup)] ||
    ![info exists cname2oid(mixed_netgroup)]} return

    edit_class role {
	upvar #0 $oid object
	array set object [array get F]
	set object(Class) role
	#
	foreach op {create update delete} {
	    foreach grp_class {host_netgroup user_netgroup mixed_netgroup} {
		if {[set i [lsearch -exact $object($f($op))\
			$cname2oid($grp_class)]] >= 0} {
		    set object($f($op)) [lreplace $object($f($op)) $i $i]
		    if {[lsearch -exact $object($f($op)) $cname2oid(netgroup)]
		    == -1} {
			lappend object($f($op)) $cname2oid(netgroup)
		    }
		}
	    }
	}
	dump_instance $oid $uuid
	unset object
    }
    finish_class role
}

proc v8_convert_netgroups {} {
    global fields unrestored instances

    edit_class netgroup_member

    ## Create oid2classname array
    foreach cname {region cell computer router hub terminal_server\
	    server_alias host_alias user_login system_login \
	    application_login} {
	if {[info exists unrestored($cname)]} {
	    load_class $cname {
		set oid2classname($oid) $cname
	    }
	}
    }

    edit_class netgroup
    foreach cname {user_netgroup host_netgroup mixed_netgroup} {
	if {[info exists unrestored($cname)]} {
	    load_class $cname {
		set oid2classname($oid) $cname
		upvar #0 $oid object
		array set object [array get F]
		set object(Class) netgroup
		dump_instance $oid $uuid
	    }
	    foreach var {fields unrestored instances} {
		unset ${var}($cname)
	    }
	}
    }
    finish_class netgroup

    foreach class {host_netgroup_member user_netgroup_member
    mixed_netgroup_member} {
	if {[info exists unrestored($class)]} {
	    load_class $class {
		upvar #0 $oid item
		set item(Class) netgroup_member
		array set item [array get F]
		foreach f {host user ng} {
		    set item(ng_$f) ""
		}
		switch $oid2classname($F(ng_member)) {
		    region -
		    cell {
			switch $class {
			    user_netgroup_member {
				set item(ng_user) $F(ng_member)
			    }
			    host_netgroup_member {
				set item(ng_host) $F(ng_member)
			    }
			    mixed_netgroup_member {
				upvar [set new_uuid [uuidgen]] item2
				array set item2 [array get item]
				set item2(Class) netgroup_member
				set item2(ng_user) $F(ng_member)
				dump_instance $new_uuid $new_uuid

				set item(ng_host) $F(ng_member)
			    }
			}
		    }
		    computer -
		    hub -
		    terminal_server -
		    router -
		    server_alias -
		    host_alias {
			set item(ng_host) $F(ng_member)
		    }
		    user_login -
		    system_login -
		    application_login {
			set item(ng_user) $F(ng_member)
		    }
		    host_netgroup -
		    user_netgroup -
		    mixed_netgroup {
			set item(ng_ng) $F(ng_member)
		    }
		}
		dump_instance $oid $uuid
	    }
	    foreach var {unrestored fields instances} {
		unset ${var}($class)
	    }
	}
    }

    finish_class netgroup_member
}

####			Start of main Tcl code

## Grab the action this script was called with
set argv [lassign $argv action]

switch -- $action {
    upgrade_schema {
        ## Get the current database version
        lassign [split [unameit_schema_version] .] major minor micro

	#
	# Major schema version numbers below 3 are no longer in circulation.
	#
	
	#
	#-------------------------------------------------------
	# Upgrade from 3.x.y schema to 4.x.1 schema if necessary
	#-------------------------------------------------------
	#
	if {$major < 4} {
	    banner 4
	    unameit_commit -noCommit -schemaMajor 4 -schemaMinor $minor
	    #
	    # Create Mail forwarding address class under named item
	    #
	    unameit_create unameit_data_class bfN2K7do2R0hEEU.65b.VU\
		    unameit_class_name mail_route\
		    unameit_class_label {Mail Route}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}
	    # Override domain of mail_route owner to be host_or_region
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    bfN3z7do2R0hEEU.65b.VU\
		    unameit_attribute_whence eJmGyYyj2R0BWUU.65b.VU\
		    unameit_attribute_class bfN2K7do2R0hEEU.65b.VU\
		    unameit_attribute_label Owner\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain 5sT5ci5L2QyUsUU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Block\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    # Make mailing_list_member_object a subclass of mail_route
	    unameit_update 5sTEHi5L2QyUsUU.65b.VU\
		    unameit_class_supers bfN2K7do2R0hEEU.65b.VU
	    # Add comment field to display list of mail_route
	    unameit_update bfN2K7do2R0hEEU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Replace named_item with mail_route as superclass of abstract_host
	    unameit_update 5sSqBi5L2QyUsUU.65b.VU\
		    unameit_class_supers bfN2K7do2R0hEEU.65b.VU
	    # Create mailbox subclass of mailing_list_member_object
	    unameit_create unameit_data_class bfN5Addo2R0hEEU.65b.VU\
		    unameit_class_name mailbox\
		    unameit_class_label Mailbox\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers 5sTEHi5L2QyUsUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}
	    # Add mailbox_route field to mailbox class with domain of mail_route
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		    bfN6Lddo2R0hEEU.65b.VU unameit_attribute_name mailbox_route\
		    unameit_attribute_class bfN5Addo2R0hEEU.65b.VU\
		    unameit_attribute_label {Mailbox Route}\
		    unameit_attribute_null NULL\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain bfN2K7do2R0hEEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Block\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    # Create mail routing enum for mailbox class
	    unameit_create unameit_enum_defining_scalar_data_attribute\
		    NhXlrdh/2R0f1.U.65b.VU unameit_attribute_name preferred_mailbox\
		    unameit_attribute_class bfN5Addo2R0hEEU.65b.VU\
		    unameit_attribute_label {Preferred Mailbox}\
		    unameit_attribute_null NULL\
		    unameit_attribute_updatable Yes\
		    unameit_enum_attribute_values {Account Person}
	    # Display new fields
	    unameit_update bfN5Addo2R0hEEU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    NhXlrdh/2R0f1.U.65b.VU bfN6Lddo2R0hEEU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Create aliasable_mailbox class
	    unameit_create unameit_data_class bfN7Wddo2R0hEEU.65b.VU\
		    unameit_class_name aliasable_mailbox\
		    unameit_class_label {Aliasable Mailbox}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers bfN5Addo2R0hEEU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    NhXlrdh/2R0f1.U.65b.VU bfN6Lddo2R0hEEU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Add aliasable_mailbox as superclass of person
	    unameit_update 5sjNei5L2QyUsUU.65b.VU\
		    unameit_class_supers bfN7Wddo2R0hEEU.65b.VU
	    # Make user login an aliasable mailbox, not an abstract mailing list
	    unameit_update 5siIfi5L2QyUsUU.65b.VU\
		    unameit_class_supers {5sdLHC5L2QyUsUU.65b.VU\
		    5sgTEi5L2QyUsUU.65b.VU bfN7Wddo2R0hEEU.65b.VU}
	    # Drop the old subclasses of mailing_list_member
	    unameit_delete 5sokuC5L2QyUsUU.65b.VU
	    unameit_delete 5snudi5L2QyUsUU.65b.VU
	    unameit_delete 5soEYC5L2QyUsUU.65b.VU
	    # Drop all triggers on mailing_list_login
	    unameit_delete 5so5li5L2QyUsUU.65b.VU
	    unameit_delete 5soAAC5L2QyUsUU.65b.VU
	    # Drop all triggers on mailing_list_address
	    unameit_delete 5soy0C5L2QyUsUU.65b.VU
	    unameit_delete 5soteC5L2QyUsUU.65b.VU
	    # Drop all triggers on mailing_list sublist
	    unameit_delete 5soc5i5L2QyUsUU.65b.VU
	    unameit_delete 5sogTi5L2QyUsUU.65b.VU
	    # Drop ml_host and ml_address fields from mailing_list_member
	    unameit_delete 5snlti5L2QyUsUU.65b.VU
	    unameit_delete 5snqFi5L2QyUsUU.65b.VU
	    # Drop above fields from display list of mailing_list_member
	    unameit_update 5snYjC5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU 5snhVi5L2QyUsUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Make mailing_list_member concrete
	    unameit_update 5snYjC5L2QyUsUU.65b.VU unameit_class_readonly No
	    # Add ml_member as second name attribute
	    unameit_update 5snYjC5L2QyUsUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU 5snhVi5L2QyUsUU.65b.VU}
	    # Make domain of mailing_list_member.owner = mailing_list
	    unameit_update 5snd7i5L2QyUsUU.65b.VU\
		    unameit_pointer_attribute_domain 5snCrC5L2QyUsUU.65b.VU
	    # Add collision table, uniqueness rule for mailing_list_member objects
	    unameit_create unameit_data_collision_table bfN8k7do2R0hEEU.65b.VU\
		    unameit_collision_name mailist_list_member
	    unameit_create unameit_data_collision_rule bfN9sddo2R0hEEU.65b.VU\
		    unameit_collision_table bfN8k7do2R0hEEU.65b.VU\
		    unameit_colliding_class 5snYjC5L2QyUsUU.65b.VU\
		    unameit_collision_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU 5snhVi5L2QyUsUU.65b.VU}\
		    unameit_collision_local_strength Strong\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength None\
		    unameit_collision_global_strength None
	    # Drop abstract_mailing_list as superclass of mailing_list
	    unameit_update 5snCrC5L2QyUsUU.65b.VU\
		    unameit_class_supers 5sTEHi5L2QyUsUU.65b.VU
	    # Move promoted uniqueness of user_login vs mailing list
	    # to mailing_list collision table
	    unameit_create unameit_data_collision_rule bfNBaddo2R0hEEU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class 5siIfi5L2QyUsUU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength None\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Strong\
		    unameit_collision_global_strength None
	    unameit_create unameit_data_collision_rule bfNClddo2R0hEEU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class 5sjNei5L2QyUsUU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength None\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Strong\
		    unameit_collision_global_strength None
	    unameit_delete 5snPzC5L2QyUsUU.65b.VU
	    # Create mailbox alias class
	    unameit_create unameit_data_class oE7ovdg92R0C.EU.65b.VU\
		    unameit_class_name mailbox_alias\
		    unameit_class_label {Mailbox Alias}\
		    unameit_class_group Mail\
		    unameit_class_readonly No\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU\
		    unameit_class_name_attributes eJmJwYyj2R0BWUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Override validation of name attribute of mailbox_alias
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    oE7qddg92R0C.EU.65b.VU\
		    unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		    unameit_attribute_class oE7ovdg92R0C.EU.65b.VU\
		    unameit_attribute_label Alias unameit_attribute_null Error\
		    unameit_attribute_updatable Yes unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 63\
		    unameit_string_attribute_case lower\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}\
		    {regexp EMAILCHARS {^[^][:,;@<>\(\)"\\!#/]*$}}}
	    # Override domain of owner mailbox_alias
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    oE7rtdg92R0C.EU.65b.VU\
		    unameit_attribute_whence eJmGyYyj2R0BWUU.65b.VU\
		    unameit_attribute_class oE7ovdg92R0C.EU.65b.VU\
		    unameit_attribute_label Mailbox unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain bfN7Wddo2R0hEEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Cascade\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    # Set up uniqueness rules for mailbox aliases
	    unameit_create unameit_data_collision_rule oE7tA7g92R0C.EU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class oE7ovdg92R0C.EU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength None\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Strong\
		    unameit_collision_global_strength None
	    # Create file_mailbox class
	    unameit_create unameit_data_class oE7uSdg92R0C.EU.65b.VU\
		    unameit_class_name file_mailbox\
		    unameit_class_label {File Mailbox}\
		    unameit_class_group Mail\
		    unameit_class_readonly No\
		    unameit_class_supers\
		    {bfN5Addo2R0hEEU.65b.VU 5sd/ZC5L2QyUsUU.65b.VU}\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    bfN6Lddo2R0hEEU.65b.VU 5sd3ui5L2QyUsUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Override validation of name of file_mailbox
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    oE7vl7g92R0C.EU.65b.VU\
		    unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		    unameit_attribute_class oE7uSdg92R0C.EU.65b.VU\
		    unameit_attribute_label {Mailbox Name}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 63\
		    unameit_string_attribute_case lower\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}\
		    {regexp EMAILCHARS {^[^][:,;@<>\(\)"\\!#/]*$}}}
	    # Add validation of unix_pathname for file mailboxes
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    rD69m7zF2R0pcEU.65b.VU\
		    unameit_attribute_whence 5sd3ui5L2QyUsUU.65b.VU\
		    unameit_attribute_class oE7uSdg92R0C.EU.65b.VU\
		    unameit_attribute_label {File Name}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 255\
		    unameit_string_attribute_case Mixed\
		    unameit_string_attribute_vlist\
		    {{regsub {^ *:include: *(.*)} {:include:\1}}\
		    {regexp ENOTGRAPH "^(:include:)?[^\001-\040\177-\377]*$"}\
		    {regexp E1STNOTSLASH {^(:include:)?/}}\
		    {regsuball {//+} {/}}}
	    # Override label and domain of mail_route field of file_mailbox
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    oE7x1dg92R0C.EU.65b.VU\
		    unameit_attribute_whence bfN6Lddo2R0hEEU.65b.VU\
		    unameit_attribute_class oE7uSdg92R0C.EU.65b.VU\
		    unameit_attribute_label {File Host}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain 5sSqBi5L2QyUsUU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Block\
		    unameit_pointer_attribute_update_access Yes\
		    unameit_pointer_attribute_detect_loops Off
	    # Create program mailbox class
	    unameit_create unameit_data_class oE7yvdg92R0C.EU.65b.VU\
		    unameit_class_name program_mailbox\
		    unameit_class_label {Program Mailbox}\
		    unameit_class_group Mail\
		    unameit_class_readonly No\
		    unameit_class_supers\
		    {bfN5Addo2R0hEEU.65b.VU 5sd/ZC5L2QyUsUU.65b.VU}\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    bfN6Lddo2R0hEEU.65b.VU 5sd3ui5L2QyUsUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Override unix_pathname field of program mailbox
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    oE8.C7g92R0C.EU.65b.VU\
		    unameit_attribute_whence 5sd3ui5L2QyUsUU.65b.VU\
		    unameit_attribute_class oE7yvdg92R0C.EU.65b.VU\
		    unameit_attribute_label {Program & Args}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 255\
		    unameit_string_attribute_case Mixed\
		    unameit_string_attribute_vlist\
		    {{regexp E1STNOTSLASH {^/}}\
		    {regexp ENOTPRINT "^[^\001-\037\177-\377]*$"}\
		    {regsuball {//+} {/}}}
	    # Create uniqueness rule for program mailboxes
	    unameit_create unameit_data_collision_rule oE81F7g92R0C.EU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class oE7yvdg92R0C.EU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength Normal\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Weak\
		    unameit_collision_global_strength None
	    # Create uniqueness rule for file mailboxes
	    unameit_create unameit_data_collision_rule oE82Xdg92R0C.EU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class oE7uSdg92R0C.EU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength Normal\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Weak\
		    unameit_collision_global_strength None
	    # Create external mail address class
	    unameit_create unameit_data_class oE83q7g92R0C.EU.65b.VU\
		    unameit_class_name external_mail_address\
		    unameit_class_label {External Mail Address}\
		    unameit_class_group Mail unameit_class_readonly No\
		    unameit_class_supers 5sTEHi5L2QyUsUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Create uniqueness rule for external mail addresses
	    unameit_create unameit_data_collision_rule oE856dg92R0C.EU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class oE83q7g92R0C.EU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength Normal\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Weak\
		    unameit_collision_global_strength None
	    # Override name of program mailbox
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    oE86P7g92R0C.EU.65b.VU\
		    unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		    unameit_attribute_class oE7yvdg92R0C.EU.65b.VU\
		    unameit_attribute_label {Mailbox Name}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 63\
		    unameit_string_attribute_case lower\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}\
		    {regexp EMAILCHARS {^[^][:,;@<>\(\)"\\!#/]*$}}}
	    # Create EBACKSLASH error code used below
	    unameit_create unameit_error oE8/w7g92R0C.EU.65b.VU\
		    unameit_error_code EBACKSLASH\
		    unameit_error_proc 5suy1i5L2QyUsUU.65b.VU\
		    unameit_error_type Normal\
		    unameit_error_message {Value may not contain a '\'}
	    # Override name (address) of external mail address
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    oE87f7g92R0C.EU.65b.VU\
		    unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		    unameit_attribute_class oE83q7g92R0C.EU.65b.VU\
		    unameit_attribute_label {Forwarding Address}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 255\
		    unameit_string_attribute_case lower\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTPRINT "^[^\001-\037\177-\377]*$"}\
		    {regexp EBACKSLASH {^[^\\]*$}} {code {
	        #
		# Partial rfc822 support, does not allow entries which require
		# quoting in the "aliases" file, or other "exotic" constructs.
		#
		switch -regexp -- $value {
		    {^[A-Za-z][A-Za-z0-9+.-]+$} {
			#
			# Support indirect (i.e. string) local recipients
			#
		    }
		    {^@?[a-zA-Z0-9/=!%_.:-]+@[A-Za-z][A-Za-z0-9.-]+$} {
			#
			# Support domain addresses possibly source routed
			#
		    }
		    {^[a-zA-Z0-9.-]+![a-zA-Z0-9.!-]+$} {
			#
			# Support UUCP addresses
			#
		    }
		    default {
			unameit_error EBADMLADDR $uuid $attr $value
		    }
		}
    }   }   }
    	    # Clone collision rule for mailing_lists,  the fields are
	    # write-once
    	    unameit_create unameit_data_collision_rule oE88xdg92R0C.EU.65b.VU\
		    unameit_collision_table 5sPO4C5L2QyUsUU.65b.VU\
		    unameit_colliding_class 5snCrC5L2QyUsUU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength Normal\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength Weak\
		    unameit_collision_global_strength None
	    unameit_delete 5snULC5L2QyUsUU.65b.VU
	    # Override name (mail handle) field of person
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    NhXhidh/2R0f1.U.65b.VU\
		    unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		    unameit_attribute_class 5sjNei5L2QyUsUU.65b.VU\
		    unameit_attribute_label {Mail Handle}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 63\
		    unameit_string_attribute_case lower\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}\
		    {regexp EMAILCHARS {^[^][:,;@<>\(\)"\\!#/]*$}}}
	    # Override mail_route field of program_mailbox
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    NhXjJ7h/2R0f1.U.65b.VU\
		    unameit_attribute_whence bfN6Lddo2R0hEEU.65b.VU\
		    unameit_attribute_class oE7yvdg92R0C.EU.65b.VU\
		    unameit_attribute_label {Program Host}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain 5sSqBi5L2QyUsUU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Block\
		    unameit_pointer_attribute_update_access Yes\
		    unameit_pointer_attribute_detect_loops Off
	    # Create phone number attribute of person
	    unameit_create unameit_string_defining_scalar_data_attribute\
		    NhXn5dh/2R0f1.U.65b.VU\
		    unameit_attribute_name person_phone\
		    unameit_attribute_class 5sjNei5L2QyUsUU.65b.VU\
		    unameit_attribute_label {Phone Number}\
		    unameit_attribute_null NULL\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 63\
		    unameit_string_attribute_case Mixed\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTPHONENUM {^[()0-9+, -]*$}}}
	    # Add expiration date field to person
	    unameit_create unameit_time_defining_scalar_data_attribute\
		    NhXoLdh/2R0f1.U.65b.VU\
		    unameit_attribute_name person_expiration\
		    unameit_attribute_class 5sjNei5L2QyUsUU.65b.VU\
		    unameit_attribute_label {Account Expiration Date}\
		    unameit_attribute_null NULL\
		    unameit_attribute_updatable Yes
	    # Add displayed fields to person class
	    unameit_update 5sjNei5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {5sjS0i5L2QyUsUU.65b.VU eJmJwYyj2R0BWUU.65b.VU\
		    eJmGyYyj2R0BWUU.65b.VU NhXn5dh/2R0f1.U.65b.VU\
		    NhXlrdh/2R0f1.U.65b.VU bfN6Lddo2R0hEEU.65b.VU\
		    NhXoLdh/2R0f1.U.65b.VU Wo1YKZ5j2R00DUU.65b.VU}
	    # Drop login_enabled attribute
	    unameit_delete 5siv0i5L2QyUsUU.65b.VU
	    # Drop mailhost attribute from user_login
	    unameit_delete 5siqei5L2QyUsUU.65b.VU
	    # Drop ref_cell trigger on user_login mailhost
	    unameit_delete 5sjJGi5L2QyUsUU.65b.VU
	    # Update displayed attributes of user_login
	    unameit_update 5siIfi5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    5sg.pC5L2QyUsUU.65b.VU 5sg38i5L2QyUsUU.65b.VU\
		    5sg7Wi5L2QyUsUU.65b.VU 5siUci5L2QyUsUU.65b.VU\
		    5sgBsC5L2QyUsUU.65b.VU 5sdPci5L2QyUsUU.65b.VU\
		    5sdCZi5L2QyUsUU.65b.VU 5sd3ui5L2QyUsUU.65b.VU\
		    5sgGEC5L2QyUsUU.65b.VU NhXlrdh/2R0f1.U.65b.VU\
		    bfN6Lddo2R0hEEU.65b.VU Wo1YKZ5j2R00DUU.65b.VU}
	    #
	    # Clean up netgroup schema to allow domains as members
	    # and turn subnetgroups into member objects
	    #
	    # Delete subnetgroups attribute
	    unameit_delete 5smB8C5L2QyUsUU.65b.VU
	    # Create host netgroup member object abstract class
	    unameit_create unameit_data_class NSK7Ke6e2R0YhEU.65b.VU\
		    unameit_class_name host_netgroup_member_object\
		    unameit_class_label {Host Netgroup Member Object}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Create user_netgroup_member_object abstract class
	    unameit_create unameit_data_class NSK92e6e2R0YhEU.65b.VU\
		    unameit_class_name user_netgroup_member_object\
		    unameit_class_label {User Netgroup Member Object}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Drop subnetgroups field from display list of netgroup
	    unameit_update 5sm2OC5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Create netgroup_member_object class
	    unameit_create unameit_data_class NSKAB86e2R0YhEU.65b.VU\
		    unameit_class_name netgroup_member_object\
		    unameit_class_label {Netgroup Member Object}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Create netgroup member class
	    unameit_create unameit_data_class NSKBOe6e2R0YhEU.65b.VU\
		    unameit_class_name netgroup_member\
		    unameit_class_label {Netgroup Member}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes
	    # Create ng_member attribute of netgroup_member domain
	    # netgroup_member_object
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		    NSKCZe6e2R0YhEU.65b.VU\
		    unameit_attribute_name ng_member\
		    unameit_attribute_class NSKBOe6e2R0YhEU.65b.VU\
		    unameit_attribute_label Member\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain NSKAB86e2R0YhEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Cascade\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    # Set name attributes of netgroup_member class (owner, ng_member)
	    # Set displayed attributes of netgroup_member class (owner, ng_member, comment)
	    unameit_update NSKBOe6e2R0YhEU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Fix superclass of {host,user}_netgroup_member_object to be netgroup_member_object
	    unameit_update NSK92e6e2R0YhEU.65b.VU\
		    unameit_class_supers NSKAB86e2R0YhEU.65b.VU
	    unameit_update NSK7Ke6e2R0YhEU.65b.VU\
		    unameit_class_supers NSKAB86e2R0YhEU.65b.VU
	    # Make host_netgroup_member a subclass of netgroup_member
	    unameit_update 5smfoi5L2QyUsUU.65b.VU\
		    unameit_class_supers NSKBOe6e2R0YhEU.65b.VU
	    # Make user_netgroup_member a subclass of netgroup_member
	    unameit_update 5smxIi5L2QyUsUU.65b.VU\
		    unameit_class_supers NSKBOe6e2R0YhEU.65b.VU
	    # Fix name attributes of host_netgroup_member
	    unameit_update 5smfoi5L2QyUsUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}
	    # Fix name attributes of user_netgroup_member
	    unameit_update 5smxIi5L2QyUsUU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}
	    # Fix displayed attributes of {host,user}_netgroup_member
	    unameit_update 5smfoi5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    unameit_update 5smxIi5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Fix displayed attributes of host_netgroup class
	    unameit_update 5smFWC5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Fix displayed attributes of user_netgroup class
	    unameit_update 5smSgi5L2QyUsUU.65b.VU\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    # Override domain of host_netgroup_member ng_member
	    # (= host_netgroup_member_object)
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    NSKDke6e2R0YhEU.65b.VU\
		    unameit_attribute_whence NSKCZe6e2R0YhEU.65b.VU\
		    unameit_attribute_class 5smfoi5L2QyUsUU.65b.VU\
		    unameit_attribute_label Member\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain NSK7Ke6e2R0YhEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Cascade\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    # Override domain of user_netgroup_member ng_member
	    # (= user_netgroup_member_object)
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    NSKEt86e2R0YhEU.65b.VU\
		    unameit_attribute_whence NSKCZe6e2R0YhEU.65b.VU\
		    unameit_attribute_class 5smxIi5L2QyUsUU.65b.VU\
		    unameit_attribute_label Member\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain NSK92e6e2R0YhEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Cascade\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    # Add user_netgroup_member_object as superclass of login
	    unameit_update 5sgTEi5L2QyUsUU.65b.VU\
		    unameit_class_supers\
		    {5sfnmC5L2QyUsUU.65b.VU NSK92e6e2R0YhEU.65b.VU\
		    5sTEHi5L2QyUsUU.65b.VU}
	    # Add user_netgroup_member_object as superclass of user_netgroup
	    unameit_update 5smSgi5L2QyUsUU.65b.VU\
		    unameit_class_supers {NSK92e6e2R0YhEU.65b.VU 5sm2OC5L2QyUsUU.65b.VU}
	    # Add host_netgroup_member_object as superclass of host_netgroup
	    unameit_update 5smFWC5L2QyUsUU.65b.VU\
		    unameit_class_supers {NSK7Ke6e2R0YhEU.65b.VU 5sm2OC5L2QyUsUU.65b.VU}
	    # Add host_netgroup_member_object as superclass of abstract_host
	    unameit_update 5sSqBi5L2QyUsUU.65b.VU\
		    unameit_class_supers {NSK7Ke6e2R0YhEU.65b.VU bfN2K7do2R0hEEU.65b.VU}
	    # Add host_netgroup_member_object as superclass of host
	    unameit_update 5sWXri5L2QyUsUU.65b.VU\
		    unameit_class_supers\
		    {NSK7Ke6e2R0YhEU.65b.VU 5sT5ci5L2QyUsUU.65b.VU\
		    5sVcTi5L2QyUsUU.65b.VU}
	    # Make region subclass of host_netgroup_member_object and
	    # user_netgroup_member_object
	    unameit_update 5sUFUC5L2QyUsUU.65b.VU\
		    unameit_class_supers\
		    {NSK7Ke6e2R0YhEU.65b.VU 5sT5ci5L2QyUsUU.65b.VU\
		    NSK92e6e2R0YhEU.65b.VU}
	    # Drop subnetgroups override of host_netgroup
	    unameit_delete 5smJuC5L2QyUsUU.65b.VU
	    # Drop subnetgroups override of user_netgroup
	    unameit_delete 5smX2i5L2QyUsUU.65b.VU
	    # Drop ng_host and ng_login attributes
	    unameit_delete 5smoYi5L2QyUsUU.65b.VU
	    unameit_delete 5sn45C5L2QyUsUU.65b.VU
	    # Replace uniqueness rules for netgroup members
	    unameit_delete 5smswi5L2QyUsUU.65b.VU
	    unameit_delete 5sn8TC5L2QyUsUU.65b.VU
	    unameit_create unameit_data_collision_rule B8S3c87p2R0WS.U.65b.VU\
		    unameit_collision_table 5sP2ii5L2QyUsUU.65b.VU\
		    unameit_colliding_class 5smfoi5L2QyUsUU.65b.VU\
		    unameit_collision_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}\
		    unameit_collision_local_strength Strong\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength None\
		    unameit_collision_global_strength None
	    unameit_create unameit_data_collision_rule B8S5He7p2R0WS.U.65b.VU\
		    unameit_collision_table 5sSLmC5L2QyUsUU.65b.VU\
		    unameit_colliding_class 5smxIi5L2QyUsUU.65b.VU\
		    unameit_collision_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}\
		    unameit_collision_local_strength Strong\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength None\
		    unameit_collision_global_strength None
	    #
	    # Allow user principal objects to point to user in same org,
	    # but different cells.
	    #
	    unameit_update 5sezaC5L2QyUsUU.65b.VU\
		    unameit_trigger_proc unameit_check_ref_org
	    #
	    # Create new EXORG error code
	    #
	    unameit_create unameit_error wt1yR8Zn2R0v7kU.65b.VU\
		    unameit_error_code EXORG\
		    unameit_error_proc 5supPC5L2QyUsUU.65b.VU\
		    unameit_error_type Normal\
		    unameit_error_message\
		    {Attribute must point to item in same organization}
	}
	
	#
	#-------------------------------------------------------
	# Upgrade from 4.x.y schema to 5.x.1 schema if necessary
	#-------------------------------------------------------
	#
	if {$major < 5} {
	    banner 5
	    unameit_commit -noCommit -schemaMajor 5 -schemaMinor $minor
	    #
	    # Allow underscores in "local" external addresses
	    #
	    unameit_update oE87f7g92R0C.EU.65b.VU\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTPRINT "^[^\001-\037\177-\377]*$"}\
		    {regexp EBACKSLASH {^[^\\]*$}} {code {
		#
		# Partial rfc822 support, does not allow entries which require
		# quoting in the "aliases" file, or other "exotic" constructs.
		#
		switch -regexp -- $value {
		    {^[A-Za-z][A-Za-z0-9='_+.-]+$} {
			#
			# Support indirect (i.e. string) local recipients
			#
		    }
		    {^@?[a-zA-Z0-9/='!%_.:-]+@[A-Za-z][A-Za-z0-9_.-]+$} {
			#
			# Support domain addresses possibly source routed
			#
		    }
		    {^[a-zA-Z0-9.-]+![a-zA-Z0-9.!-]+$} {
			#
			# Support UUCP addresses
			#
		    }
		    default {
			unameit_error EBADMLADDR $uuid $attr $value
		    }
		}
    }   }   }
	}

	#
	#-------------------------------------------------------
	# Upgrade from 5.x.y schema to 6.x.1 schema if necessary
	#-------------------------------------------------------
	#
	if {$major < 6} {
	    banner 6
	    unameit_commit -noCommit -schemaMajor 6 -schemaMinor $minor
	    #
	    # Allow dashes and underscores principal names
	    #
	    unameit_update 5seQpC5L2QyUsUU.65b.VU\
		    unameit_string_attribute_vlist {{regexp E1STNOTLETTER {^[a-zA-Z]}}\
		    {regexp ENOTDASHGENALNUM {^([-_]?[0-9A-Za-z])*$}}}
	    #
	    # Allow host principals to be owned by any region in host's
	    # organization.  This is for v4 compatibility.  Eventually could
	    # drop constraint entirely.
	    #
	    unameit_update 5sfJKi5L2QyUsUU.65b.VU\
		    unameit_trigger_proc unameit_check_ref_org
	}
	
	#
	#-------------------------------------------------------
	# Upgrade from 6.x.y schema to 7.x.1 schema if necessary
	#-------------------------------------------------------
	#
	if {$major < 7} {
	    banner 7
	    unameit_commit -noCommit -schemaMajor 7 -schemaMinor $minor
	    #
	    # Create mixed_netgroup_member_object abstract class
	    #
	    unameit_create unameit_data_class 1SMI30ff2R4MJEU.65b.VU\
		    unameit_class_name mixed_netgroup_member_object\
		    unameit_class_label {Mixed Netgroup Member Object}\
		    unameit_class_group {}\
		    unameit_class_readonly Yes\
		    unameit_class_supers NSKAB86e2R0YhEU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    #
	    # Create mixed_netgroup as subclass of Generic Netgroup
	    # that allows hosts and users
	    #
	    unameit_create unameit_data_class 1SMG3Wff2R4MJEU.65b.VU\
		    unameit_class_name mixed_netgroup\
		    unameit_class_label {Mixed Netgroup}\
		    unameit_class_group Netgroups\
		    unameit_class_readonly No\
		    unameit_class_supers\
		    {1SMI30ff2R4MJEU.65b.VU 5sm2OC5L2QyUsUU.65b.VU}\
		    unameit_class_name_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    #
	    # Set up syntax validation for mixed_netgroup name
	    #
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		    1SMPRWff2R4MJEU.65b.VU\
		    unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		    unameit_attribute_class 1SMG3Wff2R4MJEU.65b.VU\
		    unameit_attribute_label Name\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_string_attribute_minlen 1\
		    unameit_string_attribute_maxlen 255\
		    unameit_string_attribute_case Mixed\
		    unameit_string_attribute_vlist\
		    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}\
		    {regexp ENETGRCHARS {^[^@,\(\)#]*$}}}
	    #
	    # Make mixed netgroup name collide with user and host netgroup names
	    #
	    unameit_create unameit_data_collision_rule 1SMJY0ff2R4MJEU.65b.VU\
		    unameit_collision_table 5sPSKi5L2QyUsUU.65b.VU\
		    unameit_colliding_class 1SMG3Wff2R4MJEU.65b.VU\
		    unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		    unameit_collision_local_strength Normal\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength None\
		    unameit_collision_global_strength Weak
	    #
	    # Create mixed_netgroup_member class
	    #
	    unameit_create unameit_data_class 1SMO/0ff2R4MJEU.65b.VU\
		    unameit_class_name mixed_netgroup_member\
		    unameit_class_label {Mixed Netgroup Member}\
		    unameit_class_group Netgroups\
		    unameit_class_readonly No\
		    unameit_class_supers NSKBOe6e2R0YhEU.65b.VU\
		    unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}\
		    unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU\
		    Wo1YKZ5j2R00DUU.65b.VU}
	    #
	    # Create overrides for owner and ng_member for the
	    # mixed_netgroup_member class
	    #
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    1SML10ff2R4MJEU.65b.VU\
		    unameit_attribute_whence eJmGyYyj2R0BWUU.65b.VU\
		    unameit_attribute_class 1SMO/0ff2R4MJEU.65b.VU\
		    unameit_attribute_label {Mixed Netgroup}\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain 1SMG3Wff2R4MJEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Cascade\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    #
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		    1SMMW0ff2R4MJEU.65b.VU\
		    unameit_attribute_whence NSKCZe6e2R0YhEU.65b.VU\
		    unameit_attribute_class 1SMO/0ff2R4MJEU.65b.VU\
		    unameit_attribute_label Member\
		    unameit_attribute_null Error\
		    unameit_attribute_updatable Yes\
		    unameit_pointer_attribute_domain 1SMI30ff2R4MJEU.65b.VU\
		    unameit_pointer_attribute_ref_integrity Cascade\
		    unameit_pointer_attribute_update_access No\
		    unameit_pointer_attribute_detect_loops Off
	    #
	    # Add mixed_netgroup_member_object as a superclass
	    # of host_netgroup_member_object and user_netgroup_member_object
	    #
	    unameit_update NSK7Ke6e2R0YhEU.65b.VU\
		    unameit_class_supers 1SMI30ff2R4MJEU.65b.VU
	    unameit_update NSK92e6e2R0YhEU.65b.VU\
		    unameit_class_supers 1SMI30ff2R4MJEU.65b.VU
	    #
	    # XXX: This entry has not been done at Fuji yet. We need to have
	    # Fuji execute the next couple of lines.
	    #
	    unameit_create unameit_data_collision_table oBV1FX9K2R4hoUU.65b.VU\
		    unameit_collision_name mixed_netgroup_member
	    #
	    unameit_create unameit_data_collision_rule oBV4.X9K2R4hoUU.65b.VU\
		    unameit_collision_table oBV1FX9K2R4hoUU.65b.VU\
		    unameit_colliding_class 1SMO/0ff2R4MJEU.65b.VU\
		    unameit_collision_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU NSKCZe6e2R0YhEU.65b.VU}\
		    unameit_collision_local_strength Strong\
		    unameit_collision_cell_strength None\
		    unameit_collision_org_strength None\
		    unameit_collision_global_strength None
	}
	
	### Upgrade from 7.x.y schema to 8.x.1 schema
	if {$major < 8} {
	    banner 8
	    unameit_commit -noCommit -schemaMajor 8 -schemaMinor $minor
	    #
	    # Set address as name attribute of generic IP node
	    #
	    unameit_update 5sSQ3C5L2QyUsUU.65b.VU\
		unameit_class_name_attributes 5sSd8i5L2QyUsUU.65b.VU
	    #
	    # Display comment as last field
	    #
	    unameit_update 5sSQ3C5L2QyUsUU.65b.VU\
		unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU 5sSYmi5L2QyUsUU.65b.VU\
		     5sSd8i5L2QyUsUU.65b.VU Wo1YKZ5j2R00DUU.65b.VU}
	    # 
	    # Create ip net_start attribute
	    #
	    unameit_create unameit_address_defining_scalar_data_attribute\
		sd.KNX2U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_net_start\
		unameit_attribute_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_attribute_label {Network Address}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_address_attribute_octets 4\
		unameit_address_attribute_format IP
	    #
	    # Create ip net_end attribute
	    #
	    unameit_create unameit_address_defining_scalar_data_attribute\
		sd.O012U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_net_end\
		unameit_attribute_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_attribute_label {Last Address}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_address_attribute_octets 4\
		unameit_address_attribute_format IP
	    #
	    # Create new IP net mask attribute
	    #
	    unameit_create unameit_address_defining_scalar_data_attribute\
		sd.PV12U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_net_mask\
		unameit_attribute_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_attribute_label {Subnet Mask}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_address_attribute_octets 4\
		unameit_address_attribute_format IP
	    #
	    # Create IP net bits attribute
	    #
	    unameit_create unameit_integer_defining_scalar_data_attribute\
		sd.R.12U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_net_bits\
		unameit_attribute_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_attribute_label {Network Bits}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_integer_attribute_min 0\
		unameit_integer_attribute_max 30\
		unameit_integer_attribute_base Decimal
	    #
	    # Create new ipv4_net_type attribute
	    #
	    unameit_create unameit_enum_defining_scalar_data_attribute\
		sd.SQX2U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_net_type\
		unameit_attribute_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_attribute_label {Netmask Type}\
		unameit_attribute_null Error\
		unameit_attribute_updatable Yes\
		unameit_enum_attribute_values {Fixed Variable}
	    #
	    # Create parent network attribute for networks
	    #
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		sd.Tt12U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_net_netof\
		unameit_attribute_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_attribute_label {Parent Network}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain 5sUwyi5L2QyUsUU.65b.VU\
		unameit_pointer_attribute_ref_integrity Block\
		unameit_pointer_attribute_update_access No\
		unameit_pointer_attribute_detect_loops Off
	    #
	    # Drop Label override of old address of network
	    #
	    unameit_delete 5sV3gC5L2QyUsUU.65b.VU
	    #
	    # Drop obsolete subnodes attribute
	    #
	    unameit_delete 5sVL5C5L2QyUsUU.65b.VU
	    #
	    # Drop old last_address attribute
	    #
	    unameit_delete 5sV8/i5L2QyUsUU.65b.VU
	    #
	    # Drop old mask attribute
	    #
	    unameit_delete 5sVCNi5L2QyUsUU.65b.VU
	    #
	    # Drop old mask_type attribute
	    #
	    unameit_delete 5sVGjC5L2QyUsUU.65b.VU
	    #
	    # Fix name, displayed attributes and superclasses of ipv4_network
	    #
	    unameit_update 5sUwyi5L2QyUsUU.65b.VU\
		unameit_class_name_attributes\
		    {sd.KNX2U2R4AxEU.65b.VU sd.R.12U2R4AxEU.65b.VU\
		     eJmJwYyj2R0BWUU.65b.VU}\
		unameit_class_display_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU\
		     sd.Tt12U2R4AxEU.65b.VU sd.KNX2U2R4AxEU.65b.VU\
		     sd.R.12U2R4AxEU.65b.VU sd.PV12U2R4AxEU.65b.VU\
		     sd.SQX2U2R4AxEU.65b.VU sd.O012U2R4AxEU.65b.VU\
		     Wo1YKZ5j2R00DUU.65b.VU}\
		unameit_class_supers eJmIRYyj2R0BWUU.65b.VU
	    #
	    # Update network trigger
	    #
	    unameit_update 5sVY5i5L2QyUsUU.65b.VU\
		unameit_trigger_proc unameit_inet_network_trigger\
		unameit_trigger_args ipv4\
		unameit_trigger_attributes\
		    {sd.Tt12U2R4AxEU.65b.VU sd.KNX2U2R4AxEU.65b.VU\
		     sd.O012U2R4AxEU.65b.VU sd.R.12U2R4AxEU.65b.VU\
		     sd.PV12U2R4AxEU.65b.VU sd.SQX2U2R4AxEU.65b.VU}
	    #
	    # Create IP range class
	    #
	    unameit_create unameit_data_class\
		sd.VxX2U2R4AxEU.65b.VU\
		unameit_class_name ipv4_range\
		unameit_class_label {IP Range}\
		unameit_class_group {IP}\
		unameit_class_readonly No\
		unameit_class_supers {}\
		unameit_class_name_attributes {}\
		unameit_class_display_attributes {}
	    #
	    # Use "owner" as range_netof attribute
	    #
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		Xearg1Ou2R4eukU.65b.VU\
		unameit_attribute_whence eJmGyYyj2R0BWUU.65b.VU\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label Network\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain 5sUwyi5L2QyUsUU.65b.VU\
		unameit_pointer_attribute_ref_integrity Block\
		unameit_pointer_attribute_update_access No\
		unameit_pointer_attribute_detect_loops Off
	    #
	    # Create range_start field
	    #
	    unameit_create unameit_address_defining_scalar_data_attribute\
		sd.XT12U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_range_start\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {Range Start}\
		unameit_attribute_null Error\
		unameit_attribute_updatable Yes\
		unameit_address_attribute_octets 4\
		unameit_address_attribute_format IP
	    #
	    # Create Range End attribute
	    #
	    unameit_create unameit_address_defining_scalar_data_attribute\
		sd.av12U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_range_end\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {Range End}\
		unameit_attribute_null Error\
		unameit_attribute_updatable Yes\
		unameit_address_attribute_octets 4\
		unameit_address_attribute_format IP
	    #
	    # Create Range Type attribute
	    #
	    unameit_create unameit_enum_defining_scalar_data_attribute\
		Bguol1Xx2R4Zk.U.65b.VU\
		unameit_attribute_name ipv4_range_type\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {Range Type}\
		unameit_attribute_null Error\
		unameit_attribute_updatable Yes\
		unameit_enum_attribute_values {Dynamic Static}
	    #
	    # Add range_class enum attribute
	    # Order for decent display layout of checkbuttons.
	    #
	    unameit_create unameit_enum_defining_set_data_attribute\
		sd.sCX2U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_range_devices\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {Device Classes}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_enum_attribute_values\
		    {Router Hub {Terminal Server} Computer}
	    #
	    # Create dhcp server field
	    #
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		sd.cLX2U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_range_server\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {DHCP Server}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain 5sWthC5L2QyUsUU.65b.VU\
		unameit_pointer_attribute_ref_integrity Block\
		unameit_pointer_attribute_update_access Yes\
		unameit_pointer_attribute_detect_loops Off
	    #
	    # Create Host Prefix attribute
	    #
	    unameit_create unameit_string_defining_scalar_data_attribute\
		sd.nj12U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_range_prefix\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {Host Name Prefix}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_string_attribute_minlen 1\
		unameit_string_attribute_maxlen 47\
		unameit_string_attribute_case lower\
		unameit_string_attribute_vlist\
		    {{regexp E1STNOTALNUM {^[a-z0-9]}}\
		     {regexp EDOT {^[^.]*$}}\
		     {regexp ENOTDNSLABEL {^([-]?[a-z0-9])*$}}}
	    #
	    # Create lease_length attribute.
	    #
	    unameit_create unameit_integer_defining_scalar_data_attribute\
		sd.pEX2U2R4AxEU.65b.VU\
		unameit_attribute_name ipv4_lease_length\
		unameit_attribute_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_attribute_label {Lease Duration (seconds)}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_integer_attribute_min 60\
		unameit_integer_attribute_max {}\
		unameit_integer_attribute_base Decimal
	    #
	    # Set name attributes of range
	    #
	    unameit_update sd.VxX2U2R4AxEU.65b.VU\
		unameit_class_name_attributes\
		    {sd.XT12U2R4AxEU.65b.VU sd.av12U2R4AxEU.65b.VU}
	    #
	    # Set Displayed attributes of range
	    #
	    unameit_update sd.VxX2U2R4AxEU.65b.VU\
		unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU sd.XT12U2R4AxEU.65b.VU\
		     sd.av12U2R4AxEU.65b.VU Bguol1Xx2R4Zk.U.65b.VU\
		     sd.sCX2U2R4AxEU.65b.VU sd.cLX2U2R4AxEU.65b.VU\
		     sd.nj12U2R4AxEU.65b.VU sd.pEX2U2R4AxEU.65b.VU\
		     Wo1YKZ5j2R00DUU.65b.VU}
	    #
	    # Create IP range trigger
	    #
	    unameit_create unameit_data_trigger DkjPqXb32R486UU.65b.VU\
		unameit_trigger_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_trigger_proc unameit_inet_range_trigger\
		unameit_trigger_inherited Yes\
		unameit_trigger_oncreate Before\
		unameit_trigger_onupdate Before\
		unameit_trigger_ondelete No\
		unameit_trigger_args ipv4\
		unameit_trigger_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU sd.XT12U2R4AxEU.65b.VU\
		     sd.av12U2R4AxEU.65b.VU}\
		unameit_trigger_computes {}
	    #
	    # Create IP address family
	    #
	    unameit_create unameit_address_family\
		sd.qjX2U2R4AxEU.65b.VU\
		unameit_family_name ipv4\
		unameit_address_octets 4\
		unameit_node_zero Reserved\
		unameit_last_node Reserved\
		unameit_net_zero Reserved\
		unameit_last_net Reserved\
		unameit_node_class 5sSQ3C5L2QyUsUU.65b.VU\
		unameit_node_netof_attribute 5sSYmi5L2QyUsUU.65b.VU\
		unameit_node_address_attribute 5sSd8i5L2QyUsUU.65b.VU\
		unameit_net_class 5sUwyi5L2QyUsUU.65b.VU\
		unameit_net_netof_attribute sd.Tt12U2R4AxEU.65b.VU\
		unameit_net_start_attribute sd.KNX2U2R4AxEU.65b.VU\
		unameit_net_end_attribute sd.O012U2R4AxEU.65b.VU\
		unameit_net_bits_attribute sd.R.12U2R4AxEU.65b.VU\
		unameit_net_mask_attribute sd.PV12U2R4AxEU.65b.VU\
		unameit_net_type_attribute sd.SQX2U2R4AxEU.65b.VU\
		unameit_range_class sd.VxX2U2R4AxEU.65b.VU\
		unameit_range_netof_attribute eJmGyYyj2R0BWUU.65b.VU\
		unameit_range_start_attribute sd.XT12U2R4AxEU.65b.VU\
		unameit_range_end_attribute sd.av12U2R4AxEU.65b.VU\
		unameit_range_type_attribute Bguol1Xx2R4Zk.U.65b.VU\
		unameit_range_devices_attribute sd.sCX2U2R4AxEU.65b.VU
	    #
	    # Convert netgroups to ng_host and ng_user schema.
	    #
	    #
	    # Drop the host_netgroup and host_netgroup_member classes
	    #
	    unameit_delete 5smFWC5L2QyUsUU.65b.VU
	    unameit_delete 5smfoi5L2QyUsUU.65b.VU
	    #
	    # Drop the user_netgroup and user_netgroup_member classes
	    #
	    unameit_delete 5smSgi5L2QyUsUU.65b.VU
	    unameit_delete 5smxIi5L2QyUsUU.65b.VU
	    #
	    # Drop the mixed_netgroup classes
	    #
	    unameit_delete 1SMG3Wff2R4MJEU.65b.VU
	    unameit_delete 1SMO/0ff2R4MJEU.65b.VU
	    unameit_delete 1SMI30ff2R4MJEU.65b.VU
	    #
	    # Make the netgroup and netgroup_member classes concrete
	    #
	    unameit_update 5sm2OC5L2QyUsUU.65b.VU\
		unameit_class_readonly No\
		unameit_class_label Netgroup
	    #
	    unameit_update NSKBOe6e2R0YhEU.65b.VU\
		unameit_class_readonly No\
		unameit_class_group Netgroups
	    #
	    # Validate inherited "name" attribute of netgroup.
	    # Previously abstract class,  so had no validation.
	    #
	    unameit_create unameit_string_inherited_scalar_data_attribute\
		PQq2QXXj2R4J9EU.65b.VU\
		unameit_attribute_whence eJmJwYyj2R0BWUU.65b.VU\
		unameit_attribute_class 5sm2OC5L2QyUsUU.65b.VU\
		unameit_attribute_label Name\
		unameit_attribute_null Error\
		unameit_attribute_updatable Yes\
		unameit_string_attribute_minlen 1\
		unameit_string_attribute_maxlen 255\
		unameit_string_attribute_case Mixed\
		unameit_string_attribute_vlist\
		    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}\
		     {regexp ENETGRCHARS {^[^@,\(\)#]*$}}}
	    #
	    # Remove collision rule between netgroup name and server type name.
	    #
	    unameit_delete 5sbPKi5L2QyUsUU.65b.VU
	    #
    	    # Add collision rule for now concrete "netgroup" class
	    #
	    unameit_create unameit_data_collision_rule rCWiTXXr2R42KUU.65b.VU\
		unameit_collision_table 5sPSKi5L2QyUsUU.65b.VU\
		unameit_colliding_class 5sm2OC5L2QyUsUU.65b.VU\
		unameit_collision_attributes\
		    {eJmJwYyj2R0BWUU.65b.VU eJmGyYyj2R0BWUU.65b.VU}\
		unameit_collision_local_strength Strong\
		unameit_collision_cell_strength None\
		unameit_collision_org_strength None\
		unameit_collision_global_strength None
	    #
	    # Fix superclasse of {host,user}_netgroup_member_object
	    # netgroup_member_object, not mixed_netgroup_member_object.
	    #
	    unameit_update NSK7Ke6e2R0YhEU.65b.VU\
		unameit_class_supers NSKAB86e2R0YhEU.65b.VU
	    unameit_update NSK92e6e2R0YhEU.65b.VU\
		unameit_class_supers NSKAB86e2R0YhEU.65b.VU
	    #
	    # Delete ng_member field. Add ng_host and ng_user fields
	    # instead.
	    #
	    unameit_delete NSKCZe6e2R0YhEU.65b.VU
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		.pYBDXIS2R4oDEU.65b.VU\
		unameit_attribute_name ng_host\
		unameit_attribute_class NSKBOe6e2R0YhEU.65b.VU\
		unameit_attribute_label {Host Member}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain\
		NSK7Ke6e2R0YhEU.65b.VU\
		unameit_pointer_attribute_ref_integrity Cascade\
		unameit_pointer_attribute_update_access No\
		unameit_pointer_attribute_detect_loops Off
	    #
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		.pYDD1IS2R4oDEU.65b.VU\
		unameit_attribute_name ng_user\
		unameit_attribute_class NSKBOe6e2R0YhEU.65b.VU\
		unameit_attribute_label {User Member}\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain\
		NSK92e6e2R0YhEU.65b.VU\
		unameit_pointer_attribute_ref_integrity Cascade\
		unameit_pointer_attribute_update_access No\
		unameit_pointer_attribute_detect_loops Off
	    #
	    # Make a ng_ng field for sub-netgroups
	    #
	    unameit_create unameit_pointer_defining_scalar_data_attribute\
		Lzmej1Iy2R4L5EU.65b.VU\
		unameit_attribute_name ng_ng\
		unameit_attribute_class NSKBOe6e2R0YhEU.65b.VU\
		unameit_attribute_label Subnetgroup\
		unameit_attribute_null NULL\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain 5sm2OC5L2QyUsUU.65b.VU\
		unameit_pointer_attribute_ref_integrity Cascade\
		unameit_pointer_attribute_update_access No\
		unameit_pointer_attribute_detect_loops Off
	    #
	    # Delete ng_member field from netgroup_member's name fields
	    # and display list. Add the new ng_host, ng_user and ng_ng
	    # fields instead.
	    #
	    unameit_update NSKBOe6e2R0YhEU.65b.VU\
		unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU .pYBDXIS2R4oDEU.65b.VU}
	    unameit_update NSKBOe6e2R0YhEU.65b.VU\
		unameit_class_name_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU .pYBDXIS2R4oDEU.65b.VU\
		     .pYDD1IS2R4oDEU.65b.VU Lzmej1Iy2R4L5EU.65b.VU}
	    unameit_update NSKBOe6e2R0YhEU.65b.VU\
		unameit_class_display_attributes\
		    {eJmGyYyj2R0BWUU.65b.VU .pYBDXIS2R4oDEU.65b.VU\
		     .pYDD1IS2R4oDEU.65b.VU Lzmej1Iy2R4L5EU.65b.VU\
		     Wo1YKZ5j2R00DUU.65b.VU}
	    #
	    # Drop netgroup_member_object class.
	    #
	    unameit_delete NSKAB86e2R0YhEU.65b.VU
	    #
	    # Make host_netgroup_member_object and
	    # user_netgroup_member_objects named_items.
	    #
	    unameit_update NSK7Ke6e2R0YhEU.65b.VU\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU
	    unameit_update NSK92e6e2R0YhEU.65b.VU\
		    unameit_class_supers eJmIRYyj2R0BWUU.65b.VU
	    #
	    # Add trigger for netgroup_member so you can't enter invalid
	    # combinations of ng_host and ng_user.
	    #
	    unameit_create unameit_data_trigger sXqhPXIU2R4oDEU.65b.VU\
		    unameit_trigger_class NSKBOe6e2R0YhEU.65b.VU\
		    unameit_trigger_proc\
		    unameit_check_ng_member_compatibility\
		    unameit_trigger_inherited Yes\
		    unameit_trigger_oncreate Before\
		    unameit_trigger_onupdate Before\
		    unameit_trigger_ondelete No\
		    unameit_trigger_args {}\
		    unameit_trigger_attributes\
			{.pYBDXIS2R4oDEU.65b.VU .pYDD1IS2R4oDEU.65b.VU\
			 Lzmej1Iy2R4L5EU.65b.VU}\
		    unameit_trigger_computes {}
	    #
	    # Make owner of netgroup member be a netgroup
	    #
	    unameit_create unameit_pointer_inherited_scalar_data_attribute\
		Xn1kt1Ln2R4tJkU.65b.VU\
		unameit_attribute_whence eJmGyYyj2R0BWUU.65b.VU\
		unameit_attribute_class NSKBOe6e2R0YhEU.65b.VU\
		unameit_attribute_label Netgroup\
		unameit_attribute_null Error\
		unameit_attribute_updatable Yes\
		unameit_pointer_attribute_domain 5sm2OC5L2QyUsUU.65b.VU\
		unameit_pointer_attribute_ref_integrity Cascade\
		unameit_pointer_attribute_update_access No\
		unameit_pointer_attribute_detect_loops Off
	    #
	    # Fix unameit_item_attr error proc to take any number of
	    # attributes.
	    #
	    unameit_update 5sub.i5L2QyUsUU.65b.VU\
		unameit_error_proc_name unameit_item_alist\
		unameit_error_proc_args {item args}\
		unameit_error_proc_body {
    append result "[unameit_display_item $item]"
    foreach aname $args {
	append result "\nField: [unameit_display_attr $item $aname]"
    }
    return $result
}
	    #
	    # Fix unameit_item_attr error proc to take any number of
	    # attribute/value pairs
	    #
	    unameit_update 5suy1i5L2QyUsUU.65b.VU\
		unameit_error_proc_name unameit_item_avlist\
		unameit_error_proc_args {item args}\
		unameit_error_proc_body {
    append result "[unameit_display_item $item]"
    foreach {aname value} $args {
	append result "\nField: [unameit_display_attr $item $aname]"
	append result "\nValue: [unameit_display_value $item $aname $value]"
    }
    return $result
}
	    #
	    # Update unameit_uniqueness to remove an extra layer
	    # of list quoting
	    #
	    unameit_update 5sw5Yi5L2QyUsUU.65b.VU\
		unameit_error_proc_body {
    set result ""
    foreach {item alist} $args {
	append result "\n[unameit_display_item $item]\n"
	foreach aname $alist {
	    append result "Field: [unameit_display_attr $item $aname]\n"
	}
    }
    set result
}
	    #
	    # Update item_item to item_item_alist (allow trailing list
	    # common attributes
	    #
	    unameit_update 5svLzi5L2QyUsUU.65b.VU\
		unameit_error_proc_name unameit_item_item_alist\
		unameit_error_proc_args {item1 item2 args}\
		unameit_error_proc_body {
    append result "[unameit_display_item $item1]\n"
    append result "[unameit_display_item $item2]"
    foreach aname $args {
	append result "\nField: [unameit_display_attr $item2 $aname]"
    }
    set result
}
	    #
	    # Fix all error codes that use:
	    #   class or
	    #   class_attr or
	    #   item or
	    #	item_attr_attr or
	    # To use unameit_item_alist.
	    #
	    # Fix all error codes that use:
	    #	item_attr_item or
	    #	item_attr_value_attr_value or
	    #	bad_net_size
	    # To use unameit_item_avlist.
	    #
	    foreach {old new} {
		    5stvbC5L2QyUsUU.65b.VU 5sub.i5L2QyUsUU.65b.VU
		    5stzwi5L2QyUsUU.65b.VU 5sub.i5L2QyUsUU.65b.VU
		    5suSJi5L2QyUsUU.65b.VU 5sub.i5L2QyUsUU.65b.VU
		    5sugaC5L2QyUsUU.65b.VU 5sub.i5L2QyUsUU.65b.VU
		    5supPC5L2QyUsUU.65b.VU 5suy1i5L2QyUsUU.65b.VU
		    5sv0NC5L2QyUsUU.65b.VU 5suy1i5L2QyUsUU.65b.VU
		    5strIC5L2QyUsUU.65b.VU 5suy1i5L2QyUsUU.65b.VU
		} {
		foreach ecode\
		    [unameit_decode_items -result\
			[unameit_qbe unameit_error\
			    [list unameit_error_proc = $old]]] {
		    unameit_update $ecode\
			unameit_error_proc $new
		}
		# Drop obsolete error proc
		unameit_delete $old
	    }
	    #
	    # Delete previously orphaned error_procs and error codes
	    #
	    unameit_delete 5sutiC5L2QyUsUU.65b.VU; # item_attr_item_attr_item
	    unameit_delete 5svHgi5L2QyUsUU.65b.VU; # item_class_class
	    unameit_delete 5t1AMi5L2QyUsUU.65b.VU; # ENOUPDATE
	    unameit_delete 5t4hbi5L2QyUsUU.65b.VU; # EWRONGCLASS
	    unameit_delete 5t.svC5L2QyUsUU.65b.VU; # ENOMASK
	    unameit_delete 5t0Dki5L2QyUsUU.65b.VU; # ENOTNETCLASS
	    unameit_delete 5sy.ei5L2QyUsUU.65b.VU; # ECLASSNQUERY
	    unameit_delete 5sySwC5L2QyUsUU.65b.VU; # ECONN
	    unameit_delete 5sxf2C5L2QyUsUU.65b.VU; # EBADREALM
	    unameit_delete 5szY3C5L2QyUsUU.65b.VU; # EIO
	    unameit_delete 5szPOC5L2QyUsUU.65b.VU; # EIEIO
	    unameit_delete 5t2.MC5L2QyUsUU.65b.VU; # EPASSWDINCORRECT
	    unameit_delete 5t2Ffi5L2QyUsUU.65b.VU; # EPRINCIPALNOTUNIQUE
	    unameit_delete 5t/43i5L2QyUsUU.65b.VU; # ENOPRINCIPAL
	    #
	    # Create an error code for User or Host Member being a region and
	    # the other is set.
	    #
	    unameit_create unameit_error yqqoaXOg2R4D5.U.65b.VU\
		unameit_error_code ENGREGIONONLY\
		unameit_error_proc 5sub.i5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message\
	    {Field value of Region requires other field to be empty.}
	    #
	    # Update network error codes
	    #
	    #
	    # Create item_family error proc
	    #
	    unameit_create unameit_error_proc 0dKHoXl32R4.B.U.65b.VU\
		unameit_error_proc_name unameit_item_family\
		unameit_error_proc_args {item family}\
		unameit_error_proc_body {
    append result "[unameit_display_item $item]\n"
    append result "Address Family: $family"
}
	    unameit_update 5t.8wi5L2QyUsUU.65b.VU\
		unameit_error_code EINETBOUNDS\
		unameit_error_message\
		    {Network or range start not compatible with end}
	    unameit_update 5t0I4C5L2QyUsUU.65b.VU\
		unameit_error_code EINETNOTNODE\
		unameit_error_proc 0dKHoXl32R4.B.U.65b.VU
	    unameit_update 5t/8PC5L2QyUsUU.65b.VU\
		unameit_error_code EINETNOROOT\
		unameit_error_proc 0dKHoXl32R4.B.U.65b.VU\
		unameit_error_message\
		    {No 'universe' network (Data not restored?)}
	    unameit_update 5swvTC5L2QyUsUU.65b.VU\
		unameit_error_code EINETMASK\
		unameit_error_message\
		    {Subnet mask illegal or not compatible\
			with network bit count}
	    unameit_update 5t.Lui5L2QyUsUU.65b.VU\
		unameit_error_code EINETFULL\
		unameit_error_message {Network is full}
	    unameit_update 5t0V2C5L2QyUsUU.65b.VU\
		unameit_error_code EINETPARENT\
		unameit_error_message\
		    {Supplied addresses not constistent with network}
	    unameit_update 5t/H4C5L2QyUsUU.65b.VU\
		unameit_error_code EINETNOTADDR
	    #
	    # Create EINETBITS error code
	    #
	    unameit_create unameit_error 0dKKB1l32R4.B.U.65b.VU\
		unameit_error_code EINETBITS\
		unameit_error_proc 5suy1i5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message\
		    {Bit count too small for given network address}
	    #
	    unameit_create unameit_error /EOr41lB2R4.B.U.65b.VU\
		unameit_error_code EINETAUTOTOP\
		unameit_error_proc 5sub.i5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message {Cannot autogenerate top level networks}
	    #
	    # Add error code for bogus address family
	    #
	    unameit_create unameit_error qU5oK1r42R4FQ.U.65b.VU\
		unameit_error_code EINETNOFAMILY\
		unameit_error_proc 5steFC5L2QyUsUU.65b.VU\
		unameit_error_type Internal\
		unameit_error_message {Address family not found}
	    #
	    # Create range overlap error code
	    #
	    unameit_create unameit_error 2rwiOXuj2R4NSkU.65b.VU\
		unameit_error_code EINETRANGEOVERLAP\
		unameit_error_proc 5svLzi5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message {Ranges overlap}
	    #
	    # Create NODE_ZERO error code
	    #
	    unameit_create unameit_error 2rwjtXuj2R4NSkU.65b.VU\
		unameit_error_code EINETNODEZERO\
		unameit_error_proc 5suy1i5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message\
		    {Start address of each network is reserved}
	    #
	    # Create last node error code
	    #
	    unameit_create unameit_error 2rwl2Xuj2R4NSkU.65b.VU\
		unameit_error_code EINETLASTNODE\
		unameit_error_proc 5suy1i5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message\
		    {Last address of each network is reserved}
	    #
	    # Create EINETDUPNODE
	    #
	    unameit_create unameit_error mvFx8Y1R2R4RvUU.65b.VU\
		unameit_error_code EINETDUPNODE\
		unameit_error_proc 5svLzi5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message {Duplicate address}
	    #
	    # Create EINETDUPNET
	    #
	    unameit_create unameit_error mvFyOY1R2R4RvUU.65b.VU\
		unameit_error_code EINETDUPNET\
		unameit_error_proc 5svLzi5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message {Duplicate network}
	    #
	    # Create EINETBADNODE
	    #
	    unameit_create unameit_error jVDZFY2o2R4LukU.65b.VU\
		unameit_error_code EINETBADNODE\
		unameit_error_proc 5svLzi5L2QyUsUU.65b.VU\
		unameit_error_type Normal\
		unameit_error_message {Illegal node in network range}
	    #
	    # Update EINETLASTNET and EINETNETZERO
	    #
	    unameit_update 5szghi5L2QyUsUU.65b.VU\
		unameit_error_code EINETLASTNET\
		unameit_error_message\
		    {Last subnet of each network is reserved}
	    unameit_update 5t4qEC5L2QyUsUU.65b.VU\
		unameit_error_code EINETNETZERO\
		unameit_error_message\
			{Subnet "zero" of each network is reserved}
	    #
	    # Update EINET(NOT)SUBNETTED
	    #
	    unameit_update 5t0v3C5L2QyUsUU.65b.VU\
		unameit_error_code EINETNOTSUBNETTED
	    unameit_update 5t44ci5L2QyUsUU.65b.VU\
		unameit_error_code EINETSUBNETTED
	    #
	    # Update ENOSUBNETS
	    #
	    unameit_update 5t/Cki5L2QyUsUU.65b.VU\
		unameit_error_code EINETNOSUBNETS\
		unameit_error_message\
		    {Network too small to be subnetted}
	    #
	    # Delete EADDRRESERVED
	    #
	    unameit_delete 5swRBi5L2QyUsUU.65b.VU
	    #
	    # Delete EBADNETSIZE
	    #
	    unameit_delete 5sxF6C5L2QyUsUU.65b.VU
	    #
	    # Delete ECOMPATTR
	    #
	    unameit_delete 5syKFC5L2QyUsUU.65b.VU
	    #
	    # Delete EDEFAULTMASKFIXED
	    #
	    unameit_delete 5sybYi5L2QyUsUU.65b.VU
	    #
	    # Delete EDUPADDR
	    #
	    unameit_delete 5syx9C5L2QyUsUU.65b.VU
	    #
	    # Delete unameit_dupaddr proc
	    #
	    unameit_delete 5suJcC5L2QyUsUU.65b.VU
	    #
	    # Delete EDUPNET
	    #
	    unameit_delete 5sz/SC5L2QyUsUU.65b.VU
	    #
	    # Delete EFIXEDMASK
	    #
	    unameit_delete 5szGli5L2QyUsUU.65b.VU
	    #
	    # Delete ENOTPAIRLIST
	    #
	    unameit_delete 5t0Qii5L2QyUsUU.65b.VU
	    #
	    # Delete EPROTATTR
	    #
	    unameit_delete 5t2bLC5L2QyUsUU.65b.VU
	}
	#
	# Commit and checkpoint schema update
	#
	puts -nonewline "\nCommit..."; unameit_commit
	puts -nonewline "\nDump..."; unameit_dump
	puts Done
    }
    convert_data {
	#
	lassign $argv SMAJOR DATA DVERSION NEW_DVERSION
	set IDIR [file join $DATA data data.$DVERSION]
	set ODIR [file join $DATA data data.$NEW_DVERSION]

	if {$SMAJOR >= 8} return
	#
	#
	# Convert mail related classes.
	#
	## Create new version directory.
	file mkdir [file join $DATA data data.$NEW_DVERSION]

	old_init
	if {$SMAJOR < 4} {
	    puts "Converting data to schema version 4"
	    set code [catch {
		load_info
		v4_convert_mail
		v4_convert_netgroups
		v4_convert_roles
		convert_unchanged
		dump_info
	    } result]
	    if {$code != 0} {
		puts stderr $result
		puts stderr $errorCode
		puts stderr $errorInfo
		exit $code
	    }
	} else {
	    file delete -force $ODIR
	    file copy $IDIR $ODIR
	}
	    
	if {$SMAJOR < 7} {
	    puts "Converting data to schema version 7"
	    load_info
	    v7_convert_roles
	    dump_info
	}
	
	if {$SMAJOR < 8} {
	    puts "Converting data to schema version 8"
	    load_info
	    v8_convert_networks
	    v8_convert_netgroups
	    v8_convert_roles

	    ## Delete oid2classname entries
	    foreach index [array names oid2classname] {
		set temp($oid2classname($index)) $index
	    }
	    foreach class {host_netgroup host_netgroup_member user_netgroup\
		    user_netgroup_member mixed_netgroup\
		    mixed_netgroup_member mixed_netgroup_member_object\
		    netgroup_member_object} {
		catch {unset oid2classname($temp($class))}
	    }

	    set root_oid(ipv4_network) $root_oid(ipv4_node)
	    unset root_oid(ipv4_node)
	    dump_info
	}
		
	## Write new version file
	write_version_file $DATA $NEW_DVERSION
    }
    convert_schema {
        convert_schema $argv
    }
    default {
	error "Unsupported conversion action: $action"
    }
}
exit 0
END_TCL_CODE
    
#
# Shell script begins here
#
    
die() {
    echo $1 1>&2
    exit 1
}
    
read_version_files() {
    [ ! -f $DATA/data/data.version ] && \
	die "File $DATA/data/data.version not found"
    [ ! -f $DATA/data/schema.version ] && \
	die "File $DATA/data/schema.version not found"
	
    DVERSION=`cat $DATA/data/data.version`
    SVERSION=`cat $DATA/data/schema.version`
    SMAJOR=`echo $SVERSION | sed -e 's/\..*//; q'`
}

next_version() {
    set -- `(IFS=.; echo $1)`
    echo "$1.`expr $2 + 1`.0"
}

## Die on exit status 1.
set -e

## Parse args
[ $# -ne 1 ] && die "Usage: $0 <mode>"
DATA="`unameit_config unameitd All data`"
UNAMEIT_MODE=$1; export UNAMEIT_MODE
UNAMEIT=`unameit_filename UNAMEIT`

unameit_mode check "$UNAMEIT_MODE" || exit 1

read_version_files

########## Testing
# Compute new data version directory.
#SMAJOR=3
#NEW_DVERSION=`next_version $DVERSION`
#
# Upgrade data
#unameitcl "$0" convert_data $SMAJOR $DATA $DVERSION $NEW_DVERSION
#exit 0
########## Testing

## Shutdown w/checkpoint the server if running.
set +e
unameit_shutdown
set -e

## Do schema and data migration.
case "$SMAJOR" in
    3|4|5|6|7)
	### First migrate old schema to new format.

        ## Create temporary schema directory.
	NEW_SVERSION=`next_version $SVERSION`
	mkdir -p $DATA/data/schema.$NEW_SVERSION
	cp $DATA/data/schema.$SVERSION/* $DATA/data/schema.$NEW_SVERSION

	## Do conversion to new schema.
	$UNAMEIT/lbin/tcl "$0" convert_schema $DATA/data/schema.$NEW_SVERSION

	## Replace schema.version file
	rm -f $DATA/data/schema.version
	echo $NEW_SVERSION > $DATA/data/schema.version

	## Delete old database
	if unameit_spacedb >/dev/null 2>&1
	then
	    unameit_deletedb
	fi

	## Create new database
	unameit_makedb

	## Restore converted schema
	unameitd -R schema

	## Upgrade the schema to the latest version
	unameitd "$0" upgrade_schema

	## Start up unameitd so we can run unameitcl
	unameitd

        ## Compute new data version directory.
	NEW_DVERSION=`next_version $DVERSION`

	## Upgrade data
	unameitcl "$0" convert_data $SMAJOR $DATA $DVERSION $NEW_DVERSION

	## Shut down unameitd
	unameit_shutdown

	## Restore data
	unameitd -R data

	## Restart the server
	echo "Starting the UName*It server..."
	unameitd
	;;
    8)
	: Do nothing
	;;
    *)
	die "Unsupported schema major number: '$SMAJOR'"
	;;
esac

exit 0
