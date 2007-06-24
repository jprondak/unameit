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
static char rcsid[] = "$Id: errcode.c,v 1.26.18.4 1997/10/09 01:10:28 viktor Exp $";

#include <stdarg.h>
#include <uconfig.h>
#include <dbi.h>

#include "errcode.h"
#include "lookup.h"
#include "misc.h"
#include "convert.h"

int
Udb_Error(Tcl_Interp *interp, const char *code, ...)
{
    va_list 	ap;
    char	*s;

    assert(code);

    Tcl_SetErrorCode(interp, "UNAMEIT", code, (char *)NULL);

    va_start(ap, code);
    while ((s = va_arg(ap, char *)) != NULL)
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}

int
Udb_EREFINTEGRITY(Tcl_Interp *interp, const char *ecode)
{
    assert(interp);
    assert(ecode);

    Tcl_SetResult(interp, "Dangling references to deleted item", TCL_STATIC);
    Tcl_SetErrorCode(interp, "UNAMEIT", "EREFINTEGRITY", (char *)NULL);

    Tcl_SetVar2(interp, "errorCode", NULL, " ",
		TCL_APPEND_VALUE|TCL_GLOBAL_ONLY);
    Tcl_SetVar2(interp, "errorCode", NULL, (char *)ecode,
		TCL_APPEND_VALUE|TCL_GLOBAL_ONLY);
    return TCL_ERROR;
}

static void
Construct_Uuid_Attr_List(
    Tcl_Interp *interp,
    DB_OBJECT *cache_class,
    DB_COLLECTION *items,
    int item_count,
    Tcl_DString *list
)
{
    int 	i;

    DB_VALUE	obj_value;
    DB_OBJECT	*obj;
    DB_OBJECT	*obj_class;

    Tcl_DString	dstr;
    char	*attr_list;

    assert(cache_class);
    assert(db_is_class(cache_class));
    assert(items);
    assert(item_count >= 0);
    assert(list);

    for (i = 0; i < item_count; i++)
    {
	Udb_Get_Collection_Value(items, i, DB_TYPE_OBJECT, &obj_value);
	obj = DB_GET_OBJECT(&obj_value);

	Tcl_DStringAppendElement(list, Udb_Get_Uuid(obj, NULL));

	obj_class = db_get_class(obj);

	Tcl_DStringInit(&dstr);
	Tcl_DStringAppend(&dstr, (char *)db_get_class_name(obj_class), -1);
	Tcl_DStringAppend(&dstr, ".", -1);
	Tcl_DStringAppend(&dstr, (char *)db_get_class_name(cache_class), -1);

	check(attr_list = Tcl_GetVar2(interp, "UNAMEIT_COLLISION_ATTRS",
				Tcl_DStringValue(&dstr), TCL_GLOBAL_ONLY));
	Tcl_DStringFree(&dstr);

	Tcl_DStringStartSublist(list);
	Tcl_DStringAppend(list, attr_list, -1);
	Tcl_DStringEndSublist(list);
    }
}


int
Udb_EDIRECTUNIQ(
    Tcl_Interp *interp,
    DB_OBJECT *cache_class,
    DB_COLLECTION *items,
    int item_count
)
{
    Tcl_DString uuid_attr_list;

    assert(interp);
    assert(cache_class);
    assert(items);
    assert(item_count > 1);

    Tcl_DStringInit(&uuid_attr_list);
    Tcl_DStringAppendElement(&uuid_attr_list, "UNAMEIT");
    Tcl_DStringAppendElement(&uuid_attr_list, "EDIRECTUNIQ");
    Construct_Uuid_Attr_List(interp, cache_class, items, item_count,
			     &uuid_attr_list);

    /*
     * We have to use Tcl_SetErrorCode first or Tcl_SetResult will clear the
     * errorCode and the Tcl_SetVar below won't work.
     */
    Tcl_SetErrorCode(interp, (char *)NULL);
    Tcl_SetResult(interp, "Uniqueness violation", TCL_STATIC);
    Tcl_SetVar(interp, "errorCode", Tcl_DStringValue(&uuid_attr_list),
	       TCL_GLOBAL_ONLY);

    Tcl_DStringFree(&uuid_attr_list);

    return TCL_ERROR;
}


int
Udb_EINDIRUNIQ(
    Tcl_Interp *interp,
    DB_OBJECT *cache_class,
    DB_COLLECTION *globals,
    DB_COLLECTION *locals,
    int     local_count
)
{
    Tcl_DString	uuid_attr_list;

    assert(interp);
    assert(cache_class);
    assert(globals);
    assert(locals);
    assert(local_count >= 1);

    Tcl_DStringInit(&uuid_attr_list);
    Tcl_DStringAppendElement(&uuid_attr_list, "UNAMEIT");
    Tcl_DStringAppendElement(&uuid_attr_list, "EINDIRUNIQ");
    Construct_Uuid_Attr_List(interp, cache_class, globals, 1, &uuid_attr_list);
    Construct_Uuid_Attr_List(interp, cache_class, locals, local_count,
			     &uuid_attr_list);

    Tcl_SetErrorCode(interp, (char *)NULL);
    Tcl_SetResult(interp, "Uniqueness violation", TCL_STATIC);
    Tcl_SetVar(interp, "errorCode", Tcl_DStringValue(&uuid_attr_list),
	       TCL_GLOBAL_ONLY);

    Tcl_DStringFree(&uuid_attr_list);

    return TCL_ERROR;
}

int
Udb_EROWCOUNT(Tcl_Interp *interp, int rowcount, int maxcount)
{
    char ibuf1[64];
    char ibuf2[64];

    assert(interp);
    assert(rowcount > 0);
    assert(rowcount > maxcount);

    sprintf(ibuf1, "%d", rowcount);
    sprintf(ibuf2, "%d", maxcount);

    Tcl_SetErrorCode(interp, "UNAMEIT", "EROWCOUNT", ibuf1, ibuf2,
	(char *)NULL);
    return TCL_ERROR;
}
