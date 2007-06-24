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
 *
 * This is a loadable module which reads configuration files, and
 * contains compiled-in defaults.
 */

#include <uconfig.h>

#include "confproc.h"
#define CONFIG_NAME 		("Config")
#define CONFIG_VERSION 		("1.3")

#if HAVE_SYSCONF && defined(_SC_PAGESIZE)
#    define PSIZE	(sysconf(_SC_PAGESIZE))
#elif HAVE_GETPAGESIZE
#    define PSIZE	((long)getpagesize())
#else
#    define PSIZE	4096L
#endif


static int
Config_Pagesize (
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    sprintf (interp->result, "%ld", PSIZE);
    return TCL_OK;
}

	
#ifdef _MSC_VER	 
__declspec(dllexport)
#endif
int
Config_Init (Tcl_Interp *interp)
{
    int		result;
    char 	**procedures = NULL;
    
    for (procedures = confproc;*procedures; ++procedures)
    {
	if (Tcl_Eval (interp, *procedures) != TCL_OK)
	    return TCL_ERROR;
    }
    
    Tcl_CreateCommand (interp, "unameit_config_pagesize",
		       Config_Pagesize, NULL, NULL);
    
    result = Tcl_PkgProvide (interp, CONFIG_NAME, CONFIG_VERSION);
    return result;
}
