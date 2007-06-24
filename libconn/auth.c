/*
 * Copyright (c) 1996, 1997 Enterprise Systems Management Corp.
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
/*
 *
 * This is a loadable module which calls loadable authorization
 * modules that have registered their entry points. Any such modules
 * should use Tcl_PkgRequire on Auth to ensure that initialization is
 * done properly, and then call Auth_Register to register their routines.
 *
 * Each module must implement a params command which returns a list of
 * parameter names for each command. 
 *
 * The set_ccache command describes the type of credential cache. The
 * implementation varies from module to module. The types are:
 * 
 *	default		use the default mechanism. 
 *	file		use a cache file. empty name indicates default.
 *	temporary	initialize private temporary credential cache.
 */
static char rcsid[] = "$Id: auth.c,v 1.6.8.4 1997/09/21 23:42:21 viktor Exp $";

#include <auth.h>
#include "authtcl.h"

/*
 * Context data for unameit_authorize module.
 */
typedef struct
{
    Tcl_HashTable    *auth_modules_by_name;
    Tcl_HashTable    *auth_modules_by_type;
    Auth_MasterFunctions functions;
} Auth_Context;
    
static Auth_Context *auth = NULL;

static int
Auth_Error (Tcl_Interp *interp, const char *code, ...)
{
    va_list 	ap;
    char	*s;

    assert(code);
    
    Tcl_ResetResult (interp);
    
    Tcl_SetErrorCode (interp, "UNAMEIT", AUTH_ERROR,  
		      "auth", code, (char *)NULL);

    va_start(ap, code);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}


#define Auth_BadArgs() Auth_Error (interp, "EBADARGS", (char *)NULL)

/*
 * Store the callbacks for the module.
 * This must be called by the _Init routine of the module when it is loaded.
 * Currently this call makes the commands available to any module
 * which has Auth loaded. 
 * If 'procedures' is not NULL, the strings in it will be eval'ed.
 * NOTE: the callback structure is NOT copied.
 * TBD - does not check for previously registered name or number.
 */

int
Auth_Register (Tcl_Interp *interp, Auth_Functions *calls, char **procedures)
{
    int name_is_new = 0;
    int type_is_new = 0;
    Tcl_HashEntry *ten = Tcl_CreateHashEntry (auth->auth_modules_by_name,
					     (char *) calls->name, 
					     &name_is_new);
    Tcl_HashEntry *tet = Tcl_CreateHashEntry (auth->auth_modules_by_type,
					      (char *) calls->type, 
					      &type_is_new);

    Tcl_SetHashValue (tet, (ClientData) calls);
    Tcl_SetHashValue (ten, (ClientData) calls);
    if (procedures)
    {
	for (;*procedures; ++procedures)
	{
	    if (Tcl_Eval (interp, *procedures) != TCL_OK)
		return TCL_ERROR;
	}
    }
    
    return TCL_OK;
}

/*
 * This routine is invoked when a connection is accepted. The
 * authorization type is in the incoming message.
 */
int
Auth_Read (ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    conn_t *conn = (conn_t *)d;
    int		result = TCL_ERROR;
    conn_auth_t	auth_type = conn->conn_message.auth_type;
    Auth_Functions *auth_functions = NULL;
    Tcl_HashEntry *te = NULL;
    char 	*buf = NULL;
    unsigned32  len = 0;
    unsigned32  ret_code;

    assert (conn);
    
    if (conn->conn_errno)
    {
	return Auth_Error (interp, "EIO", (char *)NULL);
    }
    
    /*
     * This gives us ownership of the underlying memory!
     * We must free it as soon as ready to do so.
     */
    buf = Unameit_Conn_Read(conn, &len, &ret_code);

    /*
     * Check the message integrity 
     */
    if (conn->conn_message.read_crypto.mic_ok != 1)
    {
	/*
	 * Session is corrupted: Return diagnostic to client
	 */
	Tcl_SetResult (interp, "Message integrity check failed.", TCL_STATIC);
	result = Auth_Error (interp, "EBADMIC", (char *)NULL);
	goto cleanup;
    }

    te = Tcl_FindHashEntry (auth->auth_modules_by_type, (char *) auth_type);
    if (!te)
    {
	result = Auth_Error (interp, "EWEAKMOD", (char *)NULL);
	goto cleanup;
    }
    auth_functions = (Auth_Functions *) Tcl_GetHashValue (te);

    assert (auth_functions->read_auth_function != NULL);
    result = 
	auth_functions->read_auth_function (auth_functions->read_auth_data, 
					    conn, interp, buf, len);
cleanup:    
    if (buf)
	ckfree (buf);
    return result;
}

int
Auth_Write (ClientData d, Tcl_Interp *interp, int argc, char **argv)
{
    conn_t		*conn = (conn_t *)d;
    int			result;
    char		*auth_name = NULL;
    Auth_Functions	*auth_functions = NULL;
    Tcl_HashEntry	*te = NULL;

    if (conn->conn_errno)
    {
	return Auth_Error (interp, "EIO", (char *)NULL);
    }

    if (argc < 2)
    {
	return Auth_BadArgs ();
    }
    auth_name = argv[1];
    
    te = Tcl_FindHashEntry (auth->auth_modules_by_name, auth_name);
    if (!te)
    {
	return Auth_Error (interp, "ENOMOD", auth_name, (char *)NULL);
    }
    auth_functions = (Auth_Functions *) Tcl_GetHashValue (te);

    assert (auth_functions->write_auth_function != NULL);
    result = 
	auth_functions->write_auth_function (auth_functions->write_auth_data, 
					     conn, interp, argc, argv);
    return result;
}

/*
 * Command for Auth objects. 
 */
static int
Auth_Cmd (ClientData d, Tcl_Interp *interp, int argc, char **argv)
{
    const char *auth_name = NULL;
    Auth_Functions *auth_functions = NULL;
    Tcl_HashEntry *te = NULL;
    cmd_entry *c = NULL;
    int params_only = (int) d;
    const char *command = NULL;
    
    if (argc < 3)
    {
	return Auth_BadArgs();
    }
    auth_name = argv[1];
    
    te = Tcl_FindHashEntry (auth->auth_modules_by_name, (char *) auth_name);
    if (!te)
    {
	return Auth_Error (interp, "ENOMOD", auth_name, (char *)NULL);
    }
    auth_functions = (Auth_Functions *) Tcl_GetHashValue (te);

    assert (auth_functions != NULL);
    assert (auth_functions->command_functions != NULL);
    command = argv[2];
    
    for (c = auth_functions->command_functions; c->command; c++)
    {
	if (!strcmp (command, c->command))
	{
	    if (params_only)
	    {
		Tcl_SetResult (interp, (char *) c->params, TCL_STATIC);
		return TCL_OK;
	    }
	    return (c->proc (c->command_data, interp, argc, argv));
	}
    }
    return Auth_Error (interp, "ENOTSUPPCMD", 
		       auth_name, command, (char *)NULL);
}

int
Auth_Init (Tcl_Interp *interp)
{
    int		result;
    char 	**procedures = NULL;
    
    if (!auth) 
    {
	auth = (Auth_Context *) ckalloc (sizeof (*auth));
	if (!auth)
	    panic ("Out of memory");
	memset (auth, 0, sizeof (*auth));
    
	auth->auth_modules_by_type = (Tcl_HashTable *) ckalloc (sizeof (Tcl_HashTable));
	if (!auth->auth_modules_by_type)
	    panic ("Out of memory");
	auth->auth_modules_by_name = (Tcl_HashTable *) ckalloc (sizeof (Tcl_HashTable));
	if (!auth->auth_modules_by_name)
	    panic ("Out of memory");
	
	Tcl_InitHashTable (auth->auth_modules_by_name, TCL_STRING_KEYS);
	Tcl_InitHashTable (auth->auth_modules_by_type, TCL_ONE_WORD_KEYS);

	/*
	 * Save addresses of functions to be used by loaded modules.
	 */
	auth->functions.Auth_Register = (auth_func *) Auth_Register;
	auth->functions.Unameit_Conn_Write = (auth_func *) Unameit_Conn_Write;
    }
    
    for (procedures = authtcl;*procedures; ++procedures)
    {
	if (Tcl_Eval (interp, *procedures) != TCL_OK)
	    return TCL_ERROR;
    }
    Tcl_CreateCommand (interp, "unameit_authorize", 
		       Auth_Cmd, (ClientData) 0, NULL);
    Tcl_CreateCommand (interp, "unameit_authorize_params", 
		       Auth_Cmd, (ClientData) 1, NULL);

    Tcl_SetAssocData (interp, AUTH_MASTER_FUNCTIONS_KEY, 
		      NULL, (ClientData) &(auth->functions));
    
    result = Tcl_PkgProvide (interp, AUTH_NAME, AUTH_VERSION);
    return result;
}

#include "md5.c"
