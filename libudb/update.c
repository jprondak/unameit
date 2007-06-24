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
static char rcsid[] = "$Id: update.c,v 1.36.20.5 1997/09/29 00:14:39 viktor Exp $";

/* Routines related to object update in the database. */

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "uuid.h"
#include "update.h"
#include "lookup.h"
#include "misc.h"
#include "init.h"
#include "convert.h"
#include "name_cache.h"
#include "relation.h"
#include "transaction.h"
#include "errcode.h"


static int
Check_Owner(Tcl_Interp *interp, char *uuid, DB_OBJECT *object, char *owner)
{
    DB_OBJECT *oldCell = Udb_Get_Cell(interp, object, NULL, FALSE);
    DB_OBJECT *newOwner;
    DB_OBJECT *newCell;

    if (Equal(owner, ""))
    {
	return Udb_Error(interp, "ENULL", uuid, "owner", owner, (char *)NULL);
    }

    if (object == oldCell /* object IS A cell */)
    {
	/*
	 * Cell owner is unconstrained
	 */
	return TCL_OK;
    }

    check(newOwner = Udb_Find_Object(owner));
    newCell = Udb_Get_Cell(interp, newOwner, object, FALSE);

    /*
     * Objects may not be moved to another cell.
     * Clone/delete if necessary!
     */
    if (newCell != oldCell)
    {
	return Udb_Error(interp, "ECELLMOVE", uuid, "owner", owner, (char *)NULL);
    }
    return TCL_OK;
}


static int
Check_Organization(
    Tcl_Interp *interp,
    char *uuid,
    DB_OBJECT *object,
    char *org
)
{
    DB_OBJECT *oldOrg = Udb_Get_Cell(interp, object, NULL, TRUE);
    DB_OBJECT *newOrg;

    if (Equal(org, ""))
    {
	newOrg = object;
    }
    else
    {
	check(newOrg = Udb_Find_Object(org));
    }

    /*
     * Cells may not be moved to another organization.
     * Restore if necessary!
     */
    if (newOrg != oldOrg)
    {
	return Udb_Error(interp, "EORGMOVE", uuid, "cellorg", org,
			 (char *)NULL);
    }
    return TCL_OK;
}


int
Udb_Update(
    ClientData data,
    Tcl_Interp *interp, 
    int argc,
    char *argv[]
)
{
    char		*uuid;
    DB_OBJECT		*object;
    DB_OBJECT		*class;
    DB_OTMPL		*template;
    int			i;
    Tcl_HashTable	relations;

    /*
     * Name cache tables for current object.
     */
    Tcl_HashTable	oldTables[NCACHE_TABLES], newTables[NCACHE_TABLES];

    if (argc < 2 || argc % 2 != 0)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "uuid ?attr value?...",
			 (char *)NULL);
    }

    uuid = argv[1];

    argv += 2;
    argc -= 2;

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }
    object = Udb_Find_Object(uuid);

    if (object == NULL)
    {
	return Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
    }

    class = db_get_class(object);

    if (Udb_Class_Is_Readonly(interp, class))
    {
	return Udb_Error(interp, "EREADONLY", uuid, Udb_Get_Class_Name(class),
			 (char *)NULL);
    }

    if (argc == 0)
    {
	return TCL_OK;
    }

    check(template = dbt_edit_object(object));

    Udb_Populate_Caches(interp, object, oldTables);
    Tcl_InitHashTable(&relations, TCL_STRING_KEYS);

    for (i = 0; i < argc; i += 2)
    {
	int ok;

	/*
	 * Update template
	 */
	ok = Udb_Set_Attribute(interp, uuid, object, template,
			       argv[i], argv[i+1], &relations);

	if (ok == TCL_OK && Equal(argv[i], "owner"))
	{
	    ok = Check_Owner(interp, uuid, object, argv[i+1]);
	}

	if (ok == TCL_OK && Equal(argv[i], "cellorg"))
	{
	    ok = Check_Organization(interp, uuid, object, argv[i+1]);
	}

	if (ok != TCL_OK)
	{
	    dbt_abort_object(template);
	    Udb_Free_Dynamic_Table(&relations, (Tcl_FreeProc *)db_value_free,
				   FALSE);
	    Udb_Free_Cache_Tables(oldTables);
	    return TCL_ERROR;
	}
    }

    /*
     * Update the object and then its name cache entries
     */
    check(object == Udb_Finish_Object(class, template, FALSE));

    Udb_Populate_Caches(interp, object, newTables);

    if (Udb_Update_Caches(interp, uuid, object, oldTables, newTables) !=
	TCL_OK)
    {
	Udb_Free_Dynamic_Table(&relations, (Tcl_FreeProc *)db_value_free,
			       FALSE);
	Udb_Force_Rollback(interp);
	return TCL_ERROR;
    }

    /*
     * This will also free the relation table
     */
    if (Udb_Restore_Mode(NULL) == RESTOREDATA)
    {
	Udb_Update_Relations(interp, class, object, &relations, TRUE, FALSE);
    }
    else
    {
	Udb_Update_Relations(interp, class, object, &relations, FALSE, FALSE);
    }

    return TCL_OK;
}
