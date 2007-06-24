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
static char rcsid[] = "$Id: init.c,v 1.5.10.3 1997/09/21 23:42:35 viktor Exp $";

#include <uconfig.h>

#define SCHEMA_MGR_VERSION "2.0"

#include "schema_mgr.h"

int Schema_mgr_Init(Tcl_Interp *interp)
{
    char	**s;
    int		result;

    assert(interp);

    if ((result = Tclx_Init(interp)) != TCL_OK) {
	return result;
    }

    for (s = schema_mgr; *s; s++) {
	if ((result = Tcl_Eval(interp, *s)) != TCL_OK) {
	    return result;
	}
    }

    if ((result = Tcl_PkgProvide(interp, "Schema_mgr", SCHEMA_MGR_VERSION))
	!= TCL_OK) {
	return result;
    }

    return TCL_OK;
}

int Schema_mgr_SafeInit(Tcl_Interp *interp)
{
    assert(interp);

    return Schema_mgr_Init(interp);
}
