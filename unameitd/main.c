/*
 * Copyright (c) 1997, Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: main.c,v 1.23.12.4 1997/09/21 23:43:06 viktor Exp $";

#include <uconfig.h>
#include <unameit_init.h>

#include "bootstrap.h"

/*
 * All the packages that are statically linked against unameitd should
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
	{"Tclx", Tclx_Init, Tclx_SafeInit, 1},
	{"Uuid", Uuid_Init, Uuid_Init, 1},
	{"Userver", Userver_Init, NULL, 1},
	{"Auth", Auth_Init, Auth_Init, 1},
	{"Upasswd", Upasswd_Init, Upasswd_Init, 1},
	{"Udb", Udb_Init, NULL, 0},
	{"Umeta", Umeta_Init, NULL, 0},
	{"Uaddress", Uaddress_Init, Uaddress_Init, 0},
	{"Uqbe", Uqbe_Init, Uqbe_Init, 0},
	{"Ucanon", Ucanon_Init, Ucanon_Init, 0},
	{NULL, NULL, NULL, 0}
    };

#ifdef DEBUG
/*
 * The internal version of the server exports the 'master_eval'
 * command to '-b' bootstrap scripts,  so we can get access to udb_interp
 * and meta_interp for debugging.
 */
static int
MasterEval(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    char *cmd = Tcl_Merge(argc-1, argv+1);
    int result = Tcl_GlobalEval(interp, cmd);
    ckfree(cmd);
    return result;
}
#endif


static int
AppInit(Tcl_Interp *interp)
{
    char		*argv0;
    char		*tail;
    struct Inits	*initPtr;
    char		**procdef;
    
    assert(interp);

    argv0 = Tcl_GetVar2(interp, "argv0", NULL, TCL_GLOBAL_ONLY);

    if (argv0 == NULL)
    {
	argv0 = "UName*It";
    }
    else if ((tail = strrchr(argv0, '/')) != NULL)
    {
	argv0 = ++tail;
    }

    openlog(argv0, LOG_PID, LOG_LOCAL0);

    Tcl_InitMemory(interp);

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
    Tcl_CreateCommand(interp, "master_eval", MasterEval, 0, 0);
#endif

    return TCL_OK;
}

/* The initialization procedure works like this:

   - main() inserts "-c unameit_start" in argv
   - It then calls TclX_Main
   - TclX_Main calls AppInit
   - AppInit
       - Calls all the *_Init functions it needs to for the main interpreter
       - Registers all the statically linked packages it uses in this
         application
       - Loads all the bootstrap procedures into the interpreter
   - Tcl sees the "-c unameit_start" command and runs it. It
       - Calls unameit_db_login which creates the udb_interp and
         umeta_interp interpreters and loads the appropriate packages into
	 the new interpreters.
       - Runs the rest of the main Tcl code for the application.

   The *_Init routines registered in the packages above are either invoked
   invoked manually in AppInit or invoked via "load {} <pkg> <interp>" in
   the Tcl code. These *_Init routines are written manually. They

   - Read in all the Tcl procedures stored in the global string created by
     the tcl2c program.
   - Add any additional bindings to C functions in the C code.
   - Call Tcl_PkgProvide to designate that this package has been loaded into
     this interpreter.
*/
int
main(int argc, char *argv[])
{
    int  new_argc;
    char **new_argv;
    char **sp;

    new_argc = argc + 2;
    new_argv = (char **)ckalloc((new_argc+1) * sizeof(char *));
    new_argv[0] = argv[0];
    new_argv[1] = "-nc";
    new_argv[2] = "unameit_start";

    for(sp = &new_argv[2]; argc--;)
    {
	*++sp = *++argv;
    }

    Tcl_CreateExitHandler((Tcl_ExitProc *)Tcl_Free, (ClientData)new_argv);
    TclX_Main(new_argc, new_argv, AppInit);
    return 1;
}
