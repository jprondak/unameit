/*
 * Copyright (c) 1995-1997 Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: passwd.c,v 1.9.8.5 1997/09/21 23:42:26 viktor Exp $";

#include <uconfig.h>
#include <auth.h>

#define UPASSWD_VERSION "1.1"
#include "passwdtcl.h"
#include "passwderr.h"

typedef struct
{
    char *user_name;
    char *password;
}
Upasswd_Context;

static void
stringset (char **ps, const char *s)
{
    if (*ps)
	ckfree(*ps);
    if (s)
    {
	*ps = ckalloc (strlen(s) + 1);
	strcpy (*ps, s);
    }
    else
    {
	*ps = NULL;
    }
}


static int
Upasswd_Error (Tcl_Interp *interp, const char *code, ...)
{
    va_list 	ap;
    char	*s;

    assert(code);

    Tcl_ResetResult (interp);

    Tcl_SetErrorCode (interp, "UNAMEIT", AUTH_ERROR,
		      CONN_AUTH_UPASSWD, code, (char *)NULL);

    va_start(ap, code);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}

#define Upasswd_BadArgs() Upasswd_Error (interp, "EBADARGS", (char *)NULL)

/*
 * Generate a message for authenticating to the server.
 * No arguments are used. Errors are left in the interpreter.
 * This routine sends the message and sets the connection authentication.
 */

static int
Upasswd_write_auth (
    ClientData d,
    conn_t *conn,
    Tcl_Interp *interp,
    int argc,
    char **argv
)
{
    Upasswd_Context	*upw = (Upasswd_Context *)d;
    int			namelen = 0;
    int			passwdlen = 0;
    int			len = 0;
    char		*buf = NULL;

    assert(conn);
    assert(upw);

    namelen = strlen(upw->user_name);
    passwdlen = strlen(upw->password);

    if (namelen < 1)
    {
	return Upasswd_Error (interp, "NONAME", (char *)NULL);
    }
    if (passwdlen < 1)
    {
	return Upasswd_Error (interp, "NOPASSWORD", (char *)NULL);
    }

    len = namelen + passwdlen + 2;
    buf = ckalloc(len);

    strcpy(buf, upw->user_name);
    strcpy(buf+namelen+1, upw->password);

    Unameit_Conn_Write(conn, buf, len, CONN_AUTH_ID_UPASSWD, 0, TCL_DYNAMIC);

    return TCL_OK;
}


/*
 * Process an authentication request after receiving it.
 * The read has already been done by the caller (Auth_Read).
 * This routine invokes the appropriate user login proc with the
 * realm and name of the principal.
 */

static int
Upasswd_read_auth (
    ClientData 	d,
    conn_t 	*conn,
    Tcl_Interp 	*interp,
    char 	*buf,
    unsigned32  len
)
{
    Upasswd_Context	*upw = (Upasswd_Context *)d;
    char		*user_name;
    char		*password;
    Tcl_DString		cmd;
    int			result = TCL_ERROR;

    assert(upw);
    assert(conn);

    user_name = buf;
    password = user_name + strlen(user_name) + 1;

    if (password + strlen(password) + 1 != buf + len)
    {
	return Upasswd_BadArgs();
    }

    if (password == buf + 1)
    {
	return Upasswd_Error (interp, "NONAME", (char *)NULL);
    }

    /*
     * Password authentication is never privileged.
     */
    Tcl_DStringInit (&cmd);
    Tcl_DStringAppend (&cmd, "unameit_login_upasswd", -1);
    Tcl_DStringAppendElement (&cmd, user_name);
    Tcl_DStringAppendElement (&cmd, password);
    result = Tcl_Eval (interp, Tcl_DStringValue(&cmd));
    Tcl_DStringFree(&cmd);
    return result;
}


static int
Upasswd_kinit(ClientData d, Tcl_Interp *interp, int argc, char **argv)
{
    Upasswd_Context *upw = (Upasswd_Context *)d;
    assert (upw);

    if (argc != 5)
    {
	return Upasswd_BadArgs();
    }

    stringset (&upw->user_name, argv[3]);
    stringset (&upw->password, argv[4]);
    return TCL_OK;
}

/*
 * Close the credential cache and destroy it. Currently a NOP.
 */
static int
Upasswd_kdestroy(ClientData d, Tcl_Interp *interp, int argc, char **argv)
{
    Upasswd_Context *upw = (Upasswd_Context *)d;
    assert (upw);

    if (argc != 3)
    {
	return Upasswd_BadArgs();
    }
    stringset(&upw->user_name, NULL);
    stringset(&upw->password, NULL);
    return TCL_OK;
}


int
Upasswd_Init(Tcl_Interp *interp)
{
    char	**procPtr;

    static Upasswd_Context upw;

    static cmd_entry commands[] =
    {
	{"kinit", (ClientData)&upw, Upasswd_kinit, "login password"},
	{"kdestroy", (ClientData)&upw, Upasswd_kdestroy, ""},
	{NULL, NULL, NULL, NULL}
    };

    static Auth_Functions calls =
    {
	CONN_AUTH_UPASSWD,
	CONN_AUTH_ID_UPASSWD,
	Upasswd_read_auth, (ClientData)&upw,
	Upasswd_write_auth,(ClientData) &upw,
	commands
    };

    if (Tcl_PkgRequire (interp, AUTH_NAME, AUTH_VERSION, 0) == NULL)
    {
	Tcl_AppendResult (interp,
			  "\ncould not load password module without ",
			  AUTH_NAME, " ", AUTH_VERSION, NULL);
	return TCL_ERROR;
    }

    for (procPtr = passwderr; *procPtr; ++procPtr)
    {
	if (Tcl_Eval (interp, *procPtr) != TCL_OK)
	    return TCL_ERROR;
    }

    /*
     * We call Auth_Register directly.  OK, since this module is
     * always linked statically.
     */
    if (Auth_Register (interp, &calls, passwdtcl) != TCL_OK)
    {
	Tcl_AppendResult (interp, "\ncould not initialize password module",
			  NULL);
	return TCL_ERROR;
    }

    return (Tcl_PkgProvide (interp, "upasswd", UPASSWD_VERSION));
}
