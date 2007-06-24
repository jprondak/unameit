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
static char rcsid[] = "$Id: fetch.c,v 1.26.20.3 1997/09/21 23:42:40 viktor Exp $";

/* Routines related to fetching objects from the database. */

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "fetch.h"
#include "lookup.h"
#include "uuid.h"
#include "tcl_mem.h"
#include "errcode.h"
#include "misc.h"


static int
Do_Fetch_Processing(
    Tcl_Interp *interp,
    Tcl_HashTable *streamTbl,
    DB_OBJECT *class,
    DB_OBJECT *object,
    char *uuid,
    int argc,
    char *argv[],
    int nameFields
)
{
    DB_ATTRIBUTE	*attrs;
    DB_VALUE		value;
    char		*aname;
    int			i;

    DB_MAKE_OBJECT(&value, class);
    Udb_Store_Value(streamTbl, object, NULL, &value);

    if (Udb_Find_Object(uuid) != NULL)
    {
	/*
	 * Object is not deleted
	 */
	DB_MAKE_NULL(&value);
    }
    else
    {
	/*
	 * Object is deleted
	 */
	DB_MAKE_STRING(&value, "Yes");
    }
    Udb_Store_Value(streamTbl, object, "deleted", &value);

    if (nameFields)
    {
	/*
	 * MUST be done before storing the uuid
	 */
	Udb_Delay_Fetch(streamTbl, object);
    }

    DB_MAKE_STRING(&value, uuid);
    Udb_Store_Value(streamTbl, object, "uuid", &value);

    if (argc == 0)
    {
	/*
	 * Return all fields
	 */

	attrs = Udb_Get_Attributes(class);

	for (/* noop */; attrs; attrs = db_attribute_next(attrs))
	{
	    DB_DOMAIN *domain;

	    aname = (char *)db_attribute_name(attrs);
	    domain = Udb_Attribute_Domain(class, aname);
	    /*
	     * Can't return unprintable fields
	     */
	    if (!Udb_Attribute_Is_Printable(domain))
	    {
		continue;
	    }

	    check(db_get(object, aname, &value) == NOERROR);
	    Udb_Store_Value(streamTbl, object, aname, &value);
	    db_value_clear(&value);
	}
    }
    else
    {
	for (i = 0; i < argc; i++)
	{
	    DB_DOMAIN *domain = Udb_Attribute_Domain(class, argv[i]);

	    if (domain == NULL || !Udb_Attribute_Is_Printable(domain))
	    {
		return Udb_Error(interp, "ENOATTR", uuid, argv[i],
				 (char *)NULL);
	    }
	    check(db_get(object, argv[i], &value) == NOERROR);
	    Udb_Store_Value(streamTbl, object, argv[i], &value);
	    db_value_clear(&value);
	}
    }
    return TCL_OK;
}


int
Udb_Fetch(
    ClientData data,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    Tcl_HashTable streamTbl;
    DB_OBJECT	  *class;
    DB_OBJECT	  *object;
    int 	  nameFields = FALSE;
    int		  streamFlag = FALSE;
    char	  *argv0 = argv[0];
    int		  uuid_argc;
    char 	  **uuid_argv;
    int		  result;
    int		  i;

    /* Skip over command name */
    ++argv, --argc;

    for (; argc > 0; ++argv, --argc)
    {
	if (Equal(*argv, "-nameFields"))
	{
	    nameFields = TRUE;
	}
	else if (Equal(*argv, "-stream"))
	{
	    streamFlag = TRUE;
	}
	else
	{
	    break;
	}
    }

    if (argc < 1)
    {
	return Udb_Error(interp, "EUSAGE", argv0,
			 "?-nameFields? ?-stream? "
			 "uuidlist ?args? ...", (char *)NULL);
    }

    if (Tcl_SplitList(interp, argv[0], &uuid_argc, &uuid_argv) != TCL_OK)
    {
	return TCL_ERROR;
    }
    ++argv, --argc;

    Tcl_InitHashTable(&streamTbl, TCL_ONE_WORD_KEYS);

    for (i = 0; i < uuid_argc; ++i)
    {
	char *uuid = uuid_argv[i];

	if (!Uuid_Valid(uuid))
	{
	    Udb_Delete_Stream_Table(&streamTbl);
	    (void)Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
	    ckfree((char *)uuid_argv);
	    return TCL_ERROR;
	}

	object = _Udb_Find_Object(uuid);

	if (object == NULL)
	{
	    Udb_Delete_Stream_Table(&streamTbl);
	    (void)Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
	    ckfree((char *)uuid_argv);
	    return TCL_ERROR;
	}

	check(class = db_get_class(object));

	if (Do_Fetch_Processing(interp, &streamTbl, class, object, uuid,
				argc, argv, nameFields) != TCL_OK)
	{
	    ckfree((char *)uuid_argv);
	    Udb_Delete_Stream_Table(&streamTbl);
	    return TCL_ERROR;
	}
    }
    ckfree((char *)uuid_argv);
    result = Udb_Stream_Encode(interp, &streamTbl, nameFields,
			       streamFlag, TRUE);
    Udb_Delete_Stream_Table(&streamTbl);

    /*
     * If we successfully serialized some objects,  interp->result should
     * be a non-empty string
     */
    assert(streamFlag == FALSE || interp->result[0] != '\0' ||
	   result != TCL_OK || uuid_argc == 0);

    return result;
}
