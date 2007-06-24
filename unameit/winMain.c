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
static char rcsid[] = "$Id: winMain.c,v 1.2.12.2 1997/09/21 23:43:03 viktor Exp $";

/* 
 * winMain.c --
 *
 * Provides a default version of the Tcl_AppInit procedure for use with
 * applications built with Extended Tcl and Tk on Windows 95/NT systems.
 * This is based on the the UCB Tk file tkAppInit.c
 */
#include <uconfig.h>
#include <tk.h>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#undef WIN32_LEAN_AND_MEAN
#include <malloc.h>
#include <locale.h>

#include <unameit_init.h>
#include "bootstrap.h"

/*
 * The following declarations refer to internal Tk routines.  These
 * interfaces are available for use, but are not supported.
 */

EXTERN void
TkConsoleCreate (void);

EXTERN int
TkConsoleInit (Tcl_Interp *interp);

/*
 * All the packages that are statically linked against unameit should
 * go in the list below.
 */
static struct Inits
    {
	char			*pkg;
	Tcl_PackageInitProc	*pkg_init;
	Tcl_PackageInitProc	*pkg_safe_init;
	int			init_now;
    }
    inits[] =
    {
	{"Tk", Tk_Init, NULL, 1},
	{"Tclx", Tclx_Init, Tclx_SafeInit, 1},
	{"Auth", Auth_Init, Auth_Init, 1},
	{"Upasswd", Upasswd_Init, Upasswd_Init, 1},
	{"Uclient", Uclient_Init, NULL, 0},
	{"Uqbe", Uqbe_Init, Uqbe_Init, 0},
	{"Uaddress", Uaddress_Init, Uaddress_Init, 0},
	{"Cache_mgr", Cache_mgr_Init, NULL, 0},
	{"Schema_mgr", Schema_mgr_Init, NULL, 0},
	{"Ucanon", Ucanon_Init, Ucanon_Init, 0},
	{"Ordered_list", Ordered_list_Init, Ordered_list_Init, 1},
	{NULL, NULL, NULL, 0}
    };

static int
AppInit(Tcl_Interp *interp)
{
    struct Inits	*initPtr;
    char 		**procdef;

    assert(interp);

    /*
     * The "Tcl" Package is special.  It should not be registered as
     * a loadable package.
     */
    if (Tcl_Init(interp) != TCL_OK)
    {
	return TCL_ERROR;
    }
    
    for (initPtr = inits; initPtr->pkg; initPtr++)
    {
	if (initPtr->init_now && initPtr->pkg_init(interp) != TCL_OK)
	{
	    return TCL_ERROR;
	}
	Tcl_StaticPackage(initPtr->init_now ? interp : NULL,
			  initPtr->pkg,
			  initPtr->pkg_init,
			  initPtr->pkg_safe_init);
    }

    for (procdef = bootstrap; *procdef; ++procdef)
    {
	if (Tcl_Eval(interp, *procdef) != TCL_OK)
	    return TCL_ERROR;
    }

#ifdef DEBUG
    /*
     * Initialize the console for interactive applications.
     */
    if (TkX_ConsoleInit (interp) == TCL_ERROR)
        return TCL_ERROR;
#endif

    return Tcl_VarEval(interp, "after idle unameit_start", (char *)NULL);
}

/*-----------------------------------------------------------------------------
 * WinMain --
 *
 * This is the main program for the application.
 *-----------------------------------------------------------------------------
 */
int APIENTRY
WinMain(hInstance, hPrevInstance, lpszCmdLine, nCmdShow)
    HINSTANCE hInstance;
    HINSTANCE hPrevInstance;
    LPSTR lpszCmdLine;
    int nCmdShow;
{
    char **argv;
    int argc;
    char buffer [MAX_PATH];

    /*
     * Set up the default locale to be standard "C" locale so parsing
     * is performed correctly.
     */
    setlocale(LC_ALL, "C");

    /*
     * Increase the application queue size from default value of 8.
     * At the default value, cross application SendMessage of WM_KILLFOCUS
     * will fail because the handler will not be able to do a PostMessage!
     * This is only needed for Windows 3.x, since NT dynamically expands
     * the queue.
     */
    SetMessageQueue(64);

    /*
     * Create the console channels and install them as the standard
     * channels.  All I/O will be discarded until TkConsoleInit is
     * called to attach the console to a text widget.
     */
    TkConsoleCreate();

    /*
     * Parse the command line. Since Windows programs don't get passed the
     * command name as the first argument, we need to fetch it explicitly.
     */
    TclX_SplitWinCmdLine (&argc, &argv);
    GetModuleFileName (NULL, buffer, sizeof (buffer));
    argv[0] = buffer;

    TkX_Main(argc, argv, AppInit);

    return 0;                   /* Needed only to prevent compiler warning. */
}
