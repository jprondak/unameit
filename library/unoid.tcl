#! /opt/tcl/bin/tcl
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

set progname $argv0
set progdir [file dirname $argv0]
source [file join $progdir atomic.tcl]

lassign $argv ptrs_in ptrs_out workdir

set fd [open $ptrs_in r]
while {[gets $fd line] != -1} {
    set is_ptr([string trim $line]) 1
}
close $fd

if {![cequal $ptrs_out ""]} {
    set ptr_fd [atomic_open $ptrs_out 0444]
}

source [file join $workdir Info.tcl]
set clist [array names unrestored]

proc load_oids {dir cname} {
    global unrestored oidmap fields
    #
    set fd [open [file join $dir $unrestored($cname)] r]
    while {[lgets $fd line] != -1} {
	lassign $line oid uuid
	set oidmap($oid) $uuid
    }
    close $fd
}

proc map_oids {dir cname} {
    global unrestored oidmap fields is_ptr ptr_fd ptr_list oid2classname
    #
    set cmd {lassign $DATA}
    foreach f $fields($cname) {
	lappend cmd F($f)
    }
    set in [open [file join $dir $unrestored($cname)] r]
    set out [atomic_open [file join $dir $unrestored($cname)] 0444]
    #
    while {[lgets $in line] != -1} {
	lassign $line oid uuid DATA
	set NEWDATA {}
	eval $cmd
	foreach f $fields($cname) {
	    if {[info exists is_ptr($f)]} {
		set u {}
		foreach o $F($f) {lappend u $oidmap($o)}
		lappend NEWDATA $u
	    } else {
		switch -- $f {
		    unameit_role_create_classes -
		    unameit_role_delete_classes -
		    unameit_role_update_classes {
			set n {}
			foreach c $F($f) {lappend n $oid2classname($c)}
			lappend NEWDATA $n
		    }
		    default {
			lappend NEWDATA $F($f)
		    }
		}
	    }
	}
	if {[info exists ptr_fd] &&
		[info exists F(unameit_pointer_attribute_domain)] &&
		[info exists F(unameit_attribute_name)]} {
	    lappend ptr_list $F(unameit_attribute_name)
	}
	puts $out [list $uuid $uuid $NEWDATA]
    }
    close $in
    atomic_close $out
}

proc map_protected {dir} {
    global oidmap
    #
    set in [open [file join $dir Protected.dat] r]
    set out [atomic_open [file join $dir Protected.dat] 0444]
    #
    while {[lgets $in line] != -1} {
	lassign $line oid uuid
	puts $out [list $oidmap($oid) $uuid]
    }
    close $in
    atomic_close $out
}

proc map_info {dir} {
    global oid2uuid oidmap unrestored fields instances
    global subclasses oid2classname root_oid
    #
    set fd [atomic_open [file join $dir Info.tcl] 0444]
    foreach oid [lsort [array names oid2uuid]] {
	puts $fd [list set oid2uuid($oidmap($oid)) $oid2uuid($oid)]
    }
    foreach cname [lsort [array names root_oid]] {
	puts $fd [list set root_oid($cname) $oidmap($root_oid($cname))]
    }
    foreach cname [lsort [array names unrestored]] {
	puts $fd [list set unrestored($cname) $unrestored($cname)]
    }
    foreach cname [lsort [array names fields]] {
	puts $fd [list set fields($cname) $fields($cname)]
    }
    foreach cname [lsort [array names instances]] {
	puts $fd [list set instances($cname) $instances($cname)]
    }
    foreach cname [lsort [array names subclasses]] {
	puts $fd [list set subclasses($cname) $subclasses($cname)]
    }
    foreach oid [lsort [array names oid2classname]] {
	set name $oid2classname($oid)
	puts $fd [list set oid2classname($name) $name]
    }
    atomic_close $fd
}

foreach cname $clist {
    load_oids $workdir $cname
}
foreach oid [array names oid2uuid] {
    set oidmap($oid) $oid2uuid($oid)
}
foreach cname $clist {
    map_oids $workdir $cname
}
map_protected $workdir
map_info $workdir

if {[info exists ptr_fd]} {
    foreach ptr_name [lsort $ptr_list] {
	puts $fd $ptr_name
    }
    atomic_close $ptr_fd
}
