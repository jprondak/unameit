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
#include <uconfig.h>
#include <winreg.h>
#include <tcl.h>

/*
 * The registry command connects to the requested key on the requested
 * machine.
 * 
 *	registry name host key
 *
 * where host may be "" and key is one of 
 *	HKEY_LOCAL_MACHINE
 *	HKEY_USERS
 *	HKEY_CURRENT_USER
 *	HKEY_CLASSES_ROOT
 *
 * Note that only the first two are valid on a foreign host.
 *
 * This creates a command 'name' that has the following subcommands (similar
 * to array commands):
 *
 *	name keys path
 *		returns list of keys at that path
 *	name names path
 *		returns list of value names at that path
 *	name set path name value [name value...]
 *		sets values at that path
 *	name get path
 *		returns [name value...] 
 */

typedef struct
{
    HKEY hkey;
}
RegistryInfo;

static int
Registry_Error (Tcl_Interp *interp, const char *code, LONG err)
{
    LPVOID lpMsgBuf = NULL;
   
    Tcl_SetResult (interp, "registry command failed", TCL_STATIC);
    
    if (err != 0)
    {
	FormatMessage( 
	    FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
	    NULL,
	    err,
	    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
	    (LPTSTR) &lpMsgBuf,
	    0,
	    NULL);
    }
    Tcl_SetErrorCode (interp, "REGISTRY", code, lpMsgBuf, (char *)NULL);

    if (lpMsgBuf)
	LocalFree(lpMsgBuf);
    
    return TCL_ERROR;
}



/*
 *---------------------------------------------------------------------------
 * Return a list of all of the subkeys in the given path. Does not return
 * value names.
 *---------------------------------------------------------------------------
 */
static int
Registry_Keys (ClientData d, 
	       Tcl_Interp *interp, 
	       int argc, 
	       char **argv)
{ 
    int result = TCL_ERROR;
    RegistryInfo *reginfo = (RegistryInfo *)d;
    char *path;
    LONG regresult;
    HKEY hkey;
    DWORD keynum = 0;
    int *goofy= NULL;
    
    assert (reginfo);
    if (argc != 2)
    {
	Tcl_SetResult (interp,
		       "wrong # args",
		       TCL_STATIC);
	return TCL_ERROR;
    }
    path = argv[1];
    
    regresult = RegOpenKeyEx (reginfo->hkey,
			      path,
			      0,
			      KEY_READ,
			      &hkey);
    if (ERROR_SUCCESS != regresult)
    {
	Registry_Error (interp, "RegOpenKeyEx", regresult);
	return TCL_ERROR;
    }

    for (keynum = 0; ; keynum++)
    {
	char keyname[1000];
	char keyclass[1000];
	DWORD keyname_size = sizeof keyname;
	DWORD keyclass_size = sizeof keyclass;
	
	regresult = RegEnumKeyEx (hkey,
				  keynum,
				  keyname,
				  &keyname_size,
				  NULL,
				  keyclass,
				  &keyclass_size,
				  NULL);
	
	if (ERROR_NO_MORE_ITEMS == regresult)
	    break;
	
	if (ERROR_SUCCESS != regresult)
	{
	    Registry_Error (interp, "RegEnumKeyEx", regresult);
	    goto finished;
	}
	Tcl_AppendElement (interp, keyname);
    }
    RegCloseKey (hkey);
    result = TCL_OK;
    
finished:
    return result;
}


/*
 *---------------------------------------------------------------------------
 * Return the names of the values at the given path. Does not return keys,
 * just the leaf nodes.
 *---------------------------------------------------------------------------
 */
static int
Registry_Names (ClientData d, 
		Tcl_Interp *interp, 
		int argc, 
		char **argv)
{ 
    int result = TCL_ERROR;
    RegistryInfo *reginfo = (RegistryInfo *)d;
    char *path;
    LONG regresult;
    HKEY hkey;
    DWORD valuenum = 0;
    char *pattern = NULL;
    
    assert (reginfo);
    switch (argc)
    {
    case 3 :
	pattern = argv[2];
	/* fall through */

    case 2 :
	path = argv[1];
	break;
	
    default :
	Tcl_SetResult (interp,
		       "wrong # args",
		       TCL_STATIC);
	return TCL_ERROR;
    }
    
    regresult = RegOpenKeyEx (reginfo->hkey,
			      path,
			      0,
			      KEY_READ,
			      &hkey);
    if (ERROR_SUCCESS != regresult)
    {
	Registry_Error (interp, "RegOpenKeyEx", regresult);
	return TCL_ERROR;
    }

    for (valuenum = 0; ; valuenum++)
    {
	char value_name[1000];
	DWORD value_name_size = sizeof value_name;
	DWORD value_type = 0;
	BOOL addme = FALSE;
	
	regresult = RegEnumValue (hkey,
				  valuenum,
				  value_name,
				  &value_name_size,
				  NULL,
				  &value_type,
				  NULL,
				  NULL);
	
	if (ERROR_NO_MORE_ITEMS == regresult)
	    break;
	
	if (ERROR_SUCCESS != regresult)
	{
	    Registry_Error (interp, "RegEnumKeyEx", regresult);
	    goto finished;
	}

	switch (value_type)
	{
	case REG_SZ : 
	case REG_EXPAND_SZ : 
	    addme = pattern ? Tcl_StringMatch (pattern, value_name) : TRUE;
	}

	if (addme)
	    Tcl_AppendElement (interp, value_name);
    }
    RegCloseKey (hkey);
    result = TCL_OK;
    
finished:
    return result;
}


/*
 *---------------------------------------------------------------------------
 * Return a list of name value pairs.
 *---------------------------------------------------------------------------
 */
static int
Registry_Get (ClientData d, 
	      Tcl_Interp *interp, 
	      int argc, 
	      char **argv)
{ 
    int result = TCL_ERROR;
    RegistryInfo *reginfo = (RegistryInfo *)d;
    char *path;
    LONG regresult;
    HKEY hkey;
    DWORD valuenum = 0;
    char *pattern = NULL;
    
    assert (reginfo);
    switch (argc)
    {
    case 3 :
	pattern = argv[2];
	/* fall through */

    case 2 :
	path = argv[1];
	break;
	
    default :
	Tcl_SetResult (interp,
		       "wrong # args",
		       TCL_STATIC);
	return TCL_ERROR;
    }

    regresult = RegOpenKeyEx (reginfo->hkey,
			      path,
			      0,
			      KEY_READ,
			      &hkey);
    if (ERROR_SUCCESS != regresult)
    {
	Registry_Error (interp, "RegOpenKeyEx", regresult);
	return TCL_ERROR;
    }

    for (valuenum = 0; ; valuenum++)
    {
	char value_name[1000];
	char value[1000];
	DWORD value_name_size = sizeof value_name;
	DWORD value_size = sizeof value;
	DWORD value_type = 0;
	BOOL addme = FALSE;
	
	regresult = RegEnumValue (hkey,
				  valuenum,
				  value_name,
				  &value_name_size,
				  NULL,
				  &value_type,
				  value,
				  &value_size);
	
	if (ERROR_NO_MORE_ITEMS == regresult)
	    break;
	
	if (ERROR_SUCCESS != regresult)
	{
	    Registry_Error (interp, "RegEnumKeyEx", regresult);
	    goto finished;
	}
	
	switch (value_type)
	{
	case REG_SZ : 
	case REG_EXPAND_SZ : 
	    addme = pattern ? Tcl_StringMatch (pattern, value_name) : TRUE;
	}

	if (addme)	
	{
	    Tcl_AppendElement (interp, value_name);
	    Tcl_AppendElement (interp, value);
	}
    }

    RegCloseKey (hkey);
    result = TCL_OK;
    
finished:
    return result;
}


/*
 *---------------------------------------------------------------------------
 * Set a list of values in the given key. The key is created if it does
 * not exist. An empty list of arguments is allowable, to create an empty
 * key.
 *---------------------------------------------------------------------------
 */
static int
Registry_Set (ClientData d, 
	      Tcl_Interp *interp, 
	      int argc, 
	      char **argv)
{ 
    int result = TCL_ERROR;
    RegistryInfo *reginfo = (RegistryInfo *)d;
    char *path = NULL;
    LONG regresult;
    HKEY hkey;
    int i;
    
    assert (reginfo);
    if (argc < 2)
    {
	Tcl_SetResult (interp, "wrong # args", TCL_STATIC);
	return TCL_ERROR;
    }
    if (argc & 1)
    {
	Tcl_SetResult (interp, "unbalanced argument list", TCL_STATIC);
	return TCL_ERROR;
    }
    path = argv[1];
    
    regresult = RegCreateKeyEx (reginfo->hkey,
				path,
				0,
				NULL,
				0,
				KEY_ALL_ACCESS,
				NULL,
				&hkey,
				NULL);
    if (ERROR_SUCCESS != regresult)
    {
	Registry_Error (interp, "RegCreateKeyEx", regresult);
	return TCL_ERROR;
    }

    for (i = 2; i < argc; i+=2)
    {
	regresult = RegSetValueEx (hkey,
				   argv[i],
				   0,
				   REG_SZ,
				   argv[i+1],
				   strlen (argv[i+1]) + 1);
	if (ERROR_SUCCESS != regresult)
	{
	    Registry_Error (interp, "RegSetValueEx", regresult);
	    goto finished;
	}
    }
    result = TCL_OK;
    
finished:
    RegCloseKey (hkey);
    return result;
}

/*
 *---------------------------------------------------------------------------
 * Return true if the key exists and is readable.
 *---------------------------------------------------------------------------
 */
static int
Registry_Exists (ClientData d, 
		 Tcl_Interp *interp, 
		 int argc, 
		 char **argv)
{ 
    int result = TCL_ERROR;
    RegistryInfo *reginfo = (RegistryInfo *)d;
    LONG regresult;
    char *path = NULL;
    HKEY hkey;
    
    assert (reginfo);
    if (argc != 2)
    {
	Tcl_SetResult (interp,
		       "wrong # args",
		       TCL_STATIC);
	return TCL_ERROR;
    }
    path = argv[1];
    
    regresult = RegOpenKeyEx (reginfo->hkey,
			      path,
			      0,
			      KEY_READ,
			      &hkey);
    if (ERROR_SUCCESS == regresult)
    {
	Tcl_SetResult (interp, "1", TCL_STATIC);
	RegCloseKey (hkey);
    }
    else
	Tcl_SetResult (interp, "0", TCL_STATIC);
    return TCL_OK;
}


/*
 *---------------------------------------------------------------------------
 * Execute a subcommand.
 *---------------------------------------------------------------------------
 */
static int
Registry_Cmd (ClientData d, 
	      Tcl_Interp *interp, 
	      int argc, 
	      char **argv)
{ 
    int result = TCL_ERROR;
    RegistryInfo *reginfo = (RegistryInfo *)d;
    char *command;

    assert (reginfo);
    if (argc < 2)
    {
	Tcl_SetResult (interp,
		       "wrong # args: must supply a subcommand",
		       TCL_STATIC);
	return TCL_ERROR;
    }
    command = argv[1];
    
    if (! (strcmp (command, "keys")))
	return (Registry_Keys (d, interp, argc-1, argv+1));
    if (! (strcmp (command, "names")))
	return (Registry_Names (d, interp, argc-1, argv+1));
    if (! (strcmp (command, "get")))
	return (Registry_Get (d, interp, argc-1, argv+1));
    if (! (strcmp (command, "set")))
	return (Registry_Set (d, interp, argc-1, argv+1));
    if (! (strcmp (command, "exists")))
	return (Registry_Exists (d, interp, argc-1, argv+1));

    Tcl_SetResult (interp,
		   "registry commands are keys, names, get, set",
		   TCL_STATIC);
    return TCL_ERROR;
}

    
    
static void
Registry_Disconnect (ClientData d)
{
    RegistryInfo *reginfo = (RegistryInfo *)d;

    assert (reginfo);
    
    RegCloseKey (reginfo->hkey);
    ckfree ((void *) reginfo);
}


static int
Registry_Connect (ClientData d, 
		 Tcl_Interp *interp, 
		 int argc, 
		 char **argv)
{ 
    int result = TCL_ERROR;
    char *host;
    char *command;
    char *key;
    HKEY hkey;
    LONG regresult;
    RegistryInfo *reginfo = NULL;
    
    if (argc != 4)
    {
	Tcl_SetResult (interp,
		       "wrong # args: registry name host key",
		       TCL_STATIC);
	return TCL_ERROR;
    }
    
    command = argv[1];
    if (strlen (argv[2]) > 0)
	host = argv[2];
    else 
	host = NULL;
    key = argv[3];
    
    if (! strcmp (key, "HKEY_LOCAL_MACHINE"))
	hkey = HKEY_LOCAL_MACHINE;
    else if (! strcmp (key, "HKEY_USERS"))
	hkey = HKEY_USERS;
    else if (! strcmp (key, "HKEY_CURRENT_USER"))
	hkey = HKEY_CURRENT_USER;
    else if (! strcmp (key, "HKEY_CLASSES_ROOT"))
	hkey = HKEY_CLASSES_ROOT;
    else
    {
	Tcl_AppendResult (interp, key, " is not a valid key", (char *) NULL);
	return TCL_ERROR;
    }

    reginfo = (RegistryInfo *) ckalloc (sizeof (*reginfo));
    assert (reginfo);
    
    regresult = RegConnectRegistry (host,
				    hkey,
				    &(reginfo->hkey));
    if (regresult != ERROR_SUCCESS)
    {
	Registry_Error (interp, "RegConnectRegistry", regresult);
	goto finished;
    }

    Tcl_CreateCommand (interp, 
		       command, 
		       Registry_Cmd, 
		       (ClientData) reginfo, 
		       Registry_Disconnect);
    result = TCL_OK;
    
finished:
    if (result != TCL_OK)
    {
	if (reginfo)
	    ckfree ((void *) reginfo);
    }
    return result; 
} 




#ifdef _MSC_VER  
__declspec(dllexport)
#endif
int
Registry_Init (Tcl_Interp *interp)
{
    int		result;

    Tcl_CreateCommand (interp, 
		       "registry", 
		       Registry_Connect, 
		       NULL, 
		       NULL);
    result = Tcl_PkgProvide (interp, "Registry", "1.0");
    return result;
}

