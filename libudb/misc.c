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
static char rcsid[] = "$Id: misc.c,v 1.21.16.6 1997/09/29 23:08:57 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "misc.h"
#include "lookup.h"


int
_Udb_Get_Value(
    DB_OBJECT *object,
    const char *aname,
    DB_TYPE type,
    DB_VALUE *value
)
{
    DB_TYPE value_type;

    assert(object);
    assert(aname);
    assert(value);

    switch (db_get(object, aname, value))
    {
    case NOERROR:
	if ((value_type = DB_VALUE_DOMAIN_TYPE(value)) != type
	    /* Unisql bug workaround */ && value_type != DB_TYPE_NULL)
	{
	    panic("Attribute %s of class %s is not of type %s", aname,
		  Udb_Get_Class_Name(db_get_class(object)),
		  db_get_type_name(type));
	}
	return TCL_OK;

    case ER_OBJ_INVALID_ATTRIBUTE:
	break;

    default:
	panic("db_get(%s, %s): %s", Udb_Get_Class_Name(db_get_class(object)),
	      aname, db_error_string(1));
	break;
    }
    return TCL_ERROR;
}


void
Udb_Get_Value(
    DB_OBJECT *object,
    const char *aname,
    DB_TYPE type,
    DB_VALUE *value
)
{
    check(_Udb_Get_Value(object, aname, type, value) == TCL_OK);
}


void
Udb_Get_Collection_Value(
    DB_COLLECTION *col,
    DB_INT32 index,
    DB_TYPE type,
    DB_VALUE *value
)
{
    assert(col);
    assert(value);

    if (db_col_get(col, index, value) != NOERROR)
    {
	panic("Error accessing index %u in a sequence", index);
    }

    /*
     * Check for *non-null* element value of correct type
     */
    if (DB_VALUE_TYPE(value) != type)
    {
	panic("Collection element is of type %s: expected %s",
		db_get_type_name(DB_VALUE_TYPE(value)),
		db_get_type_name(type));
    }
}


void
Udb_Add_To_Set(
    DB_COLLECTION *set,
    DB_OBJECT *elem
)
{
    DB_VALUE v;

    assert(set && db_col_type(set) == DB_TYPE_SET);
    assert(elem);

    DB_MAKE_OBJECT(&v, elem);
    check(db_set_add(set, &v) == NOERROR);
}


int
Udb_Drop_From_Set(
    DB_COLLECTION *set,
    DB_OBJECT *elem
)
{
    DB_VALUE v;

    assert(set && db_col_type(set) == DB_TYPE_SET);
    assert(elem);

    DB_MAKE_OBJECT(&v, elem);
    check(db_set_drop(set, &v) == NOERROR);

    return db_col_size(set);
}


int
Udb_Col_Equal(DB_COLLECTION *col1, DB_COLLECTION *col2)
{
    DB_VALUE v1;
    DB_VALUE v2;

    if (col1 == NULL || col2 == NULL)
    {
	return col1 == col2;
    }

    DB_MAKE_COLLECTION(&v1, col1);
    DB_MAKE_COLLECTION(&v2, col2);

    return db_value_compare(&v1, &v2) == DB_EQ;
}


DB_ERROR
Udb_Run_Query(
    const char *query,
    DB_SESSION **session,
    DB_QUERY_RESULT **cursor,
    DB_INT32 numvalues,
    DB_VALUE *vlist,
    int fatal
)
{
    STATEMENT_ID	stmt_id;
    DB_ERROR 		rowcount;

    assert(query && session && cursor);

    check(*session = db_open_buffer(query));

    if (numvalues > 0)
    {
	db_push_values(*session, numvalues, vlist);
    }
    stmt_id = db_compile_statement(*session);

    if (fatal)
    {
	check(stmt_id >= 0);
    }
    else if (stmt_id < 0)
    {
	return -1;
    }

    rowcount = db_execute_statement(*session, stmt_id, cursor);
    check(rowcount >= 0);
    return rowcount;
}
