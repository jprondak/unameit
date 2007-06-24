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
/* $Id: misc.h,v 1.11.16.4 1997/09/29 23:08:58 viktor Exp $ */
#ifndef _MISC_H
#define _MISC_H
#include <dbi.h>
#include <tcl.h>

/*
 * Gets the value of a certain field of an object. If the field exists
 * it must be of the appropriate type or a fatal error occurs.
 * Returns TCL_OK on success, TCL_ERROR on failure.
 */
extern int
_Udb_Get_Value(
    DB_OBJECT *object,
    const char *aname,
    DB_TYPE type,
    DB_VALUE *value
);

/*
 * Gets the value of a certain field of an object. The field must exist
 * and be of the appropriate type or a fatal error occurs.
 */
extern void
Udb_Get_Value(
    DB_OBJECT *object,
    const char *aname,
    DB_TYPE type,
    DB_VALUE *value
);

/*
 * This routine gets the value of the collection at the index and stores it
 * in value. The type of value retrieved must be "type" (non-null!).
 */
extern void Udb_Get_Collection_Value(
    DB_COLLECTION *coll,
    DB_INT32 index,
    DB_TYPE type,
    DB_VALUE *value
);

/*
 * Add an object to a set of objects.
 */
extern void Udb_Add_To_Set(DB_COLLECTION *set, DB_OBJECT *elem);

/*
 * Drop an object from a set of objects,  returns new size of set.
 */
extern int Udb_Drop_From_Set(DB_COLLECTION *set, DB_OBJECT *elem);

/*
 * Compare two collections for equality
 */
extern int Udb_Col_Equal(DB_COLLECTION *col1, DB_COLLECTION *col2);

/*
 * Run a query,  and return the rowcount,
 * also fill in the session and query handles 
 */
extern DB_ERROR Udb_Run_Query(
    const char *query,
    DB_SESSION **session,
    DB_QUERY_RESULT **cursor,
    DB_INT32 numvalues,
    DB_VALUE *vlist,
    int fatal
);

#endif
