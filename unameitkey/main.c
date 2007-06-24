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
static char rcsid[] = "$Id: main.c,v 1.19.2.4 1997/09/21 23:43:07 viktor Exp $";

#include <uconfig.h>
#include <error.h>

#include <time.h>
#include <termios.h>

#include <net/if.h>
#ifndef linux
#include <netinet/if_ether.h>
#endif

#include <krb5.h>
#include <md5.h>
#include <radix.h>

#include "bootstrap.h"

static char	padding[] = "\0""0123456789abcdef";

static char 	item_query[] = "select count(x) "
			       "from all named_item x "
			       "where x.\"deleted\" IS NULL";
static char 	host_query[] = "select count(x) "
			       "from all host x "
			       "where x.\"deleted\" IS NULL";
static char 	person_query[] = "select count(x) "
			       "from all person x "
			       "where x.\"deleted\" IS NULL";

static union {
    unsigned char buf[16];
    struct {
	unsigned32	i1;
	unsigned32	i2;
	unsigned32	i3;
	unsigned32	i4;
    } iarr;
} iun;

static int
New_Key(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    register int 	i;
    register char	*p;
    MD5_CTX		ctx;
    char		*host_units_str, *person_units_str;
    int			host_units, person_units;
    char		*start_time_str, *end_time_str;
    time_t		start_time, end_time;
    char		*type;
    char		ascii_key[R16], ascii_key_w_dashes[R16+(R16/4)];
    char		phrase[256];
    int			phrase_len = sizeof(phrase);
    char		*macaddress;
    char		*prompt = "Passphrase: ";

    if (argc != 7) {
	return TCL_ERROR;
    }

    if (krb5_read_password(NULL, prompt, prompt, phrase, &phrase_len) != 0)
    {
	Tcl_SetResult(interp, "Password mismatch", TCL_STATIC);
	return TCL_ERROR;
    }

    type = *++argv;
    host_units_str = *++argv;
    if (Tcl_GetInt(interp, host_units_str, &host_units) != TCL_OK) {
	return TCL_ERROR;
    }
    person_units_str = *++argv;
    if (Tcl_GetInt(interp, person_units_str, &person_units) != TCL_OK) {
	return TCL_ERROR;
    }
    start_time_str = *++argv;
    start_time = strtol(start_time_str, NULL, 10);
    end_time_str = *++argv;
    end_time = strtol(end_time_str, NULL, 10);
    macaddress = *++argv;

    MD5Init(&ctx);
    MD5Update(&ctx, phrase, phrase_len+1);
    MD5Update(&ctx, padding, sizeof(padding));
    MD5Update(&ctx, item_query, sizeof(item_query));
    MD5Update(&ctx, host_query, sizeof(host_query));
    MD5Update(&ctx, person_query, sizeof(person_query));
    MD5Update(&ctx, macaddress, strlen(macaddress)+1);
    MD5Update(&ctx, type, strlen(type)+1);
    MD5Update(&ctx, host_units_str, strlen(host_units_str)+1);
    MD5Update(&ctx, person_units_str, strlen(person_units_str)+1);
    MD5Update(&ctx, start_time_str, strlen(start_time_str)+1);
    MD5Update(&ctx, end_time_str, strlen(end_time_str)+1);
    MD5Final(&ctx);

    iun.iarr.i1 = unsigned32_hton((unsigned32)host_units);
    iun.iarr.i2 = unsigned32_hton((unsigned32)person_units);
    iun.iarr.i3 = unsigned32_hton((unsigned32)start_time);
    iun.iarr.i4 = unsigned32_hton((unsigned32)end_time);

    for (i = 0; i < 16; ++i) {
	iun.buf[i] ^= ctx.digest[i];
    }

    Udb_Radix16_Encode(iun.buf, sizeof(iun.buf), ascii_key);
    for (i = 0, p = ascii_key_w_dashes; i < R16-1; i++, p++) {
	if (i != 0 && i % 4 == 0) {
	    *p++ = '-';
	}
	*p = ascii_key[i];
    }
    *p = '\0';

    Tcl_AppendElement(interp, ascii_key_w_dashes);
    return TCL_OK;
}


static int
AppInit(Tcl_Interp *interp)
{
    char	**procdef;

    assert(interp);

    Tcl_Init(interp);
    Tclx_Init(interp);

    Tcl_CreateCommand(interp, "new_key", New_Key, 0, 0);

    for (procdef = bootstrap; *procdef; ++procdef)
    {
	if (Tcl_Eval(interp, *procdef) != TCL_OK)
	    return TCL_ERROR;
    }
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

    for(sp = new_argv+2; argc--;)
    {
	*++sp = *++argv;
    }
    TclX_Main(new_argc, new_argv, AppInit);
    /*
     * We should not really get here
     */
    ckfree((char *)new_argv);
    exit(1);
}
