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
static char rcsid[] = "$Id: transaction.c,v 1.36.4.4 1997/09/21 23:42:54 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include <fcntl.h>

#if   defined(O_DSYNC)
#	define LOG_FLAGS	O_WRONLY|O_APPEND|O_CREAT|O_DSYNC
#elif defined(O_SYNC)
#	define LOG_FLAGS	O_WRONLY|O_APPEND|O_CREAT|O_SYNC
#else
#	error O_SYNC not supported
#endif

#include "uuid.h"
#include "transaction.h"
#include "lookup.h"
#include "misc.h"
#include "schema.h"
#include "errcode.h"
#include "license.h"
#include "convert.h"

/*
 * Prototypes for integrity checking functions
 */
#include "relation.h"
#include "name_cache.h"
#include "inet.h"
#include "range.h"

/* Routines related to transaction processing. */

static 		int syscall_db_updated = FALSE;
static 		int tx_db_updated = FALSE;
static 		int force_rollback = FALSE;
static 		int schema_modified = FALSE;
static 		Tcl_DString saved_error;
/*
 * Must reset all static object pointers on rollback!
 */
static		DB_OBJECT *tx_class;
static		DB_INT32 tx_dmajor;
static		DB_INT32 tx_dminor;
static		DB_INT32 tx_dmicro;
static		DB_INT32 tx_smajor;
static		DB_INT32 tx_sminor;
static		DB_INT32 tx_smicro;
static		int new_tx_dmicro;
static		int new_tx_smicro;
static		char clientName[256];
static		int logFd = -1;


static int
Schema_Updated(DB_OBJECT *class)
{
    if (Udb_Is_Data_Class(class))
    {
	return FALSE;
    }
    return schema_modified = TRUE;
}


RestoreMode
Udb_Restore_Mode(RestoreMode *new)
{
    static   RestoreMode	now = NORESTORE;
    register RestoreMode	old = now;

    if (new) now = *new;

    return old;
}


static void
Load_Tran_Versions()
{
    DB_VALUE value;

    tx_class = Udb_Get_Class("unameit_transaction");
    tx_dmajor = tx_dminor = tx_dmicro = 0;
    tx_smajor = tx_sminor = tx_smicro = 0;

    Udb_Get_Value(tx_class, "data_major", DB_TYPE_INTEGER, &value);
    if(!DB_IS_NULL(&value))
    {
	tx_dmajor = DB_GET_INTEGER(&value);
    }

    Udb_Get_Value(tx_class, "data_minor", DB_TYPE_INTEGER, &value);
    if(!DB_IS_NULL(&value))
    {
	tx_dminor = DB_GET_INTEGER(&value);
    }

    Udb_Get_Value(tx_class, "data_micro", DB_TYPE_INTEGER, &value);
    if(!DB_IS_NULL(&value))
    {
	tx_dmicro = DB_GET_INTEGER(&value);
    }

    Udb_Get_Value(tx_class, "schema_major", DB_TYPE_INTEGER, &value);
    if(!DB_IS_NULL(&value))
    {
	tx_smajor = DB_GET_INTEGER(&value);
    }

    Udb_Get_Value(tx_class, "schema_minor", DB_TYPE_INTEGER, &value);
    if(!DB_IS_NULL(&value))
    {
	tx_sminor = DB_GET_INTEGER(&value);
    }

    Udb_Get_Value(tx_class, "schema_micro", DB_TYPE_INTEGER, &value);
    if(!DB_IS_NULL(&value))
    {
	tx_smicro = DB_GET_INTEGER(&value);
    }
}


/*
 * item_class should be NON-NULL iff template is for a subclass of
 * 'unameit_item'
 *
 * This function may return a NULL object,  indicating failure
 * if a non NULL template was supplied.  The caller must check
 * for the NULL result (the template is aborted here).
 */
DB_OBJECT *
Udb_Finish_Object(
    DB_OBJECT *item_class,
    DB_OTMPL *template,
    int item_deleted
)
{
    DB_OBJECT	*object;
    DB_VALUE	value;
    char	idbuf[64];

    if (item_class == NULL)
    {
	/*
	 * A database change to something other than a unameit_item.
	 * Just finish the template and return.
	 */
	tx_db_updated = syscall_db_updated = TRUE;

	if (template)
	{
	    check(object = dbt_finish_object(template));
	    return object;
	}
	return NULL;
    }

    assert(template);

    /*
     * During restore the modification fields are not protected,
     * we require the caller to handle these manually
     */
    if (Udb_Restore_Mode(NULL) != NORESTORE)
    {
	tx_db_updated = syscall_db_updated = TRUE;
	/*
	 * It is ok to return a NULL object,  the caller must
	 * check for a non NULL return from Udb_Finish_Object().
	 */
	if ((object = dbt_finish_object(template)) != NULL)
	{
	    (void) Schema_Updated(item_class);
	}
	else
	{
	    dbt_abort_object(template);
	}
	return object;
    }

    if (tx_class == NULL)
    {
	Load_Tran_Versions();
    }

    DB_MAKE_INTEGER(&value, (DB_INT32)time(NULL));
    check(dbt_put(template, "mtime", &value) == NOERROR);

    DB_MAKE_STRING(&value, clientName);
    check(dbt_put(template, "modby", &value) == NOERROR);

    if (Schema_Updated(item_class) == FALSE)
    {
	new_tx_dmicro = TRUE;

	sprintf(idbuf, "%ld.%ld.%ld",
		(long)tx_dmajor, (long)tx_dminor, (long)tx_dmicro);
	DB_MAKE_STRING(&value, idbuf);
	check(dbt_put(template, "mtran", &value) == NOERROR);
    }
    else
    {
	new_tx_smicro = TRUE;

	sprintf(idbuf, "%ld.%ld.%ld",
		(long)tx_smajor, (long)tx_sminor, (long)tx_smicro);
	DB_MAKE_STRING(&value, idbuf);
	check(dbt_put(template, "mtran", &value) == NOERROR);
    }

    if (item_deleted == TRUE)
    {
	DB_MAKE_STRING(&value, "Yes");
	check(dbt_put(template, "deleted", &value) == NOERROR);
    }

    if ((object = dbt_finish_object(template)) != NULL)
    {
	tx_db_updated = syscall_db_updated = TRUE;
    }
    else
    {
	dbt_abort_object(template);
    }
    return object;
}


void
Udb_CloseLog(void)
{
    if (logFd == -1)
	return;

    if (close(logFd) == -1)
    {
	Unameit_eComplain("log file close failed");
	exit(1);
    }

    logFd = -1;
}


void
Udb_OpenLog(const char *logPrefix)
{
    Tcl_DString	logPath;
    char	buf[64];

    assert(logPrefix);

    if (tx_class == NULL)
    {
	Load_Tran_Versions();
    }

    Udb_CloseLog();

    Tcl_DStringInit(&logPath);

    Tcl_DStringAppend(&logPath, (char *)logPrefix, -1);
    sprintf(buf, ".%d.%d", tx_dmajor, tx_dminor);
    Tcl_DStringAppend(&logPath, buf, -1);

    logFd = open(Tcl_DStringValue(&logPath), LOG_FLAGS, 0600);

    Tcl_DStringFree(&logPath);

    if (logFd == -1)
    {
	Unameit_eComplain("log file open failed");
	exit(1);
    }
}


static void
WriteLog(const char *entry)
{
    Tcl_DString logEntry;
    int		len = 0;

    if (logFd == -1) return;

    Tcl_DStringInit(&logEntry);

    sprintf(Tcl_DStringValue(&logEntry), "%ld.%ld.%ld %ld.%ld.%ld %ld%n",
	    (long)tx_dmajor, (long)tx_dminor, (long)tx_dmicro,
	    (long)tx_smajor, (long)tx_sminor, (long)tx_smicro,
	    (long)time(NULL), &len);

    assert(len > 0 && len < TCL_DSTRING_STATIC_SIZE);
    Tcl_DStringSetLength(&logEntry, len);

    Tcl_DStringAppendElement(&logEntry, clientName);
    if (entry)
    {
	Tcl_DStringAppendElement(&logEntry, (char *)entry);
    }
    Tcl_DStringAppend(&logEntry, "\n", 1);

    entry = Tcl_DStringValue(&logEntry);
    len = Tcl_DStringLength(&logEntry);

    if (write(logFd, entry, len) != len)
    {
	Unameit_eComplain("Log I/O error");
	db_abort_transaction();
	exit(1);
    }

    Tcl_DStringFree(&logEntry);
}


void
Udb_Force_Rollback(Tcl_Interp *interp)
{
    char *ecode;

    if (force_rollback == TRUE)
    {
	/*
	 * We are already going to roll back
	 */
	return;
    }

    force_rollback = TRUE;

    Tcl_DStringInit(&saved_error);
    Tcl_DStringAppend(&saved_error, "error", -1);
    Tcl_DStringAppendElement(&saved_error, interp->result);

    ecode = Tcl_GetVar2(interp, "errorCode", NULL, TCL_GLOBAL_ONLY);

    Tcl_DStringAppendElement(&saved_error, "");
    Tcl_DStringAppendElement(&saved_error, ecode ? ecode : "NONE");
}


int
Udb_Syscall(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    int result;
    int save;

    if (argc != 2)
    {
	return Udb_Error(interp,"EUSAGE", argv[0], "script", (char *)NULL);
    }

    if (force_rollback == TRUE)
    {
	return TCL_ERROR;
    }

    /*
     * Make call reentrant by saving and restoring the
     * old value of db_updated
     */
    save = syscall_db_updated;

    syscall_db_updated = FALSE;

    result = Tcl_Eval(interp, argv[1]);

    if (result != TCL_OK && syscall_db_updated == TRUE)
    {
	Udb_Force_Rollback(interp);
    }

    syscall_db_updated = save;

    return result;
}


int
/* ARGSUSED */
Udb_Transaction(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    int result;

    if (argc == 3 && Equal(argv[1], "-restore_mode"))
    {
	RestoreMode mode = RESTOREDATA;

	if (Equal(argv[2], "schema"))
	{
	    mode = RESTORESCHEMA;
	}
	(void) Udb_Restore_Mode(&mode);
    }
    else if (argc != 2)
    {
	Udb_Error(interp, "EUSAGE", argv[0], "clientName", (char *)NULL);
	return TCL_ERROR;
    }
    else
    {
	(void) strncpy(clientName, argv[1], sizeof(clientName) - 1);
    }

    /*
     * Roll back any uncommitted transactions.  (Should be none)
     */
    result = Udb_Do_Rollback(interp);

    /*
     * Default value,  to be reset by call to `udb_principal'
     */
    Udb_Server_Principal();

    return result;
}


int
Udb_Version(ClientData d, Tcl_Interp *interp, int argc, char *argv[]) 
{
    if (argc != 2 && !Equal(argv[1], "data") && !Equal(argv[1], "schema"))
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "data|schema", (char *)NULL);
    }

    if (tx_class == NULL)
    {
	Load_Tran_Versions();
    }

    if (Equal(argv[1], "data"))
    {
	sprintf(interp->result, "%ld.%ld.%ld",
		(long)tx_dmajor, (long)tx_dminor, (long)tx_dmicro);
    }
    else
    {
	sprintf(interp->result, "%ld.%ld.%ld",
		(long)tx_smajor, (long)tx_sminor, (long)tx_smicro);
    }
    return TCL_OK;
}


int
Udb_Rollback(ClientData d, Tcl_Interp *interp, int argc, char *argv[]) 
{
    return Udb_Do_Rollback(interp);
}

int
Udb_Do_Rollback(Tcl_Interp *interp)
{
    int result = TCL_OK;

    tx_class = NULL;
    new_tx_dmicro = FALSE;
    new_tx_smicro = FALSE;

    if (force_rollback == TRUE)
    {
	result = Tcl_Eval(interp, Tcl_DStringValue(&saved_error));
	Tcl_DStringFree(&saved_error);
    }
    else if (tx_db_updated == FALSE)
    {
	Udb_Uncache_Items(TRUE, FALSE);
	return TCL_OK;
    }

    /*
     * Reset for next transaction
     */
    schema_modified = FALSE;
    force_rollback = FALSE;

    /*
     * Need to clear validation tables.
     */
    Udb_Reset_Reference_Checks();
    Udb_Reset_Unique_Checks();
    Udb_Reset_Loop_Checks();
    Udb_Inet_Reset_Checks();

    /*
     * On a rollback, we need to get rid of all cached items
     * some or all of them may now be invalid.
     */
    Udb_Uncache_Items(TRUE, FALSE);

    /*
     * Undo tentative license count changes
     */
    Udb_Rollback_License_Limits();

    /*
     * We now have no outstanding references to any database objects!
     * XXX: If only there was a way to convey this to this GC code in
     * the database workspace,  the rollback would go a *lot* faster.
     * For now we just run with GC disabled.
     */
    check(db_abort_transaction() == NOERROR);

    return result;
}

int
Udb_Commit(
   ClientData nused,
   Tcl_Interp *interp,
   int argc,
   char *argv[]
)
{
    char	*argv0 = argv[0];
    char	*dmajor;
    char	*dminor;
    char	*smajor;
    char	*sminor;
    int		noCommit = 0;

    ++argv; --argc;

    dmajor = dminor = smajor = sminor = NULL;

    while (argc > 1)
    {
	if (argv[0][0] != '-')
	{
	    break;
	}
	if (Equal(argv[0], "--"))
	{
	    ++argv; --argc;
	    break;
	}
	if (Equal(argv[0], "-dataMajor"))
	{
	    dmajor = argv[1];
	    argv += 2; argc -= 2;
	}
	else if (Equal(argv[0], "-dataMinor"))
	{
	    dminor = argv[1];
	    argv += 2; argc -= 2;
	}
	else if (Equal(argv[0], "-schemaMajor"))
	{
	    smajor = argv[1];
	    argv += 2; argc -= 2;
	}
	else if (Equal(argv[0], "-schemaMinor"))
	{
	    sminor = argv[1];
	    argv += 2; argc -= 2;
	}
	else if (Equal(argv[0], "-noCommit"))
	{
	    noCommit = 1;
	    ++argv; --argc;
	}
	else
	{
	    break;
	}
    }

    if (argc > 1)
    {
	return Udb_Error(interp, "EUSAGE", argv0, "?logEntry?", (char *)NULL);
    }

    if (tx_class == NULL)
    {
	Load_Tran_Versions();
    }

    if (dmajor)
    {
	DB_VALUE value;

	if (Udb_String_To_Int32(interp, dmajor, &tx_dmajor) != TCL_OK)
	{
	    return noCommit ? TCL_ERROR : Udb_Do_Rollback(interp);
	}

	DB_MAKE_INTEGER(&value, tx_dmajor);
	check(db_put(tx_class, "data_major", &value) == NOERROR);
	tx_dminor = 0;
    }

    if (dminor && Udb_String_To_Int32(interp, dminor, &tx_dminor) != TCL_OK)
    {
	return noCommit ? TCL_ERROR : Udb_Do_Rollback(interp);
    }

    if (dmajor || dminor)
    {
	DB_VALUE value;

	/*
	 * Force a commit
	 */
	tx_db_updated = TRUE;

	DB_MAKE_INTEGER(&value, tx_dminor);
	check(db_put(tx_class, "data_minor", &value) == NOERROR);

	new_tx_dmicro = TRUE;
	/*
	 * It will be incremented during commit
	 */
	tx_dmicro = noCommit ? 0 : -1;
    }

    if (smajor)
    {
	DB_VALUE value;

	if (Udb_String_To_Int32(interp, smajor, &tx_smajor) != TCL_OK)
	{
	    return noCommit ? TCL_ERROR : Udb_Do_Rollback(interp);
	}

	DB_MAKE_INTEGER(&value, tx_smajor);
	check(db_put(tx_class, "schema_major", &value) == NOERROR);
	tx_sminor = 0;
    }

    if (sminor && Udb_String_To_Int32(interp, sminor, &tx_sminor) != TCL_OK)
    {
	return noCommit ? TCL_ERROR : Udb_Do_Rollback(interp);
    }

    if (smajor || sminor)
    {
	DB_VALUE value;

	/*
	 * Force a commit
	 */
	tx_db_updated = TRUE;

	DB_MAKE_INTEGER(&value, tx_sminor);
	check(db_put(tx_class, "schema_minor", &value) == NOERROR);

	new_tx_smicro = TRUE;
	/*
	 * It will be incremented during commit
	 */
	tx_smicro = noCommit ? 0 : -1;
    }

    return noCommit ? TCL_OK : Udb_Do_Commit(interp, argv[0]);
}

int
Udb_Do_Commit(Tcl_Interp *interp, const char *logEntry)
{
    static char	loadcmd[] = "unameit_load_schema";
    static char	changecmd[] = "unameit_change_schema";
    int		code;

    if (force_rollback == TRUE)
    {
	return Udb_Do_Rollback(interp);
    }

    if (tx_db_updated == FALSE)
    {
	return TCL_OK;
    }

    /*
     * If not restoring, or restoring the schema
     * run standard checks
     */
    if (Udb_Restore_Mode(NULL) != RESTOREDATA)
    {
	if (Udb_Do_Reference_Checks(interp) != TCL_OK)
	{
	    Udb_Do_Rollback(interp);
	    return TCL_ERROR;
	}
	if (Udb_Do_Unique_Checks(interp) != TCL_OK)
	{
	    Udb_Do_Rollback(interp);
	    return TCL_ERROR;
	}
	if (Udb_Do_Loop_Checks(interp) != TCL_OK)
	{
	    Udb_Do_Rollback(interp);
	    return TCL_ERROR;
	}
    }

    /*
     * If not restoring run data checks
     */
    if (Udb_Restore_Mode(NULL) == NORESTORE)
    {
	if (Udb_Inet_Check_Integrity(interp) != TCL_OK)
	{
	    Udb_Do_Rollback(interp);
	    return TCL_ERROR;
	}
    }

    if (schema_modified == TRUE)
    {
	Tcl_Interp	*metaInterp;
	char		*noargs = NULL;

	/*
	 * Schema metadata has been updated.
	 * Validate the new schema and do the schema changes.
	 */
	check(metaInterp = Tcl_GetMaster(interp));
	check(metaInterp = Tcl_GetSlave(metaInterp, "umeta_interp"));

	Tcl_CreateAlias(interp, changecmd, metaInterp, changecmd, 0, &noargs);
	Tcl_CreateAlias(interp, loadcmd, metaInterp, loadcmd, 0, &noargs);

	code = Tcl_GlobalEval(interp, changecmd);
	Tcl_DeleteCommand(interp, changecmd);

	if (code != TCL_OK)
	{
	    Tcl_DeleteCommand(interp, loadcmd);
	    Udb_Do_Rollback(interp);
	    return TCL_ERROR;
	}
	/*
	 * We have modified the schema.  Uncache all schema info.
	 */
	Udb_Uncache_Schema();
    }

    if (new_tx_dmicro == TRUE)
    {
	DB_VALUE value;
	DB_MAKE_INTEGER(&value, ++tx_dmicro);
	check(db_put(tx_class, "data_micro", &value) == NOERROR);
	new_tx_dmicro = FALSE;
    }

    if (new_tx_smicro == TRUE)
    {
	DB_VALUE value;
	DB_MAKE_INTEGER(&value, ++tx_smicro);
	check(db_put(tx_class, "schema_micro", &value) == NOERROR);
	new_tx_smicro = FALSE;
    }

    WriteLog(logEntry);

    check(db_commit_transaction() == NOERROR);

    /*
     * Cleanup for next transaction
     */
    Udb_Uncache_Items(FALSE, FALSE);
    Udb_Update_License_Limits();
    Udb_Reset_Reference_Checks();
    Udb_Reset_Unique_Checks();
    Udb_Reset_Loop_Checks();
    Udb_Inet_Reset_Checks();
    tx_db_updated = FALSE;

    if (schema_modified == TRUE)
    {
	check(Tcl_GlobalEval(interp, loadcmd) == TCL_OK);
	Tcl_DeleteCommand(interp, loadcmd);
	schema_modified = FALSE;
    }
    Tcl_ResetResult(interp);
    return TCL_OK;
}
