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
static char rcsid[] = "$Id: main.c,v 1.12.18.6 1997/09/21 23:43:08 viktor Exp $";

#include <uconfig.h>
#include <unameit_init.h>
#include "bootstrap.h"

extern int Udb_Radix64_Decode(char *s1, char *s2);


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
	{"Uaddress", Uaddress_Init, Uaddress_Init, 1},
	{NULL, NULL, NULL, 0}
    };


static int
Uuid_To_Hex(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    int			i;
    unsigned char	buf[16];
    char		hex_buf[3];

    if (argc != 2) {
	Tcl_SetResult(interp, argv[0], TCL_VOLATILE);
	Tcl_AppendResult(interp, " uuid", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EINTERNAL", "EUSAGE", "uuid",
			 (char *)NULL);
	return TCL_ERROR;
    }
    if (Udb_Radix64_Decode(argv[1], buf) != 0) {
	Tcl_SetResult(interp, "Invalid item UUID", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "ENOTUUID", argv[1], (char *)NULL);
	return TCL_ERROR;
    }
    for (i = 0; i < 16; i++) {
	(void)sprintf(hex_buf, "%02x", buf[i]);
	(void)strcat(interp->result, hex_buf);
    }
    return TCL_OK;
}

static int
AppInit(Tcl_Interp *interp)
{
    struct Inits	*initPtr;
    char		**procdef;

    assert(interp);

    if (Tcl_Init(interp) == TCL_ERROR)
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

    Tcl_CreateCommand(interp, "uuid_to_hex", Uuid_To_Hex, 0, 0);

    for (procdef = bootstrap; *procdef; ++procdef)
    {
	if (Tcl_Eval(interp, *procdef) != TCL_OK)
	    return TCL_ERROR;
    }
    return TCL_OK;
}


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

    TclX_Main(new_argc, new_argv, AppInit);
    /* Should not get here. */
    ckfree((char *)new_argv);
    return 1;
}
