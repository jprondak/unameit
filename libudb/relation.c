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
static char rcsid[] = "$Id: relation.c,v 1.6.58.7 1997/10/09 01:10:33 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "uuid.h"
#include "relation.h"
#include "misc.h"
#include "lookup.h"
#include "name_cache.h"
#include "transaction.h"
#include "inet.h"
#include "errcode.h"


#define	SPACE '\040'

/*
 * Forward declarations
 */
static void Add_Reference_Check(DB_OBJECT *object);
static void Add_Loop_Check(
    DB_OBJECT *object,
    const char *aname,
    DB_TYPE type
);
static void Drop_Loop_Check(DB_OBJECT *object);


/*
 * Returns static data overwritten on each call
 */
static const char *
Backpointer_Name(const char *action)
{
    static char backpName[24];

    assert(strlen(action) < 16);
    sprintf(backpName, "backp/%s", action);
    return backpName;
}


static void
Maybe_Add_Loop_Check(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    DB_OBJECT *object,
    char *aname,
    DB_TYPE type
)
{
    char		*cname = Udb_Get_Class_Name(class);
    Tcl_DString		dstr;
    char		*check;

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, cname, -1);
    Tcl_DStringAppend(&dstr, ".", -1);
    Tcl_DStringAppend(&dstr, aname, -1);

    check = Tcl_GetVar2(interp, "UNAMEIT_DETECT_LOOPS",
			Tcl_DStringValue(&dstr), TCL_GLOBAL_ONLY);
    Tcl_DStringFree(&dstr);

    if (check != NULL)
    {
	Add_Loop_Check(object, aname, type);
    }
}


static void
Build_Relation(DB_OTMPL *template, DB_OBJECT *rhs, const char *backp)
{
    DB_VALUE		value;
    DB_OBJECT		*next;
    DB_OBJECT		*newRel;

    assert(template && rhs && backp);

    /*
     * Store 'rhs' in new template
     */
    DB_MAKE_OBJECT(&value, rhs);
    check(dbt_put(template, "rhs", &value) == NOERROR);

    /*
     * The 'prev' pointer of new relation points back at 'rhs'
     */
    check(dbt_put(template, "prev", &value) == NOERROR);

    /*
     * Get old queue head (may be NULL)
     */
    Udb_Get_Value(rhs, backp, DB_TYPE_OBJECT, &value);
    next = DB_GET_OBJECT(&value);

    /*
     * The 'next' pointer of new relation points at old queue head
     */
    check(dbt_put(template, "next", &value) == NOERROR);

    check(newRel = Udb_Finish_Object(NULL, template, FALSE));
    DB_MAKE_OBJECT(&value, newRel);

    /*
     * Point 'rhs' at new queue head
     */
    check(db_put(rhs, backp, &value) == NOERROR);

    /*
     * Update backpointer of old queue head
     */
    if (next != NULL)
    {
	check(db_put(next, "prev", &value) == NOERROR);
    }
}


static void
New_Relation(
    DB_OBJECT *relclass,
    DB_OBJECT *lhs,
    DB_OBJECT *rhs,
    const char *backp
)
{
    DB_OTMPL		*template;
    DB_VALUE		value;

    assert(relclass && lhs);

    template = Udb_Edit_Free_Object(relclass);

    DB_MAKE_OBJECT(&value, lhs);
    check(dbt_put(template, "lhs", &value) == NOERROR);

    Build_Relation(template, rhs, backp);
}


static void
Update_Relation(
    Tcl_Interp *interp,
    DB_OBJECT *relclass,
    DB_OBJECT *relation,
    DB_OBJECT *rhs,
    DB_OBJECT *newrhs,
    const char *backp
)
{
    DB_VALUE	value;
    DB_OBJECT	*prev;
    DB_OBJECT	*next;
    DB_OTMPL	*template;

    assert(relclass && relation && rhs && backp);

    Udb_Get_Value(relation, "prev", DB_TYPE_OBJECT, &value);
    check(prev = DB_GET_OBJECT(&value));

    /*
     * Point 'prev.next' at 'next' (may be NULL)
     */
    Udb_Get_Value(relation, "next", DB_TYPE_OBJECT, &value);
    next = DB_GET_OBJECT(&value);

    if (prev != rhs)
    {
	check(db_put(prev, "next", &value) == NOERROR);
    }
    else
    {
	check(db_put(prev, backp, &value) == NOERROR);
    }

    if (next != NULL)
    {
	/*
	 * Point 'next.prev' at 'prev'
	 */
	DB_MAKE_OBJECT(&value, prev);
	check(db_put(next, "prev", &value) == NOERROR);
    }

    check(template = dbt_edit_object(relation));

    if (newrhs != NULL)
    {
	/*
	 * Caller intends to reuse the relation with a new 'rhs'
	 */
	Build_Relation(template, newrhs, backp);
	return;
    }

    /*
     * Add dead relation to free list
     */
    Udb_Append_Free_List(relclass, template, "lhs");
}


/*
 * Update relation object to reflect change in scalar pointer attribute value.
 */
static void
Update_Scalar_Relation(
    Tcl_Interp *interp,
    DB_OBJECT *lhs_class,
    DB_OBJECT *lhs,
    char *aname,
    DB_OBJECT *rhs,
    int new_object,
    int dont_loopcheck
)
{
    DB_VALUE	value;
    DB_OBJECT	*relclass;
    DB_OBJECT	*relation = NULL;
    const char	*action;
    const char	*backp;

    assert(lhs);

    relclass = Udb_Relation_Class(aname);
    action = Udb_Get_Relaction(interp, lhs_class, aname);
    backp = Backpointer_Name(action);

    if (new_object == FALSE)
    {
	DB_MAKE_OBJECT(&value, lhs);
	relation = db_find_unique(relclass, "lhs", &value);
    }

    if (relation != NULL)
    {
	DB_OBJECT *oldrhs;
	Udb_Get_Value(relation, "rhs", DB_TYPE_OBJECT, &value);
	check(oldrhs = DB_GET_OBJECT(&value));
	Update_Relation(interp, relclass, relation, oldrhs, rhs, backp);
    }
    else
    {
	if (rhs != NULL)
	{
	    New_Relation(relclass, lhs, rhs, backp);
	}
    }

    if (rhs && new_object == FALSE && dont_loopcheck == FALSE)
    {
	/*
	 * Since, we point at `rhs' start there
	 */
	Maybe_Add_Loop_Check(interp, db_get_class(rhs), rhs,
			     aname, DB_TYPE_OBJECT);
    }
}


/*
 * Update relation object to reflect change in set pointer attribute value.
 */
static void
Update_Vector_Relation(
    Tcl_Interp *interp,
    DB_OBJECT *lhs_class,
    DB_OBJECT *lhs,
    char *aname,
    DB_COLLECTION *rhs,
    int new_object,
    int dont_loopcheck
)
{
    DB_OBJECT		*relclass;
    const char		*action;
    const char		*backp;
    Tcl_HashTable	rhs_table;
    Tcl_HashSearch	rhsSearch;
    Tcl_HashEntry	*ePtr;
    DB_VALUE  		value;
    DB_INT32		rhs_count = 0;
    DB_OBJECT 		*rhs_elem;

    assert(lhs && aname);

    relclass = Udb_Relation_Class(aname);
    action = Udb_Get_Relaction(interp, lhs_class, aname);
    backp = Backpointer_Name(action);

    if (rhs)
    {
	DB_INT32	count;
	DB_INT32	index;

	Tcl_InitHashTable(&rhs_table, TCL_ONE_WORD_KEYS);

	count = db_col_size(rhs);

	for(index = 0; index < count; ++index)
	{
	    int newEntry;
	    Udb_Get_Collection_Value(rhs, index, DB_TYPE_OBJECT, &value);
	    rhs_elem = DB_GET_OBJECT(&value);
	    Tcl_CreateHashEntry(&rhs_table, (ClientData)rhs_elem, &newEntry);
	    if (newEntry) ++rhs_count;
	}
    }

    if (new_object == FALSE)
    {
	char		*relcname = Udb_Get_Class_Name(relclass);
	DB_ERROR	rows;
	DB_SESSION	*sess_id;
	DB_QUERY_RESULT	*cursor;
	DB_INT32	more;
	Tcl_DString	query;

	/*
	 * Find old relation tuples
	 */
	Tcl_DStringInit(&query);
	Tcl_DStringAppend(&query, "select x.\"rhs\", x from \"", -1);
	Tcl_DStringAppend(&query, relcname, -1);
	Tcl_DStringAppend(&query, "\" x where x.\"lhs\" = ?", -1);

	DB_MAKE_OBJECT(&value, lhs);
	rows = Udb_Run_Query(Tcl_DStringValue(&query), &sess_id, &cursor,
			     1, &value, 1);
	check(db_query_column_count(cursor) == 2);

	Tcl_DStringFree(&query);

	/*
	 * For every old relation,  either keep it,  and trim rhs_table
	 * or free it
	 */
	for (more = db_query_first_tuple(cursor);
	     more == DB_CURSOR_SUCCESS;
	     --rows, more = db_query_next_tuple(cursor))
	{
	    DB_VALUE	reldata[2];
	    DB_OBJECT	*relation;

	    check(db_query_get_tuple_valuelist(cursor, 2, reldata) == NOERROR);

	    rhs_elem = DB_GET_OBJECT(&reldata[0]);
	    relation = DB_GET_OBJECT(&reldata[1]);

	    if (rhs_count > 0)
	    {
		ePtr = Tcl_FindHashEntry(&rhs_table, (ClientData)rhs_elem);
		if (ePtr != NULL)
		{
		    /*
		     * Relation is unchanged, drop from lookup table,  also
		     * reduce rhs_count, to keep track of unprocessed relations
		     */
		    Tcl_DeleteHashEntry(ePtr);
		    --rhs_count;
		    continue;
		}
	    }
	    /*
	     * This relation is extant,  free it (by updating rhs to NULL)
	     */
	    Update_Relation(interp, relclass, relation, rhs_elem, NULL, backp);
	}
	check (rows == 0);
	db_query_end(cursor);
	db_close_session(sess_id);
    }

    if (rhs_count == 0)
    {
	if (rhs)
	{
	    Tcl_DeleteHashTable(&rhs_table);
	}
	return;
    }

    if (new_object == FALSE && dont_loopcheck == FALSE)
    {
	Maybe_Add_Loop_Check(interp, lhs_class, lhs, aname, DB_TYPE_SET);
    }

    /*
     * We have freed all the extant relation tuples
     * and removed the stable relations from `rhs_table'.
     * The remaining entries in `rhs_table' are new relations.
     */
    while ((ePtr = Tcl_FirstHashEntry(&rhs_table, &rhsSearch)) != NULL)
    {
	rhs_elem = (DB_OBJECT *)Tcl_GetHashKey(&rhs_table, ePtr);
	Tcl_DeleteHashEntry(ePtr);

	New_Relation(relclass, lhs, rhs_elem, backp);
    }
    Tcl_DeleteHashTable(&rhs_table);
}


/*
 * Update relations from hash table of DB_VALUE pointers keyed by
 * attribute name.
 */
void
Udb_Update_Relations(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    DB_OBJECT *object,
    Tcl_HashTable *relations,
    int new_object,
    int dont_loopcheck
)
{
    Tcl_HashEntry *ePtr;
    Tcl_HashSearch search;

    for(ePtr = Tcl_FirstHashEntry(relations, &search);
	ePtr;
	ePtr = Tcl_NextHashEntry(&search))
    {
	DB_TYPE		type;
	char		*aname = Tcl_GetHashKey(relations, ePtr);
	DB_VALUE	*value = (DB_VALUE *)Tcl_GetHashValue(ePtr);
	DB_OBJECT	*rhs_obj;
	DB_COLLECTION	*rhs_col;

	switch (type = DB_VALUE_DOMAIN_TYPE(value))
	{
	case DB_TYPE_OBJECT:
	    rhs_obj = DB_GET_OBJECT(value);
	    Update_Scalar_Relation(interp, class, object, aname, rhs_obj,
				   new_object, dont_loopcheck);
	    break;

	case DB_TYPE_SET:
	case DB_TYPE_SEQUENCE:
	    rhs_col = DB_GET_COLLECTION(value);
	    Update_Vector_Relation(interp, class, object, aname, rhs_col,
				   new_object, dont_loopcheck);
	    break;

	default:
	    panic("Non-object relation type: %s attribute %s",
		  db_get_type_name(type), aname);
	    break;
	}
	db_value_free(value);
    }
    Tcl_DeleteHashTable(relations);
}


/*
 * Nullify attribute `aname' of object `lhs'.  Bypass Update_Relation
 * code,  since caller has handle on relation,  and it is more efficient
 * to let the caller free it.
 */
static void
Nullify_Attribute(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *lhs,
    char *aname,
    DB_OBJECT *rhs
)
{
    DB_OTMPL		*template;
    DB_OBJECT		*lhs_class;
    DB_DOMAIN		*domain;
    DB_TYPE		type;
    DB_VALUE		value;
    DB_COLLECTION	*col;
    DB_COLLECTION	*newcol;
    DB_INT32 		col_size;
    DB_INT32 		index;
    Tcl_HashTable	new_tables[NCACHE_TABLES];
    Tcl_HashTable	old_tables[NCACHE_TABLES];

    lhs_class = db_get_class(lhs);

    check(domain = Udb_Attribute_Domain(lhs_class, aname));

    check(template = dbt_edit_object(lhs));

    switch(type = db_domain_type(domain))
    {
    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	/*
	 * Drop rhs object from set or sequence, by building new set
	 * or sequence that skips references to 'rhs'
	 */
	Udb_Get_Value(lhs, aname, type, &value);
	col = DB_GET_COLLECTION(&value);
	col_size = db_col_size(col);
	check(newcol = db_col_create(type, col_size-1, domain));

	for (index = 0; index < col_size; ++index)
	{
	    Udb_Get_Collection_Value(col, index, DB_TYPE_OBJECT, &value);
	    if (rhs == DB_GET_OBJECT(&value)) continue;
	    check(db_col_add(newcol, &value) == NOERROR);
	}
	DB_MAKE_COLLECTION(&value, newcol);
	check(dbt_put(template, aname, &value) == NOERROR);

	db_col_free(col);
	db_col_free(newcol);

	check(lhs == Udb_Finish_Object(lhs_class, template, FALSE));
	break;

    case DB_TYPE_OBJECT:
	DB_MAKE_NULL(&value);
	check(dbt_put(template, aname, &value) == NOERROR);
	/*
	 * If we null out a scalar attribute,
	 * may need to update uniqueness tables.
	 */
	Udb_Populate_Caches(interp, lhs, old_tables);
	check(lhs == Udb_Finish_Object(lhs_class, template, FALSE));
	Udb_Populate_Caches(interp, lhs, new_tables);
	Udb_Update_Caches(interp, uuid, lhs, old_tables, new_tables);
	break;

    default:
	panic("Illegal data type '%s' for nullified attribute: %s",
	      db_get_type_name(type), aname);
	break;
    }
}


static void
Drop_Lhs_Relations(Tcl_Interp *interp, DB_OBJECT *lhs_class, DB_OBJECT *lhs)
{
    DB_TYPE		type;
    char		**relattrs;
    char		*aname;

    assert(lhs_class && lhs);

    check(relattrs = Udb_Get_Relattributes(interp, lhs_class));

    while((aname = *relattrs++) != NULL)
    {
	DB_DOMAIN *domain = Udb_Attribute_Domain(lhs_class, aname);
	switch (type = db_domain_type(domain))
	{
	case DB_TYPE_OBJECT:
	    Update_Scalar_Relation(interp, lhs_class, lhs, aname, NULL,
				   FALSE, TRUE);
	    break;
	case DB_TYPE_SET:
	case DB_TYPE_SEQUENCE:
	    Update_Vector_Relation(interp, lhs_class, lhs, aname, NULL,
				   FALSE, TRUE);
	    break;
	default:
	    panic("Non-object relation type: %s attribute %s",
		  db_get_type_name(type), aname);
	    break;
	}
    }
}


/*
 * Cascade, or Nullify relations in which object is "rhs".
 */
static int
Process_Rhs_Relations(Tcl_Interp *interp, DB_OBJECT *rhs)
{
    const char	*backp;
    DB_VALUE	value;
    DB_OBJECT	*lhs;
    DB_OBJECT	*relation;
    char	uuid[UDB_UUID_SIZE];

    assert(rhs);

    /*
     * As we cascade objects, the queue head will move to the next uncascaded
     * relation,  so we *need/should* not walk the queue
     */
    for(;;)
    {
	/*
	 * backp is from a static buffer,  and this loop is reentrant,
	 * so reinitialize on each iteration
	 */
	backp = Backpointer_Name("Cascade");

	Udb_Get_Value(rhs, backp, DB_TYPE_OBJECT, &value);
	relation = DB_GET_OBJECT(&value);

	if (relation == NULL)
	{
	    /*
	     * We have cascaded away all the objects
	     */
	    break;
	}

	Udb_Get_Value(relation, "lhs", DB_TYPE_OBJECT, &value);
	check(lhs = DB_GET_OBJECT(&value));

	if (Tcl_VarEval(interp, "unameit_delete ", Udb_Get_Uuid(lhs, uuid),
			(char *)NULL) != TCL_OK)
	{
	    return TCL_ERROR;
	}
    }

    backp = Backpointer_Name("Nullify");

    for(;;)
    {
	char *aname;

	Udb_Get_Value(rhs, backp, DB_TYPE_OBJECT, &value);
	relation = DB_GET_OBJECT(&value);

	if (relation == NULL)
	{
	    break;
	}

	Udb_Get_Value(relation, "lhs", DB_TYPE_OBJECT, &value);
	check(lhs = DB_GET_OBJECT(&value));
	aname = Udb_Relation_Attribute(db_get_class(relation));

	Nullify_Attribute(interp, Udb_Get_Uuid(lhs, uuid), lhs, aname, rhs);
	Update_Relation(interp, db_get_class(relation), relation, rhs,
			NULL, backp);
    }

    backp = Backpointer_Name("Block");
    Udb_Get_Value(rhs, backp, DB_TYPE_OBJECT, &value);

    if (!DB_IS_NULL(&value))
    {
	Add_Reference_Check(rhs);
    }
    return TCL_OK;
}


int
Udb_Delete_Object(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    const char *uuid,
    DB_OBJECT *object
)
{
    DB_OTMPL		*template;

    /*
     * Drop uniqueness cache entries
     */
    Udb_Delete_All_Caches(interp, uuid, object);

    /*
     * Drop all relations in which object is "lhs",
     */
    Drop_Lhs_Relations(interp, class, object);

    /*
     * No loop checks on deleted objects
     */
    Drop_Loop_Check(object);

    check(template = dbt_edit_object(object));
    check(object == Udb_Finish_Object(class, template, TRUE /* deleted */));

    /*
     * recache as deleted
     */
    Udb_Cache_Object(uuid, object, TRUE);

    /*
     * Process all relations in which object is "rhs", performing cascade,
     * nullify or pending block as necessary.
     */
    return Process_Rhs_Relations(interp, object);
}


static void
Reference_Error(DB_OBJECT *rhs, DB_OBJECT *relation, Tcl_DString *errorCode)
{
    DB_VALUE	value;
    DB_OBJECT	*lhs;
    char	*aname;

    Udb_Get_Value(relation, "lhs", DB_TYPE_OBJECT, &value);
    lhs = DB_GET_OBJECT(&value);
    aname = Udb_Relation_Attribute(db_get_class(relation));

    Tcl_DStringStartSublist(errorCode);
    Tcl_DStringAppendElement(errorCode, Udb_Get_Uuid(lhs, NULL));
    Tcl_DStringAppendElement(errorCode, aname);
    Tcl_DStringAppendElement(errorCode, Udb_Get_Uuid(rhs, NULL));
    Tcl_DStringEndSublist(errorCode);
}


static Tcl_HashTable refTable;
static Tcl_HashTable *refTablePtr;


/*
 * Add object to table of objects to be checked at commit time.
 * The commit will fail unless the object has no 'Block' backpointers
 * by the end of the transaction.
 */
static void
Add_Reference_Check(DB_OBJECT *object)
{
    int new;

    if (refTablePtr == NULL)
    {
	refTablePtr = &refTable;
	Tcl_InitHashTable(refTablePtr, TCL_ONE_WORD_KEYS);
    }
    (void) Tcl_CreateHashEntry(refTablePtr, (ClientData)object, &new);
}


/*
 * Drop all reference checks.  The decision to commit or rollback has been made
 */
void
Udb_Reset_Reference_Checks()
{
    if (refTablePtr)
    {
	Tcl_DeleteHashTable(refTablePtr);
	refTablePtr = NULL;
    }
}


int
Udb_Do_Reference_Checks(Tcl_Interp *interp)
{
    Tcl_HashSearch	search;
    Tcl_HashEntry	*ePtr;
    int			refcount = 0;

    if (refTablePtr)
    {
	const char 	*backp = Backpointer_Name("Block");
	Tcl_DString	errorCode;

	Tcl_DStringInit(&errorCode);

	while (refcount < 10 &&
	       (ePtr = Tcl_FirstHashEntry(refTablePtr, &search)))
	{
	    DB_OBJECT	*object;
	    DB_VALUE	value;
	    DB_OBJECT	*relation;
	    
	    object = (DB_OBJECT *)Tcl_GetHashKey(refTablePtr, ePtr);
	    Tcl_DeleteHashEntry(ePtr);

	    Udb_Get_Value(object, backp, DB_TYPE_OBJECT, &value);
	    relation = DB_GET_OBJECT(&value);

	    while (relation && refcount < 10)
	    {
		++refcount;
		Reference_Error(object, relation, &errorCode);

		Udb_Get_Value(relation, "next", DB_TYPE_OBJECT, &value);
		relation = DB_GET_OBJECT(&value);
	    }
	}

	if (refcount > 0)
	{
	    (void) Udb_EREFINTEGRITY(interp, Tcl_DStringValue(&errorCode));
	    Tcl_DStringFree(&errorCode);
	    return TCL_ERROR;
	}
    }
    return TCL_OK;
}


static Tcl_HashTable loopTable;
static Tcl_HashTable *loopTblPtr;

static void
Add_Loop_Check(DB_OBJECT *object, const char *aname, DB_TYPE type)
{
    int	new;
    Tcl_HashEntry *ePtr;
    Tcl_HashTable *objectTable;

    if (loopTblPtr == NULL)
    {
	loopTblPtr = &loopTable;
	Tcl_InitHashTable(loopTblPtr, TCL_STRING_KEYS);
    }

    ePtr = Tcl_CreateHashEntry(loopTblPtr, (char *)aname, &new);

    if (new)
    {
	objectTable = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
	Tcl_InitHashTable(objectTable, TCL_ONE_WORD_KEYS);
	Tcl_SetHashValue(ePtr, objectTable);
	/*
	 * Trick: Store attribute type in NULL object slot
	 */
	ePtr = Tcl_CreateHashEntry(objectTable, NULL, &new);
	Tcl_SetHashValue(ePtr, (ClientData)type);
    }
    else
    {
	objectTable = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }
    (void) Tcl_CreateHashEntry(objectTable, (ClientData)object, &new);
}


static void
Drop_Loop_Check(DB_OBJECT *object)
{
    Tcl_HashEntry *ePtr;
    Tcl_HashSearch search;
    Tcl_HashTable *objectTable;

    if (loopTblPtr == NULL)
    {
	return;
    }

    for (ePtr = Tcl_FirstHashEntry(loopTblPtr, &search);
	 ePtr;
	 ePtr = Tcl_NextHashEntry(&search))
    {
	objectTable = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	ePtr = Tcl_FindHashEntry(objectTable, (ClientData)object);
	if (ePtr != NULL)
	{
	    Tcl_DeleteHashEntry(ePtr);
	}
    }
}


void
Udb_Reset_Loop_Checks(void)
{
    if (loopTblPtr)
    {
	Udb_Free_Static_Table_Table(loopTblPtr);
	loopTblPtr = NULL;
    }
}


/*
 * These recursive functions check collection DAGs for loops.
 */
static DB_OBJECT *
Collection_Loop_Leaf(
    Tcl_HashTable *verifiedTable,	/* Hash table of verified nodes */
    Tcl_HashTable *pathTable,		/* Hash table to record path nodes */
    DB_OBJECT *object,			/* Node to search from */
    char *aname,			/* Attribute to use. */
    Tcl_DString *loop_uuids		/* DString for loop node UUIDs */
)
{
    DB_COLLECTION	*col;
    DB_VALUE		value;
    int			col_size;
    int			i;
    int			new;

    /*
     * Make sure we have plausible input data:
     */
    assert(verifiedTable && pathTable && object && aname && loop_uuids);

    /*
     * If node already verified,  nothing to check
     */
    if (Tcl_FindHashEntry(verifiedTable, (ClientData)object))
    {
	return NULL;
    }

    /*
     * Find all objects pointed to from this collection
     */
    switch(db_get(object, aname, &value))
    {
    case NOERROR:
	break;
    case ER_OBJ_INVALID_ATTRIBUTE:
	DB_MAKE_NULL(&value);
	break;
    default:
	panic("db_get(%s): %s", aname, db_error_string(1));
    }

    if (DB_IS_NULL(&value))
    {
	/*
	 * This node is not in any loop,  save as verified to avoid
	 * pathological cases,  where it may be checked a very large
	 * number of times
	 */
	(void) Tcl_CreateHashEntry(verifiedTable, (ClientData)object, &new);
	return NULL;
    }

    check(DB_VALUE_TYPE(&value) == DB_TYPE_SET||
	  DB_VALUE_TYPE(&value) == DB_TYPE_SEQUENCE);

    col = DB_GET_COLLECTION(&value);

    col_size = db_col_size(col);

    for (i = 0; i < col_size; ++i)
    {
	Tcl_HashEntry	*ePtr;
	DB_OBJECT		*next;
	DB_OBJECT		*leaf;
	int			new;

	Udb_Get_Collection_Value(col, i, DB_TYPE_OBJECT, &value);
	next = DB_GET_OBJECT(&value);

	/*
	 * If we have seen it before we have a loop
	 */
	if (Tcl_FindHashEntry(pathTable, (ClientData)next))
	{
	    /*
	     * Record the uuid in loop_uuids and return the offending object,
	     * we will stop recording when we encounter it again.
	     * (After it gets deleted from the hash table)
	     */
	    Tcl_DStringInit(loop_uuids);
	    Tcl_DStringAppendElement(loop_uuids,
				     Udb_Get_Uuid(next, NULL));
	    db_col_free(col);
	    return next;
	}

	/*
	 * Add/Del referencing item to hash table around recursion
	 */
	ePtr = Tcl_CreateHashEntry(pathTable, (char *)next, &new);
	leaf = Collection_Loop_Leaf(verifiedTable, pathTable, next,
				    aname, loop_uuids);
	Tcl_DeleteHashEntry(ePtr);

	if (leaf)
	{
	    if (Tcl_FindHashEntry(pathTable, (char *)leaf))
	    {
		/*
		 * Record UUIDs in loop as we unwind
		 */
		Tcl_DStringAppendElement(loop_uuids,
					 Udb_Get_Uuid(next, NULL));
	    }
	    db_col_free(col);
	    return leaf;
	}
    }
    db_col_free(col);

    /*
     * This node is not in any loop,  save as verified to avoid
     * pathological cases,  where it may be checked a very large
     * number of times
     */
    (void) Tcl_CreateHashEntry(verifiedTable, (ClientData)object, &new);

    return NULL;
}


static DB_OBJECT *
Scalar_Loop_Leaf(
    Tcl_HashTable *verifiedTable,	/* Hash table of verified nodes */
    Tcl_HashTable *pathTable,		/* Hash table to record path nodes */
    DB_OBJECT *object,			/* Node to search forward from */
    char *aname,			/* Attribute to use. */
    Tcl_DString *loop_uuids		/* DString for loop node UUIDs */
)
{
    DB_VALUE		value;
    DB_OBJECT		*next;
    DB_OBJECT		*leaf;
    Tcl_HashEntry	*ePtr;
    int			new;

    /*
     * Make sure we have plausible input data
     */
    assert(verifiedTable && pathTable && object && aname && loop_uuids);

    /*
     * If node already verified,  nothing to check
     */
    if (Tcl_FindHashEntry(verifiedTable, (ClientData)object))
    {
	return NULL;
    }

    switch (db_get(object, aname, &value))
    {
    case NOERROR:
	break;
    case ER_OBJ_INVALID_ATTRIBUTE:
	DB_MAKE_NULL(&value);
	break;
    default:
	panic("db_get(%s): %s", aname, db_error_string(1));
    }

    if (DB_IS_NULL(&value))
    {
	(void) Tcl_CreateHashEntry(verifiedTable, (ClientData)object, &new);
	return NULL;
    }

    check(db_value_type(&value) == DB_TYPE_OBJECT);
    next = DB_GET_OBJECT(&value);

    if (Tcl_FindHashEntry(pathTable, (ClientData)next))
    {
	Tcl_DStringInit(loop_uuids);
	Tcl_DStringAppendElement(loop_uuids,
				 Udb_Get_Uuid(next, NULL));
	return next;
    }

    ePtr = Tcl_CreateHashEntry(pathTable, (ClientData)next, &new);
    leaf = Scalar_Loop_Leaf(verifiedTable, pathTable, next,
			    aname, loop_uuids);
    Tcl_DeleteHashEntry(ePtr);

    if (leaf)
    {
	if (Tcl_FindHashEntry(pathTable, (char *)leaf))
	{
	    Tcl_DStringAppendElement(loop_uuids,
				     Udb_Get_Uuid(next, NULL));
	}
	return leaf;
    }

    (void) Tcl_CreateHashEntry(verifiedTable, (ClientData)object, &new);
    return NULL;
}


int
Udb_Do_Loop_Checks(Tcl_Interp *interp) 
{
    Tcl_HashEntry		*ePtr;
    Tcl_HashSearch		attributeSearch;

    if (loopTblPtr == NULL)
    {
	return TCL_OK;
    }

    /*
     * Search each loop attribute in turn
     */
    for (ePtr = Tcl_FirstHashEntry(loopTblPtr, &attributeSearch);
	 ePtr;
	 ePtr = Tcl_NextHashEntry(&attributeSearch))
    {
	Tcl_HashTable  verifiedTable;
	Tcl_HashTable  *objectTable;
	Tcl_HashSearch objectSearch;
	char	       *aname;
	DB_TYPE		atype;

	Tcl_InitHashTable(&verifiedTable, TCL_ONE_WORD_KEYS);

	aname = (char *)Tcl_GetHashKey(loopTblPtr, ePtr);
	objectTable = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);

	/*
	 * Trick: NULL object slot holds attribute type
	 */
	check((ePtr = Tcl_FindHashEntry(objectTable, NULL)) != NULL);
	atype = (DB_TYPE)Tcl_GetHashValue(ePtr);
	Tcl_DeleteHashEntry(ePtr);

	for (ePtr = Tcl_FirstHashEntry(objectTable, &objectSearch);
	     ePtr;
	     ePtr = Tcl_NextHashEntry(&objectSearch))
	{
	    DB_OBJECT		*object;
	    DB_OBJECT		*loop_leaf;
	    Tcl_DString		loop_uuids;
	    Tcl_HashTable	pathTable;
	    int			new;
	    
	    Tcl_InitHashTable(&pathTable, TCL_ONE_WORD_KEYS);

	    object = (DB_OBJECT *)Tcl_GetHashKey(objectTable, ePtr);

	    Tcl_CreateHashEntry(&pathTable, (ClientData)object, &new);

	    switch (atype)
	    {
	    case DB_TYPE_SET:
	    case DB_TYPE_SEQUENCE:
		loop_leaf = Collection_Loop_Leaf(&verifiedTable, &pathTable,
						 object, aname, &loop_uuids);
		break;
	    default:
		loop_leaf = Scalar_Loop_Leaf(&verifiedTable, &pathTable,
					     object, aname, &loop_uuids);
		break;
	    }

	    Tcl_DeleteHashTable(&pathTable);

	    if (loop_leaf)
	    {
		(void) Udb_Error(interp, "ELOOP", aname,
				 Tcl_DStringValue(&loop_uuids), (char *)NULL);
		Tcl_DStringFree(&loop_uuids);
		Tcl_DeleteHashTable(&verifiedTable);
		return TCL_ERROR;
	    }
	    Tcl_CreateHashEntry(&verifiedTable, (ClientData)object, &new);
	}
	Tcl_DeleteHashTable(&verifiedTable);
    }
    return TCL_OK;
}
