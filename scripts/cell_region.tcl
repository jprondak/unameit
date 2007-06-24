#!/bin/sh
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

# $Id: cell_region.tcl,v 1.4.58.1 1997/08/28 18:28:58 viktor Exp $


# TBD - cellorg
# TBD - top level cells (owned by .) CANNOT become regions

###########################################################################
#
# Read the datafile containing all instances of a given class.
# Construct global variables containing each instance.
# Set OpenOids to a list of the open objects, whose names will
# be the OIDs. SparseOids is a list of the OIDs that have only
# Class and owner information, and which do not have to be written
# back out.

proc open_class {class} {
    set callback {
	global $oid OpenOids 

	lappend OpenOids $oid
	array set $oid [array get F]
    }
    
    dump_edit_class $class $callback
}

proc get_class_owners {class} {
    set callback {
	global SparseOids 
	upvar #0 $oid instance

	lappend SparseOids $oid
	set instance(Class) $class
	if {[info exists F(owner)]} {
	    set instance(owner) $F(owner)
	} else {
	    puts "no owner for $oid in $class"
	    set instance(owner) ""
	}
    }
    
    dump_process_class $class $callback
}
    
###########################################################################
# Access methods for instance variables assume that the variables
# are global. The error checking is for debug purposes only; it can
# be removed without affecting funcionality.

proc setfield {instance field value} {
    upvar #0 $instance item
    #    puts "setfield: $instance $field $value"
    if {! [array exists item]} {
	error "setfield: no such array $instance"
    }
    set item($field) $value
}

proc getfield {instance field} {
    upvar #0 $instance item

    if {! [array exists item]} {
	error "getfield: no such array <$instance>"
    }

    if {! [info exists item($field)]} {
	error "getfield: no such field <$field> in <$instance>"
    } 

    log_debug "getfield <$instance> <$field> <$item($field)>"

    return $item($field)
}

# Debugging aid; describes an oid's object based on its class.
proc describe {oid} {

    set class [getfield $oid Class]
    switch -- $class {
	cell -
	region {
	    set name [getfield $oid name]
	    return "$oid ($class $name)"
	}
	automount_map {
	    set name [getfield $oid name]
	    set mount_point [getfield $oid mount_point]
	    return "$oid ($class $name @ $mount_point)"
	}
    }

    return "$oid ($class)"
}

###########################################################################
#
# Change a cell to a region.
# 1. change the Class to region.

proc cell2region {cell} {

    puts "changing [describe $cell] to a region"

    setfield $cell Class region

    global c2r_oid
    set c2r_oid($cell) 1
}

# Change a region to a cell.
proc region2cell {region} {

    puts "changing [describe $region] to a cell"

    setfield $region Class cell

    global r2c_oid
    set r2c_oid($region) 1
}

proc is_r2c {oid} {
    global r2c_oid
    info exists r2c_oid($oid)
}

proc is_c2r {oid} {
    global c2r_oid
    info exists c2r_oid($oid)
}

proc c2r_list {} {
    global c2r_oid
    array names c2r_oid
}

proc r2c_list {} {
    global r2c_oid
    array names r2c_oid
}

proc is_deleted {oid} {
    global Deleted
    info exists Deleted($oid)
}

proc set_deleted {oid} {
    global Deleted
    set Deleted($oid) 1
}

# use set_remap $cell $old $new 
# so the objects referencing the old map can be updated.
# TBD - check for collisions

proc set_remap {cell from to} {
    set remapvar "Remap_$cell"
    upvar #0 $remapvar remap
    set remap($from) $to
}

# Returns true if the map referenced by 'from' needs to be updated
# in the given cell (which may be "" for all cells).
# If true, sets 'to' to the new map, otherwise it is unchanged.

proc is_remap {cell from to} {
    set remapvar "Remap_$cell"
    upvar #0 $remapvar remap
    upvar 1 $to new_map

    if {[info exists remap($from)]} {
	
	puts "replace $from with $remap($from)"
	
	set new_map $remap($from)
	return 1
    }
    
    # default 
    return 0
}

proc reset_remap {} {
    foreach var [info vars Remap*] {
	puts "removing $var"
	unset $var
    }
}


# Replace all references in the given object with the remapped oids.
# This only needs to happen if an object's containing cell has changed.

proc remap_oids_in_class {class} {

    global fields

    # Determine which fields for this class are pointer type.
    set dofields {}
    foreach field $fields($class) {
	if {[cequal [unameit_get_attribute_syntax $class $field] pointer]} {
	    lappend dofields $field 
	}
    }

    puts "remap $class fields $dofields"

    if {[llength dofields] <= 0} return

    # The code will be eval'ed with oid and F set.
    dump_edit_class $class {
	catch {unset ccc}

	# if the old containing cell became a region,
	# replace references to maps in the old containing cell

	set old_cc [get_old_containing_cell $oid]
	if {[is_c2r $old_cc]} {
	    set ccc $old_cc
	}
	set new_cc [get_new_containing_cell $oid]
	if {[is_r2c $new_cc]} {
	    set ccc $new_cc
	}

	if {[info exists ccc]} {
	    foreach field $dofields {
		set new_field {}
		foreach fielditem $F($field) {
		    if {[is_remap $old_cc $fielditem new_map]} {
			lappend new_field $new_map
		    } else {
			lappend new_field $fielditem
		    }
		set F($field) $new_field
		}
	    }
	}
	dump_put_instance $oid F
    }
}

# This operation is done with all objects written out to start with.
# Replace all references to remapped oids (for moved automount maps).
# This only needs to happen if an object's containing cell has changed.

proc remap_oids {} {

    global unrestored

    dump_open_dir data

    foreach class [array names unrestored] {
	remap_oids_in_class $class
    }

    dump_close_dir
}
###########################################################################
# The containing cell of a cell is itself.
# The containing cell of a non-cell is the containing cell of its owner.
# The root of the tree is the cell '.' which has no owner.
# The containing cells must be found before switching cells to regions
# and vice versa.

# The containing cell of anything not a cell which has no owner is
# Noone.

# Find the first cell in the chain of owners.

proc set_containing_cell {oid var} {

    upvar #0 $var ContainingCell
    
    if {[info exists ContainingCell($oid)]} {
	return
    }

    set class [getfield $oid Class]
    if {[cequal cell $class]} {
	set ContainingCell($oid) $oid
	return
    }
	
    set owner [getfield $oid owner]

    if {[string length $owner] == 0} {
	set ContainingCell($oid) Noone
	puts "Noone owns [describe $oid]"
	return
    }

    set_containing_cell $owner $var
    set ContainingCell($oid) $ContainingCell($owner)
    return
}

# Return the containing cell. 

proc get_old_containing_cell {oid} {

    global OldContainingCell

    return $OldContainingCell($oid)
}

proc get_new_containing_cell {oid} {

    global NewContainingCell

    return $NewContainingCell($oid)
}


proc class_list {class} {
    global Class
    if {[info exists Class($class)]} {
	return $Class($class)
    } else {
	return {} 
    }
}

# Set up the global variables needed for later processing.
# Then set the OldContainingCell.
# After regions and cells are changed, NewContainingCell will be set
# using the same routine.

proc setup_indices {which} {
    global Class Deleted OpenOids SparseOids Oids
    catch {unset Class}
    catch {unset Deleted}

    append which ContainingCell

    set Oids [concat $OpenOids $SparseOids] 

    foreach oid $Oids {
	set_containing_cell $oid $which
	set class [getfield $oid Class]
	lappend Class($class) $oid
    }
}

###########################################################################
# Process each cell. Change it to a region if required.
# Changed cell oids are saved in c2r_oid.

proc update_c2r_cells {c2r_array} {
    upvar 1 $c2r_array c2r 

    foreach cell [class_list cell] {
	set name [getfield $cell name]

	puts [describe $cell]

	if {[info exists c2r($name)]} {
	    cell2region $cell
	}
    }
}

# Process each region. Change it to a cell if required.
# Changed region oids are saved in r2c_oid.

proc update_r2c_regions {r2c_array} {

    upvar 1 $r2c_array r2c

    foreach region [class_list region] {
	set name [getfield $region name]

	puts [describe $region]

	if {[info exists r2c($name)]} {
	    region2cell $region
	}
    }
}

###########################################################################
# Process classes descended from principal. Change the prealm to the 
# first cell up the chain of owners.

proc update_principals {} {

    set subs [concat principal [unameit_get_subclasses principal]]
    puts "handling principal subclasses: $subs"

    foreach class $subs {
	foreach oid [class_list $class] {
	    set prealm [get_new_containing_cell $oid]
	    setfield $oid prealm $prealm
	}
    }
}

###########################################################################
#
# Automount maps in this now-a-region get reparented to the owner cell.
# 1. If the owner cell has no map with this name or mount point,
# reparent the map.
# 2. If the mount point is already in the owner cell, drop this map and use
# the owner's map which has the same mount point.
# 3. If there is a name collision but the mount point is different, use the
# map with the same name.
# 4. If the owner cell has a map with the same name and same mount point
# use it.

# In case 1, no further adjustments are needed.
# In cases 2 and 3, a warning is issued.
# Case 2 has precedence over case 3.
# In cases 2, 3, and 4, all references to the old map need to be updated.

# find a map with the same name or the same mount point.
# set the_case_name to 1, 2, 3, or 4
# We take 2 passes in case 2 and 3 are both true.

proc find_parents_map {old_map_oid new_map_oid the_case_name} {
    upvar 1 \
	    $new_map_oid new_map \
	    $the_case_name decision
    global Maps
    puts "find_parents_map $old_map_oid $new_map_oid $the_case_name"

    # Find the new owner cell, then use its list
    # of maps. If there are none, it is case 1.
    set owner [get_new_containing_cell $old_map_oid]
    
    if {! [info exists Maps($owner)]} {
	puts "no maps"
	# This map is unique, so we can use it.
	set decision 1
	set new_map $old_map_oid 
	return
    }

    set maps $Maps($owner)

    puts "examining $maps"
    set mount_point [getfield $old_map_oid mount_point]
    set name [getfield $old_map_oid name]

    # Look for one with the same mount point
    foreach new_map $maps {
	if {[cequal $mount_point [getfield $new_map mount_point]]} {
	    if {[cequal $name [getfield $new_map name]]} {
		set decision 4
		return
	    } else {
		set decision 2
		return
	    }
	}
    }
    
    # Look for one with the same name, although the mount point is different
    foreach new_map $maps {
	if {[cequal $name [getfield $new_map name]]} {
	    set decision 3
	    return
	}
    }

    # This map is unique, so we can use it.
    set decision 1
    set new_map $old_map_oid 
    return
}

proc owner_dots {a b} {
    dots [getfield [getfield $a owner] name] [getfield [getfield $b owner] name] 
}

proc update_c2r_maps {} {

    global Maps

    # Get lists of all maps for each cell.
    # Also, mark the maps whose parent cells are becoming regions.

    set MapsToChange {}
    foreach oid [class_list automount_map] {

	set owner [getfield $oid owner]
	lappend Maps($owner) $oid
	
	puts "map [describe $oid], owner [describe $owner]"

	if {[is_c2r $owner]} {
	    lappend MapsToChange $oid
	}
    }

    # Process the maps topdown based on the owner cell's order.
    set MapsToChange [lsort -command owner_dots $MapsToChange]

    set nmaps [llength $MapsToChange]
    puts "replacing $nmaps automount_maps $MapsToChange"

    foreach oid $MapsToChange {

	# Determine which case we are dealing with.
	find_parents_map $oid new_oid decision
	
	switch -- $decision {
	    1 {
		set containing_cell [get_new_containing_cell $oid]
		setfield $oid owner $containing_cell 
		lappend Maps($owner) $oid
		puts "note: promoting unique map [describe $oid]"
		puts "note: now owned by [describe $containing_cell]"
	    }
	    2 {
		puts "warning: replacing [describe $oid]"
		puts "warning: with [describe $new_oid]"
		set containing_cell [get_old_containing_cell $oid]
		set_remap $containing_cell $oid $new_oid
		set_deleted $oid
	    }
	    3 {
		puts "warning: replacing [describe $oid]"
		puts "warning: with [describe $new_oid]"
		set containing_cell [get_old_containing_cell $oid]
		set_remap $containing_cell $oid $new_oid
		set_deleted $oid
	    }
	    4 {
		puts "note: replacing [describe $oid]";
		puts "note: with [describe $new_oid]; same name and mount point"
		set containing_cell [get_old_containing_cell $oid]
		set_remap $containing_cell $oid $new_oid
		set_deleted $oid
	    }
	    default {
		error "bug in update_maps"
	    }
	}
    }
}

###########################################################################
#
# When a region becomes a cell, all automount_map objects are copied from
# the old containing cell. Then the map oids are marked for remapping
# in the new cell. 
proc update_r2c_maps {} {
    global Maps OpenOids OldContainingCell NewContainingCell

    # Get lists of all maps for each cell.
    catch {unset Maps}
    foreach oid [class_list automount_map] {

	set owner [getfield $oid owner]
	lappend Maps($owner) $oid
	
	puts "map [describe $oid], owner [describe $owner]"
    }
    foreach new_cell [r2c_list] {
	set new_cell_name [getfield $new_cell name]
	set old_cc [get_old_containing_cell $new_cell]
	puts "update_r2c_maps [describe $new_cell]"
	puts "update_r2c_maps copying maps from [describe $old_cc]"

	if {[info exists Maps($old_cc)]} {
	    foreach map $Maps($old_cc) {
		set name [getfield $map name]
		set new_map "$name.automount_map.$new_cell_name"

		puts "creating $new_map from $map [array get $map]"

		global $new_map $map 
		array set $new_map [array get $map]
		setfield $new_map uuid ""
		setfield $new_map owner $new_cell
		set OldContainingCell($new_map) Noone
		set NewContainingCell($new_map) $new_cell
		puts [describe $new_map]
		lappend OpenOids $new_map
		set_remap $new_cell $map $new_map
	    }
	}
    }
}

# Write out all of the classes that have been opened
proc finish_open_oids {} {
    global OpenOids 
    foreach oid $OpenOids {
	global $oid
	if {! [is_deleted $oid]} {
	    dump_put_instance $oid $oid
	}
	unset $oid
    }
    unset OpenOids
}

# Delete all sparse objects
# At this time, nothing was updated so we just delete them.
proc finish_sparse_oids {} {
    global SparseOids 
    foreach oid $SparseOids {
	global $oid
	unset $oid
    }
}


proc ProcessCell2Region {c2r_array} {

    global SparseOids OpenOids unrestored 
    upvar 1 $c2r_array c2r

    # Read information about the classes in the dump data
    dump_open_dir data 

    # mod_classes is a list of the classes that will (potentially) be modified.
    # sparse_classes is a list of the rest of the classes in unrestored.
    set mod_classes [concat cell region automount_map \
	    principal [unameit_get_subclasses principal]]

    set all_classes [array names unrestored]

    set sparse_classes [lindex [intersect3 $all_classes $mod_classes] 0]

    set OpenOids {}
    foreach class $mod_classes {
	open_class $class
    }

    set SparseOids {}
    foreach class $sparse_classes {
	get_class_owners $class
    }

    setup_indices Old

    update_c2r_cells c2r 

    setup_indices New

    # NOTE: At this point we no longer need the sparse objects since the 
    # NewContainingCell array has been set.

    update_principals

    update_c2r_maps

    # write out all open oids
    finish_open_oids
    finish_sparse_oids

    # Write out the info file and close the files
    dump_close_dir

    remap_oids

    puts [info vars]
}

################################################################
proc ProcessRegion2Cell {r2c_array} {
    global SparseOids OpenOids unrestored 
    upvar 1 $r2c_array r2c

    # Read information about the classes in the dump data
    dump_open_dir data 

    # mod_classes is a list of the classes that will (potentially) be modified.
    # sparse_classes is a list of the rest of the classes in unrestored.
    set mod_classes [concat cell region automount_map \
	    principal [unameit_get_subclasses principal]]

    set all_classes [array names unrestored]

    set sparse_classes [lindex [intersect3 $all_classes $mod_classes] 0]

    set OpenOids {}
    foreach class $mod_classes {
	open_class $class
    }

    set SparseOids {}
    foreach class $sparse_classes {
	get_class_owners $class
    }

    setup_indices Old

    update_r2c_regions r2c 

    setup_indices New

    # NOTE: At this point we no longer need the sparse objects since the 
    # NewContainingCell array has been set.

    update_principals

    update_r2c_maps

    # write out all open oids
    finish_open_oids
    finish_sparse_oids

    # Write out the info file and close the files
    dump_close_dir

    remap_oids

    puts [info vars]
}

##########################################################################
# These arrays determine which cells become regions and vice versa
# The conversion is done in 2 passes to avoid confusion:
# first cells to regions, then regions to cells.

source dump_common.tcl

array set c2r [list \
	eng.xyz.com 1 \
	aerosys.eng.xyz.com 1 \
	mfg.xyz.com 1]

# TBD - A new organization name may be specified
array set r2c [list \
	ussales.mktg.xyz.com {} \
	res.aerosys.eng.xyz.com {} ]

#ProcessCell2Region c2r
ProcessRegion2Cell r2c
