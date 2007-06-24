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
# Routines for construction of in memory schema image
#

#
# Save class name,  so we can output a "CREATE CLASS" for it later
#
proc create_class {class} {
    global CLASSES
    lappend CLASSES $class
}

proc create_index {class args} {
    global INDICES
    lappend INDICES [list $class $args]
}

proc make_unique {class args} {
    global UNIQUE
    lappend UNIQUE [list $class $args]
}

#
# Save class, super class name pairs,  so we can output
# an "ALTER CLASS ADD SUPERCLASS" later
#
proc add_super_class {class super} {
    global SUPERS
    lappend SUPERS($class) $super
}

#
# Save class name, attribute name and SQL/X type (domain) so we can generate
# ALTER CLASS ADD ATTRIBUTE clauses later.
#
proc new_attribute {class attr type} {
    global ATTRIBUTES ATTR_CLASSES
    if {![info exists ATTRIBUTES($class)]} {
	lappend ATTR_CLASSES $class
    }
    lappend ATTRIBUTES($class) [list $attr $type]
}

#
# Indirect call to new_attribute.  So we can keep of track of directly
# created attributes.
#
proc raw_attribute {class attr type} {
    global RAW_ATTRIBUTES
    lappend RAW_ATTRIBUTES($class) [list $attr $type]
    new_attribute $class $attr $type
}

#
# Save class name, attribute name and SQL/X type (domain) so we can generate
# ALTER CLASS ADD CLASS ATTRIBUTE clauses later.
#
proc new_class_attribute {class attr type} {
    global CLASS_ATTRIBUTES CLASS_ATTR_CLASSES
    if {![info exists CLASS_ATTRIBUTES($class)]} {
	lappend CLASS_ATTR_CLASSES $class
    }
    lappend CLASS_ATTRIBUTES($class) [list $attr $type]
}

#
# Indirect call to new_class_attribute.  So we can keep of track of directly
# created class attributes.
#
proc raw_class_attribute {class attr type} {
    global RAW_CLASS_ATTRIBUTES
    lappend RAW_CLASS_ATTRIBUTES($class) [list $attr $type]
    new_class_attribute $class $attr $type
}

proc new_rel_class {attr multiplicity} {
    global REL_CREATED
    if {[info exists REL_CREATED($attr)]} return
    #
    set REL_CREATED($attr) 1
    #
    set relcname "relation/$attr"
    create_class $relcname
    new_class_attribute $relcname nextfree object
    new_attribute $relcname nextfree object
    new_attribute $relcname lhs object
    new_attribute $relcname rhs object
    new_attribute $relcname prev object
    new_attribute $relcname next object
    #
    switch -- $multiplicity {
	Scalar {
	    make_unique $relcname lhs
	}
	Set - Sequence {
	    create_index $relcname lhs
	}
    }
}

#
# Create pointer attribute
#
proc new_function {class attr domain} {
    new_attribute $class $attr "\"$domain\""
    new_rel_class $attr Scalar
}

#
# Create schema (setof) pointer with referential integrity
#
proc new_relation {class attr domain} {
    new_attribute $class $attr "SET OF \"$domain\" DEFAULT {}"
    new_rel_class $attr Set
}

#
# Create schema (seqof) pointer with referential integrity
#
proc new_order {class attr domain} {
    new_attribute $class $attr "SEQUENCE OF \"$domain\" DEFAULT {}"
    new_rel_class $attr Sequence
}

#
# Create a reference with a backpointer (RELATIVES)
# Don't bother with backpointers from readonly schema classes.
#
proc new_reference {from attr to} {
    global RELATIVES
    upvar #0 $from from_item
    lappend RELATIVES($to) [list $attr $from]
    lappend from_item($attr) $to
}


#
# Create a schema class.  Inserts into one of these cause
# (delayed till commit time) schema changes.  Some may be readonly,
# in which case their instances are frozen after this compiler is done.
#
proc new_schema_class {class readonly label name_attrs args} {
    global INSTANCES POINTER CLASSOF CLASS_UUID
    upvar #0 [set uuid [next_uuid]] item
    #
    create_class $class
    #
    foreach super $args {
	add_super_class $class $super
    }
    #
    lappend INSTANCES(unameit_class) $uuid
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    set CLASSOF($uuid) unameit_class
    #
    set item(uuid) $uuid
    set item(unameit_class_name)  $class
    set item(unameit_class_readonly) $readonly
    set item(unameit_class_label) $label
    set item(unameit_class_name_attributes) $name_attrs
    set item(unameit_class_supers) $args
    set item(unameit_class_group) ""
    if {[cequal $readonly No] && ![cequal $class unameit_address_family]} {
	set item(unameit_class_group) "Schema"
    }
    set CLASS_UUID($class) $uuid
}


#
# Create a schema class.  Inserts into one of these cause
# (delayed till commit time) schema changes.  Some may be readonly,
# in which case their instances are frozen after this compiler is done.
#
proc new_syntax_class {syntax resolution multiplicity namespace supers} {
    global SYNTAX_TYPE
    global INSTANCES POINTER CLASSOF CLASS_UUID
    #
    set params [concat $syntax $resolution $multiplicity]
    set class\
	[unameit_syntax_class $syntax $resolution $multiplicity $namespace]
    set type $SYNTAX_TYPE($class)
    #
    switch -- $resolution {
	Inherited {
	    set nalist {unameit_attribute_class unameit_attribute_whence}
	}
	Defining {
	    set nalist unameit_attribute_name
	}
	default {
	    set nalist {}
	}
    }
    if {[cequal $namespace Data]} {
	set label [concat $params Attribute]
    } else {
	set label [concat $params Generic Attribute]
    }
    #
    create_class $class
    #
    upvar #0 [set uuid [next_uuid]] item
    lappend INSTANCES(unameit_syntax_class) $uuid
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    set CLASSOF($uuid) unameit_syntax_class
    set CLASS_UUID($class) $uuid
    #
    set item(uuid) $uuid
    set item(unameit_class_name)  $class
    set item(unameit_class_label) $label
    set item(unameit_syntax_name) [string tolower $syntax]
    set item(unameit_syntax_type) $type
    set item(unameit_syntax_resolution) $resolution
    set item(unameit_syntax_multiplicity) $multiplicity
    set item(unameit_syntax_domain) $namespace
    #
    # Figure out whether class is readonly
    #
    set num_params [llength $params]
    switch -- $namespace {
	Data {set readonly [expr $num_params < 3 || [cequal $syntax UUID]]}
	default {set readonly 1}
    }
    if {$readonly} {
	set item(unameit_class_readonly) Yes
	set item(unameit_class_group) ""
    } else {
	set item(unameit_class_readonly) No
	#
	# Hide sequence attributes,  these are now deprecated.
	#
	if {![cequal $multiplicity Sequence]} {
	    set item(unameit_class_group) [concat Schema Attribute $params]
	}
    } 
    if {![cequal $resolution ""]} {
	if {[cequal $resolution Defining]} {
	    display $class unameit_attribute_name
	} else {
	    display $class unameit_attribute_whence
	}
	display $class unameit_attribute_class
	display $class unameit_attribute_label
	display $class unameit_attribute_null
	display $class unameit_attribute_updatable
    }
    set item(unameit_class_name_attributes) $nalist
    foreach baseclass $supers {
	add_super_class $class $baseclass
	lappend item(unameit_class_supers) $baseclass
    }
}

#
# Create a data class.  Inserts into one of these cause
# (delayed till commit time) schema changes.  Some may be readonly,
# in which case their instances are frozen after this compiler is done.
#
proc new_data_class {class uuid readonly group label name_attrs args} {
    global INSTANCES CLASS_UUID CLASSOF POINTER PROTECTED
    create_class $class
    #
    upvar #0 $uuid item
    set PROTECTED($uuid) 1
    #
    switch -- $class {
	unameit_item {}
	unameit_data_item {
	    add_super_class $class unameit_item
	}
	named_item {
	    add_super_class $class unameit_data_item
	    #
	    # "Named Item" does not override the "owner" attribute,  but
	    # being a data class needs to "shadow" the attribute.
	    #
	    new_function $class owner unameit_data_item
	}
	default {
	    add_super_class $class unameit_data_item
	}
    }
    foreach super $args {
	add_super_class $class $super
    }
    lappend INSTANCES(unameit_data_class) $uuid
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    set CLASSOF($uuid) unameit_data_class
    #
    set item(uuid) $uuid
    set item(unameit_class_name)  $class
    set item(unameit_class_readonly) $readonly
    set item(unameit_class_label) $label
    set item(unameit_class_name_attributes) $name_attrs
    set item(unameit_class_supers) $args
    set item(unameit_class_group) $group
    set CLASS_UUID($class) $uuid
}

#
# A collision table is not an item class (although the
# class of collision tables is an item class, its instances represent
# tables that only hold collision data, rather than unameit items, sigh...)
#
proc new_collision_table {name} {
    global INSTANCES POINTER COLLISION_UUID CLASSOF
    set class "collision/$name"
    create_class $class
    new_class_attribute $class nextfree object
    new_attribute $class nextfree object
    new_attribute $class key STRING
    make_unique $class key
    new_attribute $class strong "SET OF unameit_item DEFAULT {}"
    new_attribute $class normal "SET OF unameit_item DEFAULT {}"
    new_attribute $class weak "SET OF unameit_item DEFAULT {}"
    #
    upvar #0 [set uuid [next_uuid]] item
    lappend INSTANCES(unameit_collision_table) $uuid
    set CLASSOF($uuid) unameit_collision_table
    #
    set item(uuid) $uuid
    set item(unameit_collision_name)  $name
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    set COLLISION_UUID($name) $uuid
}

#
# A collision table is not an item class (although the
# class of collision tables is an item class, its instances represent
# tables that only hold collision data, rather than unameit items, sigh...)
#
proc new_data_collision_table {name} {
    global INSTANCES POINTER COLLISION_UUID CLASSOF
    set class "collision/$name"
    create_class $class
    new_class_attribute $class nextfree object
    new_attribute $class nextfree object
    new_attribute $class key STRING
    make_unique $class key
    new_attribute $class strong "SET OF unameit_item DEFAULT {}"
    new_attribute $class normal "SET OF unameit_item DEFAULT {}"
    new_attribute $class weak "SET OF unameit_item DEFAULT {}"
    #
    upvar #0 [set uuid [next_uuid]] item
    lappend INSTANCES(unameit_data_collision_table) $uuid
    set CLASSOF($uuid) unameit_data_collision_table
    #
    set item(uuid) $uuid
    set item(unameit_collision_name)  $name
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    set COLLISION_UUID($name) $uuid
}

#
# A collision_rule is not a class.
#
proc new_collision_rule {table_name class attrs ls cs os gs} {
    global INSTANCES POINTER CLASS_UUID CLASSOF COLLISION_UUID
    global ATTRIBUTE_UUID COLLISION_RULES
    #
    # Really local,  but static
    #
    global collision_rule_count
    #
    upvar #0 [set uuid [next_uuid]] item
    lappend INSTANCES(unameit_collision_rule) $uuid
    set CLASSOF($uuid) unameit_collision_rule
    lappend COLLISION_RULES($class) $uuid
    set item(uuid) $uuid
    new_reference $uuid unameit_collision_table $COLLISION_UUID($table_name)
    new_reference $uuid unameit_colliding_class $CLASS_UUID($class)
    foreach attr $attrs {
	new_reference $uuid unameit_collision_attributes $ATTRIBUTE_UUID($attr)
    }
    set item(unameit_collision_local_strength) $ls
    set item(unameit_collision_cell_strength) $cs
    set item(unameit_collision_org_strength) $os
    set item(unameit_collision_global_strength) $gs
    if {![info exists collision_rule_count]} {
	set collision_rule_count 0
    }
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
}

#
# A collision_rule is not a class.
#
proc new_data_collision_rule {table_name class attrs ls cs os gs} {
    global INSTANCES POINTER CLASS_UUID CLASSOF COLLISION_UUID
    global ATTRIBUTE_UUID COLLISION_RULES
    #
    # Really local,  but static
    #
    global collision_rule_count
    #
    upvar #0 [set uuid [next_uuid]] item
    lappend INSTANCES(unameit_data_collision_rule) $uuid
    set CLASSOF($uuid) unameit_data_collision_rule
    lappend COLLISION_RULES($class) $uuid
    set item(uuid) $uuid
    new_reference $uuid unameit_collision_table $COLLISION_UUID($table_name)
    new_reference $uuid unameit_colliding_class $CLASS_UUID($class)
    foreach attr $attrs {
	new_reference $uuid unameit_collision_attributes $ATTRIBUTE_UUID($attr)
    }
    set item(unameit_collision_local_strength) $ls
    set item(unameit_collision_cell_strength) $cs
    set item(unameit_collision_org_strength) $os
    set item(unameit_collision_global_strength) $gs
    if {![info exists collision_rule_count]} {
	set collision_rule_count 0
    }
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
}

proc new_trigger\
	{class inherited oncreate onupdate ondelete proc args deplist clist} {
    global INSTANCES CLASSOF TRIGGERS ATTRIBUTE_UUID CLASS_UUID
    global POINTER _trigger
    #
    upvar #0 [set uuid [next_uuid]] item
    #
    lappend INSTANCES(unameit_trigger) $uuid
    set CLASSOF($uuid) unameit_trigger
    #
    lappend TRIGGERS($class) $uuid
    if {![info exists _trigger]} {
	set _trigger 0
    } else {
	incr _trigger
    }
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    #
    set item(uuid) $uuid
    new_reference $uuid unameit_trigger_class $CLASS_UUID($class)
    set item(unameit_trigger_inherited) $inherited
    set item(unameit_trigger_proc) $proc
    set item(unameit_trigger_args) $args
    #
    set item(unameit_trigger_computes) {}
    set item(unameit_trigger_oncreate) $oncreate
    set item(unameit_trigger_onupdate) $onupdate
    set item(unameit_trigger_ondelete) $ondelete
    foreach attr $clist {
	new_reference $uuid unameit_trigger_computes $ATTRIBUTE_UUID($attr)
    }
    #
    set item(unameit_trigger_attributes) {}
    foreach attr $deplist {
	new_reference $uuid unameit_trigger_attributes $ATTRIBUTE_UUID($attr)
    }
}

proc new_data_trigger\
	{class inherited oncreate onupdate ondelete proc args deplist clist} {
    global INSTANCES CLASSOF TRIGGERS ATTRIBUTE_UUID CLASS_UUID
    global POINTER _trigger
    #
    upvar #0 [set uuid [next_uuid]] item
    #
    lappend INSTANCES(unameit_data_trigger) $uuid
    set CLASSOF($uuid) unameit_data_trigger
    #
    lappend TRIGGERS($class) $uuid
    if {![info exists _trigger]} {
	set _trigger 0
    } else {
	incr _trigger
    }
    set POINTER($uuid) ":o\[[incr POINTER(count)]\]"
    #
    set item(uuid) $uuid
    new_reference $uuid unameit_trigger_class $CLASS_UUID($class)
    set item(unameit_trigger_inherited) $inherited
    set item(unameit_trigger_proc) $proc
    set item(unameit_trigger_args) $args
    #
    set item(unameit_trigger_computes) {}
    set item(unameit_trigger_oncreate) $oncreate
    set item(unameit_trigger_onupdate) $onupdate
    set item(unameit_trigger_ondelete) $ondelete
    foreach attr $clist {
	new_reference $uuid unameit_trigger_computes $ATTRIBUTE_UUID($attr)
    }
    #
    set item(unameit_trigger_attributes) {}
    foreach attr $deplist {
	new_reference $uuid unameit_trigger_attributes $ATTRIBUTE_UUID($attr)
    }
}

proc new_errcode {code type message err_proc} {
    global INSTANCES CLASSOF ERR_PROC_UUID
    upvar #0 [set uuid [next_uuid]] item

    lappend INSTANCES(unameit_error) $uuid
    set CLASSOF($uuid) unameit_error
    set item(unameit_error_code) $code
    set item(unameit_error_message) $message
    set item(unameit_error_proc) $ERR_PROC_UUID($err_proc)
    set item(unameit_error_type) $type
}

proc new_errproc {proc_name arg_list body} {
    global INSTANCES CLASSOF ERR_PROC_UUID
    upvar #0 [set uuid [next_uuid]] item

    lappend INSTANCES(unameit_error_proc) $uuid
    set CLASSOF($uuid) unameit_error_proc
    set item(unameit_error_proc_name) $proc_name
    set item(unameit_error_proc_args) $arg_list
    set item(unameit_error_proc_body) $body
    set ERR_PROC_UUID($proc_name) $uuid
}
proc new_attr_order {class attr} {
    global ATTRIBUTE_UUID ATTR_ORDER
    lappend ATTR_ORDER $ATTRIBUTE_UUID($class.$attr)
}

proc display {class attr} {
    global DISPLAY
    lappend DISPLAY($class) $attr
}
