#
# Copyright (c) 1996 Enterprise Systems Management Corp.
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
# $Id: ordered_list.tcl,v 1.6 1996/10/13 22:56:00 simpson Exp $

####			Ordered list routines (no duplicates allowed)

proc init_ordered_list {list_var} {
    upvar 1 $list_var list

    if {[info exists list(count^)]} {
	for {set count 0; set list_size [ordered_list_size list]}\
		{$count < $list_size} {incr count} {
	    set value $list([list value $count])
	    unset list([list value $count])
	    unset list([list index $value])
	}
    }
    set list(count^) 0
}

proc ordered_list_size {list_var} {
    upvar 1 $list_var list

    return $list(count^)
}

### This routine adds values to a ordered list. Duplicates are silently
### ignored. The values added to the list are returned (which may be less
### than the values passed since duplicates are ignored).
proc add_to_ordered_list {list_var args} {
    upvar 1 $list_var list

    set count $list(count^)

    set values_added {}

    foreach value $args {
	# Ignore duplicates. Duplicates won't work.
	if {[info exists list([list index $value])]} {
	    continue
	}

	set list([list index $value]) $count
	set list([list value $count]) $value

	lappend values_added $value

	incr count
    }

    set list(count^) $count

    return $values_added
}

proc set_ordered_list {list_var args} {
    upvar 1 $list_var list

    init_ordered_list list

    eval add_to_ordered_list list $args
}

proc get_values_from_ordered_list {list_var} {
    upvar 1 $list_var list

    set result {}

    for {set i 0} {$i < $list(count^)} {incr i} {
	lappend result $list([list value $i])
    }

    return $result
}

proc get_nth_from_ordered_list {list_var n} {
    upvar 1 $list_var list

    if {$list(count^) <= $n} {
	error "List index too large"
    }

    return $list([list value $n])
}

proc get_index_from_ordered_list {list_var value} {
    upvar 1 $list_var list

    return $list([list index $value])
}

proc ordered_list_contains_value {list_var value} {
    upvar 1 $list_var list

    return [info exists list([list index $value])]
}

proc delete_value_from_ordered_list {list_var value} {
    upvar 1 $list_var list

    set index [get_index_from_ordered_list list $value]
    for {set i $index} {$i < $list(count^)-1} {incr i} {
	set next_value $list([list value [expr $i+1]])
	set list([list value $i]) $next_value
	set list([list index $next_value]) $i
    }
    unset list([list value $i])
    unset list([list index $value])

    incr list(count^) -1

    return $index
}

proc delete_nth_from_ordered_list {list_var n} {
    upvar 1 $list_var list

    delete_value_from_ordered_list list [get_nth_from_ordered_list list $n]
}

proc get_indices_from_ordered_list {list_var} {
    upvar 1 $list_var list

    set result {}
    for {set i 0} {$i < [ordered_list_size list]} {incr i} {
	lappend result $list([list value $i])
    }
    return $result
}
