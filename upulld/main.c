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
static char rcsid[] = "$Id: main.c,v 1.8.18.2 1997/09/21 23:43:12 viktor Exp $";

#include <uconfig.h>
#include "ether.h"

/*
 * Stub get-mac-address function. Upulld needs non-recurring uuids,
 * but they do not need to be globally unique. This function can be
 * run by non-root upulld processes.
 */
int
Uuid_Get_Macaddress(ether_addr_t *ea)
{
    assert(ea);

    memset (ea, 0, sizeof(*ea));
    return TCL_OK;
}


int
main(int argc, char **argv)
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
    TclX_Main(new_argc, new_argv, Tcl_AppInit);
    /*
     * We should not really get here
     */
    ckfree((char *)new_argv);
    exit(1);
}
