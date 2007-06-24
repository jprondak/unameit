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
static char rcsid[] = "$Id: name_cache.c,v 1.37.58.10 1997/10/09 01:10:32 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "misc.h"
#include "name_cache.h"
#include "lookup.h"
#include "inet.h"
#include "convert.h"
#include "shared_const.h"
#include "range.h"
#include "uuid.h"
#include "transaction.h"
#include "errcode.h"


/*
 * Returns pointer to allocated memory
 */
static void *
Decode_Rule(
    Tcl_Interp *interp,
    char *rule,
    char **collision_class,
    char **attr_list,
    int *local_strength,
    int *cell_strength,
    int *org_strength,
    int *global_strength
)
{
    int		argc;
    char	**argv;
    char	*rule_data;

    assert(rule);
    assert(collision_class);
    assert(attr_list);
    assert(global_strength && org_strength && cell_strength && local_strength);

    check(rule_data = Tcl_GetVar2(interp, "UNAMEIT_COLLISION_RULE", rule,
				  TCL_GLOBAL_ONLY));
    check(Tcl_SplitList(NULL, rule_data, &argc, &argv) == TCL_OK);
    check(argc == 7);

    *collision_class = argv[1];
    *attr_list = argv[2];
    *local_strength = atoi(argv[3]);
    *cell_strength = atoi(argv[4]);
    *org_strength = atoi(argv[5]);
    *global_strength = atoi(argv[6]);

    return argv;
}


/*
 * Converts collisiong strength to appropriate slot (field) in cache object.
 */
static char *
Strength_To_Slot(int strength)
{
    switch (strength)
    {
    case STRONG_COLLISION:
	return "strong";
    case NORMAL_COLLISION:
	return "normal";
    case WEAK_COLLISION:
	return "weak";
    default:
	break;
    }
    panic("Illegal collision strength: %d", strength);
    return NULL;
}


static void
Populate_Range_Table(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *table
)
{
    DB_OBJECT		*class;
    DB_VALUE		value;
    DB_OBJECT		*owner;
    char		*class_name;
    char		*ranges;
    int			range_argc;
    char		**range_argv;
    int			i;
    int			new;

    check(class = db_get_class(object));
    check(class_name = (char *)db_get_class_name(class));

    /*
     * Loop over each range attribute of this class
     */
    if (!(ranges = Tcl_GetVar2(interp, "UNAMEIT_AUTO_ATTRIBUTES", class_name,
			 TCL_GLOBAL_ONLY))) {
	return;
    }

    check(Tcl_SplitList(NULL, ranges, &range_argc, &range_argv) == TCL_OK);

    Udb_Get_Value(object, "owner", DB_TYPE_OBJECT, &value);
    owner = DB_GET_OBJECT(&value);

    for (i = 0; i < range_argc; ++i)
    {
	char		*aname = range_argv[i];
	DB_VALUE	avalue;
	DB_INT32	ival;
	char		ibuf[32];
	Tcl_DString	hash_value;
	Tcl_HashEntry	*ePtr;
	char		*valPtr;
	char		*level;
	DB_OBJECT	*promoted_owner;

	/*
	 * If integer value is null, skip it. Null values don't go in
	 * the range structures.
	 */
	Udb_Get_Value(object, aname, DB_TYPE_INTEGER, &avalue);
	if (DB_IS_NULL(&avalue)) continue;

	ival = DB_GET_INTEGER(&avalue);

	/*
	 * Determine the autogeneration level for this attribute
	 */
	check(level = Tcl_GetVar2(interp, "UNAMEIT_AUTO_LEVEL", aname,
				  TCL_GLOBAL_ONLY));

	/*
	 * Promote owner per above level
	 */
	check(promoted_owner = Udb_Get_Promoted_Owner(interp, owner, level));

	/* Insert "<int_value> <promoted_owner>" into range hash table
	   indexed by attribute_name. */
	(void)sprintf(ibuf, "%ld", (long)ival);
	Tcl_DStringInit(&hash_value);
	Tcl_DStringAppendElement(&hash_value, ibuf);
	Tcl_DStringAppendElement(&hash_value,
			 Udb_Get_Oid(promoted_owner, NULL));

	valPtr = ckalloc(Tcl_DStringLength(&hash_value)+1);
	(void)strcpy(valPtr, Tcl_DStringValue(&hash_value));
	Tcl_DStringFree(&hash_value);

	ePtr = Tcl_CreateHashEntry(table, aname, &new);
	Tcl_SetHashValue(ePtr, (ClientData)valPtr);
    }
    ckfree((char *)range_argv);
}


static void
Generate_Collision(
    DB_OBJECT	  *object,
    char	  *rule,
    char	  **attrs,
    int		  table,
    Tcl_HashTable *tables,
    DB_OBJECT     **promoted_owner
)
{
    DB_VALUE		value;
    int			owner_found = FALSE;
    Tcl_DString		key;
    char		*valPtr;
    int			new;
    Tcl_HashEntry	*ePtr;

    Tcl_DStringInit(&key);

    for (; *attrs; ++attrs)
    {
	check(db_get(object, *attrs, &value) == NOERROR);
	if (DB_IS_NULL(&value))
	{
	    Tcl_DStringFree(&key);
	    return;
	}
	check(DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_INTEGER ||
	      DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_STRING ||
	      DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_OBJECT);

	if (Equal(*attrs, "owner"))
	{
	    check(DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_OBJECT);
	    switch (table)
	    {
	    case 0:
		*promoted_owner = DB_GET_OBJECT(&value);
		break;
	    case 1:
	    case 2:
	    case 3:
		/*
		 * Promoted owner is passed in
		 */
		break;
	    default:
		panic("Illegal collision table index: %d", table);
		break;
	    }
	    DB_MAKE_OBJECT(&value, *promoted_owner);
	    owner_found = TRUE;
	}
	Udb_Stringify_Value(&key, &value);
	db_value_clear(&value);
    }
    if (table > 0 && owner_found == FALSE)
    {
	panic("Illegal owner promotion in uniqueness rule with no owner: %s",
		rule);
    }
    valPtr = ckalloc(Tcl_DStringLength(&key)+1);
    (void) strcpy(valPtr, Tcl_DStringValue(&key));
    Tcl_DStringFree(&key);

    ePtr = Tcl_CreateHashEntry(&tables[table], rule, &new);
    Tcl_SetHashValue(ePtr, (ClientData)valPtr);
}


void
Udb_Populate_Caches(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *tables
)
{
    DB_OBJECT	*class;
    char	*class_name;
    DB_OBJECT	*owner;
    DB_OBJECT	*cell;
    DB_OBJECT	*org;
    DB_OBJECT	*root;
    int		local_strength;
    int		cell_strength;
    int		org_strength;
    int		global_strength;
    int		i;
    char	*rules;
    int		rule_argc;
    char	**rule_argv;
    char	*rule_attributes;
    char	*collision_class_name;
    int		attr_argc;
    char	**attr_argv;

    assert(tables);
    assert(object);

    for (i = 0; i < NCACHE_TABLES; i++)
    {
	Tcl_InitHashTable(&tables[i], TCL_STRING_KEYS);
    }

    check(class = db_get_class(object));
    check(class_name = (char *)db_get_class_name(class));

    /*
     * If an entry doesn't exist, there are no collision rules for this
     * class.
     */
    rules = Tcl_GetVar2(interp, "UNAMEIT_COLLISIONS", class_name,
			TCL_GLOBAL_ONLY);

    /*
     * XXX: Should it be legal for a
     * concrete class not to have collision rules?
     */
    if (rules != NULL)
    {
	check(Tcl_SplitList(NULL, rules, &rule_argc, &rule_argv) == TCL_OK);

	for (i = 0; i < rule_argc; ++i)
	{
	    void *mem;
	    
	    mem = Decode_Rule(interp, rule_argv[i],
			      &collision_class_name, &rule_attributes,
			      &local_strength, &cell_strength,
			      &org_strength, &global_strength);

	    switch (local_strength)
	    {
	    case NO_COLLISION:
	    case STRONG_COLLISION:
	    case NORMAL_COLLISION:
	    case WEAK_COLLISION:
		break;
	    default:
		panic("Illegal local collision strength: %d", local_strength);
	    }

	    switch (cell_strength)
	    {
	    case NO_COLLISION:
	    case STRONG_COLLISION:
	    case NORMAL_COLLISION:
	    case WEAK_COLLISION:
		break;
	    default:
		panic("Illegal cell collision strength: %d", cell_strength);
	    }

	    switch (org_strength)
	    {
	    case NO_COLLISION:
	    case STRONG_COLLISION:
	    case NORMAL_COLLISION:
	    case WEAK_COLLISION:
		break;
	    default:
		panic("Illegal org collision strength: %d", org_strength);
	    }

	    switch (global_strength)
	    {
	    case NO_COLLISION:
	    case STRONG_COLLISION:
	    case NORMAL_COLLISION:
	    case WEAK_COLLISION:
		break;
	    default:
		panic("Illegal global collision strength: %d", global_strength);
	    }

	    check(Tcl_SplitList(NULL, rule_attributes, &attr_argc,
				&attr_argv) == TCL_OK);
	    
	    owner = NULL;

	    if (local_strength != NO_COLLISION)
	    {
		Generate_Collision(object, rule_argv[i], attr_argv,
				   0, tables, &owner);
	    }

	    cell = NULL;

	    if (cell_strength != NO_COLLISION)
	    {
		cell = owner ? owner : object;
		cell = Udb_Get_Promoted_Owner(interp, cell, "Cell");

		if (cell != owner)
		{
		    Generate_Collision(object, rule_argv[i], attr_argv,
				       1, tables, &cell);
		}
	    }

	    org = NULL;

	    if (org_strength != NO_COLLISION)
	    {
		org = cell ? cell : (owner ? owner : object);
		org = Udb_Get_Promoted_Owner(interp, org, "Org");

		if (org != owner && org != cell)
		{
		    Generate_Collision(object, rule_argv[i], attr_argv,
				       2, tables, &org);
		}
	    }

	    root = NULL;

	    if (global_strength != NO_COLLISION)
	    {
		root = Udb_Get_Promoted_Owner(interp, object, "Global");

		if (root != owner && root != cell && root != org)
		{
		    Generate_Collision(object, rule_argv[i], attr_argv,
				       3, tables, &root);
		}
	    }

	    ckfree((char *)attr_argv);
	    ckfree(mem);
	}
	ckfree((char *)rule_argv);
    }
    Udb_Inet_Populate_Tables(interp, object, &tables[INET_TABLE]);
    Populate_Range_Table(interp, object, &tables[RANGE_TABLE]);
}


static void
Drop_Collision_Entry_If_Empty(DB_OBJECT *class, DB_OBJECT *object)
{
    static int strengths[3] = {
	STRONG_COLLISION,
	NORMAL_COLLISION,
	WEAK_COLLISION
    };
    int		i;
    DB_VALUE	v;
    
    assert(object);

    for (i = 0; i < 3; ++i)
    {
	DB_COLLECTION	*col;
	int		size;

	Udb_Get_Value(object, Strength_To_Slot(strengths[i]),
			     DB_TYPE_SET, &v);
	col = DB_GET_COLLECTION(&v);
	size = db_col_size(col);
	db_col_free(col);
	if (size > 0)
	{
	    return;
	}
    }

    /*
     * This cache object is empty,  remove from collision check table
     */
    Udb_Drop_Unique_Check(object);
    Udb_Append_Free_List(class, dbt_edit_object(object), "key");
}


static void
Grow_Cache_Entry(
    DB_OBJECT *cache_object, 
    int strength,
    DB_OBJECT *object
)
{
    DB_VALUE		value;
    DB_COLLECTION	*col = NULL;
    char		*slot;

    slot = Strength_To_Slot(strength);

    switch(strength)
    {
    case STRONG_COLLISION:
	Udb_Add_Unique_Check(cache_object);

	Udb_Get_Value(cache_object, slot, DB_TYPE_SET, &value);
	col = DB_GET_COLLECTION(&value);
	break;

    case NORMAL_COLLISION:
	Udb_Get_Value(cache_object, slot, DB_TYPE_SET, &value);
	col = DB_GET_COLLECTION(&value);
	if (db_col_size(col) > 0)
	{
	    Udb_Add_Unique_Check(cache_object);
	}
	else 
	{
	    Udb_Get_Value(cache_object,
				 Strength_To_Slot(STRONG_COLLISION),
				 DB_TYPE_SET, &value);
	    if (db_col_size(DB_GET_COLLECTION(&value)) > 0)
	    {
		Udb_Add_Unique_Check(cache_object);
	    }
	    db_value_clear(&value);
	}
	break;

    case WEAK_COLLISION:
	Udb_Get_Value(cache_object,
			     Strength_To_Slot(STRONG_COLLISION),
			     DB_TYPE_SET, &value);
	if (db_col_size(DB_GET_COLLECTION(&value)) > 0)
	{
	    Udb_Add_Unique_Check(cache_object);
	}
	db_value_clear(&value);
	Udb_Get_Value(cache_object, slot, DB_TYPE_SET, &value);
	col = DB_GET_COLLECTION(&value);
	break;

    default:
	panic("Bad collision strength: %d", strength);
	break;
    }

    Udb_Add_To_Set(col, object);
    db_col_free(col);
}


/*
 * We must do deletions before creations or we can run into a serious name
 * cache integrity problem.
 * Suppose you have a name cache that gets updated has the following data
 * 			normal (slot 0)		cell (slot 1)
 *			------			----
 * 	old_table	h,region1		h,foo.com
 *	new_table	h,foo.com
 *  and they both are WEAK_COLLISIONS (i.e., they both go on the
 *  weak_collisions slot in the name cache). If you process all the
 *  additions and deletions in slot 0, then all the additions and deletions
 *  in slot 1, then what happens is that foo.com is incorrectly deleted from
 *  the cache
 */
static void
Update_Uniqueness_Caches(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *old_tables,
    Tcl_HashTable *new_tables
)
{
    int			i;

    assert(object);

    if (old_tables)
    {
	for (i = 0; i < 4; i++)
	{
	    Tcl_HashEntry	*ePtr;
	    Tcl_HashSearch	search;

	    ePtr = Tcl_FirstHashEntry(&old_tables[i], &search);
	    for ( ; ePtr; ePtr = Tcl_NextHashEntry(&search))
	    {
		int		strength[4];
		char		*collision_class_name;
		char		*attributes;
		DB_OBJECT	*cache_class;
		DB_OBJECT	*cache_object;
		DB_VALUE	value;
		char		*rule;
		char		**rule_argv;
		char		*old_cache_key;
		char		*new_cache_key;

		rule = (char *)Tcl_GetHashKey(&old_tables[i], ePtr);
		rule_argv=
		    Decode_Rule(interp, rule,
				&collision_class_name, &attributes,
				&strength[0], &strength[1],
				&strength[2], &strength[3]);
		cache_class = Udb_Get_Class(collision_class_name);
		ckfree((char *)rule_argv);
		
		old_cache_key = (char *)Tcl_GetHashValue(ePtr);

		if (new_tables &&
		    (ePtr = Tcl_FindHashEntry(&new_tables[i], rule)))
	        {
		    new_cache_key = (char *)Tcl_GetHashValue(ePtr);

		    if (Equal(new_cache_key, old_cache_key))
		    {
			/*
			 * No change, drop from new table
			 */
			ckfree(new_cache_key);
			Tcl_DeleteHashEntry(ePtr);
			continue;
		    }
		}
		DB_MAKE_STRING(&value, old_cache_key);
		cache_object = db_find_unique(cache_class, "key", &value);

		check(cache_object != NULL);

		Udb_Get_Value(cache_object,
		     Strength_To_Slot(strength[i]), DB_TYPE_SET, &value);

		if (Udb_Drop_From_Set(DB_GET_COLLECTION(&value), object) == 0)
		{
		    Drop_Collision_Entry_If_Empty(cache_class, cache_object);
		}
		db_value_clear(&value);
	    }
	}
    }
    if (new_tables)
    {
	for (i = 0; i < 4; i++)
	{
	    Tcl_HashEntry  *ePtr;
	    Tcl_HashSearch search;

	    ePtr = Tcl_FirstHashEntry(&new_tables[i], &search);
	    for ( ; ePtr; ePtr = Tcl_NextHashEntry(&search))
	    {
		int		strength[4];
		char		*collision_class_name;
		char		*attributes;
		DB_OBJECT	*cache_class;
		DB_OBJECT	*cache_object;
		DB_VALUE	value;
		char		*rule;
		char		**rule_argv;
		char		*new_cache_key;

		rule = (char *)Tcl_GetHashKey(&new_tables[i], ePtr);
		rule_argv =
		    Decode_Rule(interp, rule,
				&collision_class_name, &attributes,
				&strength[0], &strength[1],
				&strength[2], &strength[3]);
		cache_class = Udb_Get_Class(collision_class_name);
		ckfree((char *)rule_argv);
		
		new_cache_key = (char *)Tcl_GetHashValue(ePtr);

		DB_MAKE_STRING(&value, new_cache_key);
		cache_object = db_find_unique(cache_class, "key", &value);
		if (cache_object == NULL)
		{
		    DB_OTMPL		*template;
		    DB_COLLECTION	*col;

		    template = Udb_Edit_Free_Object(cache_class);
		    check(dbt_put(template, "key", &value) == NOERROR);

		    check(col = db_col_create(DB_TYPE_SET, 1, NULL));
		    Udb_Add_To_Set(col, object);

		    DB_MAKE_COLLECTION(&value, col);
		    check(dbt_put(template, Strength_To_Slot(strength[i]),
				  &value) == NOERROR);
		    db_col_free(col);

		    check(Udb_Finish_Object(NULL, template, FALSE));
		}
		else
		{
		    Grow_Cache_Entry(cache_object, strength[i], object);
		}
	    }
	}
    }
}


void
Udb_Free_Cache_Tables(Tcl_HashTable *tables)
{
    int i;

    for (i = 0; i < NCACHE_TABLES; i++)
    {
	switch (i)
	{
	case INET_TABLE:
	    Udb_Inet_Free_Table(&tables[i]);
	    break;

	default:
	    Udb_Free_Dynamic_Table(&tables[i], NULL, TRUE);
	    break;
	}
    }
}


static void
Update_Range_Caches(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *old_table,
    Tcl_HashTable *new_table
)
{
    Tcl_HashEntry	*ePtr;
    Tcl_HashEntry	*newPtr;
    Tcl_HashSearch	search;
    int			old_argc;
    char		**old_argv;
    int			new_argc;
    char		**new_argv;

    if (old_table)
    {
	/*
	 * Each key in hash table is a range attribute name
	 * For each attribute,  check value and owner.
	 */
	for (ePtr = Tcl_FirstHashEntry(old_table, &search);
	     ePtr;
	     ePtr = Tcl_NextHashEntry(&search))
	{
	    char	*attribute;
	    char	*old_state;
	    char	*new_state;
	    DB_INT32	old_int;
	    DB_OBJECT	*old_owner;
	    DB_INT32	new_int;
	    DB_OBJECT	*new_owner;

	    attribute = Tcl_GetHashKey(old_table, ePtr);

	    old_state = (char *)Tcl_GetHashValue(ePtr);

	    check(Tcl_SplitList(NULL, old_state, &old_argc, &old_argv)
		  == TCL_OK);
	    assert(old_argc == 2);

	    check(Udb_String_To_Int32(NULL, old_argv[0], &old_int) == TCL_OK);

	    check(old_owner = Udb_Decode_Oid(old_argv[1]));
	    ckfree((char *)old_argv);

	    if (new_table == NULL ||
		(newPtr = Tcl_FindHashEntry(new_table, attribute)) == NULL)
	    {
		Udb_Delete_Range_Entry(old_owner, attribute, old_int, object);
		continue;
	    }

	    new_state = (char *)Tcl_GetHashValue(newPtr);

	    check(Tcl_SplitList(NULL, new_state, &new_argc, &new_argv)
		  == TCL_OK);
	    assert(new_argc == 2);

	    /*
	     * Drop entry from new table so that at the end of this loop,
	     * the new table contains only new entries.
	     */ 
	    ckfree(new_state);
	    Tcl_DeleteHashEntry(newPtr);

	    check(Udb_String_To_Int32(NULL, new_argv[0], &new_int) == TCL_OK);
	    check(new_owner = Udb_Decode_Oid(new_argv[1]));
	    ckfree((char *)new_argv);

	    if (new_int != old_int || new_owner != old_owner)
	    {
		Udb_Delete_Range_Entry(old_owner, attribute, old_int, object);
		Udb_Add_Range_Entry(new_owner, attribute, new_int, object);
	    }
	}
    }

    if (new_table == NULL)
    {
	return;
    }

    for (ePtr = Tcl_FirstHashEntry(new_table, &search);
	 ePtr;
	 ePtr = Tcl_NextHashEntry(&search))
    {
	char		*attribute;
	char		*new_state;
	DB_INT32	new_int;
	DB_OBJECT	*new_owner;
	int		new_argc;
	char		**new_argv;

	attribute = Tcl_GetHashKey(new_table, ePtr);
	new_state = (char *)Tcl_GetHashValue(ePtr);

	check(Tcl_SplitList(NULL, new_state, &new_argc, &new_argv) == TCL_OK);
	assert(new_argc == 2);

	check(Udb_String_To_Int32(NULL, new_argv[0], &new_int) == TCL_OK);
	check(new_owner = Udb_Decode_Oid(new_argv[1]));
	ckfree((char *)new_argv);

	Udb_Add_Range_Entry(new_owner, attribute, new_int, object);
    }
}


int
Udb_Update_Caches(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object, 
    Tcl_HashTable *old_tables, 
    Tcl_HashTable *new_tables
)
{
    int result;

    assert(object);

    result = Udb_Inet_Update(interp, uuid, object,
			     old_tables ? &old_tables[INET_TABLE] : NULL,
			     new_tables ? &new_tables[INET_TABLE] : NULL);

    if (result == TCL_OK)
    {
	Update_Uniqueness_Caches(interp, object, old_tables, new_tables);

	Update_Range_Caches(interp, object,
			    old_tables ? &old_tables[RANGE_TABLE] : NULL,
			    new_tables ? &new_tables[RANGE_TABLE] : NULL);
    }

    if (old_tables)
    {
	Udb_Free_Cache_Tables(old_tables);
    }
    if (new_tables)
    {
	Udb_Free_Cache_Tables(new_tables);
    }
    return result;
}


void
Udb_Delete_All_Caches(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object
)
{
    Tcl_HashTable	old_tables[NCACHE_TABLES];
    
    Udb_Populate_Caches(interp, object, old_tables);
    check(Udb_Update_Caches(interp, uuid, object, old_tables, NULL) == TCL_OK);
}


static Tcl_HashTable uniqTable;
static Tcl_HashTable *uniqTblPtr;


void
Udb_Add_Unique_Check(DB_OBJECT *object) 
{
    int	new;
    if (uniqTblPtr == NULL)
    {
	uniqTblPtr = &uniqTable;
	Tcl_InitHashTable(uniqTblPtr, TCL_ONE_WORD_KEYS);
    }
    (void) Tcl_CreateHashEntry(uniqTblPtr, (ClientData)object, &new);
}


void
Udb_Drop_Unique_Check(DB_OBJECT *object) 
{
    Tcl_HashEntry *ePtr;

    if (uniqTblPtr &&
	(ePtr = Tcl_FindHashEntry(uniqTblPtr, (ClientData)object)))
    {
	Tcl_DeleteHashEntry(ePtr);
    }
}


void
Udb_Reset_Unique_Checks(void) 
{
    if (uniqTblPtr)
    {
	Tcl_DeleteHashTable(uniqTblPtr);
	uniqTblPtr = NULL;
    }
}


int
Udb_Do_Unique_Checks(Tcl_Interp *interp)
{
    DB_VALUE		value;
    DB_COLLECTION	*strong_set;
    DB_COLLECTION	*normal_set;
    DB_COLLECTION	*weak_set;
    int			strong_count;
    int			normal_count;
    int			weak_count;
    Tcl_HashEntry	*ePtr;
    Tcl_HashSearch	search;

    if (uniqTblPtr == NULL)
    {
	return TCL_OK;
    }

    while((ePtr = Tcl_FirstHashEntry(uniqTblPtr, &search)) != NULL)
    {
	DB_OBJECT	*bucket;

	bucket = (DB_OBJECT *)Tcl_GetHashKey(uniqTblPtr, ePtr);
	Tcl_DeleteHashEntry(ePtr);

	Udb_Get_Value(bucket, Strength_To_Slot(STRONG_COLLISION),
			     DB_TYPE_SET, &value);
	strong_set = DB_GET_COLLECTION(&value);
	strong_count = db_col_size(strong_set);

	/*
	 * First detect direct violations:
	 *    Two or more strong in same slot or
	 */
	if (strong_count > 1)
	{
	    (void) Udb_EDIRECTUNIQ(interp, db_get_class(bucket),
				   strong_set, strong_count);
	    db_col_free(strong_set);
	    return TCL_ERROR;
	}

	Udb_Get_Value(bucket, Strength_To_Slot(NORMAL_COLLISION),
			     DB_TYPE_SET, &value);
	normal_set = DB_GET_COLLECTION(&value);
	normal_count = db_col_size(normal_set);

	if (normal_count > 1)
	{
	    (void) Udb_EDIRECTUNIQ(interp, db_get_class(bucket),
				   normal_set, normal_count);
	    db_col_free(strong_set);
	    db_col_free(normal_set);
	    return TCL_ERROR;
	}

	if (strong_count > 0  && normal_count > 0)
	{
	    (void) Udb_EINDIRUNIQ(interp, db_get_class(bucket),
				  strong_set, normal_set, normal_count);
	    db_col_free(strong_set);
	    db_col_free(normal_set);
	    return TCL_ERROR;
	}
	db_col_free(normal_set);

	if (strong_count > 0)
	{
	    Udb_Get_Value(bucket, Strength_To_Slot(WEAK_COLLISION),
				 DB_TYPE_SET, &value);
	    weak_set = DB_GET_COLLECTION(&value);
	    weak_count = db_col_size(weak_set);

	    if (weak_count > 0)
	    {
		(void) Udb_EINDIRUNIQ(interp, db_get_class(bucket),
				      strong_set, weak_set, weak_count);
		db_col_free(strong_set);
		db_col_free(weak_set);
		return TCL_ERROR;
	    }
	    db_col_free(weak_set);
	}
	db_col_free(strong_set);
    }
    return TCL_OK;
}
