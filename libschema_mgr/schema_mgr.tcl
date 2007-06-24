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
# $Id: schema_mgr.tcl,v 1.70.4.5 1997/10/01 22:48:13 viktor Exp $

#### The cache manager interpreter is a sibling of the schema manager 
#### interpreter. Both of them are children of a parent interpreter that 
#### uses their resources. The parent interpreter may be the forms manager 
#### (if we are using regular UName*It) or the SCI.

####			Initialization routines

### This routine returns a list of all the commands that should be exported to 
### the cache manager only.
proc unameit_get_cache_mgr_commands {} {
    return {
    }
}

### This routine contains all the commands exported by this interpreter;
### that is, this routine returns the API of this interpreter. Aliases are
### made for every interpreter that uses the schema manager.
proc unameit_get_interface_commands {} {
    return {
	unameit_initialize_schema_mgr

	unameit_menu_info

	unameit_class_uuid
	unameit_class_exists
	unameit_get_name_attributes
	unameit_is_name_attribute
	unameit_get_subclasses
	unameit_get_class_list
	unameit_get_attributes
	unameit_get_displayed_attributes
	unameit_get_settable_attributes
	unameit_display_item
	unameit_is_subclass
	unameit_is_readonly

	unameit_defining_class
	unameit_attribute_type
	unameit_is_pointer
	unameit_get_attribute_domain
	unameit_is_attr_of_class
	unameit_isa_protected_attribute
	unameit_get_netpointers
	unameit_isa_computed_attribute
	unameit_display_attr
	unameit_display_value
	unameit_get_attribute_syntax
	unameit_get_attribute_multiplicity
	unameit_get_attribute_mdata_fields
	unameit_get_attribute_promotion
	unameit_is_nullable

	unameit_check_syntax

	unameit_error
	unameit_get_errtext
	unameit_get_error_proc
	unameit_get_error_msg
    }
}

### Any initialization code for the schema manager should go here. This routine
### should be able to be called more than once!
proc unameit_initialize_schema_mgr {} {
    set global_vars {
	UNAMEIT_CLASS_UUID
	UNAMEIT_CLASS_NAME
	UNAMEIT_ISA
	UNAMEIT_SUBS
	UNAMEIT_MENU_INFO
	UNAMEIT_ATTRIBUTE_UUID
	UNAMEIT_ATTRIBUTE_CLASS
	UNAMEIT_ATTRIBUTE_SYNTAX
	UNAMEIT_ATTRIBUTE_MULTIPLICITY
	UNAMEIT_ATTRIBUTE_TYPE
	UNAMEIT_ATTRIBUTE_PROM0TION
	UNAMEIT_META_UUIDS
	UNAMEIT_SYNTAX_COUNT
	UNAMEIT_SYNTAX_PROC
	UNAMEIT_POINTER_DOMAIN
	UNAMEIT_NAME_ATTRIBUTES
	UNAMEIT_ATTRIBUTES
	UNAMEIT_PROTECTED_ATTRIBUTE
	UNAMEIT_NETPOINTER
	UNAMEIT_ATTRIBUTE_COMPUTED
	UNAMEIT_ERROR
	UNAMEIT_ERROR_PROC
	UNAMEIT_CLASS_LABEL
	UNAMEIT_ATTRIBUTE_LABEL
	UNAMEIT_ATTR_ORDER
	UNAMEIT_CLASS_RO
    }
    global UNAMEIT_META_UUIDS UNAMEIT_SYNTAX_COUNT

    load {} Ucanon
    load {} Auth
    load {} Upasswd

    if {[info exists UNAMEIT_META_UUIDS]} {
	foreach key [array names UNAMEIT_META_UUIDS] {
	    global $key
	    catch {unset $key}
	}
    }

    if {[info exists UNAMEIT_SYNTAX_COUNT] && $UNAMEIT_SYNTAX_COUNT > 0} {
	for {set i 1} {$i <= $UNAMEIT_SYNTAX_COUNT} {incr i} {
	    rename unameit_syntax$i {}
	}
    }

    ## Unset global variables.
    foreach var $global_vars {
	global $var
	catch {unset $var}
    }

    ## At startup, we need to know all the class names and all the legal
    ## attribute names so routines in the schema manager that take class or
    ## attribute names as arguments don't need to go to the server and do
    ## a lookup to see if a class or attribute is valid.

    array set UNAMEIT_MENU_INFO [unameit_get_menu_info]
    foreach class [array names UNAMEIT_MENU_INFO] {
	lassign $UNAMEIT_MENU_INFO($class) name group label readonly

	set UNAMEIT_CLASS_RO($name) [cequal $readonly Yes]

	set UNAMEIT_CLASS_UUID($name) $class
	set UNAMEIT_CLASS_NAME($class) $name
    }
    array set UNAMEIT_ATTRIBUTE_CLASS [unameit_get_attribute_classes]

    set UNAMEIT_SYNTAX_COUNT 0

    foreach attr [unameit_get_protected_attributes] {
	set UNAMEIT_PROTECTED_ATTRIBUTE($attr) 1
    }

    array set UNAMEIT_NETPOINTER [unameit_get_net_pointers]
}

####		Routines exported to all clients

proc unameit_get_class_list {} {
    global UNAMEIT_CLASS_RO

    return [array names UNAMEIT_CLASS_RO]
}

#
# Return true and set info if this is a valid code.
# Look up the code by asking the server. This will raise an error
# if the connection is broken. An empty string will be returned
# if the code is invalid.
#
proc unameit_error_code {code p_info} {
    global UNAMEIT_ERROR
    upvar 1 $p_info info
    
    if {! [info exists UNAMEIT_ERROR($code)]} {
	set lookup [unameit_get_error_code_info $code]
	if {[string length $lookup] > 0} {
	    set UNAMEIT_ERROR($code) $lookup
	}

	if {! [info exists UNAMEIT_ERROR($code)]} {
	    return 0
	}
    }

    set info $UNAMEIT_ERROR($code)
    return 1
}

proc unameit_error_proc {proc_uuid p_proc} {
    global UNAMEIT_ERROR_PROC
    upvar 1 $p_proc proc

    if {! [info exists UNAMEIT_ERROR_PROC($proc_uuid)]} {
	set lookup [unameit_get_error_proc_info $proc_uuid]
	if {[string length $lookup] > 0} {
	    set UNAMEIT_ERROR_PROC($proc_uuid) $lookup
	}

	if {! [info exists UNAMEIT_ERROR_PROC($proc_uuid)]} {
	    return 0
	}
    }
    set proc $UNAMEIT_ERROR_PROC($proc_uuid)
    return 1
}

proc unameit_get_error_proc {code} {

    if {![unameit_error_code $code info]} {
	error "" "" [list UNAMEIT EBADERROR $code]
    }

    lassign $info msg proc_uuid
    if {![unameit_error_proc $proc_uuid info]} {
	error "" "" [list UNAMEIT EBADERROR $code]
    }

    return $info
}

proc unameit_get_error_msg {code args} {
    if {! [unameit_error_code $code info]} {
	return "Unknown error code: $code $args"
    }

    lassign $info msg proc_uuid internal
    if {! [unameit_error_proc $proc_uuid info]} {
	return "Unknown error proc: $code $args"
    }

    lassign $info name arg_list body

    if {[cequal [info proc $name] ""]} {
	proc $name $arg_list $body
    }
    eval {$name} $args
}

##
## Return *ordered* list of attributes that should be displayed
## on UI screen
##
proc unameit_get_displayed_attributes {class} {
    global UNAMEIT_ATTR_ORDER
    #
    if {[info exists UNAMEIT_ATTR_ORDER($class)]} {
	return $UNAMEIT_ATTR_ORDER($class)
    }
    unameit_class_uuid $class
    #
    return $UNAMEIT_ATTR_ORDER($class)
}

##
## Return list of attributes that the server will except in a create
## or update call.
##
proc unameit_get_settable_attributes {class} {
    set result ""
    foreach attr [unameit_get_displayed_attributes $class] {
        if {[unameit_isa_computed_attribute $class $attr]} continue
        if {[unameit_isa_protected_attribute $attr]} continue
	lappend result $attr
    }
    set result
}

### Returns the uuid of the class in the schema if it exists. It raises an 
### error otherwise. This function loads all the information about a class if 
### it isn't already loaded. It is assumed that if you ask for information 
### about a class, you probably want to know more so all the information 
### about a class is loaded.
proc unameit_class_uuid {class} {
    global UNAMEIT_CLASS_UUID

    if {![info exists UNAMEIT_CLASS_UUID($class)]} {
	unameit_error ENXCLASS $class
    }
    #
    # Nothing to do if already loaded
    #
    upvar #0 [set uuid $UNAMEIT_CLASS_UUID($class)] class_item
    if {[array exists class_item]} {return $uuid}
    #
    global\
	    UNAMEIT_ATTRIBUTES UNAMEIT_ATTRIBUTE_COMPUTED UNAMEIT_ATTRIBUTE_LABEL\
	    UNAMEIT_ATTRIBUTE_MULTIPLICITY UNAMEIT_ATTRIBUTE_SYNTAX\
	    UNAMEIT_ATTRIBUTE_TYPE UNAMEIT_ATTRIBUTE_UUID UNAMEIT_ATTR_ORDER\
	    UNAMEIT_CLASS_LABEL UNAMEIT_CLASS_RO UNAMEIT_ISA UNAMEIT_META_UUIDS\
	    UNAMEIT_NAME_ATTRIBUTE UNAMEIT_NAME_ATTRIBUTES UNAMEIT_POINTER_DOMAIN\
	    UNAMEIT_SUBS UNAMEIT_SYNTAX_COUNT UNAMEIT_SYNTAX_PROC

    array set tmp [unameit_get_class_metadata $uuid]
    #
    set new_canon_proc_attrs {}
    set UNAMEIT_ATTRIBUTES($class) {}
    foreach key [array names tmp] {
	switch -- $key {
	    Computed {
		array set UNAMEIT_ATTRIBUTE_COMPUTED $tmp($key)
	    }
	    Domain {
		array set UNAMEIT_POINTER_DOMAIN $tmp($key)
	    }
	    NameAttrs {
		set UNAMEIT_NAME_ATTRIBUTES($class) $tmp($key)
		foreach attr $tmp($key) {
		    set UNAMEIT_NAME_ATTRIBUTE($class.$attr) 1
		}
	    }
	    Order {
		set UNAMEIT_ATTR_ORDER($class) $tmp($key)
	    }
	    SubClasses {
		set UNAMEIT_ISA($uuid.$uuid) 1
		foreach u [set UNAMEIT_SUBS($uuid) $tmp($key)] {
		    set UNAMEIT_ISA($uuid.$u) 1
		}
	    }
	    default {
		#
		# This should be the uuid of an attribute or this class,
		# record the uuid as a cached uuid in the META_UUIDS array
		# (not a list since inherited attributes may be loaded
		# multiple times)
		#
		set UNAMEIT_META_UUIDS($key) 1

		#
		# Decode the metadata item
		#
		upvar #0 $key item
		array set item $tmp($key)

		#
		# If the item is a class (XXX: presumably this one),
		# record its label and continue
		#
		if {[catch {set UNAMEIT_CLASS_LABEL($uuid)\
			$item(unameit_class_label)}] == 0} continue

		#
		# The item must be an attribute:
		# the server returns name, syntax and multiplicity for each
		# attribute
		#
		set aname $item(unameit_attribute_name)
		set UNAMEIT_ATTRIBUTE_UUID($class.$aname) $key
		lappend UNAMEIT_ATTRIBUTES($class) $aname
		#
		set syntax $item(Syntax)
		set UNAMEIT_ATTRIBUTE_SYNTAX($class.$aname) $syntax
		#
		set mult $item(Multiplicity)
		set UNAMEIT_ATTRIBUTE_MULTIPLICITY($aname) $mult
		#
		set type $item(Type)
		set UNAMEIT_ATTRIBUTE_TYPE($aname) $type

		set UNAMEIT_ATTRIBUTE_LABEL($key)\
			$item(unameit_attribute_label)

		#
		# Create canonicalization function if necessary
		#
		if {[info exists UNAMEIT_SYNTAX_PROC($key)]} continue
		#
		# Build the syntax proc
		#
		set gen_proc unameit_${syntax}_syntax_gen_proc
		set proc unameit_syntax[incr UNAMEIT_SYNTAX_COUNT]
		set UNAMEIT_SYNTAX_PROC($key) $proc
		$gen_proc $proc $key $aname $mult {}
	    }
	}
    }
    return $uuid
}

proc unameit_class_exists {class} {
    global UNAMEIT_CLASS_UUID
    
    return [info exists UNAMEIT_CLASS_UUID($class)]
}


### This function checks to see if an item's class is a subclass of the class
### passed in.
proc unameit_is_subclass {parent child} {
    global UNAMEIT_ISA UNAMEIT_CLASS_UUID

    ## Check that classes passed in are OK.
    if {![info exists UNAMEIT_CLASS_UUID($parent)]} {
	unameit_error ENXCLASS $parent
    }
    if {![info exists UNAMEIT_CLASS_UUID($child)]} {
	unameit_error ENXCLASS $child
    }

    ## Convert the classes to their uuids. In the parent case, we must call
    ## unameit_class_uuid to load the UNAMEIT_ISA array if it isn't already
    ## loaded.
    set parent_uuid [unameit_class_uuid $parent]
    set child_uuid $UNAMEIT_CLASS_UUID($child)

    return [info exists UNAMEIT_ISA($parent_uuid.$child_uuid)]
}

#
# Return list of names of subclasses of the class named $super.
#
proc unameit_get_subclasses {super} {
    global UNAMEIT_SUBS UNAMEIT_CLASS_NAME

    ## Get uuid and load class if necessary
    set uuid [unameit_class_uuid $super]

    set result {}
    foreach sub $UNAMEIT_SUBS($uuid) {
	
	lappend result $UNAMEIT_CLASS_NAME($sub)
    }
    return $result
}

proc unameit_is_readonly {class} {
    global UNAMEIT_CLASS_RO

    if {![info exists UNAMEIT_CLASS_RO($class)]} {
	unameit_error ENXCLASS $class
    }
    return $UNAMEIT_CLASS_RO($class)
}

### This function also loads all the information about an attribute
### if it is not already loaded.  Returns the defining class.
proc unameit_defining_class {aname} {
    global UNAMEIT_ATTRIBUTE_CLASS UNAMEIT_ATTRIBUTE_UUID
    
    if {![info exists UNAMEIT_ATTRIBUTE_CLASS($aname)]} return

    set cname $UNAMEIT_ATTRIBUTE_CLASS($aname)

    if {![info exists UNAMEIT_ATTRIBUTE_UUID($cname.$aname)]} {
	## Preload the defining class
	unameit_class_uuid $cname
    }
    return $cname
}

### This function will give you back all the information you need to create the
### opening menus in "unameit".
proc unameit_menu_info {} {
    global UNAMEIT_MENU_INFO

    array get UNAMEIT_MENU_INFO
}

### This routine takes an attribute name and returns its type. The type
### returned will be Object, Integer or String.
proc unameit_attribute_type {attr} {
    global UNAMEIT_ATTRIBUTE_TYPE

    switch -- [unameit_defining_class $attr] "" {
	unameit_error ENXATTR $attr
    }
    set UNAMEIT_ATTRIBUTE_TYPE($attr)
}

### Is this attribute pointer valued. Don't care whether
### Scalar or Set or Sequence
proc unameit_is_pointer {aname} {
    switch -- [unameit_defining_class $aname] "" {
	unameit_error ENXATTR $aname
    }
    upvar #0 UNAMEIT_ATTRIBUTE_TYPE type
    cequal $type($aname) Object
}

proc unameit_get_attribute_syntax {class attr} {
    global UNAMEIT_ATTRIBUTE_SYNTAX

    ## Load data if need be
    set class_uuid [unameit_class_uuid $class]

    if {![info exists UNAMEIT_ATTRIBUTE_SYNTAX($class.$attr)]} {
	unameit_error ENOATTR $class $attr
    }

    return $UNAMEIT_ATTRIBUTE_SYNTAX($class.$attr)
}

proc unameit_get_attribute_multiplicity {attr} {
    global UNAMEIT_ATTRIBUTE_MULTIPLICITY

    switch -- [unameit_defining_class $attr] "" {
	unameit_error ENXATTR $attr
    }
    return $UNAMEIT_ATTRIBUTE_MULTIPLICITY($attr)
}

proc unameit_is_nullable {class attr} {
    global UNAMEIT_ATTRIBUTE_UUID

    unameit_class_uuid $class

    if {![info exists UNAMEIT_ATTRIBUTE_UUID($class.$attr)]} {
	unameit_error ENOATTR $class $attr
    }

    upvar #0 $UNAMEIT_ATTRIBUTE_UUID($class.$attr) aitem

    cequal $aitem(unameit_attribute_null) NULL
}

### This routine takes a class and an attribute returns the domain for that
### attribute.
proc unameit_get_attribute_domain {class attr} {
    global UNAMEIT_POINTER_DOMAIN UNAMEIT_CLASS_UUID UNAMEIT_ATTRIBUTE_UUID

    ## Load data if need be
    set class_uuid [unameit_class_uuid $class]

    if {![info exists UNAMEIT_ATTRIBUTE_UUID($class.$attr)]} {
	unameit_error ENOATTR $class $attr
    }

    set attr_uuid $UNAMEIT_ATTRIBUTE_UUID($class.$attr)

    if {![info exists UNAMEIT_POINTER_DOMAIN($class_uuid.$attr_uuid)]} {
	unameit_error ENOTPOINTER $class $attr
    }

    set domain_name $UNAMEIT_POINTER_DOMAIN($class_uuid.$attr_uuid)

    ## Load domain class data
    unameit_class_uuid $domain_name
    return $domain_name
}

proc unameit_check_syntax {class attr uuid value style} {
    global UNAMEIT_SYNTAX_PROC UNAMEIT_ATTRIBUTE_UUID UNAMEIT_CLASS_UUID

    ## Load data if need be
    unameit_class_uuid $class

    if {![info exists UNAMEIT_ATTRIBUTE_UUID($class.$attr)]} {
	unameit_error ENOATTR $uuid $attr
    }

    set attr_uuid $UNAMEIT_ATTRIBUTE_UUID($class.$attr)
    $UNAMEIT_SYNTAX_PROC($attr_uuid) $class $uuid $value $style
}

proc unameit_get_attribute_promotion {class attr} {
    upvar #0\
	    UNAMEIT_ATTRIBUTE_PROM0TION apromotion\
	    UNAMEIT_ATTRIBUTE_UUID auuid

    unameit_class_uuid $class
    if {![info exists auuid($class.$attr)]} {
	unameit_error ENOATTR $class $attr
    }
    if {[info exists apromotion($class.$attr)]} {
	return $apromotion($class.$attr)
    }
    set curstr 0
    set level None
    set alist $attr
    foreach rule [unameit_get_collision_rules $class] {
	lassign $rule cname table_name attributes l c o g
	if {[lsearch -exact $attributes $attr] < 0} continue
	if {$g > $curstr} {
	    set level Global
	    set curstr $g
	    set alist $attributes
	}
	if {$o > $curstr} {
	    set level Org
	    set curstr $o
	    set alist $attributes
	}
	if {$c > $curstr} {
	    set level Cell
	    set curstr $c
	    set alist $attributes
	}
	if {$l > $curstr} {
	    set level Local
	    set curstr $l
	    set alist $attributes
	}
    }
    set apromotion($class.$attr) [concat $level $alist]
}

proc unameit_get_name_attributes {class} {
    global UNAMEIT_NAME_ATTRIBUTES

    unameit_class_uuid $class
    return $UNAMEIT_NAME_ATTRIBUTES($class)
}

proc unameit_is_name_attribute {class attr} {
    global UNAMEIT_NAME_ATTRIBUTE

    unameit_class_uuid $class
    return [info exists UNAMEIT_NAME_ATTRIBUTE($class.$attr)]
}

proc unameit_is_attr_of_class {class attr} {
    global UNAMEIT_ATTRIBUTE_UUID

    unameit_class_uuid $class
    return [info exists UNAMEIT_ATTRIBUTE_UUID($class.$attr)]
}

proc unameit_get_attributes {class} {
    global UNAMEIT_ATTRIBUTES

    unameit_class_uuid $class
    return $UNAMEIT_ATTRIBUTES($class)
}

proc unameit_isa_protected_attribute {attr} {
    global UNAMEIT_PROTECTED_ATTRIBUTE

    return [info exists UNAMEIT_PROTECTED_ATTRIBUTE($attr)]
}

proc unameit_get_netpointers {} {
    uplevel #0 array get UNAMEIT_NETPOINTER
}

proc unameit_isa_computed_attribute {class attr} {
    global UNAMEIT_ATTRIBUTE_COMPUTED

    unameit_class_uuid $class
    return [info exists UNAMEIT_ATTRIBUTE_COMPUTED($class.$attr)]
}

proc unameit_run_error_proc {proc_uuid args} {
    global UNAMEIT_ERROR_PROC

    lassign $UNAMEIT_ERROR_PROC($proc_uuid) proc_name proc_args proc_body
    set proc_name @Error_Proc_$proc_name

    ## If procedure doesn't exist, define it.
    if {[catch {info args $proc_name}]} {
	proc $proc_name $proc_args $proc_body
    }

    eval [list $proc_name] $args
}

proc unameit_error {code args} {
    if {! [unameit_error_code $code info]} {
	# If we can't get the code, the code doesn't exist.
	# This may raise an error, if the connection to the server
	# is broken.
	return -code error -errorcode [concat UNAMEIT $code $args] ""
    }

    lassign $info msg proc_uuid

    if {! [unameit_error_proc $proc_uuid info]} {
	return -code error -errorcode [concat UNAMEIT $code $args] ""
    }
    lassign $info name error_args

    set args_copy $args

    for {set next_error_arg [lvarpop error_args]
    set next_arg [lvarpop args_copy]}\
	    {[llength $next_error_arg] > 0}\
	    {set next_error_arg [lvarpop error_args]
    set next_arg [lvarpop args_copy]} {

	## If the last argument is "args", just return. The user can pass
	## anything in.
	if {[llength $error_args] == 0 && [cequal $next_error_arg args]} {
	    error $msg {} [concat UNAMEIT $code $args]
	}

	## If we found a default attribute, then either the last argument
	## is "args" or the number of args given is less than or equal to
	## the number of args left.
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

proc unameit_get_errtext {arglist} {
    set arglist [lassign $arglist esys code]

    #
    switch -- $esys UNAMEIT {} default {
	return [list unknown ""]
    }

    if {! [unameit_error_code $code info]} {
	return [list unknown ""]
    }
    lassign $info error_msg proc_uuid internal

    if {! [unameit_error_proc $proc_uuid info]} {
	return [list unknown ""]
    }
    lassign $info proc_name proc_args proc_body

    set min_args [llength $proc_args]
    set max_args [llength $proc_args]
    set num_args [llength $arglist]
    #
    # If it ends in "args" there in no max_args, and min_args is one less
    #
    if {[cequal [lindex $proc_args end] args]} {
	incr min_args -1
	set max_args $num_args
	lvarpop proc_args end
    }

    #
    # Min args also goes down for every arg with a default value
    #
    while {![lempty $proc_args]} {
	switch -- [llength [lvarpop proc_args end]] {
	    0 -
	    1  break
	    2 {incr min_args -1}
	    default {
		#
		# Bad proc,  just set ridiculous min_args
		#
		set min_args [expr $num_args + 1]
	    }
	}
    }

    if {$num_args < $min_args || $num_args > $max_args} {
	return [unameit_get_errtext [concat $esys EBADERRORCALL\
		$code $arglist]]
    }

    if {[catch {format %s\n%s $error_msg\
	    [eval unameit_run_error_proc {$proc_uuid} $arglist]} text]} {
	return [unameit_get_errtext [concat $esys EBADERRORPROC $proc_name]]
    }

    # return internal or normal
    set type normal
    if {[cequal "Internal" $internal]} {
	set type "internal"
    }

    return [list $type $text]
}

proc unameit_get_attribute_mdata_fields {class attr field} {
    global UNAMEIT_ATTRIBUTE_UUID

    ## Load class if need be
    unameit_class_uuid $class

    if {![info exists UNAMEIT_ATTRIBUTE_UUID($class.$attr)]} {
	unameit_error ENOATTR $class $attr
    }

    set attr_uuid $UNAMEIT_ATTRIBUTE_UUID($class.$attr)

    upvar #0 $attr_uuid uuid_item

    return $uuid_item($field)
}

####			Display functions

## The unameit_display functions should NEVER raise an exception.

### Exported
proc unameit_display_item {item_or_class {prepend_class 1}} {
    upvar #0\
	UNAMEIT_CLASS_UUID cuuid\
	UNAMEIT_CLASS_LABEL clabel\
	UNAMEIT_CREATED created\
	UNAMEIT_UPDATED updated\
	UNAMEIT_DELETED deleted

    ## Check to see whether a class or uuid was passed in.
    if {[info exists cuuid($item_or_class)]} {
	# If unameit_class_uuid fails to load the class for some
	# reason, just return the class name.
	if {[catch {unameit_class_uuid $item_or_class}]} {
	    return $item_or_class
	}
	# UNAMEIT_CLASS_LABEL is indexed by uuid.
	return $clabel($cuuid($item_or_class))
    }
    #
    # Get Mask values for "created", "updated" and "deleted" from
    # cache manager.
    #
    if {![info exists created]} {
	lassign [unameit_get_item_states] created updated deleted
    }

    if {[catch {unameit_load_uuids [list $item_or_class]}]} {
	return $item_or_class
    }

    if {$created & [unameit_get_item_state $item_or_class]} {
	set func unameit_get_new_label
    } else {
	set func unameit_get_db_label
    }

    if {[catch {$func $item_or_class} msg]} {
	# If we can't get the label, just return the uuid.
	return $item_or_class
    } else {
	array set tmp [unameit_get_attribute_values $item_or_class new Class]
	if {$prepend_class} {
	    return "[unameit_display_item $tmp(Class)]: $msg"
	} else {
	    return $msg
	}
    }
}

## Exported
proc unameit_display_value {item_or_class attr value} {
    global UNAMEIT_CLASS_UUID

    if {[info exists UNAMEIT_CLASS_UUID($item_or_class)]} {
	set class $item_or_class
    } else {
	# If we can't load the object, then just return the value
	# uncanonicalized.
	if {[catch {unameit_load_uuids [list $item_or_class]}]} {
	    return $value
	}
	array set tmp [unameit_get_attribute_values $item_or_class new Class]
	set class $tmp(Class)
    }
    # Load class data if need be
    catch {unameit_class_uuid $class}
    #
    # If we can't canonicalize for display,  return raw data.
    #
    if {[catch {
	    unameit_check_syntax $class $attr $item_or_class $value display
	    } canon_value]} {
	return $value
    }
    #
    # If not object valued return display canonicalized value
    #
    if {![cequal [unameit_attribute_type $attr] Object]} {
	return $canon_value
    }
    #
    # If we have an object (list?) concatenate name attributes.
    #
    set list {}
    foreach uuid $canon_value {
	lappend list [unameit_display_item $uuid 0]
    }
    join $list ", "
}

### Exported
proc unameit_display_attr {item_or_class attr} {
    global UNAMEIT_CLASS_UUID UNAMEIT_ATTRIBUTE_UUID UNAMEIT_ATTRIBUTE_LABEL

    if {[info exists UNAMEIT_CLASS_UUID($item_or_class)]} {
	set class $item_or_class
    } else {
	# If we can't load the object, then just return the attribute
	# name.
	if {[catch {unameit_load_uuids [list $item_or_class]}]} {
	    return $attr
	}
	array set tmp [unameit_get_attribute_values $item_or_class new Class]
	set class $tmp(Class)
    }

    ## Load class data if need be
    catch {unameit_class_uuid $class}

    # The dummy gave an attribute that doesn't exist for the object.
    if {![info exists UNAMEIT_ATTRIBUTE_UUID($class.$attr)]} {
	return $attr
    }

    set attr_uuid $UNAMEIT_ATTRIBUTE_UUID($class.$attr)
    return $UNAMEIT_ATTRIBUTE_LABEL($attr_uuid)
}
