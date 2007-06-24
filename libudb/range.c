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
static char rcsid[] = "$Id: range.c,v 1.28.4.6 1997/09/29 23:09:00 viktor Exp $";

/*
 * This file contains routines related to ranges
 * (uniqueness and auto-generation).
 */

#include <uconfig.h>
#include <dbi.h>

#include "range.h"
#include "uuid.h"
#include "lookup.h"
#include "convert.h"
#include "misc.h"
#include "transaction.h"
#include "errcode.h"


static void
New_Block(
    DB_COLLECTION *col,
    DB_INT32 index,
    DB_INT32 start,
    DB_INT32 end
)
{
    DB_OBJECT	*block_class;
    DB_OTMPL	*template;
    DB_VALUE	value;
    DB_OBJECT	*block;

    assert(col);
    assert(0 <= index && index <= db_col_size(col));
    
    check(block_class = Udb_Get_Class("unameit_range_block"));
    template = Udb_Edit_Free_Object(block_class);

    DB_MAKE_INTEGER(&value, start);
    check(dbt_put(template, "range_start", &value) == NOERROR);

    DB_MAKE_INTEGER(&value, end);
    check(dbt_put(template, "range_end", &value) == NOERROR);

    check(block = Udb_Finish_Object(NULL, template, FALSE));

    DB_MAKE_OBJECT(&value, block);
    check(db_col_insert(col, index, &value) == NOERROR);
}


static void
Get_Bounds(
    DB_COLLECTION *col,
    DB_INT32 index,
    DB_OBJECT **block,
    DB_INT32 *start,
    DB_INT32 *end
)
{
    DB_VALUE	value;

    assert(col);
    assert(block);
    assert(start);
    assert(end);

    Udb_Get_Collection_Value(col, index, DB_TYPE_OBJECT, &value);
    check(!DB_IS_NULL(&value));
    *block = DB_GET_OBJECT(&value);

    Udb_Get_Value(*block, "range_start", DB_TYPE_INTEGER, &value);
    check(!DB_IS_NULL(&value));
    *start = DB_GET_INTEGER(&value);

    Udb_Get_Value(*block, "range_end", DB_TYPE_INTEGER, &value);
    check(!DB_IS_NULL(&value));
    *end = DB_GET_INTEGER(&value);
}


static void
Add_Used(
    DB_OBJECT *owner,
    char *aname,
    DB_INT32  ival,
    DB_OBJECT *slot
)
{
    Tcl_DString		dstr;
    DB_VALUE		value;
    DB_OBJECT		*block_class;
    DB_OBJECT		*range_class;
    /*
     * Range object
     */
    DB_OBJECT		*range;
    /*
     * Sequence of range blocks
     */
    DB_COLLECTION	*col;
    /*
     * Properties of first block in half interval search
     */
    DB_INT32		first;
    DB_OBJECT		*first_block;
    DB_INT32		start;
    DB_INT32		left;
    /*
     * Properties of last block in half interval search
     */
    DB_INT32		last;
    DB_OBJECT		*last_block;
    DB_INT32		right;
    DB_INT32		end;

    assert(owner);
    assert(aname);
    assert(slot);

    block_class = Udb_Get_Class("unameit_range_block");

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, "range/", -1);
    Tcl_DStringAppend(&dstr, aname, -1);
    Tcl_DStringAppend(&dstr, "/used", -1);

    range_class = Udb_Get_Class(Tcl_DStringValue(&dstr));
    Tcl_DStringFree(&dstr);

    DB_MAKE_OBJECT(&value, owner);

    range = db_find_unique(range_class, "range_owner", &value);

    if (range == NULL)
    {
	DB_OTMPL	*template;
	/*
	 * Creating new range sequence for given `owner'
	 */
	template = Udb_Edit_Free_Object(range_class);
	check(dbt_put(template, "range_owner", &value) == NOERROR);

	check(col = db_col_create(DB_TYPE_SEQUENCE, 1, NULL));
	New_Block(col, 0, ival, ival);

	DB_MAKE_COLLECTION(&value, col);
	check(dbt_put(template, "range_blocks", &value) == NOERROR);

	check(range = Udb_Finish_Object(NULL, template, FALSE));
	db_col_free(col);
	return;
    }

    Udb_Get_Value(range, "range_blocks", DB_TYPE_SEQUENCE, &value);

    check(col = DB_GET_COLLECTION(&value));

    first = 0;
    last = first + db_col_size(col) - 1;
    assert(last >= first);

    /*
     * Fetch first and last blocks
     */
    Get_Bounds(col, last, &last_block, &right, &end);

    if (ival == end + 1)
    {
	/*
	 *  Extend existing block
	 */
	DB_MAKE_INTEGER(&value, ival);
	check(db_put(last_block, "range_end", &value) == NOERROR);
	db_col_free(col);
	return;
    }

    if (ival > end)
    {
	/*
	 * Add new block
	 */
	New_Block(col, last+1, ival, ival);
	db_col_free(col);
	return;
    }

    Get_Bounds(col, first, &first_block, &start, &left);

    if (ival == start - 1)
    {
	/*
	 *  Extend existing block
	 */
	DB_MAKE_INTEGER(&value, ival);
	check(db_put(first_block, "range_start", &value) == NOERROR);
	db_col_free(col);
	return;
    }

    if (ival < start)
    {
	/*
	 * Add new block
	 */
	New_Block(col, first, ival, ival);
	db_col_free(col);
	return;
    }

    for (;;)
    {
	DB_INT32	mid;
	DB_OBJECT	*mid_block;
	DB_INT32	mid_start;
	DB_INT32	mid_end;
	/*
	 * ival is in newly created slot,  so it cannot (yet) be in any block
	 */
	assert(ival < right);
	assert(ival > left);

	if (ival == right - 1)
	{
	    /*
	     *  Extend existing block or merge
	     */
	    if (first != last - 1)
	    {
		Get_Bounds(col, last-1, &first_block, &start, &left);
	    }
	    if (ival > left + 1)
	    {
		DB_MAKE_INTEGER(&value, ival);
		check(db_put(last_block, "range_start", &value) == NOERROR);
	    }
	    else
	    {
		check(db_col_drop_element(col, last-1) == NOERROR);
		Udb_Append_Free_List(block_class,
				     dbt_edit_object(first_block), NULL);
		DB_MAKE_INTEGER(&value, start);
		check(db_put(last_block, "range_start", &value) == NOERROR);
	    }
	    db_col_free(col);
	    return;
	}
	else if (ival == left + 1)
	{
	    /*
	     *  Extend existing block or merge
	     */
	    if (last != first + 1)
	    {
		Get_Bounds(col, first+1, &last_block, &right, &end);
	    }
	    if (ival < right - 1)
	    {
		DB_MAKE_INTEGER(&value, ival);
		check(db_put(first_block, "range_end", &value) == NOERROR);
	    }
	    else
	    {
		check(db_col_drop_element(col, first+1) == NOERROR);
		Udb_Append_Free_List(block_class,
				     dbt_edit_object(last_block), NULL);
		DB_MAKE_INTEGER(&value, end);
		check(db_put(first_block, "range_end", &value) == NOERROR);
	    }
	    db_col_free(col);
	    return;
	}

	mid = (first + last) / 2; 

	if (mid == first)
	{
	    /*
	     * Add new block between first and last
	     */
	    New_Block(col, last, ival, ival);
	    db_col_free(col);
	    return;
	}

	/*
	 * ival lies strictly between the blocks, and extends neither,
	 * narrow to half interval.
	 */
	Get_Bounds(col, mid, &mid_block, &mid_start, &mid_end);

	if (ival < mid_start)
	{
	    last = mid;
	    last_block = mid_block;
	    right = mid_start;
	}
	else if (ival > mid_end)
	{
	    first = mid;
	    first_block = mid_block;
	    left = mid_end;
	}
	else
	{
	    panic("Corrupted range block sequence");
	}
    }
}


void
Udb_Add_Range_Entry(
    DB_OBJECT *owner,
    char *aname,
    DB_INT32 ival,
    DB_OBJECT *object
)
{
    Tcl_DString		dstr;
    DB_VALUE		value;
    DB_OBJECT		*slot_class;
    DB_OBJECT		*slot;
    DB_COLLECTION	*col;
    DB_OTMPL		*template;

    assert(owner);
    assert(aname);
    assert(object);

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, "range/", -1);
    Tcl_DStringAppend(&dstr, aname, -1);
    Tcl_DStringAppend(&dstr, "/slot", -1);

    slot_class = Udb_Get_Class(Tcl_DStringValue(&dstr));

    Tcl_DStringSetLength(&dstr, 0);

    DB_MAKE_INTEGER(&value, ival);
    Udb_Stringify_Value(&dstr, &value);

    DB_MAKE_OBJECT(&value, owner);
    Udb_Stringify_Value(&dstr, &value);

    DB_MAKE_STRING(&value, Tcl_DStringValue(&dstr));

    if ((slot = db_find_unique(slot_class, "range_key", &value)) != NULL)
    {
	/*
	 * Add an element to an existing slot.
	 */
	Udb_Get_Value(slot, "range_items", DB_TYPE_SET, &value);
	Udb_Add_To_Set(DB_GET_COLLECTION(&value), object);
	db_value_clear(&value);

	return;
    }

    /*
     * Creating new slot,  will need to update `used' sequence.
     */
    template = Udb_Edit_Free_Object(slot_class);
    check(dbt_put(template, "range_key", &value) == NOERROR);

    check (col = db_col_create(DB_TYPE_SET, 1, NULL));
    Udb_Add_To_Set(col, object);

    DB_MAKE_COLLECTION(&value, col);
    check(dbt_put(template, "range_items", &value) == NOERROR);
    db_col_free(col);
    check(slot = Udb_Finish_Object(NULL, template, FALSE));

    Add_Used(owner, aname, ival, slot);
}


static void
Del_From_Range(
    DB_OBJECT *range_class,
    DB_OBJECT *range,
    DB_COLLECTION *col,
    DB_INT32 index,
    DB_OBJECT *block,
    DB_INT32 start,
    DB_INT32 end,
    DB_INT32 ival
)
{
    DB_VALUE	value;

    assert(col);
    assert(block);
    assert(index >= 0);

    assert(ival >= start);
    assert(ival <= end);

    if (ival == start)
    {
	if (ival == end)
	{
	    DB_OBJECT *block_class = db_get_class(block);

	    check(db_col_drop_element(col, index) == NOERROR);
	    Udb_Append_Free_List(block_class, dbt_edit_object(block), NULL);
	    if (db_col_size(col) == 0)
	    {
		Udb_Append_Free_List(range_class,
				     dbt_edit_object(range), "range_owner");
		return;
	    }
	    return;
	}
	DB_MAKE_INTEGER(&value, start + 1);
	check(db_put(block, "range_start", &value) == NOERROR);
	return;
    }

    DB_MAKE_INTEGER(&value, ival - 1);
    check(db_put(block, "range_end", &value) == NOERROR);

    if (ival < end)
    {
	New_Block(col, index+1, ival+1, end);
    }
}


static void
Del_Used(
    DB_OBJECT *owner,
    char *aname,
    DB_INT32  ival
)
{
    Tcl_DString		dstr;
    DB_OBJECT		*range_class;
    DB_OBJECT		*range;
    DB_VALUE		value;
    DB_COLLECTION	*col;
    DB_INT32		first;
    DB_INT32		last;
    DB_OBJECT		*block;
    DB_INT32		start;
    DB_INT32		end;

    assert(owner);
    assert(aname);

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, "range/", -1);
    Tcl_DStringAppend(&dstr, aname, -1);
    Tcl_DStringAppend(&dstr, "/used", -1);

    range_class = Udb_Get_Class(Tcl_DStringValue(&dstr));
    Tcl_DStringFree(&dstr);

    DB_MAKE_OBJECT(&value, owner);

    check(range = db_find_unique(range_class, "range_owner", &value));

    Udb_Get_Value(range, "range_blocks", DB_TYPE_SEQUENCE, &value);

    check(col = DB_GET_COLLECTION(&value));

    first = 0;
    last = first + db_col_size(col) - 1;
    assert(last >= first);

    /*
     * Fetch first and last blocks
     */
    Get_Bounds(col, last, &block, &start, &end);

    if (ival >= start)
    {
	Del_From_Range(range_class, range, col, last, block,
		       start, end, ival);
	db_col_free(col);
	return;
    }

    Get_Bounds(col, first, &block, &start, &end);

    if (ival <= end)
    {
	Del_From_Range(range_class, range, col, first, block,
		       start, end, ival);
	db_col_free(col);
	return;
    }

    for (;;)
    {
	DB_INT32	mid;
	/*
	 * ival lies strictly between the blocks, narrow to half interval.
	 */
	mid = (first + last) / 2; 
	assert(mid > first);

	Get_Bounds(col, mid, &block, &start, &end);

	if (ival < start)
	{
	    last = mid;
	}
	else if (ival > end)
	{
	    first = mid;
	}
	else
	{
	    Del_From_Range(range_class, range, col, mid, block,
			   start, end, ival);
	    db_col_free(col);
	    return;
	}
    }
}


void
Udb_Delete_Range_Entry(
    DB_OBJECT *owner,
    char *aname,
    DB_INT32 ival,
    DB_OBJECT *object
)
{
    Tcl_DString		dstr;
    DB_VALUE		value;
    DB_OBJECT		*slot_class;
    DB_OBJECT		*slot;

    assert(owner);
    assert(aname);
    assert(object);

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, "range/", -1);
    Tcl_DStringAppend(&dstr, aname, -1);
    Tcl_DStringAppend(&dstr, "/slot", -1);

    slot_class = Udb_Get_Class(Tcl_DStringValue(&dstr));

    Tcl_DStringSetLength(&dstr, 0);

    DB_MAKE_INTEGER(&value, ival);
    Udb_Stringify_Value(&dstr, &value);

    DB_MAKE_OBJECT(&value, owner);
    Udb_Stringify_Value(&dstr, &value);

    DB_MAKE_STRING(&value, Tcl_DStringValue(&dstr));

    /*
     * Delete element from slot.
     */
    check (slot = db_find_unique(slot_class, "range_key", &value));
    Udb_Get_Value(slot, "range_items", DB_TYPE_SET, &value);

    if (Udb_Drop_From_Set(DB_GET_COLLECTION(&value), object) == 0)
    {
	Del_Used(owner, aname, ival);
	Udb_Append_Free_List(slot_class, dbt_edit_object(slot), "range_key");
    }
    db_value_clear(&value);
    return;
}


int
Udb_Auto_Integer(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_DString		dstr;
    DB_VALUE		value;
    char		*owner_uuid;
    char		*uuid;
    DB_OBJECT		*owner;
    char		*level;
    DB_OBJECT   	*promoted_owner;
    DB_OBJECT		*range_class;
    DB_OBJECT		*range = NULL;
    char		*aname;
    DB_INT32		min_free;
    DB_COLLECTION	*range_blocks = NULL;
    DB_INT32		range_count = 0;
    DB_INT32		i;

    assert(interp);
    assert(argc > 0);
    assert(argv);

    if (argc != 5)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "uuid owner attribute min",
			 (char *)NULL);
    }

    uuid = argv[1];
    owner_uuid = argv[2];
    aname = argv[3];

    if (Udb_String_To_Int32(interp, argv[4], &min_free) != TCL_OK)
    {
	return TCL_ERROR;
    }

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }

    if (!Uuid_Valid(owner_uuid))
    {
	return Udb_Error(interp, "ENOTUUID", owner_uuid, (char *)NULL);
    }

    if (!(owner = Udb_Find_Object(owner_uuid)))
    {
	return Udb_Error(interp, "ENXITEM", owner_uuid, (char *)NULL);
    }

    /*
     * Determine the autogeneration level for this attribute
     */
    level = Tcl_GetVar2(interp, "UNAMEIT_AUTO_LEVEL", aname, TCL_GLOBAL_ONLY);

    if(level == NULL)
    {
	return Udb_Error(interp, "ENOTAUTOINT", uuid, aname, (char *)NULL);
    }

    /*
     * Promote owner per above level
     */
    check(promoted_owner = Udb_Get_Promoted_Owner(interp, owner, level));

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, "range/", -1);
    Tcl_DStringAppend(&dstr, aname, -1);
    Tcl_DStringAppend(&dstr, "/used", -1);

    range_class = Udb_Get_Class(Tcl_DStringValue(&dstr));
    Tcl_DStringFree(&dstr);

    DB_MAKE_OBJECT(&value, promoted_owner);
    range = db_find_unique(range_class, "range_owner", &value);

    if (range == NULL)
    {
	/*
	 * First time for this owner,  min_free is available!
	 */
	sprintf(interp->result, "%ld", (long)min_free);
	return TCL_OK;
    }

    /*
     * Fetch range block sequence
     */
    Udb_Get_Value(range, "range_blocks", DB_TYPE_SEQUENCE, &value);
    range_blocks = DB_GET_COLLECTION(&value);
    range_count = db_col_size(range_blocks);

    for (i = 0; i < range_count; ++i)
    {
	DB_OBJECT	*range_block;
	DB_INT32	range_start;
	DB_INT32	range_end;

	Get_Bounds(range_blocks, i, &range_block, &range_start, &range_end);
	if (min_free > range_end + 1)
	{
	    /*
	     * This block is below min
	     */
	    continue;
	}
	if (min_free < range_start)
	{
	    /*
	     * min_free is unused
	     */
	    break;
	}
	min_free = range_end + 1;
    }
    db_col_free(range_blocks);

    sprintf(interp->result, "%ld", (long)min_free);

    return TCL_OK;
}
