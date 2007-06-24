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
# Definitions of attribute `syntaxes'
#

#
# Totally generic attribute
#
new_syntax "" ""\
    [list class "Class" Error Yes\
     Pointer unameit_class Cascade No Off]\
    [list label "Field Label" Error Yes\
     String 2 32 Mixed PRINT]\
    [list null "NULL Interpretation" Error Yes\
     Enum "Error NULL"]\
    [list updatable "Updatable" Error Yes\
     Enum "Yes No"]
#
# Generic defining attribute
#
sub_syntax "" Defining "" ""\
    [list name "Attribute Name" Error No\
     String 2 32 lower GENALNUM]
#
# Generic inherited attribute
#
sub_syntax "" Inherited "" ""\
    [list whence "Inherited Attribute" Error No\
     Pointer unameit_defining_attribute Cascade No Off]
#
# Generic mixed attributes
#
foreach m {"" Scalar Set Sequence} {
foreach c {"" Data} {
    if {[cequal "$m$c" ""]} continue
    sub_syntax "" Defining $m $c
}}

new_syntax Integer Integer\
    [list min "Minimum Value" NULL Yes\
     Integer "" "" Decimal]\
    [list max "Maximum Value" NULL Yes\
     Integer "" "" Decimal]\
    [list base "Input Base" Error Yes\
     Enum [list Decimal Octal Hexadecimal Any]]
#
foreach c {"" Data} {
    sub_syntax Integer Defining Scalar $c
    sub_syntax Integer Inherited Scalar $c
}

new_syntax String String\
    [list minlen "Minumum length" Error Yes\
     Integer 0 255 Decimal]\
    [list maxlen "Maximum length" Error Yes\
     Integer 1 255 Decimal]\
    [list case "String Case" Error Yes\
     Enum [list lower Mixed UPPER]]\
    [list vlist "Validation List" Error Yes\
     Vlist]
#
#
foreach c {"" Data} {
    sub_syntax String Defining Scalar $c
    sub_syntax String Inherited Scalar $c
}

new_syntax Pointer Object\
    [list domain "Domain" Error Yes\
     Pointer unameit_class Cascade No Off]\
    [list ref_integrity "Ref. Integrity" Error Yes\
     Enum [list Block Cascade Nullify]]\
    [list update_access "Update Access" Error Yes\
     Enum [list No Yes]]\
    [list detect_loops "Loop Detection" Error Yes\
     Enum [list Off On]]
#
foreach m {Scalar Set Sequence} {
    foreach c {"" Data} {
	sub_syntax Pointer Defining $m $c
	sub_syntax Pointer Inherited $m $c
    }
}

new_syntax Enum String\
    [list values "Value List" Error Yes\
     List 2 20]
#
foreach m {Scalar Set} {
    foreach c {"" Data} {
	sub_syntax Enum Defining $m $c
	sub_syntax Enum Inherited $m $c
    }
}

new_syntax Address String\
    [list octets "Number of octets" Error No\
     Integer 4 32 Decimal]\
    [list format "Display Format" Error Yes\
     Enum [list Octet MAC IP IPv6]]
#
sub_syntax Address Defining Scalar ""
sub_syntax Address Defining Scalar Data
sub_syntax Address Inherited Scalar ""
sub_syntax Address Inherited Scalar Data

new_syntax Time Integer
#
foreach m {Scalar} {
    foreach c {"" Data} {
	sub_syntax Time Defining $m $c
	sub_syntax Time Inherited $m $c
    }
}

hybrid_syntax Autoint Integer\
    [list min "Auto Minimum" Error Yes\
     Integer "" "" Decimal]\
    [list max "Auto Maximum" NULL Yes\
     Integer "" "" Decimal]\
    [list level "Maximum Uniqueness" NULL Yes\
     Enum [list Local Cell Org Global]]

#
hybrid_sub_syntax Autoint Defining Scalar ""
hybrid_sub_syntax Autoint Defining Scalar Data
hybrid_sub_syntax Autoint Inherited Scalar ""
hybrid_sub_syntax Autoint Inherited Scalar Data

hybrid_syntax Choice {Enum String}
#
hybrid_sub_syntax Choice Defining Scalar ""
hybrid_sub_syntax Choice Defining Scalar Data
hybrid_sub_syntax Choice Inherited Scalar ""
hybrid_sub_syntax Choice Inherited Scalar Data

new_syntax List String\
    [list min_elems "Minimum Elem #" NULL Yes\
     Integer 0 2147483647 Decimal]\
    [list max_elems "Maximum Elem #" NULL Yes\
     Integer 2 2147483647 Decimal]
#
sub_syntax List Defining Scalar ""
sub_syntax List Inherited Scalar ""

new_syntax Text String
sub_syntax Text Defining Scalar ""
sub_syntax Text Defining Scalar Data
sub_syntax Text Inherited Scalar ""
sub_syntax Text Inherited Scalar Data

new_syntax Code String
sub_syntax Code Defining Scalar ""

#
# XXX: not implemented yet.
#
#new_syntax Qbe String\
#    [list class "Query Class" Error No\
#    Pointer unameit_data_class Cascade No Off]
#sub_syntax Qbe Defining Scalar ""
#sub_syntax Qbe Defining Scalar Data

new_syntax Vlist String
sub_syntax Vlist Defining Scalar ""

new_syntax UUID String
sub_syntax UUID Defining Scalar ""
sub_syntax UUID Defining Scalar Data

#
# Now define the schema of each syntax class
#
foreach class [array names SYNTAX_ARGS] {
    set args [lassign $SYNTAX_ARGS($class) syntax]
    foreach arg $args {
	set rest [lassign $arg name label null updatable syntax]
	set name "${class}_${name}"
	set cmd "new_[string tolower $syntax]_attribute"
	eval [list $cmd Defining Scalar ""\
		$name $class $label $null $updatable] $rest
    }
}
#
# Now define the schema of each syntax subclass
#
foreach class [array names SUB_SYNTAX_ARGS] {
    set args \
	[lassign $SUB_SYNTAX_ARGS($class) syntax resolution multiplicity space]
    foreach arg $args {
	set rest [lassign $arg name label null updatable asyntax]
	set name "[unameit_syntax_class $syntax "" "" ""]_${name}"
	set cmd "new_[string tolower $asyntax]_attribute"
	eval [list $cmd Defining Scalar ""\
		$name $class $label $null $updatable] $rest
    }
}

#
# Compute some metadata fields of autoints,  and undisplay them.
#
set ad_class unameit_autoint_defining_scalar_data_attribute
set ai_class unameit_autoint_inherited_scalar_data_attribute
set ai_level unameit_autoint_attribute_level
#
foreach {class field value} {
	unameit_autoint_defining_scalar_data_attribute
	    unameit_attribute_null
	    NULL
	unameit_autoint_inherited_scalar_data_attribute
	    unameit_attribute_null
	    NULL
	unameit_autoint_inherited_scalar_data_attribute
	    unameit_autoint_attribute_level
	    {}
	} {
    new_trigger $class Yes Before No No\
	unameit_literal_trigger [list $value] {} $field
    #
    set i [lsearch -exact $DISPLAY($class) $field]
    set DISPLAY($class) [lreplace $DISPLAY($class) $i $i]
}
