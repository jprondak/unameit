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
#include <unameit_start.h>
#include <version.h>

/*
 * 
 */
static const char *
bad_news (const char *format, ...)
{
    static char errmsg[BUFSIZE];
    va_list ap;
    va_start (ap, format);
    (void) vsprintf (errmsg, format, ap);
    va_end (ap);
    return errmsg;
}


/*
 * Look up values in the local registry for startup.
 * NOTE: This routine will leave the key open if an error occurs, since it is 
 * assumed that an error will be fatal. Returns NULL if okay, or
 * an error string for failures.
 */

const char *
unameit_getreg (char unameit[],
		DWORD n_unameit,
		char unameit_etc[],
		DWORD n_unameit_etc)
{    
    char keypath[BUFSIZE];
    DWORD dresult;
    DWORD size;
    HKEY key;
    
    /*
     * Get unameit location from Registry.
     */
    sprintf (keypath, "%s\\%s", TOP_KEY, UNAMEIT_VERSION);
    
    dresult = RegOpenKeyEx (HKEY_LOCAL_MACHINE, keypath, 0, KEY_READ, &key);
    if (dresult != ERROR_SUCCESS)
	return bad_news ("Could not find key '%s' in Registry.", keypath);

    size = n_unameit;
    dresult = RegQueryValueEx(key, "Root", NULL, NULL, unameit, &size);
    if (dresult != ERROR_SUCCESS)
	return ("Could not find value '%s\\Root' in Registry.", keypath);

    size = n_unameit_etc;
    dresult = RegQueryValueEx(key, "etc", NULL, NULL, unameit_etc, &size);
    if (dresult != ERROR_SUCCESS)
	return ("Could not find value '%s\\etc' in Registry.", keypath);
    RegCloseKey (key);
    return NULL;
}

static BOOL
unameit_set_envar (const char *envar, ...)
{
    Tcl_DString ds;
    char *s = NULL;
    BOOL result;
    va_list ap;

    Tcl_DStringInit (&ds);
    va_start (ap, envar);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_DStringAppend (&ds, s, -1);
    }
    va_end (ap);
    result = SetEnvironmentVariable (envar, Tcl_DStringValue (&ds));
    Tcl_DStringFree (&ds);

    return result;
}


/*
 * This routine set the environment using input values. Usually it
 * is called by unameit_setenv, but it may also be called from an
 * installation program.
 *
 * Most of the environment variables are for Tcl/Tk/Tclx.
 * Also set are:
 *	UNAMEIT - root of unameit software tree.
 *	UNAMEIT_ETC - the etc directory on this machine.
 *
 * Notes:
 *	UNAMEIT_MODE - user's mode (i.e. configuration) is not set
 *	by this routine.
 *
 * Environment variables used by TCL need to have '\' characters changed
 * to '/' characters.
 *
 */
const char *
unameit_setenviron (const char *unameit,
		    const char *unameit_etc)
{    
    Tcl_DString libpath;
    Tcl_DString ds;
    char uunameit[BUFSIZE];
    char wunameit[BUFSIZE];
    DWORD size;
    BOOL result;
    const char *from;
    char *to;
    
    for (from = unameit, to = uunameit; *from; 	++from,	++to)
    {
	if (*from == '\\')
	    *to = '/';
	else
	    *to = *from;
    }
    *to = '\0';
    
    for (from = unameit, to = wunameit; *from; 	++from,	++to)
    {
	if (*from == '/')
	    *to = '\\';
	else
	    *to = *from;
    }
    *to = '\0';
    
    Tcl_DStringInit (&libpath);
    Tcl_DStringInit (&ds);

    Tcl_DStringAppend (&ds, uunameit, -1);
    Tcl_DStringAppend (&ds, "/lib/tcl/lib", -1);
    Tcl_DStringAppendElement (&libpath, Tcl_DStringValue (&ds));
    Tcl_DStringFree (&ds);

    Tcl_DStringAppend (&ds, uunameit, -1);
    Tcl_DStringAppend (&ds, "/lib/unameit", -1);
    Tcl_DStringAppendElement (&libpath, Tcl_DStringValue (&ds));
    Tcl_DStringFree (&ds);
    
    result = SetEnvironmentVariable ("TCLLIBPATH", 
				     Tcl_DStringValue (&libpath));
    Tcl_DStringFree (&libpath);
    if (!result)
	return ("Could not set Environment Variable TCLLIBPATH.");
    
    result = unameit_set_envar ("TCL_LIBRARY", uunameit, 
				"/lib/tcl/lib/tcl", TCL_VERSION,
				(char *)NULL);
    if (!result)
	return ("Could Not Set Environment Variable TCL_LIBRARY.");

    result = unameit_set_envar ("TK_LIBRARY", uunameit,
				"/lib/tcl/lib/tk", TK_VERSION, 
				(char *)NULL);
    if (!result)
	return ("Could Not Set Environment Variable TK_LIBRARY.");

    result = unameit_set_envar ("TCLX_LIBRARY", uunameit,
				"/lib/tcl/lib/tclx", TCLX_VERSION,
				(char *)NULL);
    if (!result)
	return ("Could Not Set Environment Variable TCLX_LIBRARY.");

    result = unameit_set_envar ("TKX_LIBRARY", uunameit,
				"/lib/tcl/lib/tkx", TKX_VERSION,
				(char *)NULL);
    if (!result)
	return ("Could Not Set Environment Variable TKX_LIBRARY.");

    result = unameit_set_envar ("PATH",
				"\"", wunameit, "\\bin\\exe\";",
				"\"", wunameit, "\\lib\\unameit\";",
				"\"", wunameit, "\\lib\\tcl\\bin\";",
				"\"", wunameit, "\\lib\\krb5\\bin\";",
				(char *)NULL);
    if (!result)
	return ("Could Not Set Environment Variable PATH.");

    /* Set location of unameit on this machine. */
    result = SetEnvironmentVariable ("UNAMEIT", uunameit);
    if (!result)
	return ("Could Not Set Environment Variable UNAMEIT.");
    
    /* Set location of /etc on this machine. This is optional. */
    if (unameit_etc)
    {
	result = SetEnvironmentVariable ("UNAMEIT_ETC", unameit_etc);
	if (!result)
	    return ("Could Not Set Environment Variable UNAMEIT_ETC.");
    }
    
    return NULL;
}


/*
 * Most of the environment variables are for Tcl/Tk/Tclx.
 * Also set are:
 *	UNAMEIT - root of unameit software tree.
 *	UNAMEIT_ETC - the etc directory on this machine.
 *
 * Note:
 *	UNAMEIT_MODE - user's mode (i.e. configuration) is not set
 *	by this routine.
 *
 * This routine will leave the key open if an error occurs, since it is 
 * assumed that an error will be fatal.
 */
const char *
unameit_setenv ()
{
    char unameit[BUFSIZE];
    char unameit_etc[BUFSIZE];
    const char *sresult = unameit_getreg (unameit, sizeof(unameit),
					  unameit_etc, sizeof(unameit_etc));
    if (sresult)
	return sresult;
    
    return (unameit_setenviron (unameit, unameit_etc));
}

