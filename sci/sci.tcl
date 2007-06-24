#! /bin/sh
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

# Tcl ignores the next line. The shell doesn't.\
    exec unameitcl $0 "$@"

proc scicreate {argv} {
    set class [lvarpop argv]
    switch -- $class -u {
	set argv [lassign $argv uuid class]
    } default {
	set uuid [unameit_send uuidgen]
	puts $uuid
    }
    eval unameit_create [list $class $uuid] $argv
    unameit_commit
}

proc scidelete {argv} {
    switch -- [lindex $argv 0] -s {
	lvarpop argv
	foreach uuid $argv {
	    puts [unameit_get_db_label $uuid]
	}
    }
    eval unameit_delete_items $argv
    unameit_commit
}

proc sciundelete {argv} {
    switch -- [lindex $argv 0] -s {
	lvarpop argv
	foreach uuid $argv {
	    puts [unameit_get_db_label $uuid]
	}
    }
    unameit_revert_items $argv
    unameit_commit
}

proc sciupdate {argv} {
    eval unameit_update $argv
    unameit_commit
}

proc scinewuuid {argv} {
    puts [unameit_send uuidgen]
}

proc scimatch {argv} {
    set show 0
    set options {}
    while 1 {
	set class [lvarpop argv]
	switch -- $class {
	    -s {
		set show 1
	    }
	    -maxRows {
		lappend options -maxRows [lvarpop argv]
	    }
	    -timeOut {
		lappend options -timeOut [lvarpop argv]
	    }
	    -deleted {
		lappend options -deleted
	    }
	    default {
		break
	    }
	}
    }
    lappend query Class $class
    foreach spec $argv {
	set rest [lassign $spec field]
	lappend query $field $rest
    }
    foreach uuid [unameit_query $query $options] {
	if {$show} {
	    puts [unameit_get_db_label $uuid]
	} else {
	    puts $uuid
	}
    }
}

proc scishow {argv} {
    set uuid [lvarpop argv]
    set showuuids 0
    switch -- $uuid -u {
	set uuid [lvarpop argv]
	set showuuids 1
    }
    if [lempty $argv] {
	puts [unameit_get_db_label $uuid]
	return
    }
    array set tmp [eval unameit_get_attribute_values $uuid new $argv]
    foreach attr $argv {
	if {[cequal $attr Class] || $showuuids} {
	    puts $tmp($attr)
	    continue
	}
	if {[unameit_is_pointer $attr]} {
	    set result ""
	    foreach ref $tmp($attr) {
		lappend result [unameit_get_db_label $ref]
	    }
	    puts $result
	} else {
	    puts $tmp($attr)
	}
    }
}

proc scilistattrs {argv} {
    foreach attr [unameit_get_settable_attributes $argv] {
	set t [unameit_attribute_type $attr]
	switch -- [set m [unameit_get_attribute_multiplicity $attr]] {
	    Scalar {
		puts "$attr $t"
	    }
	    default {
		puts "$attr $m $t"
	    }
	}
    }
}

switch -- [set cmd [file tail $argv0]] {
    scilistattrs - scimatch - scinewuuid - scishow -
    scicreate - scidelete - sciundelete - sciupdate {
	$cmd $argv
    }
    default {
	error "Unknown sci command: $cmd"
    }
}
