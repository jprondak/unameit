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
static char rcsid[] = "$Id: ndbmtcl.c,v 1.3.34.2 1997/09/21 23:43:00 viktor Exp $";

#include <uconfig.h>
#include <ndbm.h>


static int
ndbm_fetchCmd(ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    DBM *handle;
    datum result, key;

    if (argc < 2 || argc > 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " key ?valueVar?\"", (char *)NULL);
	return TCL_ERROR;
    }

    handle = (DBM *)cd;

    key.dsize = strlen(key.dptr = argv[1]) + 1;
    result = dbm_fetch(handle, key);

    if (result.dptr != NULL)
    {
	if (argc < 3)
	{
	    Tcl_SetResult(interp, result.dptr, TCL_VOLATILE);
	    return TCL_OK;
	}
	if (!Tcl_SetVar(interp, argv[2], result.dptr, TCL_LEAVE_ERR_MSG))
	{
	    return TCL_ERROR;
	}
	interp->result[0] = '1';
	interp->result[1] = '\0';
    }
    else
    {
	if (argc > 2)
	{
	    interp->result[0] = '0';
	    interp->result[1] = '\0';
	}
    }
    return TCL_OK;
}


static int
ndbm_insertCmd(ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    DBM		*handle;
    datum	data;
    datum	key;

    if (argc != 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " key value\"", (char *)NULL);
	return TCL_ERROR;
    }

    handle = (DBM *)cd;

    key.dsize = strlen(key.dptr = argv[1]) + 1;
    data.dsize = strlen(data.dptr = argv[2]) + 1;

    if (dbm_store(handle, key, data, DBM_REPLACE) != 0)
    {
	Tcl_AppendResult(interp, argv[0], ": Could not store key: '",
			 argv[1], "' value: '", argv[2], "'", (char *)NULL);
	return TCL_ERROR;
    }
    return TCL_OK;
}


static int
ndbm_deleteCmd(ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    DBM		*handle;
    datum	key;

    if (argc != 2)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " key\"", (char *)NULL);
	return TCL_ERROR;
    }

    handle = (DBM *)cd;

    key.dsize = strlen(key.dptr = argv[1]) + 1;

    if (dbm_delete(handle, key) != 0)
    {
	Tcl_AppendResult(interp, argv[0], ": Could not delete key: ",
			 argv[1], (char *)NULL);
	return TCL_ERROR;
    }
    return TCL_OK;
}


static int
ndbm_firstCmd(ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    datum key;

    if (argc > 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " ?keyVar? ?valueVar?\"", (char *)NULL);
	return TCL_ERROR;
    }

    key = dbm_firstkey((DBM *)cd);

    if (key.dptr != NULL)
    {
	if (argc < 2)
	{
	    Tcl_SetResult(interp, key.dptr, TCL_VOLATILE);
	    return TCL_OK;
	}
	if (!Tcl_SetVar(interp, argv[1], key.dptr, TCL_LEAVE_ERR_MSG))
	{
	    return TCL_ERROR;
	}
	if (argc > 2)
	{
	    key = dbm_fetch((DBM *)cd, key);
	    assert(key.dptr != NULL);
	    if (!Tcl_SetVar(interp, argv[2], key.dptr, TCL_LEAVE_ERR_MSG))
	    {
		return TCL_ERROR;
	    }
	}
	interp->result[0] = '1';
	interp->result[1] = '\0';
    }
    else
    {
	if (argc >= 2)
	{
	    interp->result[0] = '0';
	    interp->result[1] = '\0';
	}
    }
    return TCL_OK;
}


static int
ndbm_nextCmd(ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    datum key;

    if (argc > 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " ?keyVar? ?valueVar?\"", (char *)NULL);
	return TCL_ERROR;
    }

    key = dbm_nextkey((DBM *)cd);

    if (key.dptr != NULL)
    {
	if (argc < 2)
	{
	    Tcl_SetResult(interp, key.dptr, TCL_VOLATILE);
	    return TCL_OK;
	}
	if (!Tcl_SetVar(interp, argv[1], key.dptr, TCL_LEAVE_ERR_MSG))
	{
	    return TCL_ERROR;
	}
	if (argc > 2)
	{
	    key = dbm_fetch((DBM *)cd, key);
	    assert(key.dptr != NULL);
	    if (!Tcl_SetVar(interp, argv[2], key.dptr, TCL_LEAVE_ERR_MSG))
	    {
		return TCL_ERROR;
	    }
	}
	interp->result[0] = '1';
	interp->result[1] = '\0';
    }
    else
    {
	if (argc >= 2)
	{
	    interp->result[0] = '0';
	    interp->result[1] = '\0';
	}
    }
    return TCL_OK;
}


static int
ndbm_optCmd(ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    char *opt;

    if (argc < 2)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " option ?arg ...?\"", (char *)0);
	return TCL_ERROR;
    }

    opt = argv[1];

    if ((*opt == 'f') && !strcmp(opt, "fetch"))
    {
	return ndbm_fetchCmd(cd, interp, --argc, ++argv);
    }
    else if ((*opt == 'i') && !strcmp(opt, "insert"))
    {
	return ndbm_insertCmd(cd, interp, --argc, ++argv);
    }
    else if ((*opt == 'n') && !strcmp(opt, "next"))
    {
	return ndbm_nextCmd(cd, interp, --argc, ++argv);
    }
    else if ((*opt == 'd') && !strcmp(opt, "delete"))
    {
	return ndbm_deleteCmd(cd, interp, --argc, ++argv);
    }
    else if ((*opt == 'f') && !strcmp(opt, "first"))
    {
	return ndbm_firstCmd(cd, interp, --argc, ++argv);
    }
    else if ((*opt == 'c') && !strcmp(opt, "close"))
    {
	return Tcl_DeleteCommand(interp, argv[0]);
    }

    Tcl_AppendResult(interp, "bad option \"", opt, "\": should be "
		     "fetch, insert, next, delete, first or close",
		     (char *)NULL);
    return TCL_ERROR;
}


static int
ndbmCmd (ClientData cd, Tcl_Interp *interp, int argc, char **argv)
{
    char cmd[256];
    DBM  *handle;

    if (argc != 3 || strcmp(argv[1], "open") != 0)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " open file\"", (char *)NULL);
	return TCL_ERROR;
    }

    if (!(handle = dbm_open(argv[2], O_RDWR | O_CREAT, 0666)))
    {
	Tcl_AppendResult(interp, "dbm_open: ", Tcl_PosixError(interp),
			 (char *)NULL);
	return TCL_ERROR;
    }

    sprintf(cmd, "ndbm:%p", (void *)handle);
    Tcl_CreateCommand(interp, cmd, (Tcl_CmdProc *)ndbm_optCmd,
		      (ClientData)handle, (Tcl_CmdDeleteProc *)dbm_close);

    Tcl_SetResult(interp, cmd, TCL_VOLATILE);
    return TCL_OK;
}


int
Ndbmtcl_Init(Tcl_Interp *interp)
{
    Tcl_CreateCommand(interp, "ndbm", (Tcl_CmdProc *)ndbmCmd,
		      (ClientData)0, (Tcl_CmdDeleteProc *)0);
    Tcl_PkgProvide(interp, "Ndbmtcl", "1.0");
    return TCL_OK;
}
