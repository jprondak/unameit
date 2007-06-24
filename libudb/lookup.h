/*
 * Copyright (c) 1997 Enterprise Systems Management Corp.
 *
 * This file is part of UName*It.
 *
 * UName*It is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2, or (at your option) any later
 * version.
 *
 * UName*It is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with UName*It; see the file COPYING.  If not, write to the Free
 * Software Foundation, 59 Temple Place - Suite 330, Boston, MA
 * 02111-1307, USA.
 */
/* $Id: lookup.h,v 1.24.20.5 1997/10/11 00:55:14 viktor Exp $ */
#ifndef _LOOKUP_H
#define _LOOKUP_H
#include <dbi.h>
#include <tcl.h>


/*
 * Wrapper for deleting a table with dynamic values.
 * !!!: It is the values that are dynamic.  The table itself may be static.
 *
 * This allows the functions that clean up tables
 * to be called with either static or dynamic top level tables,  it
 * is the caller that frees the main table if necessary.
 *
 * `dockfree' controls whether we free the data,
 * freeProc deals with recursive cleanup, typically
 * of dynamically allocated subtables.
 */
extern void Udb_Free_Dynamic_Table(
    Tcl_HashTable *table,
    Tcl_FreeProc *freeProc,
    int dockfree
);

/*
 * Delete a table of dynamically allocated tables with static values
 */
extern void Udb_Free_Static_Table_Table(Tcl_HashTable *table);

/*
 * Initialize hash tables for schema and item caches
 */
extern void Udb_Init_Cache(void);

/*
 * Flush hash tables, just items,  just schema,  or all.
 */
extern void Udb_Uncache_Items(int rollback, int shutdown);
extern void Udb_Uncache_Schema(void);
extern void Udb_Uncache(void);

/*
 * Convert class name to class object pointer.
 * The named class must exist in the database.
 * Uses a cache,  which must be flushed using Udb_Uncache_Schema()
 * whenever the schema changes,  or the workspace is closed.
 */
extern DB_OBJECT *Udb_Get_Class(const char *name);

/*
 * Same as above but returns null if named class doesn't exist.
 */
extern DB_OBJECT *_Udb_Get_Class(const char *name);

/*
 * Is `class' equal to or a subclass of `super'.
 */
extern int Udb_ISA(DB_OBJECT *class, DB_OBJECT *super);

/*
 * Is `class' equal to or a subclass of "unameit_item".
 */
extern int Udb_Is_Item_Class(DB_OBJECT *class);

/*
 * Is `class' equal to or a subclass of "unameit_data_item".
 */
extern int Udb_Is_Data_Class(DB_OBJECT *class);

/*
 * Is `class' equal to or a subclass of "host"  or "user_login" respectively
 * (for license counting).
 */
extern int Udb_Is_Host_Class(DB_OBJECT *class);
extern int Udb_Is_Person_Class(DB_OBJECT *class);

/*
 * Returns whether a class is readonly (i.e. does not support inserts/updates).
 */
extern int Udb_Class_Is_Readonly(Tcl_Interp *interp, DB_OBJECT *class);

/*
 * Returns true if the attribute name is that of a protected attribute,
 * false otherwise.
 */
extern int Udb_Attr_Is_Protected(Tcl_Interp *interp, const char *aname);

/*
 * Returns true if the attribute is nullable, false otherwise.
 */
extern int Udb_Attr_Is_Nullable(
    Tcl_Interp *interp,
    const char *cname,
    const char *aname
);

/*
 * Find object matching given UUID deleted or not.  Does not use a cache.
 */
extern DB_OBJECT *_Udb_Find_Object(const char *uuid);

/*
 * Find undeleted object matching given uuid.
 * Caches objects for faster lookups.
 */
extern DB_OBJECT *Udb_Find_Object(const char *uuid);

/*
 * Explicitly add object to cache.
 */
extern void Udb_Cache_Object(const char *uuid, DB_OBJECT *object, int deleted);

/*
 * Mark object as new (and add to cache)
 */
extern void Udb_New_Object(const char *uuid, DB_OBJECT *object);

/*
 * Let TCL find out whether object is new
 */
extern Tcl_CmdProc Udb_Is_New;

/*
 * Returns (info buf) the UUID of a unameit_item.  If buf is NULL, returns
 * in a static buffer overwritten on each call.
 */
extern char *Udb_Get_Uuid(DB_OBJECT *object, char *buf);

/*
 * Returns (info buf) the Oid of an object.  If buf is NULL, returns
 * in a static buffer overwritten on each call.
 */
extern char *Udb_Get_Oid(DB_OBJECT *object, char *buf);

/*
 * Converts OID (as generated above) back to object handle
 */
extern DB_OBJECT *Udb_Decode_Oid(char *buf);

/*
 * `protect' items from further user updates.
 */
extern Tcl_CmdProc Udb_Protect_Items;

/*
 * Tcl command to test whether an object is protected
 */
extern Tcl_CmdProc Udb_Item_Protected;

/*
 * Return attribute descriptor for a named attribute of the specified class
 * Uses a cache that must be flushed on schema changes or workspace close.
 * (The underlying database function is very slow,  and is called frequently
 * in stringifying query results and elsewhere).
 */
extern DB_DOMAIN *Udb_Attribute_Domain(DB_OBJECT *class, char *aname);

/*
 * Return attribute descriptor list of all instance attributes of a class
 */
extern DB_ATTRIBUTE *Udb_Get_Attributes(DB_OBJECT *class);

/*
 * Returns cached argv array of relation attributes for the given class.
 * Usual flushing disclaimer.
 */
extern char **Udb_Get_Relattributes(Tcl_Interp *interp, DB_OBJECT *class);

/*
 * Return relation class for attribute named 'aname'
 */
extern DB_OBJECT *Udb_Relation_Class(char *aname);

/*
 * Return attribute name of relation class 'relclass'
 */
extern char *Udb_Relation_Attribute(DB_OBJECT *relclass);

/*
 * Returns cached argv array of name attributes for the given class.
 * Usual flushing disclaimer.
 */
extern char **Udb_Get_Name_Attributes(Tcl_Interp *interp, DB_OBJECT *class);

/*
 * Returns cached name of class.
 * Usual flushing disclaimer.
 */
extern char *Udb_Get_Class_Name(DB_OBJECT *class);

/*
 * Edit recycled object,  or create a new one.
 */
extern DB_OTMPL *Udb_Edit_Free_Object(DB_OBJECT *class);

/*
 * NULL out 'key' field of object and append object to free list.
 */
extern void Udb_Append_Free_List(
    DB_OBJECT *class,
    DB_OTMPL *templ,
    const char *key
);

/*
 * Can this attribute be converted to/from a string
 * Usual flushing disclaimer.
 */
extern int
Udb_Attribute_Is_Printable(DB_DOMAIN *domain);

/*
 * Return the cell containing the object.
 * If get_org is set, then return the cell's organization,
 * if loopobj is an ancestor of object,  return NULL.
 */
extern DB_OBJECT *Udb_Get_Cell(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    DB_OBJECT *loopobj,
    int get_org
);

/*
 * Implementation of Tcl command that returns UUID of cell containing the
 * object (UUID) passed in.  If the argument object is a cell, the cell
 * itself is returned.
 */
extern Tcl_CmdProc Udb_Cell_Of_Cmd;

/*
 * This function returns an owner promoted up to the level of
 * "promotion_type".
 */
extern DB_OBJECT *Udb_Get_Promoted_Owner(
    Tcl_Interp *interp,
    DB_OBJECT *owner,
    char *promotion_type
);

extern DB_OBJECT *Udb_Get_Root(DB_OBJECT *class);
extern Tcl_CmdProc Udb_Get_RootCmd;

extern void Udb_Set_Root(DB_OBJECT *class, DB_OBJECT *object);
extern Tcl_CmdProc Udb_Set_RootCmd;

extern char *Udb_Get_Relaction(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    char *aname
);

extern DB_OBJECT *Udb_Current_Principal(void);
extern void Udb_Server_Principal(void);
extern Tcl_CmdProc Udb_PrincipalCmd;

#endif
