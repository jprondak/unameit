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
static char rcsid[] = "$Id: init.c,v 1.36.4.9 1997/10/09 01:10:31 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "transaction.h"
#include "create.h"
#include "fetch.h"
#include "update.h"
#include "delete.h"
#include "qbe.h"
#include "misc.h"
#include "init.h"
#include "schema.h"
#include "uuid.h"
#include "inet.h"
#include "license.h"
#include "lookup.h"
#include "dump.h"
#include "range.h"
#include "errcode.h"
#include "udbproc.h"

#define UDB_VERSION "2.0"

/* Initialization routines for DB library. */

static		Tcl_CmdProc Login;
static		Tcl_CmdProc Shutdown;

static int
/*ARGSUSED*/
Login(ClientData not_used, Tcl_Interp *interp, int argc, char *argv[])
{
    const char *db;
    static int again;

    if (argc != 3 && argc != 4)
    {
	return Udb_Error(interp, "EUSAGE", argv[0],
			 "progname database ?logDirectory?", (char *)NULL);
    }

    db = argv[2];

    if (db_login("dba", NULL) != NOERROR ||
	db_restart(argv[1], 0, db) != NOERROR)
    {
	Tcl_AppendResult(interp, "Could not connect to database: ",
		db_error_string(1), (char *)0);
	return TCL_ERROR;
    }

#ifndef UNISQLX_GC_ON
    db_gc_disable();
#endif

    if (!again)
    {
	Udb_Init_License(interp);
	again = 1;
    }

    if (argc == 4)
    {
	Udb_OpenLog(argv[3]);
    }

    Tcl_CreateCommand(interp, "udb_shutdown", Shutdown, 0, 0);

    Udb_Inet_Create_Commands(interp, 1);

    Tcl_CreateCommand(interp, "udb_qbe", Udb_Query_By_Example, 0, 0);
    Tcl_CreateCommand(interp, "udb_fetch", Udb_Fetch, 0, 0);
    Tcl_CreateCommand(interp, "udb_protected", Udb_Item_Protected, 0, 0);
    Tcl_CreateCommand(interp, "udb_is_new", Udb_Is_New, 0, 0);
    Tcl_CreateCommand(interp, "udb_get_root", Udb_Get_RootCmd, 0, 0);
    Tcl_CreateCommand(interp, "udb_cell_of", Udb_Cell_Of_Cmd, 0, 0);
    Tcl_CreateCommand(interp, "udb_org_of", Udb_Cell_Of_Cmd, (ClientData)1, 0);

    Tcl_CreateCommand(interp, "udb_syscall", Udb_Syscall, 0, 0);
    Tcl_CreateCommand(interp, "udb_transaction", Udb_Transaction, 0, 0);
    Tcl_CreateCommand(interp, "udb_version", Udb_Version, 0, 0);
    Tcl_CreateCommand(interp, "udb_rollback", Udb_Rollback, 0, 0);
    Tcl_CreateCommand(interp, "udb_commit", Udb_Commit, 0, 0);
    Tcl_CreateCommand(interp, "udb_principal", Udb_PrincipalCmd, 0, 0);

    Tcl_CreateCommand(interp, "udb_dump_class", Udb_Dump_Class, 0, 0);
    Tcl_CreateCommand(interp, "udb_oid", Udb_OidCmd, 0, 0);
    Tcl_CreateCommand(interp, "udb_dump_protected", Udb_Dump_Protected, 0, 0);

    Tcl_CreateCommand(interp, "udb_auto_integer", Udb_Auto_Integer, 0, 0);

    Tcl_CreateCommand(interp, "udb_create", Udb_Create, 0, 0);
    Tcl_CreateCommand(interp, "udb_update", Udb_Update, 0, 0);
    Tcl_CreateCommand(interp, "udb_delete", Udb_Delete, 0, 0);
    Tcl_CreateCommand(interp, "udb_undelete", Udb_Undelete, 0, 0);
    Tcl_CreateCommand(interp, "udb_protect_items", Udb_Protect_Items, 0, 0);
    Tcl_CreateCommand(interp, "udb_set_root", Udb_Set_RootCmd, 0, 0);

    Tcl_CreateCommand(interp, "udb_license_info", Udb_License_Info, 0, 0);

    /*
     * Start running as server principal.
     */
    Udb_Server_Principal();

    /*
     * Disable Login command after we have logged in
     */
    Tcl_DeleteCommand(interp, argv[0]);

    return TCL_OK;
}


/* ARGSUSED */
static int
Shutdown(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    int result = TCL_OK;

    if (argc > 2) {
usage:
	Tcl_AppendResult(interp, "wrong # args: should be \"",
	    argv[0], "?commit?\"", (char *) NULL);
	return TCL_ERROR;
    }


    if (argc == 2)
    {
	if (!Equal(argv[1], "commit"))
	    goto usage;
	if (Udb_Do_Commit(interp, NULL) != TCL_OK)
	{
	    return TCL_ERROR;
	}
    }

    if (Udb_Do_Rollback(interp) != TCL_OK)
    {
	return TCL_ERROR;
    }

    /*
     * Uncache all cached objects and schema.
     */
    Udb_Uncache();

    (void) db_shutdown();

    Udb_Inet_Create_Commands(interp, 0);

    Tcl_DeleteCommand(interp, "udb_qbe");
    Tcl_DeleteCommand(interp, "udb_fetch");
    Tcl_DeleteCommand(interp, "udb_protected");
    Tcl_DeleteCommand(interp, "udb_is_new");
    Tcl_DeleteCommand(interp, "udb_get_root");
    Tcl_DeleteCommand(interp, "udb_cell_of");

    Tcl_DeleteCommand(interp, "udb_syscall");
    Tcl_DeleteCommand(interp, "udb_transaction");
    Tcl_DeleteCommand(interp, "udb_version");
    Tcl_DeleteCommand(interp, "udb_rollback");
    Tcl_DeleteCommand(interp, "udb_commit");
    Tcl_DeleteCommand(interp, "udb_principal");

    Tcl_DeleteCommand(interp, "udb_dump_class");
    Tcl_DeleteCommand(interp, "udb_oid");
    Tcl_DeleteCommand(interp, "udb_dump_protected");

    Tcl_DeleteCommand(interp, "udb_auto_integer");

    Tcl_DeleteCommand(interp, "udb_create");
    Tcl_DeleteCommand(interp, "udb_update");
    Tcl_DeleteCommand(interp, "udb_delete");
    Tcl_DeleteCommand(interp, "udb_undelete");
    Tcl_DeleteCommand(interp, "udb_protect_items");
    Tcl_DeleteCommand(interp, "udb_set_root");

    Tcl_DeleteCommand(interp, "udb_license_info");

    /*
     * Reenable login
     */
    Tcl_CreateCommand(interp, "udb_login", Login, 0, 0);
    /*
     * Disable shutdown
     */
    Tcl_DeleteCommand(interp, argv[0]);

    return result;
}

int
Udb_Init(Tcl_Interp *interp)
{
    char	**procPtr;

    assert(interp);
    assert(udbproc);

    Tcl_CreateCommand(interp, "udb_login", Login, 0, 0);

    for (procPtr = udbproc; *procPtr; ++procPtr)
    {
	if (Tcl_Eval(interp, *procPtr) != TCL_OK)
	{
	    return TCL_ERROR;
	}
    }

    Udb_Init_Cache();

    Tcl_PkgProvide(interp, "Udb", UDB_VERSION);
    return TCL_OK;
}
