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
static char rcsid[] = "$Id: init.c,v 1.4.20.3 1997/09/21 23:42:19 viktor Exp $";

#include <uconfig.h>
#include <arith_types.h>

#define CANON_VERSION "1.1"
#include "canon.h"
#include "des.h"

static char alphabet[] = "./0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

static int seeded = 0;

static int
Canon_Error (Tcl_Interp *interp, const char *code, ...)
{
    va_list 	ap;
    char	*s;

    assert(code);

    Tcl_ResetResult (interp);

    Tcl_SetErrorCode (interp, "UNAMEIT", "CANON", code, (char *)NULL);

    va_start(ap, code);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}

#define Canon_BadArgs() Canon_Error (interp, "EBADARGS", (char *)NULL)


static char *
Random_Salt(void)
{
    unsigned32 rval = 0;
    static char result[3];

    if (!seeded)
    {
	time_t now = time(NULL);
	srand(now);
	seeded = 1;
    }

    rval = rand();
    result[0] = alphabet[rval & 0x3f];
    rval >>= 6;
    result[1] = alphabet[rval & 0x3f];
    result[2] = 0;
    
    return result;
}


static int
/*ARGSUSED*/
CryptCmd(ClientData unused, Tcl_Interp *interp, int argc, char *argv[])
{
    char *password;
    char *salt;

    if (argc < 2 || argc > 3) {
	return Canon_BadArgs();
    }

    password = argv[1];
    if (argc == 3)
	salt = argv[2];
    else
	salt = Random_Salt();

    Tcl_SetResult(interp, crypt(password, salt), TCL_VOLATILE);
    return TCL_OK;
}



int
Ucanon_Init(Tcl_Interp *interp)
{
    char	**s;
    int		result;

    assert(interp);

    for (s = canon; *s; s++) {
	if ((result = Tcl_Eval(interp, *s)) != TCL_OK) {
	    return result;
	}
    }

    Tcl_CreateCommand(interp, "unameit_crypt", CryptCmd, 0, 0);

    if ((result = Tcl_PkgProvide(interp, "Ucanon", CANON_VERSION))
	!= TCL_OK) {
	return result;
    }

    return TCL_OK;
}
