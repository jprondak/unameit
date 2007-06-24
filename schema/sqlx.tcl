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
# Routines to dump in memory schema image to SQL/X script
#

#
# Convert a scalar attribute value to SQLX form
#
proc sqlx_convert_atom {type value nullable} {
    global POINTER
    switch -- $type {
	Integer {
	    if {[cequal $value ""]} {
		return NULL
	    }
	    return $value
	}
	String {
	    if {$nullable && [cequal $value ""]} {
		return NULL
	    }
	    regsub -all {'} $value {''} value
	    return "'$value'"
	}
	Object {
	    if {[cequal $value ""]} {
		return NULL
	    }
	    return "$POINTER($value)"
	}
	default {
	    error "Schema compiler bug"
	}
    }
}
#
# Convert any attribute value to SQLX form
#
proc sqlx_convert_value {cname aname value} {
    global ATTRIBUTE_UUID SUB_SYNTAX_ARGS SYNTAX_TYPE CLASSOF
    global ATTRIBUTE_MULTIPLICITY
    #
    if {[info exists ATTRIBUTE_UUID($cname.$aname)]} {
	set attribute $ATTRIBUTE_UUID($cname.$aname)
    } else {
	set attribute $ATTRIBUTE_UUID($aname)
    }
    set syntax_class $CLASSOF($attribute)
    set multiplicity $ATTRIBUTE_MULTIPLICITY($aname)
    set type $SYNTAX_TYPE($syntax_class)
    lassign $SUB_SYNTAX_ARGS($syntax_class) syntax
    #
    switch -- $multiplicity {
	Scalar {
	    upvar #0 $attribute attribute_item
	    set nullable [cequal $attribute_item(unameit_attribute_null) NULL]
	    return [sqlx_convert_atom $type $value $nullable]
	}
	Set -
	Sequence {
	    set sep ""
	    set set ""
	    foreach elem $value {
		append set "$sep[sqlx_convert_atom $type $elem 0]"
		set sep ", "
	    }
	    return "{$set}"
	}
    }
}
#
# The next few functions are called at the end to actually emit the SQL/X code
# to define the schema and insert the initial meta data items after all
# the declarations build an in memory image of the schema.
#
proc sqlx_generate_classes {fd} {
    global CLASSES
    foreach class $CLASSES {
	puts $fd "EXEC SQLX CREATE CLASS \"$class\";"
    }
}
proc sqlx_generate_supers {fd} {
    global SUPERS
    foreach class [array names SUPERS] {
	set add_list {}
	foreach super $SUPERS($class) {
	    lappend add_list "\"$super\""
	}
	if {[llength $add_list] > 0} {
	    puts -nonewline $fd\
		"EXEC SQLX ALTER CLASS \"$class\" ADD SUPERCLASS\n\t"
	    puts $fd "[join $add_list ",\n\t"];"
	}
    }
}
proc sqlx_generate_attrs {fd} {
    global ATTRIBUTES CLASS_ATTRIBUTES
    global ATTR_CLASSES CLASS_ATTR_CLASSES
    foreach class $ATTR_CLASSES {
	set add_list {}
	foreach attr $ATTRIBUTES($class) {
	    lassign $attr aname atype
	    lappend add_list "\"$aname\" $atype"
	}
	if {[llength $add_list] > 0} {
	    puts -nonewline $fd\
		"EXEC SQLX ALTER CLASS \"$class\" ADD ATTRIBUTE\n\t"
	    puts $fd "[join $add_list ",\n\t"];"
	}
    }
    foreach class $CLASS_ATTR_CLASSES {
	set add_list {}
	foreach attr $CLASS_ATTRIBUTES($class) {
	    lassign $attr aname atype
	    lappend add_list "\"$aname\" $atype"
	}
	if {[llength $add_list] > 0} {
	    puts -nonewline $fd\
		"EXEC SQLX ALTER CLASS \"$class\" ADD CLASS ATTRIBUTE\n\t"
	    puts $fd "[join $add_list ",\n\t"];"
	}
    }
}
proc sqlx_generate_items {fd class} {
    global INSTANCES CLASS_UUID POINTER VLIST
    if {![info exists INSTANCES($class)]} return
    foreach uuid $INSTANCES($class) {
	upvar #0 $uuid item
	set templ ""
	set data ""
	set sep ""
	foreach field [array names item] {
	    switch $field {
		unameit_pointer_attribute_domain {
		    set domain $item($field)
		    set item($field) {}
		    new_reference $uuid $field $CLASS_UUID($domain)
		}
		unameit_class_name_attributes -
		unameit_class_supers {
		    #
		    # The field in question is stored by name
		    # not uuid and the references metadata objects
		    # may not yet have been created.  We defer these
		    # fields for special processing
		    #
		    continue
		}
		unameit_string_attribute_vlist {
		    if {[info exists VLIST($item($field))]} {
			set item($field) $VLIST($item($field))
		    }
		}
	    }
	    append templ "$sep\"$field\""
	    append data "$sep[sqlx_convert_value $class $field\
			      $item($field)]"
	    set sep ", "
	}
	if {[info exists POINTER($uuid)]} {
	    puts $fd\
		"EXEC SQLX INSERT INTO \"${class}\"($templ) values($data)\
		    to $POINTER($uuid);"
	} else {
	    puts $fd\
		"EXEC SQLX INSERT INTO \"${class}\"($templ) values($data);"
	}
    }
}
proc sqlx_generate_supers_metadata {fd} {
    global INSTANCES CLASS_UUID CLASSOF POINTER
    #
    foreach meta_class {
	    unameit_class unameit_syntax_class unameit_data_class} {
	#
	if {![info exists INSTANCES($meta_class)]} continue
	foreach class $INSTANCES($meta_class) {
	    upvar #0 $class class_item
	    set supers $class_item(unameit_class_supers)
	    set class_item(unameit_class_supers) {}
	    foreach super $supers {
		new_reference $class unameit_class_supers $CLASS_UUID($super)
	    }
	    set supers $class_item(unameit_class_supers)
	    puts $fd\
		"EXEC SQLX UPDATE OBJECT $POINTER($class)\
		    SET unameit_class_supers =\
		    [sqlx_convert_value unameit_class unameit_class_supers\
		     $supers];"
	}
    }
}
proc get_refint {class attr} {
    global ATTRIBUTE_UUID
    if {[info exists ATTRIBUTE_UUID($class.$attr)]} {
	upvar #0 $ATTRIBUTE_UUID($class.$attr) attribute_item
    } else {
	upvar #0 $ATTRIBUTE_UUID($attr) attribute_item
    }
    string tolower $attribute_item(unameit_pointer_attribute_ref_integrity)
}
proc sqlx_generate_relatives {fd} {
    global RELATIVES POINTER CLASSOF ATTRIBUTE_UUID ATTRIBUTE_MULTIPLICITY
    global CLASS_UUID
    set POINTER() NULL
    #
    # Loop over every uuid that has relatives
    #
    foreach uuid [array names RELATIVES] {
	#
	# No need to generate relation tuples for pointers to
	# frozen metadata items
	#
	upvar #0 $CLASS_UUID($CLASSOF($uuid)) class_item
	switch -- $class_item(unameit_class_readonly) Yes continue
	#
	set refcount 0
	foreach reference $RELATIVES($uuid) {
	    lassign $reference attr from
	    #
	    set refitem "ref$refcount"
	    set POINTER($refitem) ":ref\[[expr $refcount % 2]\]"
	    incr refcount
	    #
	    set relclass($refitem) relation/$attr
	    set relfrom($refitem) $from
	    switch -- [set refint [get_refint $CLASSOF($from) $attr]] {
		block -
		cascade -
		nullify {}
		default {error "Bad refint for $CLASSOF($from) $attr"}
	    }
	    lappend rels($refint) $refitem
	    if {[info exists next($uuid.$refint)]} {
		set next($refitem) $next($uuid.$refint)
		set prev($next($refitem)) $refitem
		set next($uuid.$refint) $refitem
		set prev($refitem) $uuid
	    } else {
		set next($refitem) ""
		set prev($refitem) $uuid
		set next($uuid.$refint) $refitem
	    }
	}
	foreach refint {block cascade nullify} {
	    if {![info exists rels($refint)]} continue
	    foreach refitem $rels($refint) {
		puts $fd\
		    [format {EXEC SQLX INSERT INTO\
			    "%s"("lhs", "rhs", "prev", "next")\
			    values(%s, %s, NULL, %s) TO %s;}\
			$relclass($refitem) $POINTER($relfrom($refitem))\
			$POINTER($uuid) $POINTER($next($refitem))\
			$POINTER($refitem)]
		if {[cequal $next($refitem) ""]} continue
		puts $fd\
		    [format {EXEC SQLX UPDATE OBJECT %s SET "prev" = %s;}\
			$POINTER($next($refitem)) $POINTER($refitem)]
	    }
	    puts $fd\
		[format {EXEC SQLX UPDATE OBJECT %s SET "backp/%s" = %s;}\
		    $POINTER($uuid) $refint $POINTER($next($uuid.$refint))]
	}
	unset rels next prev
    }
}
proc sqlx_generate_collision_entries {fd} {
    global INSTANCES POINTER
    #
    foreach rule $INSTANCES(unameit_collision_rule) {
	upvar #0 $rule rule_item
	upvar #0 $rule_item(unameit_colliding_class) class_item
	upvar #0 $rule_item(unameit_collision_table) hashtab_item
	set cname $class_item(unameit_class_name)
	if {![info exists INSTANCES($cname)]} continue
	foreach uuid $INSTANCES($cname) {
	    upvar #0 $uuid item
	    set key {}
	    foreach attr $rule_item(unameit_collision_attributes) {
		upvar #0 $attr attr_item
		set aname $attr_item(unameit_attribute_name)
		if {[info exists item($aname)]} {
		    lappend key $item($aname)
		} else {
		    unset key
		    break
		}
	    }
	    if {![info exists key]} continue
	    puts $fd\
		"EXEC SQLX INSERT INTO\
		    \"collision/$hashtab_item(unameit_collision_name)\"\
		    (\"key\", strong, normal, weak)\
		    values('$key', {$POINTER($uuid)}, {}, {});"
	}
    }
}
proc sqlx_generate_protected_items {fd} {
    global PROTECTED POINTER
    foreach uuid [array names PROTECTED] {
	puts $fd\
	    "EXEC SQLX INSERT INTO unameit_protected_item\
		values($POINTER($uuid));"
    }
}
proc sqlx_generate_name_attrs {fd} {
    global INSTANCES ATTRIBUTE_UUID POINTER
    set f unameit_class_name_attributes
    #
    set class_classes [list\
	unameit_class\
	unameit_syntax_class\
	unameit_data_class
    ]
    #
    foreach metaclass $class_classes {
	if {![info exists INSTANCES($metaclass)]} continue
	foreach uuid $INSTANCES($metaclass) {
	    upvar #0 $uuid class_item
	    set anames $class_item($f); set class_item($f) {}
	    #
	    foreach aname $anames {
		new_reference $uuid $f $ATTRIBUTE_UUID($aname)
	    }
	    puts $fd "EXEC SQLX UPDATE OBJECT $POINTER($uuid) SET $f =\
		    [sqlx_convert_value unameit_class $f $class_item($f)];"
	}
    }
}
proc sqlx_generate_display_attrs {fd} {
    global CLASS_UUID CLASSOF ATTRIBUTE_UUID POINTER DISPLAY
    set f unameit_class_display_attributes
    #
    foreach class [array names DISPLAY] {
	upvar #0 [set uuid $CLASS_UUID($class)] class_item
	set class_item($f) {}
	foreach aname $DISPLAY($class) {
	    new_reference $uuid $f $ATTRIBUTE_UUID($aname)
	}
	puts $fd\
	    "EXEC SQLX UPDATE OBJECT $POINTER($uuid) SET $f =\
		[sqlx_convert_value unameit_class $f $class_item($f)];"
		
    }
}
proc sqlx_generate_indices {fd} {
    global INDICES UNIQUE
    if {[info exists INDICES]} {
	foreach index $INDICES {
	    lassign $index class alist
	    set qalist {}
	    foreach a $alist {
		lappend qalist "\"$a\""
	    }
	    puts $fd\
		[format {EXEC SQLX CREATE INDEX on "%s"(%s);}\
		    $class [join $qalist ,]]
	}
    }
    if {[info exists UNIQUE]} {
	foreach index $UNIQUE {
	    lassign $index class alist
	    set qalist {}
	    foreach a $alist {
		lappend qalist "\"$a\""
	    }
	    puts $fd\
		[format {EXEC SQLX ALTER CLASS "%s" ADD ATTRIBUTE\
			    CONSTRAINT "u(%s)" UNIQUE(%s);}\
		    $class [join $alist ,] [join $qalist ,]]
	}
    }
}
