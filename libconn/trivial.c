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
static char rcsid[] = "$Id: trivial.c,v 1.3.8.5 1997/09/21 23:42:28 viktor Exp $";

#include <auth.h>

#define TRIVIAL_VERSION "2.0"
#include "trivialtcl.h"
#include "triverr.h"

typedef struct
{
    char *client_principal;
    char *client_instance;
    char *client_realm;
    Auth_MasterFunctions *functions;
}
Trivial_Context;


static void
stringset (char **ps, const char *s)
{
    if (*ps)
	ckfree(*ps);
    if (s)
    {
	*ps = ckalloc (strlen (s) + 1);
	strcpy (*ps, s);
    }
    else
    {
	*ps = NULL;
    }
}


static int
Trivial_Error (Tcl_Interp *interp, const char *code, ...)
{
    va_list 	ap;
    char	*s;

    assert(code);

    Tcl_ResetResult (interp);

    Tcl_SetErrorCode (interp, "UNAMEIT", AUTH_ERROR,
		      CONN_AUTH_TRIVIAL, code, (char *)NULL);

    va_start(ap, code);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}

#define Trivial_BadArgs() Trivial_Error (interp, "EBADARGS", (char *)NULL)

/*
 * Generate a message for authenticating to the server.
 * No arguments are used. Errors are left in the interpreter.
 * This routine sends the message and sets the connection authentication.
 */

static int
Trivial_write_auth (
    ClientData ctx,
    conn_t *conn,
    Tcl_Interp *interp,
    int argc,
    char **argv
)
{
    Trivial_Context *trivial = (Trivial_Context *)ctx;
    int		namelen = 0;
    int		instlen = 0;
    int 	rlen = 0;
    int		len = 0;
    char	*buf = NULL;
    char	*p = NULL;

    assert(conn);
    assert(trivial);

    if (!trivial->client_principal || !trivial->client_instance ||
	!trivial->client_realm)
    {
	return Trivial_Error(interp, "NOKINIT", (char *)NULL);
    }

    namelen = strlen(trivial->client_principal);
    instlen = strlen(trivial->client_instance);
    rlen = strlen(trivial->client_realm);

    len = namelen + instlen + rlen + 3;
    p = buf = ckalloc(len);

    strcpy (p, trivial->client_principal);
    p += namelen + 1;

    strcpy (p, trivial->client_instance);
    p += instlen + 1;

    strcpy (p, trivial->client_realm);

    trivial->functions->Unameit_Conn_Write(conn, buf, len,
					   CONN_AUTH_ID_TRIVIAL, 0,
					   TCL_DYNAMIC);

    return TCL_OK;
}


/*
 * Process an authentication request after receiving it.
 * The read has already been done by the caller (Auth_Read).
 * This routine invokes the appropriate user login proc with the
 * domain and name of the principal.
 */

static int
Trivial_read_auth (
    ClientData	ctx,
    conn_t 	*conn,
    Tcl_Interp 	*interp,
    char 	*buf,
    unsigned32  len)
{
    Trivial_Context *trivial = (Trivial_Context *)ctx;
    char *pname;
    char *pinst;
    char *realm;

    Tcl_DString	cmd;
    int result = TCL_ERROR;

    assert (buf);
    assert (conn);

    if (!trivial->client_principal || !trivial->client_instance ||
	!trivial->client_realm)
    {
	return Trivial_Error(interp, "NOSETSERVICE", (char *)NULL);
    }

    pname = buf;
    pinst = pname + strlen (pname) + 1;

    if (pinst + 2 > buf + len)
    {
	return Trivial_BadArgs();
    }

    realm = pinst + strlen (pinst) + 1;
    if (realm + 1 > buf + len)
    {
	return Trivial_BadArgs();
    }

    if (realm + strlen(realm) + 1 != buf + len)
    {
	return Trivial_BadArgs();
    }

    /*
     * Magic principal has same name, instance and domain as server.
     */
    Tcl_DStringInit (&cmd);
    Tcl_DStringAppend (&cmd, "unameit_login_trivial", -1);

    if (strcmp(pname, trivial->client_principal) == 0 &&
	strcmp(pinst, trivial->client_instance) == 0 &&
	strcmp(realm, trivial->client_realm) == 0)
    {
	Tcl_DStringAppendElement (&cmd, AUTH_PRIVILEGED);
    }
    else
    {
	Tcl_DStringAppendElement (&cmd, AUTH_NORMAL);
    }

    Tcl_DStringAppendElement (&cmd, realm);
    Tcl_DStringAppendElement (&cmd, pname);

    if (*pinst)
    {
	Tcl_DStringAppendElement (&cmd, pinst);
    }

    result = Tcl_Eval (interp, Tcl_DStringValue(&cmd));
    Tcl_DStringFree(&cmd);
    return result;
}

/*
 * Store service info. Used by either host or client.
 */
static int
Trivial_set_service (
    ClientData	ctx,
    Tcl_Interp *interp,
    int argc,
    char **argv
)
{
    Trivial_Context *trivial = (Trivial_Context *)ctx;
    if (argc != 6)
    {
	return Trivial_BadArgs();
    }
    stringset (&trivial->client_principal, argv[3]);
    stringset (&trivial->client_instance, argv[4]);
    stringset (&trivial->client_realm, argv[5]);
    return TCL_OK;
}


static int
Trivial_kinit(
    ClientData	ctx,
    Tcl_Interp *interp,
    int argc,
    char **argv
)
{
    Trivial_Context *trivial = (Trivial_Context *)ctx;
    if (argc != 6)
    {
	return Trivial_BadArgs();
    }

    stringset (&trivial->client_principal, argv[3]);
    stringset (&trivial->client_instance, argv[4]);
    stringset (&trivial->client_realm, argv[5]);
    return TCL_OK;
}


/*
 * Check argument count,  and do nothing.
 */
static int
Trivial_Noop(ClientData d, Tcl_Interp *interp, int argc, char **argv)
{
    if (argc != 3 + (int)d)
    {
	return Trivial_BadArgs();
    }
    return TCL_OK;
}

#ifdef _MSC_VER	 
__declspec(dllexport)
#endif
int
Trivial_Init(Tcl_Interp *interp)
{
    char	**procPtr;

    static Trivial_Context trivial;

    static cmd_entry commands[] =
    {
	{"set_server", (ClientData)3, Trivial_Noop,
	    "service server_instance server_realm"},
	{"set_keytab", (ClientData)0, Trivial_Noop, ""},
	{"set_ccache", (ClientData)0, Trivial_Noop, ""},
	{"kdestroy", (ClientData)0, Trivial_Noop, ""},
	{"set_service", (ClientData)&trivial,  Trivial_set_service,
	    "service client_instance client_realm"},
	{"ksinit", (ClientData)&trivial, Trivial_kinit,
	    "client_principal client_instance client_realm"},
	{"kinit", (ClientData)&trivial, Trivial_kinit,
	    "client_principal client_instance client_realm"},
	{NULL, NULL, NULL, NULL}
    };

    static Auth_Functions calls =
    {
	CONN_AUTH_TRIVIAL,
	CONN_AUTH_ID_TRIVIAL,
	Trivial_read_auth, (ClientData)&trivial,
	Trivial_write_auth, (ClientData)&trivial,
	commands
    };

    if (Tcl_PkgRequire (interp, AUTH_NAME, AUTH_VERSION, 0) == NULL)
    {
	return TCL_ERROR;
    }

    for (procPtr = triverr; *procPtr; ++procPtr)
    {
	if (Tcl_Eval (interp, *procPtr) != TCL_OK)
	    return TCL_ERROR;
    }

    trivial.functions = (Auth_MasterFunctions *)
	Tcl_GetAssocData (interp, AUTH_MASTER_FUNCTIONS_KEY, NULL);

    assert (trivial.functions != NULL);
    assert (trivial.functions->Auth_Register != NULL);
    
    if (trivial.functions->Auth_Register(interp, &calls, trivialtcl) != TCL_OK)
    {
	Tcl_AppendResult (interp,
			  "\ncould not register trivial authentication module",
			  NULL);
	return TCL_ERROR;
    }

    return (Tcl_PkgProvide (interp, CONN_AUTH_TRIVIAL, TRIVIAL_VERSION));
}
