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
static char rcsid[] = "$Id: dump.c,v 1.21.20.4 1997/10/11 00:55:11 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "lookup.h"
#include "dump.h"
#include "errcode.h"
#include "misc.h"
#include "uuid.h"


static void
Decode_Value(Tcl_DString *dstr, DB_VALUE *value)
{
    DB_VALUE		elem_value;
    DB_COLLECTION	*col;
    int			col_size;
    char		ibuf[16];
    int			i;

    if (DB_IS_NULL(value))
    {
	Tcl_DStringAppendElement(dstr, "");
	return;
    }

    switch (DB_VALUE_DOMAIN_TYPE(value))
    {
    case DB_TYPE_STRING:
	Tcl_DStringAppendElement(dstr, (char *)DB_GET_STRING(value));
	return;
    case DB_TYPE_INTEGER:
	(void)sprintf(ibuf, "%ld", (long)DB_GET_INTEGER(value));
	Tcl_DStringAppendElement(dstr, ibuf);
	return;
    case DB_TYPE_OBJECT:
	Tcl_DStringAppendElement(dstr,
				 Udb_Get_Oid(DB_GET_OBJECT(value), NULL));
	return;
    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	col = DB_GET_COLLECTION(value);
	col_size = db_col_size(col);
	Tcl_DStringStartSublist(dstr);
	for (i = 0; i < col_size; ++i)
	{
	    check(db_col_get(col, i, &elem_value) == NOERROR);
	    Decode_Value(dstr, &elem_value);
	    db_value_clear(&elem_value);
	}
	Tcl_DStringEndSublist(dstr);
	return;
    default:
	panic("Unsupported data type: %d", DB_VALUE_DOMAIN_TYPE(value));
    }
}


static int
Dump_Object(
    Tcl_Interp *interp,
    Tcl_Channel output,
    DB_QUERY_RESULT *cursor,
    char *uuid,
    DB_OBJECT *object,
    int argc
)
{
    int			i;
    Tcl_DString		buf;
    int			want;
    int			got;

    Tcl_DStringInit(&buf);

    Tcl_DStringAppendElement(&buf, Udb_Get_Oid(object, NULL));
    Tcl_DStringAppendElement(&buf, uuid);

    if (argc != 0)
    {
	Tcl_DStringStartSublist(&buf);

	for(i = 0; i < argc; ++i)
	{
	    DB_VALUE	value;
	    check(db_query_get_tuple_value(cursor, i+2, &value) == NOERROR);
	    Decode_Value(&buf, &value);
	    db_value_clear(&value);
	}

	Tcl_DStringEndSublist(&buf);
    }

    Tcl_DStringAppend(&buf, "\n", -1);

    want = Tcl_DStringLength(&buf);
    got = Tcl_Write(output, Tcl_DStringValue(&buf), want);
    Tcl_DStringFree(&buf);

    if (want != got)
    {
	Tcl_AppendResult(interp, "Write to output file failed",
			 Tcl_PosixError(interp), (char *)NULL);
	return TCL_ERROR;
    }
    return TCL_OK;
}


static int
Decode_Channel(Tcl_Interp *interp, char *name, Tcl_Channel *chan)
{
    int		mode;

    *chan = Tcl_GetChannel(interp, name, &mode);

    if (*chan == (Tcl_Channel) NULL)
    {
        return TCL_ERROR;
    }

    if ((mode & TCL_WRITABLE) == 0)
    {
        Tcl_AppendResult(interp, "channel \"", name,
                "\" wasn't opened for writing", (char *) NULL);
        return TCL_ERROR;
    }

    return TCL_OK;
}


static int
Dump_Rows(
    Tcl_Interp *interp,
    Tcl_Channel output,
    DB_SESSION *session,
    DB_QUERY_RESULT *cursor,
    DB_ERROR rows,
    int argc
)
{
    DB_INT32	cursor_result;
    DB_INT32	count = 0;
    int		result = TCL_OK;

    for (cursor_result = db_query_first_tuple(cursor);
	 cursor_result == DB_CURSOR_SUCCESS;
	 cursor_result = db_query_next_tuple(cursor))
    {
	DB_VALUE	value;
	DB_OBJECT	*object;
	char		*uuid;

	check(db_query_get_tuple_value(cursor, 0, &value) == NOERROR);
	check(DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_OBJECT);
	check(object = DB_GET_OBJECT(&value));

	check(db_query_get_tuple_value(cursor, 1, &value) == NOERROR);
	check(DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_STRING);
	check(uuid = DB_GET_STRING(&value));

	result = Dump_Object(interp, output, cursor, uuid, object, argc);
	if (result != TCL_OK)
	{
	    break;
	}
	++count;
	db_value_clear(&value);
    }
    check(cursor_result == DB_CURSOR_END && rows == count);

    db_query_end(cursor);
    db_close_session(session);

    if (result == TCL_OK)
    {
	Tcl_ResetResult(interp);
	sprintf(interp->result, "%d", rows);
    }
    return result;
}


int  
Udb_Dump_Class(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_Channel		output;
    char		*cname;
    DB_OBJECT		*class;
    DB_SESSION		*session;
    DB_QUERY_RESULT	*cursor;
    DB_ERROR		rows;
    Tcl_DString		query;
    int			i;

    assert(interp && argc > 0 && argv);

    if (argc < 4)
    {
	return Udb_Error(interp, "EUSAGE", argv[0],
			 "file class attribute ?attribute ...?", (char *)NULL);
    }
    if (Decode_Channel(interp, argv[1], &output) != TCL_OK)
    {
        return TCL_ERROR;
    }
    if ((class = _Udb_Get_Class(cname = argv[2])) == NULL)
    {
	return Udb_Error(interp, "ENXCLASS", cname, (char *)NULL);
    }
    argv += 3; argc -= 3;

    Tcl_DStringInit(&query);
    Tcl_DStringAppend(&query, "select x, x.uuid", -1);

    for (i = 0; i < argc; ++i)
    {
	if (Udb_Attribute_Domain(class, argv[i]) == NULL)
	{
	    (void) Udb_Error(interp, "ENOATTR", cname, argv[i], (char *)NULL);
	    Tcl_DStringFree(&query);
	    return TCL_ERROR;
	}

	Tcl_DStringAppend(&query, ", \"", -1);
	Tcl_DStringAppend(&query, argv[i], -1);
	Tcl_DStringAppend(&query, "\"", -1);
    }

    Tcl_DStringAppend(&query, " from \"", -1);
    Tcl_DStringAppend(&query, cname, -1);
    Tcl_DStringAppend(&query, "\" x where x.\"deleted\" IS NULL", -1);

    rows = Udb_Run_Query(Tcl_DStringValue(&query), &session, &cursor,
			 0, NULL, 1);
    Tcl_DStringFree(&query);
    return Dump_Rows(interp, output, session, cursor, rows, argc);
}


int  
Udb_Dump_Protected(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_Channel		output;
    char		*cname;
    DB_SESSION		*session;
    DB_QUERY_RESULT	*cursor;
    DB_ERROR		rows;
    Tcl_DString		query;

    assert(interp && argc > 0 && argv);

    if (argc != 3)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "file class",
			 (char *)NULL);
    }
    if (Decode_Channel(interp, argv[1], &output) != TCL_OK)
    {
	return TCL_ERROR;
    }
    if (_Udb_Get_Class(cname = argv[2]) == NULL)
    {
	return Udb_Error(interp, "ENXCLASS", cname, (char *)NULL);
    }

    Tcl_DStringInit(&query);
    Tcl_DStringAppend(&query, "select x, item[x].uuid ", -1);
    Tcl_DStringAppend(&query, "from unameit_protected_item, all \"", -1);
    Tcl_DStringAppend(&query, cname, -1);
    Tcl_DStringAppend(&query, "\" x where x.\"deleted\" IS NULL", -1);

    rows = Udb_Run_Query(Tcl_DStringValue(&query), &session, &cursor,
			 0, NULL, 1);
    Tcl_DStringFree(&query);
    return Dump_Rows(interp, output, session, cursor, rows, 0);
}


int
Udb_OidCmd(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT *object;

    if (argc != 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "uuid", (char *)NULL);
    }

    if (!Uuid_Valid(argv[1]))
    {
	return Udb_Error(interp, "ENOTUUID", argv[1], (char *)NULL);
    }

    if ((object = Udb_Find_Object(argv[1])) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", argv[1], (char *)NULL);
    }

    Udb_Get_Oid(object, interp->result);

    return TCL_OK;
}
