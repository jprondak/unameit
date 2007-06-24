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
static char rcsid[] = "$Id: delete.c,v 1.19.20.4 1997/09/21 23:42:38 viktor Exp $";

/* Routines related to deletion of database objects. */

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "uuid.h"
#include "delete.h"
#include "lookup.h"
#include "misc.h"
#include "init.h"
#include "name_cache.h"
#include "relation.h"
#include "license.h"
#include "errcode.h"


int Udb_Delete(
    ClientData data,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    DB_OBJECT		*object;
    DB_OBJECT		*class;
    char 		*uuid;

    assert(interp && argv && argc > 0 && argv[0]);

    if (argc < 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "uuid", (char *)NULL);
    }

    uuid = argv[1];

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }

    if (!(object = Udb_Find_Object(uuid)))
    {
	return Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
    }

    class = db_get_class(object);

    if (Udb_Class_Is_Readonly(interp, class))
    {
	return Udb_Error(interp, "EREADONLY", uuid, Udb_Get_Class_Name(class),
			 (char *)NULL);
    }

    /*
     * Failed deletes,  always force rollback.  So we can adjust license
     * limits unconditionally.  (Since we may be cascading,  trying
     * to `carefully' count deletes,  is harder than it looks.)
     */
    Udb_Adjust_License_Count(class, -1);

    return Udb_Delete_Object(interp, class, uuid, object);
}
