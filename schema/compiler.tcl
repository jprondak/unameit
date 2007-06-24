#!/opt/tclx/bin/tcl
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
# $Id: compiler.tcl,v 1.24.12.2 1997/09/16 01:02:31 viktor Exp $
#

source ../library/atomic.tcl
source memory.tcl
source syntax.tcl
source uuid.tcl
#
# Load procedures for dumping meta classes to sqlx commands
#
source sqlx.tcl

set MODE Schema
set POINTER(count) -1

#
# Source definition of attribute syntax classes.
#
source syntax_defs.tcl
#
# Source definition of metadata classes, attributes, etc.
#
source meta_defs.tcl

#
# Save list of pointers fields so we can strip oids from schema dump
#
set fd [atomic_open schema_ptrs 0444]
foreach m {Scalar Set Sequence} {
    set syntax_class [unameit_syntax_class Pointer Defining $m ""]
    if {![info exists INSTANCES($syntax_class)]} continue
    foreach uuid $INSTANCES($syntax_class) {
	upvar #0 $uuid item
	lappend schema_ptrs $item(unameit_attribute_name)
    }
}
foreach aname [lsort $schema_ptrs] {
    puts $fd $aname
}
atomic_close $fd

#
# Constrain defining attribute of inherited attributes to corresponding class.
# Constrain class of data attributes to be a data class.
# Add suitable collision rules.
#
while {![lempty $SYNTAX_CLASSES]} {
    set syntax_class [lvarpop SYNTAX_CLASSES end]
    lassign $SUB_SYNTAX_ARGS($syntax_class) s r m n
    set num_params [llength [concat $s $r $m]]
    #
    # Skip abstract classes
    #
    if {$num_params < 3} continue
    switch -- $r {
	Defining {
            new_collision_rule unameit_attribute_name $syntax_class\
                unameit_attribute_name Strong None None None
            new_collision_rule unameit_inherited_attribute $syntax_class\
                "unameit_attribute_class uuid" Strong None None None
	}
	Inherited {
            new_pointer_attribute Inherited Scalar ""\
		unameit_attribute_whence $syntax_class\
		"Inherited Attribute" Error Yes\
		[unameit_syntax_class $s Defining $m $n] Cascade No Off
            new_collision_rule unameit_inherited_attribute $syntax_class\
                "unameit_attribute_class unameit_attribute_whence"\
                Strong None None None
	}
	default {error "Unexpected resolution: '$r' for $syntax_class"}
    }
    switch -- $n Data {
	#
	# Data attributes get to belong only to data classes.
	#
	new_pointer_attribute Inherited Scalar ""\
	    unameit_attribute_class $syntax_class\
	    "Attribute Class" Error No unameit_data_class Cascade No Off
	#
	switch -- $s Pointer {
	    #
	    # Inherited pointers may have a NULL domain,  implicitly
	    # inheriting the domain of the parent class(es).
	    #
	    switch -- $r Defining {set null Error} Inherited {set null NULL}
	    #
	    # Data pointer attributes get to point only at data classes.
	    #
	    new_pointer_attribute Inherited Scalar ""\
		unameit_pointer_attribute_domain $syntax_class\
		"Attribute Domain" $null Yes unameit_data_class Block No Off
	}
    }
}

#
# Hardcode `standard' indices
#
make_unique unameit_protected_item item

if {[info exists env(DECOMPILE)] && $env(DECOMPILE) == 1} {
    #
    # Load decompiler
    #
    source decompile.tcl
    #
    # Dump `pretty-printed' meta schema
    #
    set fd [atomic_open meta_defs.tcl 0644]
    decompile_vlist $fd
    decompile_collision_tables $fd ""
    decompile_data_classes $fd
    decompile_schema_classes $fd
    atomic_close $fd
}

#
# Dump metaschema in sqlx format.
#
set fd [atomic_open unameit_init.ec 0444]

puts $fd "#include <string.h>

static void generate_classes(void);
static void generate_supers(void);
static void generate_attrs(void);

static void generate_class_items(void);
static void generate_super_items(void);
static void generate_attr_items(void);

static void generate_misc_items(void);
static void generate_relations(void);

EXEC SQLX BEGIN DECLARE SECTION;
DB_OBJECT *o\[[expr $POINTER(count) + 1]\];
EXEC SQLX END DECLARE SECTION;

int
main(int argc, char **argv)
{
    EXEC SQLX BEGIN DECLARE SECTION;
    static DB_OBJECT *u;
    static char *dbname;
    EXEC SQLX END DECLARE SECTION;

    if (argc != 2)
    {
	fprintf(stderr, \"usage: %s <database>\\n\", argv\[0\]);
	exit(1);
    }
    dbname = argv\[1\];

    EXEC SQLX WHENEVER SQLERROR STOP;
    EXEC SQLX CONNECT :dbname IDENTIFIED BY 'dba';

    db_gc_disable();
    generate_classes();
    generate_supers();
    generate_attrs();

    generate_class_items();
    generate_super_items();
    generate_attr_items();

    generate_misc_items();
    generate_relations();

    memset(o, 0, sizeof(o));
    u = NULL;
    EXEC SQLX COMMIT WORK;
    EXEC SQLX DISCONNECT;
    exit(0);
}
"

puts $fd "
static void
generate_classes(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_classes $fd
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

puts $fd "
static void
generate_supers(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_supers $fd
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

puts $fd "
static void
generate_attrs(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_attrs $fd
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

#
# Order matters,  we must define all items before the items that point to them
# For now the meta schema is loop free and we can just order the classes
# May one day have to do a 2 pass algorithm (as in restore_db)
#
puts $fd "
static void
generate_class_items(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_items $fd unameit_class
sqlx_generate_items $fd unameit_data_class
sqlx_generate_items $fd unameit_syntax_class
sqlx_generate_items $fd unameit_collision_table
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

puts $fd "
static void
generate_super_items(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_supers_metadata $fd
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

puts $fd "
static void
generate_attr_items(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
#
# Dump instances of each syntax class
#
#
# Generate defining attributes before inherited attributes
#
foreach syntax_class [array names SUB_SYNTAX_ARGS] {
    lassign $SUB_SYNTAX_ARGS($syntax_class) s r m n
    if {![cequal $r Defining]} continue
    if {[llength [concat $s $m]] != 2} continue
    sqlx_generate_items $fd $syntax_class
}
foreach syntax_class [array names SUB_SYNTAX_ARGS] {
    lassign $SUB_SYNTAX_ARGS($syntax_class) s r m n
    if {![cequal $r Inherited]} continue
    if {[llength [concat $s $m]] != 2} continue
    sqlx_generate_items $fd $syntax_class
}
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

puts $fd "
static void
generate_misc_items(void)
{
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_name_attrs $fd
sqlx_generate_display_attrs $fd
sqlx_generate_items $fd unameit_trigger

sqlx_generate_items $fd unameit_collision_rule
sqlx_generate_protected_items $fd
sqlx_generate_collision_entries $fd
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

puts $fd "

static void
generate_relations(void)
{
    EXEC SQLX BEGIN DECLARE SECTION;
    DB_OBJECT *ref\[2\];
    EXEC SQLX END DECLARE SECTION;
    EXEC SQLX WHENEVER SQLERROR STOP;
"
sqlx_generate_relatives $fd
sqlx_generate_indices $fd
puts $fd "
    EXEC SQLX COMMIT WORK;
}"

atomic_close $fd
