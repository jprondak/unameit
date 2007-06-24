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
# Routines for defining and creating attributes
#

proc attribute_name {attribute} {
    upvar #0 $attribute attribute_item
    if {[info exists attribute_item(unameit_attribute_name)]} {
	return $attribute_item(unameit_attribute_name)
    }
    upvar #0 $attribute_item(unameit_attribute_whence) def_attr_item
    return $def_attr_item(unameit_attribute_name)
}

proc unameit_syntax_class {args} {
    set params ""
    foreach arg $args {
	set params [concat $params [string tolower $arg]]
    }
    join [concat unameit $params attribute] _
}

#
# Helper proc for automatically generated new_<syntax> procs
# This one creates SQLX schema info for non object attributes.
# And creates the standard fields of `attribute' metadata object
# The extended fields are created in the new_<syntax> proc itself.
#
proc unameit_atom\
	{uuid syntax resolution multiplicity namespace cname aname
	 label null updatable domain} {
    global POINTER INSTANCES PROTECTED CLASSOF CLASS_UUID ATTRIBUTE_UUID
    global ATTRIBUTE_MULTIPLICITY ATTRIBUTE_TYPE
    global SYNTAX_TYPE ATTRIBUTE_METADATA
    set metaclass\
	[unameit_syntax_class $syntax $resolution $multiplicity $namespace]
    upvar #0 $uuid item
    lappend INSTANCES($metaclass) $uuid
    set CLASSOF($uuid) $metaclass
    set item(uuid) $uuid
    #
    switch -- $resolution {
	Defining {
	    set ATTRIBUTE_MULTIPLICITY($aname) $multiplicity
	    set ATTRIBUTE_TYPE($aname) $SYNTAX_TYPE($metaclass)
	    set item(unameit_attribute_name) $aname
	    set ATTRIBUTE_UUID($aname) $uuid
	}
	Inherited {
	    #
	    # XXX: assume defining attribute is declared first
	    #
	    new_reference $uuid unameit_attribute_whence\
		$ATTRIBUTE_UUID($aname)
	}
	default {
	    error "Schema Compiler bug"
	}
    }
    switch -- $multiplicity {
	Scalar {
	    set prefix ""
	    set suffix ""
	    #
	    # The only unique field (with metadata) is `uuid'
	    #
	    if {[string compare $aname uuid] == 0} {
		make_unique $cname $aname
	    }
	}
	default {
	    error "Schema Compiler bug"
	}
    }
    new_attribute $cname $aname "$prefix $domain $suffix"
    #
    # Protect compiled in `data attributes',  the whole UUID syntax class
    # is already readonly,  so we are OK there.
    #
    if {[cequal $namespace Data] && ![cequal $syntax UUID]} {
	set PROTECTED($uuid) 1
    }
    new_reference $uuid unameit_attribute_class $CLASS_UUID($cname)
    set item(unameit_attribute_label) $label
    set item(unameit_attribute_null) $null
    set item(unameit_attribute_updatable) $updatable
    set ATTRIBUTE_UUID($cname.$aname) $uuid
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    lappend ATTRIBUTE_METADATA($cname) $uuid
    return $uuid
}

#
# Helper proc for automatically generated new_<syntax> procs
# This one creates SQLX schema info for object attributes.
# And creates the defining `attribute' metadata object.
# The inheritance object is created in the new_<syntax> proc itself.
#
# Pointer fields are declared using new_function and friends so that
# we can do referential integrity.
#
proc unameit_pointer\
	{uuid syntax resolution multiplicity namespace cname aname\
	 label null updatable domain} {
    global POINTER INSTANCES PROTECTED CLASSOF CLASS_UUID ATTRIBUTE_UUID
    global ATTRIBUTE_NAMESPACE ATTRIBUTE_MULTIPLICITY ATTRIBUTE_TYPE
    global SYNTAX_TYPE ATTRIBUTE_METADATA
    #
    set metaclass\
	[unameit_syntax_class $syntax $resolution $multiplicity $namespace]
    #
    upvar #0 $uuid item
    lappend INSTANCES($metaclass) $uuid
    set item(uuid) $uuid
    set CLASSOF($uuid) $metaclass
    #
    switch -- $resolution {
	Defining {
	    set ATTRIBUTE_MULTIPLICITY($aname) $multiplicity
	    set ATTRIBUTE_TYPE($aname) $SYNTAX_TYPE($metaclass)
	    set item(unameit_attribute_name) $aname
	    set ATTRIBUTE_UUID($aname) $uuid
	}
	Inherited {
	    set multiplicity $ATTRIBUTE_MULTIPLICITY($aname)
	    new_reference $uuid unameit_attribute_whence\
		$ATTRIBUTE_UUID($aname)
	}
	default {
	    error "Schema Compiler bug"
	}
    }
    #
    switch -- $multiplicity {
	Scalar {
	    new_function $cname $aname $domain
	}
	Set {
	    new_relation $cname $aname $domain
	}
	Sequence {
	    new_order $cname $aname $domain
	}
	default {
	    error "Schema Compiler bug"
	}
    }
    #
    # Protect compiled in `data attributes'
    #
    switch -- $namespace Data {
	set PROTECTED($uuid) 1
    }
    new_reference $uuid unameit_attribute_class $CLASS_UUID($cname)
    set item(unameit_attribute_label) $label
    set item(unameit_attribute_null) $null
    set item(unameit_attribute_updatable) $updatable
    set ATTRIBUTE_UUID($cname.$aname) $uuid
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    lappend ATTRIBUTE_METADATA($cname) $uuid
    return $uuid
}

#
# Define a new syntax.  Create a new syntax class, and a procedure
# to add elements of that class.
# The attributes of the syntax class are deferred,  since their
# defining procedures may not yet exist.
#
proc new_syntax {syntax type args} {
    global SYNTAX_TYPE SYNTAX_ARGS SYNTAX_PARAMS
    #
    set class [unameit_syntax_class $syntax "" "" ""]
    #
    # Save the args for the base syntax,  so we can build its schema,
    # once all the syntax routines have been defined.
    # Also needed to recover args (== schema) for syntax subclasses.
    #
    set SYNTAX_TYPE($class) $type
    set SYNTAX_ARGS($class) [concat [list $syntax] $args]
    set SYNTAX_PARAMS($syntax) {}
    #
    # Create the base syntax class
    #
    new_syntax_class $syntax "" "" ""\
	[compute_syntax_supers $syntax "" "" ""]
    #
    # No constructor for generic syntax!
    #
    if {[cequal $syntax ""]} return
    #
    switch -- $type {
	Integer {
	    set domain INTEGER
	    set constructor unameit_atom
	}
	String {
	    set domain STRING
	    set constructor unameit_atom
	}
	Object {
	    #
	    # For pointer syntaxes,  first parameter must be the domain.
	    # (We only have one pointer syntax for now and forseeable future)
	    #
	    lassign $args domain_param
	    lassign $domain_param domain_param_name
	    set domain "$[join [concat $class $domain_param_name] _]"
	    set constructor unameit_pointer
	}
    }
    #
    # Process meta parameters of syntax
    #
    set alist\
	{resolution multiplicity namespace aname class label null updatable}
    set body {}
    #
    # Process attributes of generic syntax and this syntax
    #
    foreach meta $args {
	set rest [lassign $meta name label anull updatable asyntax]
	set name "${class}_${name}"
	lappend alist $name
	lappend SYNTAX_PARAMS($syntax) $name
	append body "set item($name) \$$name\n"
    }

    #
    # Common code for all constructors
    #
    set head [format {
	switch -glob $namespace {
	    "" {set uuid [next_uuid]}
	    default {lassign $namespace namespace uuid}
	}
	upvar #0 $uuid item
	%s $uuid %s $resolution $multiplicity $namespace $class\
	    $aname $label $null $updatable %s
    } $constructor $syntax $domain]
    #
    # Define the proc
    #
    proc [join [concat new [string tolower $syntax] attribute] _] $alist\
	"$head$body"
}

#
# Define a syntax subclass.
#
proc sub_syntax {args} {
    global SUB_SYNTAX_ARGS SYNTAX_TYPE SYNTAX_CLASSES
    #
    lassign $args syntax resolution multiplicity namespace
    set base_class [unameit_syntax_class $syntax "" "" ""]
    set class\
	[unameit_syntax_class $syntax $resolution $multiplicity $namespace]
    lappend SYNTAX_CLASSES $class
    #
    set SUB_SYNTAX_ARGS($class) $args
    set SYNTAX_TYPE($class) $SYNTAX_TYPE($base_class)
    #
    new_syntax_class $syntax $resolution $multiplicity $namespace\
	[compute_syntax_supers $syntax $resolution $multiplicity $namespace]
    #
    if {![cequal $resolution ""]} {
	global SYNTAX_PARAMS
	foreach param $SYNTAX_PARAMS($syntax) {
	    display $class $param
	}
    }
}

proc syntax_ancestors {syntax} {
    global SYNTAX_SUPERS
    set syntax [string tolower $syntax]
    set ancestors {}
    if {[info exists SYNTAX_SUPERS($syntax)]} {
	foreach super $SYNTAX_SUPERS($syntax) {
	    eval lappend ancestors [syntax_ancestors $super]
	}
    }
    lappend ancestors [unameit_syntax_class $syntax]
    return $ancestors
}

#
# Define a hybdrid syntax. See new_syntax above
#
proc hybrid_syntax {syntax supers args} {
    global SYNTAX_TYPE SYNTAX_ARGS SYNTAX_SUPERS SYNTAX_PARAMS
    #
    set class [unameit_syntax_class $syntax "" "" ""]
    #
    if {[lempty $supers]} {
	error "Empty superclass for hybrid syntax: $syntax"
    }
    set SYNTAX_SUPERS([string tolower $syntax]) $supers
    set SYNTAX_ARGS($class) [concat $syntax $args]
    foreach super $supers {
	set superclass [unameit_syntax_class $super "" "" ""]
	#
	# Check data type compatibility of superclasses
	#
	if {![info exists SYNTAX_TYPE($class)]} {
	    set SYNTAX_TYPE($class) [set type $SYNTAX_TYPE($superclass)]
	} elseif {![cequal $type $SYNTAX_TYPE($superclass)]} {
	    error "Incompatible data types for hybrid syntax: $syntax"
	}
	#
	lappend superclasses $superclass
    }
    #
    # Create the base syntax class
    #
    new_syntax_class $syntax "" "" "" $superclasses
    #
    set ancestors [syntax_ancestors $syntax]
    #
    switch -- $type {
	Integer {
	    set domain INTEGER
	    set constructor unameit_atom
	}
	String {
	    set domain STRING
	    set constructor unameit_atom
	}
	Object {
	    #
	    # Use first parameter of first ancestor as domain parameter
	    #
	    lassign $ancestors first
	    lassign $SYNTAX_ARGS($first) first domain_param
	    lassign $domain_param domain_param_name
	    set domain "$[join [concat $first $domain_param_name] _]"
	    set constructor unameit_pointer
	}
    }
    #
    # Process meta parameters of syntax
    #
    set alist\
	{resolution multiplicity namespace aname class label null updatable}
    set body {}
    #
    # Process attributes of generic syntax and this syntax
    #
    set SYNTAX_PARAMS($syntax) {}
    foreach syntax_class $ancestors {
	foreach meta [lrange $SYNTAX_ARGS($syntax_class) 1 end] {
	    set rest [lassign $meta name label anull updatable asyntax]
	    set name "${syntax_class}_${name}"
	    lappend alist $name
	    lappend SYNTAX_PARAMS($syntax) $name
	    append body "set item($name) \$$name\n"
	}
    }
    #
    # Common code for all constructors
    #
    set head [format {
	switch -glob $namespace {
	    "" {set uuid [next_uuid]}
	    default {lassign $namespace namespace uuid}
	}
	upvar #0 $uuid item
	%s $uuid %s $resolution $multiplicity $namespace $class $aname\
	    $label $null $updatable %s]
    } $constructor $syntax $domain]
    #
    # Define the proc
    #
    proc [join [concat new [string tolower $syntax] attribute] _] $alist\
	"$head$body"
}

#
# Define a hybrid syntax subclass.
#
proc hybrid_sub_syntax {args} {
    global SUB_SYNTAX_ARGS SYNTAX_TYPE SYNTAX_SUPERS SYNTAX_CLASSES
    #
    lassign $args syntax resolution multiplicity namespace
    set base_class [unameit_syntax_class $syntax "" "" ""]
    set class\
	[unameit_syntax_class $syntax $resolution $multiplicity $namespace]
    lappend SYNTAX_CLASSES $class
    #
    set SUB_SYNTAX_ARGS($class) $args
    set SYNTAX_TYPE($class) $SYNTAX_TYPE($base_class)
    #
    set superclasses $base_class
    foreach super $SYNTAX_SUPERS([string tolower $syntax]) {
	lappend superclasses\
	    [unameit_syntax_class $super $resolution $multiplicity $namespace]
    }
    new_syntax_class $syntax $resolution $multiplicity $namespace\
	$superclasses
    #
    if {![cequal $resolution ""]} {
	global SYNTAX_PARAMS
	foreach param $SYNTAX_PARAMS($syntax) {
	    display $class $param
	}
    }
}

proc compute_syntax_supers {syntax resolution multiplicity namespace} {
    set params [concat $syntax $resolution $multiplicity]
    set num_params [llength $params]
    set supers {}
    if {$num_params > 0} {
	if {![cequal $resolution ""] && ![cequal $syntax ""]} {
	    switch -- $num_params {
		3 {
		    if {[cequal $namespace ""]} {
			lappend supers [unameit_syntax_class $syntax]
		    } else {
			lappend supers [unameit_syntax_class $params]
		    }
		    if {![cequal $resolution Inherited]} {
			lappend supers\
			    [unameit_syntax_class\
				$resolution $multiplicity $namespace]
		    } elseif {![cequal $namespace Data]} {
			lappend supers [unameit_syntax_class Inherited]
		    }
		}
		default {
		    error "Bad attribute syntax:\
			[eval unameit_syntax_class $params]"
		}
	    }
	} elseif {![cequal $resolution Inherited]} {
	    if {[cequal $namespace Data]} {
		incr num_params
		lappend params Data
	    }
	    #
	    # Do not leave out resolution if any non syntax parameters remain
	    #
	    set start 0
	    if {[cequal $resolution Defining]} {
		set start [expr $num_params > 1]
	    }
	    #
	    for {set i $start} {$i < $num_params} {incr i} {
		lappend supers\
		    [eval unameit_syntax_class [lreplace $params $i $i]]
	    }
	} else {
	    if {[cequal $namespace Data]} {
		incr num_params
		lappend params Data
	    }
	    switch -- $num_params {
		1 {
		    lappend supers [eval unameit_syntax_class ""]
		}
		default {
		    error "Bad syntax: $params Attribute"
		}
	    }
	}
    } else {
	if {[cequal $namespace Data]} {
	    lappend supers [unameit_syntax_class ""]
	} else {
	    #
	    # the unameit_attribute class has unameit_schema_item as its sole
	    # superclass
	    #
	    lappend supers unameit_schema_item
	}
    }
    return $supers
}
