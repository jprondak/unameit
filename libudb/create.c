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
static char rcsid[] = "$Id: create.c,v 1.29.20.5 1997/09/29 00:14:30 viktor Exp $";

#include <uconfig.h>
#include <error.h>
#include <dbi.h>

#include "uuid.h"
#include "create.h"
#include "lookup.h"
#include "misc.h"
#include "init.h"
#include "convert.h"
#include "name_cache.h"
#include "relation.h"
#include "transaction.h"
#include "license.h"
#include "errcode.h"


int
Udb_Create(ClientData not_used, Tcl_Interp *interp, int argc, char *argv[])
{
    char		*cname;
    char		*uuid;
    DB_OBJECT		*class;
    DB_OBJECT		*object;
    DB_OTMPL		*template;
    DB_VALUE		value;
    int			i;
    Tcl_HashTable	relations;
    Tcl_HashTable	new_tables[NCACHE_TABLES];
    int			owner_set = FALSE;
    int			set_root = FALSE;
    char	  	*argv0 = argv[0];

    /* Skip over command name */
    ++argv, --argc;

    if (argc < 2 || argc % 2 != 0)
    {
	return Udb_Error(interp, "EUSAGE", argv0,
			 "class uuid ?attribute value? ...",
			 (char *)NULL);
    }

    cname = argv[0];
    uuid = argv[1];
    argv += 2;
    argc -= 2;

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }

    if (Udb_Over_License_Count() == TRUE)
    {
	return Udb_Error(interp, "EUNITCOUNT", uuid, (char *)NULL);
    }

    /*
     * If the class doesn't exist or is not a unameit_item, error.
     */
    if (!(class = _Udb_Get_Class(cname)) || !Udb_Is_Item_Class(class))
    {
	return Udb_Error(interp, "ENXREFCLASS", uuid, cname, (char *)NULL);
    }

    if (Udb_Class_Is_Readonly(interp, class))
    {
	return Udb_Error(interp, "EREADONLY", uuid, cname, (char *)NULL);
    }

    check(template = dbt_create_object(class));

    DB_MAKE_STRING(&value, uuid);
    check(dbt_put(template, "uuid", &value) == NOERROR);

    Tcl_InitHashTable(&relations, TCL_STRING_KEYS);

    for (i = 0; i < argc; i += 2)
    {
	int ok;

	ok = Udb_Set_Attribute(interp, uuid, class, template,
			       argv[i], argv[i+1], &relations);

	/*
	 * Owner may be NULL only for the root cell
	 */
	if (ok == TCL_OK && Equal(argv[i], "owner"))
	{
	    if (Equal(argv[i+1], ""))
	    {
		if ((Equal(cname, "cell") || Equal(cname, "role")) && 
		    Udb_Get_Root(class) == NULL)
		{
		    set_root = TRUE;
		}
		else
		{
		    ok = Udb_Error(interp, "ENULL", uuid, argv[i],
				   (char *)NULL);
		}
	    }
	    owner_set = TRUE;
	}

	/*
	 * If all attributes processed,  and still no "owner"
	 * and we are creating a data item, lose (unless owner is a Network
	 * pointer for this class).
	 */
	if (i == argc - 2 && ok == TCL_OK && owner_set == FALSE)
	{
	    if (Udb_Is_Data_Class(class) &&
		!Equal(Udb_Get_Relaction(interp, class, "owner"), "Network"))
	    {
		ok = Udb_Error(interp, "ENULL", uuid, "owner", (char *)NULL);
	    }
	}

	if (ok != TCL_OK)
	{
	    dbt_abort_object(template);
	    Udb_Free_Dynamic_Table(&relations, (Tcl_FreeProc *)db_value_free,
				   FALSE);
	    return TCL_ERROR;
	}
    }

    object = Udb_Finish_Object(class, template, FALSE);

    /*
     * Optimistically assume UUIDs of created objects are going to be new,
     * so handle exceptions here.
     */
    if (object == NULL)
    {
	switch(db_error_code())
	{
	case ER_OBJ_ATTRIBUTE_NOT_UNIQUE:
	case ER_BT_UNIQUE_FAILED:
	    Udb_Free_Dynamic_Table(&relations, (Tcl_FreeProc *)db_value_free,
				   FALSE);
	    return Udb_Error(interp, "EUSEDUUID", uuid, (char *)NULL);
	default:
	    panic("dbt_finish_object(): %s", db_error_string(1));
	    break;
	}
    }

    Udb_Populate_Caches(interp, object, new_tables);

    /*
     * This also adds object to modified cache list and any other lists
     * the object should be on.
     */
    if (Udb_Update_Caches(interp, uuid, object, NULL, new_tables) != TCL_OK)
    {
	Udb_Free_Dynamic_Table(&relations,
			       (Tcl_FreeProc *)db_value_free, FALSE);
	Udb_Force_Rollback(interp);
	return TCL_ERROR;
    }

    /*
     * If this is a root cell or role, make it so.
     */
    if (set_root == TRUE)
    {
	Udb_Set_Root(class, object);
    }

    /*
     * This will also free the hash table
     */
    if (Udb_Restore_Mode(NULL) == RESTOREDATA)
    {
	Udb_Update_Relations(interp, class, object, &relations, TRUE, TRUE);
    }
    else
    {
	Udb_Update_Relations(interp, class, object, &relations, TRUE, FALSE);
    }

    Udb_Adjust_License_Count(class, +1);

    /*
     * Mark object as an uncommitted new object.
     */
    Udb_New_Object(uuid, object);

    return TCL_OK;
}


int
Udb_Undelete(ClientData not_used, Tcl_Interp *interp, int argc, char *argv[])
{
    char		*uuid;
    DB_OBJECT		*class;
    DB_OBJECT		*object;
    DB_OTMPL		*template;
    DB_VALUE		value;
    int			i;
    Tcl_HashTable	relations;
    Tcl_HashTable	new_tables[NCACHE_TABLES];
    int			owner_set = FALSE;
    char	  	*argv0 = argv[0];

    /* Skip over command name */
    ++argv, --argc;

    if (argc < 1 || argc % 2 != 1)
    {
	return Udb_Error(interp, "EUSAGE", argv0,
			 "uuid ?attribute value? ...",
			 (char *)NULL);
    }

    uuid = argv[0];
    argv += 1;
    argc -= 1;

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }

    if (Udb_Over_License_Count() == TRUE)
    {
	return Udb_Error(interp, "EUNITCOUNT", uuid, (char *)NULL);
    }

    /*
     * Make sure object exists.
     */
    if ((object = _Udb_Find_Object(uuid)) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
    }

    /*
     * Make sure it is deleted.
     */
    if (Udb_Find_Object(uuid) != NULL)
    {
	return Udb_Error(interp, "EUSEDUUID", uuid, (char *)NULL);
    }

    check(class = db_get_class(object));
    if (Udb_Class_Is_Readonly(interp, class))
    {
	return Udb_Error(interp, "EREADONLY", uuid, Udb_Get_Class_Name(class),
			 (char *)NULL);
    }

    /*
     * Undelete a deleted object
     */
    check(template = dbt_edit_object(object));
    DB_MAKE_NULL(&value);
    check(dbt_put(template, "deleted", &value) == NOERROR);

    Tcl_InitHashTable(&relations, TCL_STRING_KEYS);

    for (i = 0; i < argc; i += 2)
    {
	int ok;

	ok = Udb_Set_Attribute(interp, uuid, class, template,
			       argv[i], argv[i+1], &relations);

	/*
	 * Owner may be NULL only for the root cell and role,  and these,
	 * should never have been deleted.
	 */
	if (ok == TCL_OK && Equal(argv[i], "owner"))
	{
	    if (Equal(argv[i+1], ""))
	    {
		ok = Udb_Error(interp, "ENULL", uuid, argv[i], (char *)NULL);
	    }
	    owner_set = TRUE;
	}

	/*
	 * If all attributes processed,  and still no "owner"
	 * and we are creating a data item, lose (unless owner is a Network
	 * pointer for this class).
	 */
	if (i == argc - 2 && ok == TCL_OK && owner_set == FALSE)
	{
	    if (Udb_Is_Data_Class(class) &&
		!Equal(Udb_Get_Relaction(interp, class, "owner"), "Network"))
	    {
		ok = Udb_Error(interp, "ENULL", uuid, "owner", (char *)NULL);
	    }
	}

	if (ok != TCL_OK)
	{
	    Udb_Free_Dynamic_Table(&relations, (Tcl_FreeProc *)db_value_free,
				   FALSE);
	    dbt_abort_object(template);
	    return TCL_ERROR;
	}
    }

    check(object == Udb_Finish_Object(class, template, FALSE));

    Udb_Populate_Caches(interp, object, new_tables);

    /*
     * This also adds object to modified cache list and any other lists
     * the object should be on.
     */
    if (Udb_Update_Caches(interp, uuid, object, NULL, new_tables) != TCL_OK)
    {
	Udb_Free_Dynamic_Table(&relations,
			       (Tcl_FreeProc *)db_value_free, FALSE);
	Udb_Force_Rollback(interp);
	return TCL_ERROR;
    }

    /*
     * This will also free the hash table
     */
    Udb_Update_Relations(interp, class, object, &relations, TRUE, FALSE);

    Udb_Adjust_License_Count(class, +1);

    /*
     * Mark object as an uncommitted new object.
     */
    Udb_New_Object(uuid, object);

    return TCL_OK;
}
