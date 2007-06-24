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
/*
 * Create ShellLink shortcuts (Windows 'scripts').
 * TBD - call CoUnInitialize if this command is deleted...
 */

#include <uconfig.h>
#include <shlobj.h>
 
typedef struct
{
    int x;
}
ShortcutInfo;

static ShortcutInfo *shortcut = NULL;

static int
Shortcut_Error (Tcl_Interp *interp, const char *code)
{
    DWORD err = GetLastError();
    LPVOID lpMsgBuf = NULL;
   
    Tcl_SetResult (interp, "shortcut command failed", TCL_STATIC);
    
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
    Tcl_SetErrorCode (interp, "SHORTCUT", code, lpMsgBuf, (char *)NULL);

    if (lpMsgBuf)
	LocalFree(lpMsgBuf);
    return TCL_ERROR;
}

/*
 * CreateLink - uses the shell's IShellLink and IPersistFile interfaces 
 * to create and store a shortcut to the specified object. 
 * Returns the result of calling the member functions of the interfaces. 
 * lpszPathObj - address of a buffer containing the path of the object 
 * lpszPathLink - address of a buffer containing the path where the 
 *  shell link is to be stored (the new object to be created)
 * lpszDesc - address of a buffer containing the description of the 
 *  shell link 
 */


static int
Shortcut_Create (ClientData unused, 
		 Tcl_Interp *interp, 
		 int argc, 
		 char **argv)
{ 
    LPSTR lpszPathObj = NULL;
    LPSTR lpszPathLink = NULL;
    LPSTR lpszDesc = "UName*It shortcut";
    LPSTR lpszArguments = NULL;
    LPSTR lpszIconLocation = NULL;
    int icon = 0;
    HRESULT	hres; 
    IShellLink* psl = NULL; 
    IPersistFile* ppf = NULL; 
    WORD wsz[MAX_PATH]; 
    int result = TCL_ERROR;

    if (argc != 6)
    {
	Tcl_SetResult (interp,
		       "wrong # args: shortcut_create link file arguments icon_file icon_index",
		       TCL_VOLATILE);
	return TCL_ERROR;
    }
    lpszPathLink = argv[1];
    lpszPathObj = argv[2];
    lpszArguments = argv[3];
    lpszIconLocation = argv[4];
    if (strlen (argv[5]) > 0)
    {
	result = Tcl_GetInt (interp, argv[5], &icon);
	if (result != TCL_OK)
	    return TCL_ERROR;
    }
    
    /* Get a pointer to the IShellLink interface. */
    hres = CoCreateInstance(&CLSID_ShellLink, 
			    NULL, 
			    CLSCTX_INPROC_SERVER, 
			    &IID_IShellLink, 
			    &psl); 
    if (! (SUCCEEDED(hres)))
    {
	Shortcut_Error (interp, "CoCreateInstance");
	goto finished;
    }
    
    /* Set the path to the shortcut target, and add the description.  */
        
    hres = psl->lpVtbl->SetPath(psl, lpszPathObj); 
    if (! (SUCCEEDED(hres)))
    {
	Shortcut_Error (interp, "SetPath");
	goto finished;
    }
   
    hres = psl->lpVtbl->SetDescription(psl, lpszDesc); 
    if (! (SUCCEEDED(hres)))
    {
	Shortcut_Error (interp, "SetDescription");
	goto finished;
    }

    hres = psl->lpVtbl->SetArguments(psl, lpszArguments); 
    if (! (SUCCEEDED(hres)))
    {
	Shortcut_Error (interp, "SetArguments");
	goto finished;
    }

    if (strlen (lpszIconLocation) > 0) 
    {
	hres = psl->lpVtbl->SetIconLocation(psl, lpszIconLocation, icon); 
	if (! (SUCCEEDED(hres)))
	{
	    Shortcut_Error (interp, "SetIconLocation");
	    goto finished;
	}
    }

    /* Query IShellLink for the IPersistFile interface for saving the  */
    /* shortcut in persistent storage.  */
								      
    hres = psl->lpVtbl->QueryInterface(psl, &IID_IPersistFile, &ppf); 
    if (! (SUCCEEDED(hres)))
    {
	Shortcut_Error (interp, "QueryInterface");
	goto finished;
    }
            
    /* Ensure that the string is ANSI. */
    MultiByteToWideChar(CP_ACP, 0, lpszPathLink, -1, wsz, MAX_PATH); 
             
    /* Save the link by calling IPersistFile::Save.  */
    hres = ppf->lpVtbl->Save(ppf, wsz, TRUE); 

    if (! (SUCCEEDED(hres)))
    {
	Shortcut_Error (interp, "Save");
	goto finished;
    }
    result = TCL_OK;
    
finished:
     if (ppf)
	 ppf->lpVtbl->Release(ppf); 
     if (psl)
	 psl->lpVtbl->Release(psl); 
     return result; 
} 

#ifdef _MSC_VER  
__declspec(dllexport)
#endif
int
Shortcut_Init (Tcl_Interp *interp)
{
    int		result;

    if (!shortcut)
    {
	shortcut = (ShortcutInfo *) ckalloc (sizeof (*shortcut));
	CoInitialize (NULL);
    }

    Tcl_CreateCommand (interp, 
		       "shortcut_create", 
		       Shortcut_Create, 
		       (ClientData) shortcut, 
		       NULL);
    result = Tcl_PkgProvide (interp, "Shortcut", "1.0");
    return result;
}

