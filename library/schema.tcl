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

#
# QBE wrapper for wholesale load of class items
#
proc unameit_load_class {level class {allfields 0} {allsubs 0}} {
    upvar #$level UNAMEIT_META_INSTANCES instances
    #
    if {$allfields} {
	set data [unameit_qbe $class *]
	set items [uplevel #$level [list unameit_decode_items -result $data]]
	set instances($class) $items
    } else {
	set items $instances($class)
    }
    #
    if {$allsubs} {
	#
	# Intentional global and not upvar #$level,
	# can only query against current schema
	#
	global UNAMEIT_CLASS_UUID UNAMEIT_SUBS
	#
	foreach subclass $UNAMEIT_SUBS($UNAMEIT_CLASS_UUID($class)) {
	    #
	    # Intentional #0 and not #$level,
	    # can only query against current schema
	    #
	    upvar #0 $subclass subclass_item
	    set subclass_name $subclass_item(unameit_class_name)
	    append items " "
	    if {$allfields} {
		set data [unameit_qbe $subclass_name *]
		set instances($subclass_name)\
		    [uplevel #$level [list unameit_decode_items -result $data]]
	    }
	    append items $instances($subclass_name)
	}
    }
    set items
}

#
# Error wrapper.  Checks to make sure that error is registered,
# and is being invoked with the right number of args
#
proc unameit_error {code args} {
    global UNAMEIT_ERROR_PROC UNAMEIT_ERROR

    # If the global array doesn't exist, we haven't even bootstrapped yet.
    if {![info exists UNAMEIT_ERROR]} {
	error {} {} [concat UNAMEIT [list $code] $args]
    }

    if {![info exists UNAMEIT_ERROR($code)]} {
	eval unameit_error EBADERROR [list $code] $args
    }

    set args_copy $args
    lassign $UNAMEIT_ERROR($code) msg proc_uuid
    lassign $UNAMEIT_ERROR_PROC($proc_uuid) name error_args

    for {set next_error_arg [lvarpop error_args]
	    set next_arg [lvarpop args_copy]}\
	    {[llength $next_error_arg] > 0}\
	    {set next_error_arg [lvarpop error_args]
	    set next_arg [lvarpop args_copy]} {

	# If the last argument is "args", just return. The user can pass
	# anything in.
	if {[llength $error_args] == 0 && [cequal $next_error_arg args]} {
	    error $msg {} [concat UNAMEIT $code $args]
	}

	# If we found a default attribute, then either the last argument
	# is "args" or the number of args given is less than or equal to
	# the number of args left.
	if {[llength $next_error_arg] == 2 &&
	([cequal [lindex $error_args end] args] ||
	[llength $args_copy] <= [llength $error_args])} {
	    error $msg {} [concat UNAMEIT $code $args]
	}
    }

    if {[llength $next_arg] > 0} {
	eval unameit_error EBADERRORCALL $code $args
    }
    error $msg {} [concat UNAMEIT $code $args]
}

#
# -------------------------------------------------------
#
# Procedures to load and process various types of metadata.
#

proc unameit_load_collision_rules {level} {
    #
    upvar #$level\
	UNAMEIT_CLASS_UUID class_uuid\
	UNAMEIT_ATTRIBUTE_UUID attribute_uuid\
	UNAMEIT_ISA isa\
	UNAMEIT_SUBS subs\
	UNAMEIT_POINTER_DOMAIN pointer_domain
    #
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {
	UNAMEIT_COLLISIONS UNAMEIT_COLLISION_RULE UNAMEIT_COLLISION_ATTRS
    } {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    # CCC: Must match #defines in include/shared_const.h
    #
    set ival(None) 0
    set ival(Weak) 1
    set ival(Normal) 2
    set ival(Strong) 3
    #
    set rules [unameit_load_class $level unameit_collision_rule 1 1]
    #
    foreach rule $rules {
	upvar #$level $rule rule_item
	#
	set class $rule_item(unameit_colliding_class)
	set collision_table $rule_item(unameit_collision_table)
	#
	upvar #$level $class class_item
	set class_name $class_item(unameit_class_name)
	#
	upvar #$level $collision_table table_item
	set table_name "collision/$table_item(unameit_collision_name)"
	#	
	set collision_attributes {}
	foreach attribute $rule_item(unameit_collision_attributes) {
	    #
	    # Assume attribute is defining
	    #
	    upvar #$level $attribute attribute_item
	    lappend collision_attributes\
		$attribute_item(unameit_attribute_name)
	}
	#
	# The following variable is needed when populating the name
	# cache hash tables.
	#
	lappend UNAMEIT_COLLISIONS($class_name) $rule
	#
	# The following variable is needed when updating the name cache
	# classes from the name cache hash tables. It is also used in the
	# schema global validation code.
	#
	set UNAMEIT_COLLISION_RULE($rule)\
	    [list $class_name $table_name $collision_attributes\
		$ival($rule_item(unameit_collision_local_strength))\
		$ival($rule_item(unameit_collision_cell_strength))\
		$ival($rule_item(unameit_collision_org_strength))\
		$ival($rule_item(unameit_collision_global_strength))]
	#
	# The following variable is needed when constructing an error message
	# when a uniqueness integrity error occurs
	#
	set UNAMEIT_COLLISION_ATTRS($class_name.$table_name)\
	    $collision_attributes
    }
}

#
# Load trigger data into memory,  also note which attributes are computed.
#
proc unameit_load_triggers {level} {
    #
    upvar #$level UNAMEIT_SUBS subs
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    upvar #$level UNAMEIT_TRIGGERS triggers
    foreach export {
	UNAMEIT_GENERIC_TRIGGERS\
	UNAMEIT_COMPUTE_TRIGGERS\
	UNAMEIT_COMPUTED
    } {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    set triggers [unameit_load_class $level unameit_trigger 1 1]
    #
    foreach trigger $triggers {
	upvar #$level $trigger trigger_item
	upvar #$level [set class $trigger_item(unameit_trigger_class)]\
	    class_item
	set cname $class_item(unameit_class_name)
	#
	# Initialize trigger signature
	#
	set proc $trigger_item(unameit_trigger_proc)
	set args $trigger_item(unameit_trigger_args)
	set depnames {}
	set compnames {}
	#
	foreach attribute $trigger_item(unameit_trigger_attributes) {
	    upvar #$level $attribute attribute_item
	    lappend depnames $attribute_item(unameit_attribute_name)
	}
	#
	# There are two kinds of triggers, those that compute other
	# attributes, and those that do not.
	#
	set compattrs $trigger_item(unameit_trigger_computes)
	#
	if {[lempty $compattrs]} {
	    upvar 0 UNAMEIT_GENERIC_TRIGGERS siglist
	} else {
	    upvar 0 UNAMEIT_COMPUTE_TRIGGERS siglist
	    foreach attribute $compattrs {
		upvar #$level $attribute attribute_item
		set aname $attribute_item(unameit_attribute_name)
		set UNAMEIT_COMPUTED($cname.$aname) 1
		lappend compnames $aname
	    }
	}
	set cnames $cname
	#
	# Some triggers also apply to subclasses.
	#
	if {[cequal $trigger_item(unameit_trigger_inherited) Yes]} {
	    foreach sub $subs($class) {
		upvar #$level $sub sub_item
		lappend cnames $sub_item(unameit_class_name)
	    }
	}
	foreach cname $cnames {
	    if {![lempty compnames]} {
		foreach aname $compnames {
		    set UNAMEIT_COMPUTED($cname.$aname) 1
		}
	    }
	    foreach event {create update delete} {
		set onevent $trigger_item(unameit_trigger_on$event)
		switch -- $onevent {
		    Around -
		    Before {
			lappend siglist($event.$cname)\
			    [list $proc $args $depnames $compnames]
		    }
		}
		switch -- $onevent {
		    Around -
		    After {
			lappend siglist(post$event.$cname)\
			    [list $proc $args $depnames $compnames]
		    }
		}
	    }
	}
    }
}

proc unameit_load_name_attributes {level} {
    #
    upvar #$level UNAMEIT_SUPS sups
    #
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {UNAMEIT_NAME_ATTRIBUTES UNAMEIT_IS_NAME_ATTRIBUTE} {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    foreach class [array names sups] {
	upvar #$level $class class_item
	set class_name $class_item(unameit_class_name)
	set UNAMEIT_NAME_ATTRIBUTES($class_name) {}
	foreach attribute $class_item(unameit_class_name_attributes) {
	    upvar #$level $attribute attribute_item
	    set attribute_name $attribute_item(unameit_attribute_name)
	    lappend UNAMEIT_NAME_ATTRIBUTES($class_name) $attribute_name
	    set UNAMEIT_IS_NAME_ATTRIBUTE($class_name.$attribute_name) 1
	}
    }
}

#
# Load attribute metadata,  and parse out data needed in libudb and elsewhere
#
proc unameit_load_attributes {level} {
    #
    upvar #$level\
	UNAMEIT_SUPS sups\
	UNAMEIT_CLASS_UUID class_uuid
    #
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {
	UNAMEIT_REF_INTEGRITY UNAMEIT_DETECT_LOOPS UNAMEIT_NULLABLE
	UNAMEIT_ATTRIBUTES UNAMEIT_ATTRIBUTE_UUID UNAMEIT_UPDATABLE
	UNAMEIT_MULTIPLICITY UNAMEIT_SYNTAX UNAMEIT_ATTRIBUTE_TYPE
	UNAMEIT_ANAMES UNAMEIT_POINTER_DOMAIN UNAMEIT_ATTRIBUTE_CLASS
	UNAMEIT_CHECK_UPDATE_ACCESS UNAMEIT_QBE_CLASS UNAMEIT_ATTRIBUTE_NAME
	} {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    foreach private {UNAMEIT_ATTRIBUTE_ITEMS UNAMEIT_SYNTAX_PROC} {
	upvar #$level $private $private
	catch {unset $private}
    }
    #
    # First grab all the unameit_attribute records and store them in memory.
    #
    #
    # Trick: workaround for "empty" lappend semantics
    #
    set UNAMEIT_ATTRIBUTE_ITEMS ""
    #
    # Only the attribute classes with non-generic parameters
    # can have instances
    #
    foreach attribute_class\
	[unameit_decode_items -result\
	    [unameit_qbe unameit_syntax_class\
		{unameit_syntax_name != ""}\
		{unameit_syntax_resolution !=}\
		{unameit_syntax_multiplicity !=}]] {
	upvar #$level $attribute_class class_item
	lvarcat UNAMEIT_ATTRIBUTE_ITEMS\
	    [unameit_load_class $level $class_item(unameit_class_name) 1 0]
    }
    #
    # Initialize syntax proc counter
    #
    set pnum 0
    #
    # Special fields used below.
    #
    set p_domain unameit_pointer_attribute_domain
    set q_class  unameit_qbe_attribute_class
    #
    # In the second pass decode all attributes (need two passes, to handle
    # inherited attributes,  which point to defining attribute records).
    #
    foreach attribute $UNAMEIT_ATTRIBUTE_ITEMS {
	upvar #$level $attribute attribute_item
	#
	# Get "class" properties of attribute (from its class object)
	#
	set syntax_class $attribute_item(Class)
	upvar #$level $class_uuid($syntax_class) syntax_class_item
	set syntax $syntax_class_item(unameit_syntax_name)
	set resolution $syntax_class_item(unameit_syntax_resolution)
	#
	# Locate defining attribute for name and pointer domain key
	#
	switch -- $resolution {
	    Defining {
		set defining_attribute $attribute
		upvar #$level $attribute defining_attribute_item
	    }
	    Inherited {
		set defining_attribute $attribute_item(unameit_attribute_whence)
		upvar #$level $defining_attribute defining_attribute_item
		set syntax_class $defining_attribute_item(Class)
		upvar #$level $class_uuid($syntax_class) syntax_class_item
	    }
	}
	#
	# Get multiplicity and type from defining attribute syntax
	# class item
	#
	set multiplicity $syntax_class_item(unameit_syntax_multiplicity)
	set type $syntax_class_item(unameit_syntax_type)
	#
	set aname $defining_attribute_item(unameit_attribute_name)
	#
	# Find class for this attribute and extract its name
	#
	set class $attribute_item(unameit_attribute_class)
	upvar #$level $class class_item
	set cname $class_item(unameit_class_name)
	#
	lappend UNAMEIT_ATTRIBUTES($class) $attribute
	set UNAMEIT_ATTRIBUTE_UUID($cname.$aname) $attribute
	#
	# Save `global' information for defining attributes
	#
	switch -- $resolution Defining {
	    #
	    # Keep track of defining attribute records (by class)
	    #
	    lappend defined_attributes($class) $attribute
	    set UNAMEIT_MULTIPLICITY($aname) $multiplicity
	    set UNAMEIT_ATTRIBUTE_TYPE($aname) $type
	    set UNAMEIT_ATTRIBUTE_UUID($aname) $attribute
	    set UNAMEIT_ATTRIBUTE_CLASS($aname) $cname
	    set UNAMEIT_ATTRIBUTE_NAME($attribute) $aname
	}
	set UNAMEIT_SYNTAX($cname.$aname) $syntax
	#
	# Accumulate class attribute lists for each class
	#
	lappend UNAMEIT_ANAMES($cname) $aname
	#
	# Save nullability and updatability for udb_interp
	#
	if {[cequal $attribute_item(unameit_attribute_null) NULL]} {
	    set UNAMEIT_NULLABLE($cname.$aname) ""
	}
	set UNAMEIT_UPDATABLE($cname.$aname)\
	    [cequal $attribute_item(unameit_attribute_updatable) Yes]
	#
	if {$level != 0} continue
	#
	# Save query class for qbe attributes
	#
	if {[info exists attribute_item($q_class)]} {
	    upvar #0 $attribute_item($q_class) qbe_class_item
	    set UNAMEIT_QBE_CLASS($cname.$aname)\
		$qbe_class_item(unameit_class_name)
	}
	#
	# Save referential integrity and loop detection status for pointers.
	#
	if {[info exists attribute_item($p_domain)]} {
	    #
	    # Attribute matches current schema, get domain from database
	    #
	    set domain\
		[umeta_pointer_domain $cname $aname]
	    set UNAMEIT_POINTER_DOMAIN($class.$defining_attribute)\
		$class_uuid($domain)
	    #
	    foreach key {ref_integrity update_access detect_loops} {
		set $key\
		    $attribute_item(unameit_pointer_attribute_$key)
	    }
	    set UNAMEIT_REF_INTEGRITY($cname.$aname) $ref_integrity
	    if {[cequal $update_access Yes]} {
		set UNAMEIT_CHECK_UPDATE_ACCESS($cname.$aname) 1
	    }
	    if {[cequal $detect_loops On]} {
		set UNAMEIT_DETECT_LOOPS($cname.$aname) 1
	    }
	}
	#
	# Generate syntax checking functions
	#
	set pname "syntax_[incr pnum]"
	set UNAMEIT_SYNTAX_PROC($cname.$aname) $pname
	unameit_${syntax}_syntax_gen_proc\
	    $pname $attribute $aname $multiplicity usyntax_interp
    }
    #
    # Add information for inherited attributes with no metadata.
    #
    foreach class [array names sups] {
	upvar #$level $class class_item
	set cname $class_item(unameit_class_name)
	if {![info exists UNAMEIT_ATTRIBUTES($class)]} {
	    #
	    # Some classes may not have any
	    # attribute metadata.  Initialize attribute list to empty.
	    # (to avoid ugly [info exists ...] nonsense later)
	    #
	    set UNAMEIT_ATTRIBUTES($class) {}
	}
	foreach super $sups($class) {
	    #
	    # Bind class metadata for superclass
	    #
	    upvar #$level $super super_class_item
	    set sname $super_class_item(unameit_class_name)
	    #
	    if {![info exists defined_attributes($super)]} {
		#
		# This superclass doesn't define any attributes
		# (see initialization of defined_attributes above)
		#
		continue
	    }
	    #
	    foreach attribute $defined_attributes($super) {
		#
		# This attribute is of course the defining record.
		#
		upvar #$level $attribute attribute_item
		set aname $attribute_item(unameit_attribute_name)
		#
		# If attribute has explicit metadata we have already dealt
		# with it!
		#
		if {[info exists UNAMEIT_ATTRIBUTE_UUID($cname.$aname)]} {
		    #
		    # This attribute has metadata in the subclass
		    #
		    continue
		}
		#
		# Add to list of attributes for the class.
		#
		lappend UNAMEIT_ATTRIBUTES($class) $attribute
		lappend UNAMEIT_ANAMES($cname) $aname
		#
		if {[cequal $attribute_item(unameit_attribute_null) NULL]} {
		    set UNAMEIT_NULLABLE($cname.$aname) ""
		}
		#
		# We know that variables indexed by
		# $sname.$aname have been
		# set because they are defining attributes and were set above.
		#
		set UNAMEIT_SYNTAX($cname.$aname)\
		    $UNAMEIT_SYNTAX($sname.$aname)
		set UNAMEIT_ATTRIBUTE_UUID($cname.$aname)\
		    $UNAMEIT_ATTRIBUTE_UUID($sname.$aname)
		set UNAMEIT_UPDATABLE($cname.$aname)\
		    $UNAMEIT_UPDATABLE($sname.$aname)
		#
		if {$level != 0} continue
		#
		set UNAMEIT_SYNTAX_PROC($cname.$aname)\
		    $UNAMEIT_SYNTAX_PROC($sname.$aname)
		if {[info exists UNAMEIT_QBE_CLASS($sname.$aname)]} {
		    set UNAMEIT_QBE_CLASS($cname.$aname)\
			$UNAMEIT_QBE_CLASS($sname.$aname)
		}
		if {[cequal $UNAMEIT_SYNTAX($cname.$aname) pointer]} {
		    #
		    # Attribute matches current schema,
		    # get domain from database
		    #
		    set domain [umeta_pointer_domain $cname $aname]
		    set UNAMEIT_POINTER_DOMAIN($class.$attribute)\
			$class_uuid($domain)
		    #
		    # Save referential integrity...
		    #
		    set UNAMEIT_REF_INTEGRITY($cname.$aname)\
			$UNAMEIT_REF_INTEGRITY($sname.$aname)
		    if {[info exists\
			    UNAMEIT_CHECK_UPDATE_ACCESS($sname.$aname)]} {
			set UNAMEIT_CHECK_UPDATE_ACCESS($cname.$aname) 1
		    }
		    if {[info exists\
			    UNAMEIT_DETECT_LOOPS($sname.$aname)]} {
			set UNAMEIT_DETECT_LOOPS($cname.$aname) 1
		    }
		}
	    }
	}
    }
}

proc unameit_load_address_families {level} {
    #
    upvar #$level UNAMEIT_SUBS subs
    upvar #$level UNAMEIT_CLASS_UUID cuuid
    upvar #$level UNAMEIT_REF_INTEGRITY ref_int
    upvar #$level UNAMEIT_FAMILY_ITEMS families
    #
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {\
	UNAMEIT_NET_OF UNAMEIT_NET_CLASS\
	UNAMEIT_NODE_OF UNAMEIT_NODE_CLASS\
	UNAMEIT_RANGE_OF UNAMEIT_RANGE_CLASS\
	UNAMEIT_INET_INFO\
	UNAMEIT_FAMILY\
	UNAMEIT_NETPOINTER
    } {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    set alist {\
	node_netof node_address\
	net_netof net_start net_end net_bits net_mask net_type\
	range_netof range_type range_devices range_start range_end\
    }
    #
    set families [unameit_load_class $level unameit_address_family 1 0]
    #
    foreach family $families {
	upvar #$level $family family_item
	#
	set fname $family_item(unameit_family_name)
	#
	set UNAMEIT_INET_INFO($fname.octets)\
	    $family_item(unameit_address_octets)
	set UNAMEIT_INET_INFO($fname.node_zero)\
	    $family_item(unameit_node_zero)
	set UNAMEIT_INET_INFO($fname.last_node)\
	    $family_item(unameit_last_node)
	set UNAMEIT_INET_INFO($fname.net_zero)\
	    $family_item(unameit_net_zero)
	set UNAMEIT_INET_INFO($fname.last_net)\
	    $family_item(unameit_last_net)
	#
	foreach ctype {net node range} {
	    set key unameit_${ctype}_class
	    set CTYPE [string toupper $ctype]
	    set cArray UNAMEIT_${CTYPE}_OF
	    #
	    set class $family_item($key)
	    #
	    # Range class is optional for now
	    #
	    switch -- $class "" continue
	    upvar #$level $class class_item
	    set cname $class_item(unameit_class_name)
	    set UNAMEIT_INET_INFO($fname.${ctype}_class) $cname
	    #
	    foreach class [concat $class $subs($class)] {
		upvar #$level $class class_item
		set cname $class_item(unameit_class_name)
		lappend ${cArray}($cname) $fname
		#
		# Set label -> class mapping for node classes,
		# so we can interpret range_devices field.
		#
		switch -- $ctype node {
		    set label $class_item(unameit_class_label)
		    set UNAMEIT_INET_INFO(cname.$label) $cname
		}
	    }
	}
	#
	# Find attribute uuid from each property and record its name
	#
	foreach prop $alist {
	    set key unameit_${prop}_attribute
	    set attribute $family_item($key)
	    #
	    if {[cequal $attribute ""]} {
		#
		# Only the range attributes are optional
		# XXX: Check for all or NONE!
		#
		if {![info exists UNAMEIT_INET_INFO($fname.range_class)]} {
		    switch -glob -- $prop range_* {
			continue
		    }
		}
		#
		error "NULL network attribute: '$prop' of '$fname'" {}\
		    [list UNAMEIT ENULL $family $key]
	    }
	    upvar #$level $attribute attribute_item
	    set aname $attribute_item(unameit_attribute_name)
	    set UNAMEIT_INET_INFO($fname.$prop) $aname
	    set UNAMEIT_FAMILY($aname) $fname
	    #
	    # The parent network fields of node and network objects, are
	    # internally managed,  and have the special ref_integrity
	    # of 'Network'
	    #
	    switch -- $prop {
		net_netof - node_netof - range_netof {
		    #
		    # We need the parent network pointers for
		    # restore and loadup to schedule networks first.
		    #
		    switch -- $prop net_netof {
			set UNAMEIT_NETPOINTER($aname) $fname
		    }
		    #
		    # Set up 'Network' integrity for the net pointers
		    #
		    regsub {_netof} $prop {_class} cprop
		    set class $cuuid($UNAMEIT_INET_INFO($fname.$cprop))
		    #
		    foreach class [concat $class $subs($class)] {
			upvar #$level $class class_item
			set cname $class_item(unameit_class_name)
			set ref_int($cname.$aname) Network
		    }
		}
	    }
	}
    }
}

proc unameit_compute_inheritance_hierarchy {level} {
    #
    upvar #$level UNAMEIT_DIRECT_SUPERS direct_sups
    #
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {UNAMEIT_SUBS UNAMEIT_SUPS UNAMEIT_ISA} {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    # Every class of interest is an index in the direct_sups array
    #
    set clist [array names direct_sups]
    #
    # Initialize dag as totally disconnected graph
    #
    foreach c1 $clist {
	set UNAMEIT_SUBS($c1) {}
	set UNAMEIT_SUPS($c1) {}
	set UNAMEIT_ISA($c1.$c1) 1
    }
    #
    # Incrementally compute hierarchy
    # by adding one direct superclass link at a time
    # (adjust subclass list of all superclasses, and superclass lists of
    # all subclasses of the two nodes making the link)
    #
    foreach c1 $clist {
	foreach c2 $direct_sups($c1) {
	    foreach c3 [concat $c2 $UNAMEIT_SUPS($c2)] {
		#
		# Though the four `c1' lines below could be folded
		# into the `c4' loop,  the performance penalty for
		# redundantly searching subclasses of a class that
		# is already a subclass of c3 is severe.
		#
		if {[info exists UNAMEIT_ISA($c3.$c1)]} continue
		set UNAMEIT_ISA($c3.$c1) 1
		lappend UNAMEIT_SUBS($c3) $c1
		lappend UNAMEIT_SUPS($c1) $c3
		#
		# Add all subclasses of c1 as subclasses of c3
		#
		foreach c4 $UNAMEIT_SUBS($c1) {
		    if {[info exists UNAMEIT_ISA($c3.$c4)]} continue
		    set UNAMEIT_ISA($c3.$c4) 1
		    lappend UNAMEIT_SUBS($c3) $c4
		    lappend UNAMEIT_SUPS($c4) $c3
		}
	    }
	}
    }
}

#
# This routine sets the UNAMEIT_DIRECT_SUPERS array
# (which is used to compute the complete list of super (and sub) classes of
# each class).
#
proc unameit_load_classes {level} {
    #
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {
	UNAMEIT_DIRECT_SUPERS UNAMEIT_CLASS_UUID UNAMEIT_CLASS_RO
	UNAMEIT_CLASS_NAME UNAMEIT_CLASS_OF
    } {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    # Grab all the unameit_class classes
    #
    foreach metaclass {unameit_class unameit_syntax_class unameit_data_class} {
	lvarcat classes [unameit_load_class $level $metaclass 1 0]
    }
    #
    #
    # Save metadata for each class and record name -> uuid mapping
    #
    foreach class $classes {
	upvar #$level $class class_item
	set class_name $class_item(unameit_class_name)
	set UNAMEIT_CLASS_UUID($class_name) $class
	set UNAMEIT_CLASS_NAME($class) $class_name
	set UNAMEIT_CLASS_OF($class) $class_item(Class)
	set UNAMEIT_DIRECT_SUPERS($class) $class_item(unameit_class_supers)
	if {[cequal $class_item(unameit_class_readonly) Yes]} {
	    set UNAMEIT_CLASS_RO($class_name) 1
	}
    }
    #
    # Need `uuid' of `unameit_item' and `unameit_data_item' classes below
    #
    set i_class $UNAMEIT_CLASS_UUID(unameit_item)
    set di_class $UNAMEIT_CLASS_UUID(unameit_data_item)
    #
    foreach class $classes {
	upvar #$level $class class_item
	switch -- $class_item(Class) unameit_data_class {} default continue
	#
	# For the data classes the unameit_data_item class is an
	# implicit superclass (which in turn implicitly inherits
	# from unameit_item)
	#
	if {[cequal $class $i_class]} continue
	if {[cequal $class $di_class]} {
	    set UNAMEIT_DIRECT_SUPERS($class) $i_class
	    continue
	}
	if {[lsearch $UNAMEIT_DIRECT_SUPERS($class) $di_class] < 0} {
	    lappend UNAMEIT_DIRECT_SUPERS($class) $di_class
	}
    }
}

proc unameit_load_collision_tables {level} {
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {UNAMEIT_COLLISION_TABLE_ITEMS} {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    set UNAMEIT_COLLISION_TABLE_ITEMS\
	[unameit_load_class $level unameit_collision_table 1 1]
}

proc unameit_load_autoints {level} {
    upvar #$level\
	UNAMEIT_EXPORTED_VARS evars\
	UNAMEIT_SUBS subs\
	UNAMEIT_ATTRIBUTE_UUID auuid\
	UNAMEIT_AUTOINTS auto_ints\
	UNAMEIT_GENERIC_TRIGGERS siglist
    #
    foreach export {
	    UNAMEIT_AUTO_ATTRIBUTES
	    UNAMEIT_AUTO_LEVEL
	    UNAMEIT_AUTO_RANGE
    } {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    set auto_ints\
	[unameit_load_class $level\
	    unameit_autoint_defining_scalar_data_attribute 0 0]
    #
    set lattr unameit_autoint_attribute_level
    #
    # For uncommitted metadata we need not save any additional state
    #
    if {$level != 0} return
    #
    foreach uuid $auto_ints {
	upvar #$level $uuid auto_item
	set dclass $auto_item(unameit_attribute_class)
	set aname  $auto_item(unameit_attribute_name)
	#
	set UNAMEIT_AUTO_LEVEL($aname) $auto_item($lattr)
	#
	# Every subclass of the defining class of this attribute
	# needs to have this attribute added to UNAMEIT_AUTOINT_ATTRIBUTES.
	#
	foreach class [concat $dclass $subs($dclass)] {
	    upvar #$level $class class_item
	    set cname $class_item(unameit_class_name)
	    lappend UNAMEIT_AUTO_ATTRIBUTES($cname) $aname
	    #
	    upvar #0 $auuid($cname.$aname) attribute_item
	    #
	    # If not actually an autoint,  we are done
	    #
	    if {![info exists attribute_item($lattr)]} continue
	    #
	    # Save auto range of each subclass
	    #
	    set UNAMEIT_AUTO_RANGE($cname.$aname)\
		[list\
		    $attribute_item(unameit_autoint_attribute_min)\
		    $attribute_item(unameit_autoint_attribute_max)]
	    #
	    # Turn on autogeneration for the requested promotion levels
	    #
	    lappend siglist(create.$cname)\
		[list unameit_autoint_trigger {} [list $aname owner] {}]
	    lappend siglist(update.$cname)\
		[list unameit_autoint_trigger {} [list $aname owner] {}]
	}
    }
}

proc unameit_load_error_info {level} {
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {UNAMEIT_ERROR_PROC UNAMEIT_ERROR} {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }

    set error_items [unameit_load_class $level unameit_error 1 0]
    foreach item $error_items {
	upvar #$level $item ei
	set UNAMEIT_ERROR($ei(unameit_error_code))\
		[list $ei(unameit_error_message) $ei(unameit_error_proc)\
		$ei(unameit_error_type)]
    }

    set error_proc_items [unameit_load_class $level unameit_error_proc 1 0]
    foreach item $error_proc_items {
	upvar #$level $item ep
	set UNAMEIT_ERROR_PROC($item) [list $ep(unameit_error_proc_name)\
		$ep(unameit_error_proc_args) $ep(unameit_error_proc_body)]
    }
}

proc unameit_attr_to_name {level attr} {
    upvar #$level $attr attr_item

    if {[info exists attr_item(unameit_attribute_name)]} {
	return $attr_item(unameit_attribute_name)
    } else {
	upvar #$level $attr_item(unameit_attribute_whence) def_attr_item
	return $def_attr_item(unameit_attribute_name)
    }
}

proc unameit_load_attribute_order {level} {
    upvar #$level UNAMEIT_ATTR_ORDER UNAMEIT_ATTR_ORDER
    catch {unset UNAMEIT_ATTR_ORDER}
    #
    upvar #$level UNAMEIT_CLASS_UUID cuuid
    #
    foreach cname [array names cuuid] {
	set UNAMEIT_ATTR_ORDER($cname) {}
	upvar #$level $cuuid($cname) class_item
	foreach attribute $class_item(unameit_class_display_attributes) {
	    upvar #$level $attribute attribute_item
	    set aname $attribute_item(unameit_attribute_name)
	    lappend UNAMEIT_ATTR_ORDER($cname) $aname
	}
    }
    #
    # XXX: Hack: Schema attributes cannot be explicitly displayed
    # attributes of data classes.  Yet data attributes can only point
    # at data not schema.  Roles have to point at classes,  so
    # the corresponding attributes must be preloaded schema attributes,
    # but we want them displayed,  so just manually append them to the
    # attribute list.
    #
    lappend UNAMEIT_ATTR_ORDER(role)\
	unameit_role_create_classes\
	unameit_role_update_classes\
	unameit_role_delete_classes
    #
    # XXX: Until UI can handle these specially,  hardwire into every class
    #
    foreach cname [array names cuuid] {
	lappend UNAMEIT_ATTR_ORDER($cname)\
	    modby\
	    mtime\
	    mtran
    }
}

#
# ------------------------------------------------------------------------
#
proc unameit_load_schema {} {
    #
    # Results stored in caller's stack frame
    #
    set level [expr [info level] - 1]
    #
    if {$level == 0} {
	#
	# Level == 0 when invoked from top level via an alias the udb
	# interpreter.  This happens after the schema is committed.
	# The metadata should match the schema.  And we will export the
	# parsed variables back to the udb interpreter.
	# Since we may have previously saved state,  clean up stale
	# arrays.
	#
	upvar #0 UNAMEIT_META_INSTANCES instances
	foreach class [array names instances] {
	    foreach instance $instances($class) {
		upvar #0 $instance item
		unset item
	    }
	    unset instances($class)
	}
	#
	# Syntax procs run in a safe slave interpreter of the meta interpeter
	# It is easiest just to delete it each time,  then to separately
	# delete each of the old procs.
	#
	catch {interp delete usyntax_interp}
	interp create -safe usyntax_interp
	#
	# Add the safe TclX commands,  and uuid validation.
	#
	# Export unameit_error
	#
	usyntax_interp alias unameit_error unameit_error
	load {} tclx usyntax_interp
	load {} uuid usyntax_interp
	load {} Auth usyntax_interp
	load {} Upasswd usyntax_interp
    }
    upvar #$level UNAMEIT_EXPORTED_VARS evars
    foreach export {UNAMEIT_PROTECTED_ATTRIBUTE} {
	lappend evars $export
	upvar #$level $export $export
	catch {unset $export}
    }
    #
    # Hard-code initial protected attribute table!
    #
    set UNAMEIT_PROTECTED_ATTRIBUTE(uuid) 1
    set UNAMEIT_PROTECTED_ATTRIBUTE(modby) 1
    set UNAMEIT_PROTECTED_ATTRIBUTE(mtime) 1
    set UNAMEIT_PROTECTED_ATTRIBUTE(mtran) 1
    set UNAMEIT_PROTECTED_ATTRIBUTE(deleted) 1
    #
    # Reload metadata
    #
    unameit_load_classes $level
    unameit_compute_inheritance_hierarchy $level
    #
    # We need to compute the inheritance hierarchy before we call
    # unameit_load_attributes because the latter uses the UNAMEIT_SUPS
    # variable computed in the former.
    #
    unameit_load_attributes $level
    unameit_load_name_attributes $level
    unameit_load_triggers $level
    unameit_load_collision_tables $level
    unameit_load_collision_rules $level
    unameit_load_autoints $level
    unameit_load_address_families $level
    #
    if {$level == 0} {
	unameit_load_error_info 0
	unameit_load_attribute_order 0
	#
	# export variables to udb_interp
	#
	foreach var $evars {
	    upvar #0 $var v
	    if {[array exists v]} {
		catch {udb_unset $var}
		udb_array_set $var [array get v]
	    } elseif {[info exists v]} {
		udb_set $var [set v]
	    } else {
		catch {udb_unset $var}
	    }
	}
	udb_set UNAMEIT_STALE_AUTH(roles) 1
    }
}

proc unameit_check_syntax {class attribute uuid value} {
    upvar #0 UNAMEIT_SYNTAX_PROC($class.$attribute) proc
    usyntax_interp eval [list $proc $class $uuid $value db]
}

### System calls functions follow

proc unameit_get_menu_info {} {
    global UNAMEIT_CLASS_UUID

    foreach cname [array names UNAMEIT_CLASS_UUID] {
	set class $UNAMEIT_CLASS_UUID($cname)
	upvar #0 $class class_item
	lappend result $class\
	    [list $cname $class_item(unameit_class_label)\
		$class_item(unameit_class_group)\
		$class_item(unameit_class_readonly)]
    }
    set result
}

proc unameit_get_class_metadata {class} {
    global\
	UNAMEIT_ANAMES UNAMEIT_ATTRIBUTE_UUID UNAMEIT_CLASS_NAME\
	UNAMEIT_SUBS UNAMEIT_CLASS_NAME UNAMEIT_NAME_ATTRIBUTES\
	UNAMEIT_SYNTAX UNAMEIT_MULTIPLICITY UNAMEIT_ATTRIBUTE_TYPE\
	UNAMEIT_POINTER_DOMAIN UNAMEIT_COMPUTED UNAMEIT_ATTR_ORDER
    upvar #0 $class class_item
    #
    if {![array exists class_item]} {
	unameit_error ENXCLASS $class
    }
    set cname $class_item(unameit_class_name)

    set tmp($class) [array get class_item]
    lappend tmp($class) uuid $class
    set tmp(Computed) {}
    set tmp(NameAttrs) $UNAMEIT_NAME_ATTRIBUTES($cname)
    set tmp(Order) $UNAMEIT_ATTR_ORDER($cname)
    set tmp(SubClasses) $UNAMEIT_SUBS($class)
    #
    foreach aname $UNAMEIT_ANAMES($cname) {
	#
	upvar #0 [set attr $UNAMEIT_ATTRIBUTE_UUID($cname.$aname)] attr_item
	set syntax $UNAMEIT_SYNTAX($cname.$aname)
	set mult $UNAMEIT_MULTIPLICITY($aname)
	set type $UNAMEIT_ATTRIBUTE_TYPE($aname)
	#
	set tmp($attr) [array get attr_item]
	#
	# Insert "synthetic" properties needed by UI
	#
	lappend tmp($attr)\
	    uuid $attr Syntax $syntax Multiplicity $mult Type $type
	#
	if {[info exists attr_item(unameit_attribute_whence)]} {
	    set def_attr $attr_item(unameit_attribute_whence)
	    lappend tmp($attr) unameit_attribute_name $aname
	} else {
	    set def_attr $attr
	}
	if {[info exists UNAMEIT_COMPUTED($cname.$aname)]} {
	    lappend tmp(Computed) $cname.$aname\
		$UNAMEIT_COMPUTED($cname.$aname)
	}
	if {[info exists UNAMEIT_POINTER_DOMAIN($class.$def_attr)]} {
	    lappend tmp(Domain) $class.$attr\
		$UNAMEIT_CLASS_NAME($UNAMEIT_POINTER_DOMAIN($class.$def_attr))
	}
    }
    array get tmp
}

proc unameit_get_collision_rules {cname} {
    upvar #0\
	UNAMEIT_CLASS_UUID cuuid\
	UNAMEIT_COLLISIONS crules\
	UNAMEIT_COLLISION_RULE crule
    #
    if {![info exists cuuid($cname)]} {
	unameit_error ENXCLASS $cname
    }
    if {![info exists crules($cname)]} return
    set result {}
    foreach rule $crules($cname) {
	lappend result $crule($rule)
    }
    set result
}

proc unameit_get_attribute_classes {} {
    global UNAMEIT_ATTRIBUTE_UUID UNAMEIT_MULTIPLICITY UNAMEIT_CLASS_NAME
    #
    set result {}
    foreach aname [array names UNAMEIT_MULTIPLICITY] {
	upvar #0 $UNAMEIT_ATTRIBUTE_UUID($aname) aitem
	lappend result $aname\
	    $UNAMEIT_CLASS_NAME($aitem(unameit_attribute_class))
    }
    set result
}

proc unameit_get_protected_attributes {} {
    uplevel #0\
	array names UNAMEIT_PROTECTED_ATTRIBUTE
}

proc unameit_get_net_pointers {} {
    uplevel #0\
	array get UNAMEIT_NETPOINTER
}

proc unameit_get_error_code_info {code} {
    global UNAMEIT_ERROR

    if {![info exists UNAMEIT_ERROR($code)]} {
	return ""
    }

    return $UNAMEIT_ERROR($code)
}

proc unameit_get_error_proc_info {uuid} {
    global UNAMEIT_ERROR_PROC

    if {![info exists UNAMEIT_ERROR_PROC($uuid)]} {
	return ""
    }

    return $UNAMEIT_ERROR_PROC($uuid)
}
