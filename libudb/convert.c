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
static char rcsid[] = "$Id: convert.c,v 1.5.20.4 1997/10/11 00:55:10 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "uuid.h"
#include "convert.h"
#include "lookup.h"
#include "transaction.h"
#include "misc.h"
#include "errcode.h"

/*
 * Conversion of data to/from string form
 */


DB_ERROR
Udb_String_To_Int32_Value(
    DB_VALUE *valPtr,
    char *input
)
{
    int		len;

    assert(input);
    assert(valPtr);

    DB_MAKE_INTEGER(valPtr, 0);

    if ((len = strlen(input)) == 0)
    {
	db_value_put_null(valPtr);
	return NOERROR;
    }
    return db_value_put(valPtr, DB_TYPE_C_CHAR, input, len);
}


int
Udb_String_To_Int32(
    Tcl_Interp *interp,
    char *input,
    DB_INT32 *intPtr
)
{
    DB_VALUE	value;

    assert(input);
    assert(intPtr);

    if (Udb_String_To_Int32_Value(&value, input) != NOERROR ||
	DB_IS_NULL(&value))
    {
	if (interp)
	{
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "expected integer but got \"",
			     input, "\"", (char *)NULL);
	}
	return TCL_ERROR;
    }
    *intPtr = DB_GET_INTEGER(&value);
    return TCL_OK;
}


void
Udb_Stringify_Value(Tcl_DString *string, DB_VALUE *value)
{
    char 		int_buf[15];
    int			col_size, i;
    DB_VALUE		col_value;
    DB_COLLECTION	*col;

    assert(string);
    assert (!DB_IS_NULL(value));

    switch (DB_VALUE_DOMAIN_TYPE(value))
    {
    case DB_TYPE_STRING:
	Tcl_DStringAppendElement(string, (char *)DB_GET_STRING(value));
	return;

    case DB_TYPE_INTEGER:
	(void) sprintf(int_buf, "%ld", (long)DB_GET_INTEGER(value));
	Tcl_DStringAppendElement(string, int_buf);
	return;

    case DB_TYPE_OBJECT:
	Tcl_DStringAppendElement(string,
		 Udb_Get_Uuid(DB_GET_OBJECT(value), NULL));
	return;

    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	Tcl_DStringStartSublist(string);
	col = DB_GET_COLLECTION(value);
	col_size = db_col_size(col);
	for(i = 0; i < col_size; ++i)
	{
	    check(db_col_get(col, i, &col_value) == NOERROR);
	    Udb_Stringify_Value(string, &col_value);
	    db_value_clear(&col_value);
	}
	Tcl_DStringEndSublist(string);
	return;

    default:
	panic("Cannot stringify type `%s'",
	      db_get_type_name(DB_VALUE_DOMAIN_TYPE(value)));
    }
}


static int
Scan_Value(
    Tcl_Interp *interp,
    char *input, 
    DB_VALUE *output,
    DB_OBJECT *class,
    char *uuid,
    char *aname,
    DB_DOMAIN *domain,
    int	*dorefint
)
{
    DB_OBJECT		*o;
    DB_TYPE		type;
    DB_COLLECTION	*col;
    DB_DOMAIN		*element_domain;
    int			input_argc;
    char		**input_argv;
    int			i;
    char		*action;

    switch (type = db_domain_type(domain))
    {
    case DB_TYPE_INTEGER:

	if (dorefint)
	    *dorefint = 0;

	if (Udb_String_To_Int32_Value(output, input) == NOERROR)
	{
	    return TCL_OK;
	}

	return Udb_Error(interp, "ENOTINT", uuid, aname, input, (char *)NULL);
	
    case DB_TYPE_STRING:

	if (dorefint)
	    *dorefint = 0;

	if (input[0] != '\0')
	{
	    DB_MAKE_STRING(output, input);
	    return TCL_OK;
	}

	if (Udb_Attr_Is_Nullable(interp, Udb_Get_Class_Name(class), aname))
	{
	    DB_MAKE_NULL(output);
	}
	else
	{
	    DB_MAKE_STRING(output, "");
	}

	return TCL_OK;
    
    case DB_TYPE_OBJECT:

	if (dorefint)
	{
	    *dorefint = 1;
	    /*
	     * Some pointers have no referential integrity!
	     */
	    action = Udb_Get_Relaction(interp, class, aname);
	    if (!Equal(action, "Block") &&
		!Equal(action, "Cascade") &&
		!Equal(action, "Nullify"))
	    {
		if (Equal(action, "Network"))
		{
		    return Udb_Error(interp, "EPROTECTED", uuid, aname,
				     (char *)NULL);
		}
		else
		{
		    panic("Bad referential integrity '%s', for '%s.%s'",
			  action, Udb_Get_Class_Name(class), aname);
		}
	    }
	}

	if (input[0] == '\0')
	{
	    DB_MAKE_OBJECT(output, (DB_OBJECT *)NULL);
	    return TCL_OK;
	}

	if (!Uuid_Valid(input))
	{
	    return
		Udb_Error(interp, "ENOTREFUUID", uuid, aname, input,
			  (char *)NULL);
	}
	o = Udb_Find_Object(input);

	if (o == NULL)
	{
	    return Udb_Error(interp, "ENXREFITEM", uuid, aname, input,
			     (char *)NULL);
	}

	if (!Udb_ISA(db_get_class(o), db_domain_class(domain)))
	{
	    return  Udb_Error(interp, "EDOMAIN", uuid, aname, input);
	}

	DB_MAKE_OBJECT(output, o);
	return TCL_OK;
	
    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:

	check(element_domain = db_domain_set(domain));

	if (Tcl_SplitList(NULL, input, &input_argc, &input_argv) != TCL_OK)
	{
	    return Udb_Error(interp, "ENOTLIST", uuid, aname, input,
			     (char *)NULL);
	}

	/*
	 * Must set even if value has no elements,  so do once
	 * for all elements,  based on element domain.
	 */
	if (db_domain_type(element_domain) == DB_TYPE_OBJECT)
	{
	    *dorefint = 1;
	    /*
	     * Some pointers have no referential integrity!
	     */
	    action = Udb_Get_Relaction(interp, class, aname);
	    if (!Equal(action, "Block") &&
		!Equal(action, "Cascade") &&
		!Equal(action, "Nullify"))
	    {
		if (Equal(action, "Network"))
		{
		    return Udb_Error(interp, "EPROTECTED", uuid, aname,
				     (char *)NULL);
		}
		else
		{
		    panic("Bad referential integrity '%s', for '%s.%s'",
			  action, Udb_Get_Class_Name(class), aname);
		}
	    }
	}
	else
	{
	    *dorefint = 0;
	}

	check(col = db_col_create(type, input_argc, domain));

	for (i = 0; i < input_argc; ++i)
	{
	    DB_VALUE	value;
	    int 	result;

	    result = Scan_Value(interp, input_argv[i], &value, class, uuid,
				aname, element_domain, NULL);

	    if (result != TCL_OK)
	    {
		ckfree((char *)input_argv);
		db_col_free(col);
		return TCL_ERROR;
	    }

	    /*
	     * Silently ignore NULL elements
	     */
	    if (!DB_IS_NULL(&value))
	    {
		check(db_col_add(col, &value) == NOERROR);
	    }
	}
	ckfree((char *)input_argv);

	DB_MAKE_COLLECTION(output, col);
	return TCL_OK;

    default:
	break;
    }
    panic("Unsupported data type class %s, attribute %s",
	  Udb_Get_Class_Name(class), aname);
    return TCL_ERROR;
}


int
Udb_Set_Attribute(
    Tcl_Interp *interp,
    char *uuid,
    DB_OBJECT *object,
    DB_OTMPL *template,
    char *aname,
    char *input,
    Tcl_HashTable *relations
)
{
    DB_OBJECT		*class;
    DB_DOMAIN		*domain;
    DB_VALUE		value;
    int			dorefint;

    assert(object);
    assert(template);
    assert(aname);

    if (Udb_Attr_Is_Protected(interp, aname))
    {
	return Udb_Error(interp, "EPROTECTED", uuid, aname, (char *)NULL);
    }

    class = db_get_class(object);

    if ((domain = Udb_Attribute_Domain(class, aname)) == NULL)
    {
	return Udb_Error(interp, "ENOATTR", uuid, aname, (char *)NULL);
    }

    if (Scan_Value(interp, input, &value, class, uuid, aname, domain,
		   &dorefint) != TCL_OK)
    {
	return TCL_ERROR;
    }

    check (dbt_put(template, aname, &value) == NOERROR);

    if (dorefint)
    {
	DB_VALUE *copy;
	Tcl_HashEntry *ePtr;
	int new;
	
	check(ePtr = Tcl_CreateHashEntry(relations, aname, &new));

	check(copy = db_value_copy(&value));
	Tcl_SetHashValue(ePtr, (ClientData)copy);

    }

    if (db_value_type_is_collection(&value))
    {
	db_col_free(DB_GET_COLLECTION(&value));
    }
    return TCL_OK;
}
