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
# $Id: decompile.tcl,v 1.18.20.2 1997/09/29 23:09:11 viktor Exp $
#

#
# Routines to dump in memory schema image to input form
#
#
# Output list quoted elements
#
proc decompile_output {fd cmd indent} {
    set il [string length $indent]
    foreach elem [lassign $cmd line] {
	set ll [string length $line]
	set el [string length $elem]
	if {$il + $ll + $el < 73} {
	    lappend line $elem
	} else {
	    puts $fd "$indent$line\\"
	    set line "    [list $elem]"
	}
    }
    puts $fd "$indent$line"
}
#
# Output without list quoting elements
#
proc decompile_append {fd cmd indent} {
    set il [string length $indent]
    foreach elem [lassign $cmd line] {
	set pat "\[ \t\n\]"
	if {[regexp $pat $elem]} {
	    set elem "\"$elem\""
	}
	set ll [string length $line]
	set el [string length $elem]
	if {$il + $ll + $el < 73} {
	    if {$ll} {
		append line " $elem"
	    } else {
		set line $elem
	    }
	} else {
	    puts $fd "$indent$line\\"
	    set line "    $elem"
	}
    }
    puts $fd "$indent$line"
}
proc decompile_schema_classes {fd} {
    global INSTANCES
    foreach class $INSTANCES(unameit_class) {
	upvar #0 $class class_item
	set cmd {}
	#
	lappend cmd new_schema_class
	set class_name $class_item(unameit_class_name)
	puts $fd "\n#\n# Schema class: $class_name"
	lappend cmd $class_name
	set ro $class_item(unameit_class_readonly)
	puts $fd "# Readonly?: $ro"
	lappend cmd $ro
	set label $class_item(unameit_class_label)
	lappend cmd $label
	puts $fd "# Label: $label"
	set alist {}
	foreach attribute $class_item(unameit_class_name_attributes) {
	    upvar #0 $attribute attribute_item
	    if {[array exists attribute_item]} {
		lappend alist $attribute_item(unameit_attribute_name)
	    } else {
		lappend alist $attribute
	    }
	}
	lappend cmd $alist
	puts $fd "# Name attributes: $alist"
	set slist {}
	foreach super $class_item(unameit_class_supers) {
	    upvar #0 $super super_item
	    if {[array exists super_item]} {
		lappend slist $super_item(unameit_class_name)
	    } else {
		lappend slist $super
	    }
	}
	set cmd [concat $cmd $slist]
	puts $fd "# Superclasses: $slist\n#"
	decompile_output $fd $cmd ""
	decompile_raw_attributes $fd $class_name
	decompile_attributes $fd $class_name
	decompile_collisions $fd $class_name
	decompile_triggers $fd $class_name
	decompile_displayed_attributes $fd $class_name
    }
}
proc decompile_raw_attributes {fd class} {
    global RAW_CLASS_ATTRIBUTES RAW_ATTRIBUTES
    if {[info exists RAW_CLASS_ATTRIBUTES($class)]} {
	foreach tuple $RAW_CLASS_ATTRIBUTES($class) {
	    lassign $tuple name domain
	    puts $fd "    #"
	    decompile_output $fd\
		[list raw_class_attribute $class $name $domain] "    "
	}
    }
    if {[info exists RAW_ATTRIBUTES($class)]} {
	foreach tuple $RAW_ATTRIBUTES($class) {
	    lassign $tuple name domain
	    puts $fd "    #"
	    decompile_output $fd [list raw_attribute $class $name $domain] "    "
	}
    }
}
proc decompile_attributes {fd class} {
    global ATTRIBUTE_METADATA CLASSOF CLASS_UUID VLIST
    #
    if {![info exists ATTRIBUTE_METADATA($class)]} return
    foreach attribute $ATTRIBUTE_METADATA($class) {
	set attribute_class $CLASSOF($attribute)
	upvar #0 $CLASS_UUID($attribute_class) syntax_item
	set syntax $syntax_item(unameit_syntax_name)
	set syntax_class [unameit_syntax_class $syntax]
	#
	upvar #0 $attribute attribute_item
	set attribute_name [attribute_name $attribute]
	set cmd {}
	lappend cmd "new_${syntax}_attribute"
	set res $syntax_item(unameit_syntax_resolution)
	set mul $syntax_item(unameit_syntax_multiplicity)
	set ns $syntax_item(unameit_syntax_domain)
	lappend cmd $res
	lappend cmd $mul
	switch -- $ns {
	    "" {lappend cmd $ns}
	    Data {lappend cmd [list $ns $attribute]}
	}
	lappend cmd $attribute_name
	#
	# Append the class of the attribute
	#
	lappend cmd $class
	set label $attribute_item(unameit_attribute_label)
	lappend cmd $label
	set null $attribute_item(unameit_attribute_null)
	lappend cmd $null
	set updatable $attribute_item(unameit_attribute_updatable)
	lappend cmd $updatable
	#
	set alist {}
	#
	foreach superclass [syntax_ancestors $syntax] {
	    if {[info exists ATTRIBUTE_METADATA($superclass)]} {
		foreach parameter $ATTRIBUTE_METADATA($superclass) {
		    upvar #0 $parameter parameter_item
		    set param_name\
			$parameter_item(unameit_attribute_name)
		    lappend cmd $attribute_item($param_name)
		}
	    }
	}
	puts $fd "    #"
	decompile_output $fd $cmd "    "
    }
}
proc decompile_collision_tables {fd type} {
    global INSTANCES
    set table_class [join [concat unameit $type collision_table] _]
    if {![info exists INSTANCES($table_class)]} return
    #
    puts $fd ""
    set tables $INSTANCES($table_class)
    foreach class $tables {
	upvar #0 $class class_item
	#
	set cmd [join [concat new $type collision_table] _]
	set collision_name $class_item(unameit_collision_name)
	lappend cmd $collision_name
	decompile_output $fd $cmd ""
    }
}
proc decompile_collisions {fd class_name} {
    global INSTANCES SYNTAX_ARGS COLLISION_RULES CLASSOF
    if {![info exists COLLISION_RULES($class_name)]} return
    foreach rule $COLLISION_RULES($class_name) {
	upvar #0 $rule rule_item
	switch -- $CLASSOF($rule) {
	    unameit_collision_rule {
		set cmd new_collision_rule
	    }
	    unameit_data_collision_rule {
		set cmd new_data_collision_rule
	    }
	}
	set table $rule_item(unameit_collision_table)
	upvar #0 $table table_item
	set table_name $table_item(unameit_collision_name)
	lappend cmd $table_name $class_name
	set alist {}
	foreach attribute $rule_item(unameit_collision_attributes) {
	    upvar #0 $attribute attribute_item
	    set aname $attribute_item(unameit_attribute_name)
	    lappend alist $aname
	}
	lappend cmd $alist
	lappend cmd $rule_item(unameit_collision_local_strength)
	lappend cmd $rule_item(unameit_collision_cell_strength)
	lappend cmd $rule_item(unameit_collision_org_strength)
	lappend cmd $rule_item(unameit_collision_global_strength)
	puts $fd "    #"
	decompile_output $fd $cmd "    "
    }
}
proc decompile_vlist {fd} {
    global VLIST
    foreach index [lsort [array names VLIST]] {
	set sep ""
	set vlist ""
	foreach elem $VLIST($index) {
	    append vlist "$sep[list $elem]"
	    set sep "\\\n     "
	}
	puts $fd "#\nset VLIST($index)\\"
	puts $fd "    {$vlist}"
    }
}
proc decompile_data_classes {fd} {
    global INSTANCES
    #
    foreach class $INSTANCES(unameit_data_class) {
	upvar #0 $class class_item
	set cmd {}
	#
	set class_name $class_item(unameit_class_name)
	#
	puts $fd "\n#\n# Data class: $class_name"
	lappend cmd new_data_class $class_name $class
	set ro $class_item(unameit_class_readonly)
	puts $fd "# Readonly?: $ro"
	lappend cmd $ro
	#
	set group $class_item(unameit_class_group)
	lappend cmd $group
	puts $fd "# Group: $group"
	#
	set label $class_item(unameit_class_label)
	lappend cmd $label
	puts $fd "# Label: $label"
	#
	# Output name attributes
	#
	set alist {}
	foreach attribute $class_item(unameit_class_name_attributes) {
	    upvar #0 $attribute attribute_item
	    if {[array exists attribute_item]} {
		lappend alist $attribute_item(unameit_attribute_name)
	    } else {
		lappend alist $attribute
	    }
	}
	lappend cmd $alist
	puts $fd "# Name attributes: $alist"
	#
	# Output super classes
	#
	set slist {}
	foreach super $class_item(unameit_class_supers) {
	    upvar #0 $super super_item
	    if {[array exists super_item]} {
		lappend slist $super_item(unameit_class_name)
	    } else {
		lappend slist $super
	    }
	}
	set cmd [concat $cmd $slist]
	puts $fd "# Superclasses: $slist\n#"
	#
	puts $fd "#"
	decompile_output $fd $cmd ""
	decompile_raw_attributes $fd $class_name
	decompile_attributes $fd $class_name
	decompile_collisions $fd $class_name
	decompile_triggers $fd $class_name
	decompile_displayed_attributes $fd $class_name
    }
}
proc decompile_triggers {fd class_name} {
    global TRIGGERS CLASSOF
    if {![info exists TRIGGERS($class_name)]} return
    foreach trigger $TRIGGERS($class_name) {
	upvar #0 $trigger trigger_item
	switch -- $CLASSOF($trigger) {
	    unameit_trigger {
		set cmd new_trigger
	    }
	    unameit_data_trigger {
		set cmd new_data_trigger
	    }
	}
	lappend cmd $class_name
	#
	set inherited $trigger_item(unameit_trigger_inherited)
	lappend cmd $inherited
	#
	foreach event {create update delete} {
	    set onevent $trigger_item(unameit_trigger_on$event)
	    lappend cmd $onevent
	}
	#
	set proc $trigger_item(unameit_trigger_proc)
	lappend cmd $proc
	#
	set args $trigger_item(unameit_trigger_args)
	lappend cmd $args
	#
	set anames {}
	foreach attribute $trigger_item(unameit_trigger_attributes) {
	    set aname $attribute
	    upvar #0 $attribute attribute_item
	    if {[info exists attribute_item(uuid)]} {
		set aname $attribute_item(unameit_attribute_name)
	    }
	    lappend anames $aname
	}
	lappend cmd $anames
	#
	set anames {}
	foreach attribute $trigger_item(unameit_trigger_computes) {
	    set aname $attribute
	    upvar #0 $attribute attribute_item
	    if {[info exists attribute_item(uuid)]} {
		set aname $attribute_item(unameit_attribute_name)
	    }
	    lappend anames $aname
	}
	lappend cmd $anames
	puts $fd "    #"
	decompile_output $fd $cmd "    "
    }
}
proc decompile_displayed_attributes {fd class} {
    global DISPLAY
    if {![info exists DISPLAY($class)]} return
    puts $fd "    #"
    foreach aname $DISPLAY($class) {
	decompile_output $fd [list display $class $aname] "    "
    }
}
proc decompile_error_procs {fd} {
    global INSTANCES
    puts $fd ""
    foreach proc $INSTANCES(unameit_error_proc) {
	upvar #0 $proc proc_item
	set name2uuid($proc_item(unameit_error_proc_name)) $proc
    }
    foreach name [lsort [array names name2uuid]] {
	upvar #0 $name2uuid($name) proc_item
	#
	set cmd new_errproc
	lappend cmd $name
	set alist $proc_item(unameit_error_proc_args)
	lappend cmd $alist
	lappend cmd $proc_item(unameit_error_proc_body)
	puts $fd "#"
	decompile_output $fd $cmd ""
    }
}
proc decompile_error_codes {fd} {
    global INSTANCES
    puts $fd ""
    foreach code $INSTANCES(unameit_error) {
	upvar #0 $code code_item
	set name2uuid($code_item(unameit_error_code)) $code
    }
    foreach name [lsort [array names name2uuid]] {
	upvar #0 $name2uuid($name) code_item
	#
	set cmd new_errcode
	lappend cmd $name
	set type $code_item(unameit_error_type)
	set tstr $type
	lappend cmd $tstr
	set message $code_item(unameit_error_message)
	lappend cmd $message
	set proc $code_item(unameit_error_proc)
	upvar #0 $proc proc_item
	set proc_name $proc_item(unameit_error_proc_name)
	lappend cmd $proc_name
	puts $fd "#"
	decompile_output $fd $cmd ""
    }
}
