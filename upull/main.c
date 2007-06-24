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
static char rcsid[] = "$Id: main.c,v 1.14.20.4 1997/09/21 23:43:11 viktor Exp $";

#include <uconfig.h>
#include <unameit_init.h>

#ifdef HAVE_SHADOW_H
#    include <shadow.h>
#endif

#include <fcntl.h>
#include <net/if.h>

/*
 * All the packages that are statically linked against upull should
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
	{"Auth", Auth_Init, Auth_Init, 1},
	{"Uclient", Uclient_Init, NULL, 1},
	{NULL, NULL, NULL, 0}
    };

static int Get_IP_Addresses(ClientData d, Tcl_Interp *interp, int argc,
			  char *argv[]);

static int Lock_File(char *s)
{
    int	i, fd;

    for (i = 0; i< 15; i++)
    {
	if ((fd = open(s, O_WRONLY|O_CREAT|O_EXCL, 0600)) >= 0)
	{
	    close(fd);
	    return 1;
	}
	sleep(1);
    }
    return 0;
}

#ifdef HAVE_LCKPWDF
static int
Lock_PW_File(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_DString	dstr;

    if (argc != 2) {
	Tcl_AppendResult(interp, "Usage: ", argv[0], " directory",
			 (char *)NULL);
	return TCL_ERROR;
    }
    if (Equal(argv[1], "/etc")) {
	if (lckpwdf() == -1) {
	  cannot_lock:
	    Tcl_SetResult(interp, "Cannot lock password file", TCL_STATIC);
	    return TCL_ERROR;
	}
    } else {
	Tcl_DStringInit(&dstr);
	Tcl_DStringAppend(&dstr, argv[1], -1);
	Tcl_DStringAppend(&dstr, "/passwd.ptmp", -1);
	if (!Lock_File(Tcl_DStringValue(&dstr))) {
	    Tcl_DStringFree(&dstr);
	    goto cannot_lock;
	}
	Tcl_DStringFree(&dstr);
    }
    return TCL_OK;
}

static int
Unlock_PW_File(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_DString dstr;

    if (argc != 2) {
	Tcl_AppendResult(interp, "Usage: ", argv[0], " directory",
			 (char *)NULL);
	return TCL_ERROR;
    }
    if (Equal(argv[1], "/etc")) {
	if (ulckpwdf() == -1) {
	    Tcl_SetResult(interp, "Cannot unlock password file", TCL_STATIC);
	    return TCL_ERROR;
	}
    } else {
	Tcl_DStringInit(&dstr);
	Tcl_DStringAppend(&dstr, argv[1], -1);
	Tcl_DStringAppend(&dstr, "/passwd.ptmp", -1);
	(void)unlink(Tcl_DStringValue(&dstr));
	Tcl_DStringFree(&dstr);
    }
    return TCL_OK;
}
#else /* HAVE_LCKPWDF */

static int
Lock_PW_File(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_DString dstr;

    if (argc != 2) {
	Tcl_AppendResult(interp, "Usage: ", argv[0], " directory",
			 (char *)NULL);
	return TCL_ERROR;
    }
    Tcl_DStringInit(&dstr);
    if (Equal(argv[1], "/etc")) {
	Tcl_DStringAppend(&dstr, "/etc/ptmp", -1);
    } else {
	Tcl_DStringAppend(&dstr, argv[1], -1);
	Tcl_DStringAppend(&dstr, "/passwd.ptmp", -1);
    }
    if (!Lock_File(Tcl_DStringValue(&dstr))) {
	Tcl_DStringFree(&dstr);
	Tcl_SetResult(interp, "Cannot lock password file", TCL_STATIC);
	return TCL_ERROR;
    }
    Tcl_DStringFree(&dstr);
    return TCL_OK;
}

static int
Unlock_PW_File(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_DString dstr;

    if (argc != 2) {
	Tcl_AppendResult(interp, "Usage: ", argv[0], " directory",
			 (char *)NULL);
	return TCL_ERROR;
    }
    Tcl_DStringInit(&dstr);
    if (Equal(argv[1], "/etc")) {
	Tcl_DStringAppend(&dstr, "/etc/ptmp", -1);
    } else {
	Tcl_DStringAppend(&dstr, argv[1], -1);
	Tcl_DStringAppend(&dstr, "/passwd.ptmp", -1);
    }
    (void)unlink(Tcl_DStringValue(&dstr));
    Tcl_DStringFree(&dstr);
    return TCL_OK;
}
#endif

#define MAX_IFR		16

static int
Get_IP_Addresses(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    struct ifreq   	ifr[MAX_IFR];
    struct ifconf  	ifc;
    int 	   	s;

    assert(interp);
    assert(argc >= 1);
    assert(argv);

    if (argc != 1) {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 "\"", (char *)NULL);
	return TCL_ERROR;
    }

    if ( (s = socket(AF_INET, SOCK_DGRAM, 0)) == -1 ) {
	return TCL_ERROR;
    }

    ifc.ifc_req=ifr;
    ifc.ifc_len=sizeof(ifr);

    if (ioctl(s, SIOCGIFCONF, &ifc)==-1) {
	(void) close(s);
	return TCL_ERROR;
    }

    for ( ; ifc.ifc_len > 0; ifc.ifc_len -= sizeof(ifr[0]), ++ifc.ifc_req ) {

	if (ioctl(s, SIOCGIFFLAGS, (char *)ifc.ifc_req) < 0) {
	    continue;
	}

#define BITS_ON   	(IFF_BROADCAST | IFF_UP | IFF_RUNNING)
#define BITS_OFF	(IFF_NOARP | IFF_LOOPBACK)

	if (((ifc.ifc_req->ifr_flags & BITS_ON) != BITS_ON) ||
	    ((ifc.ifc_req->ifr_flags & BITS_OFF) != 0)) {
	    continue;
	}

	if ((ioctl(s, SIOCGIFADDR, (char *)ifc.ifc_req)) == -1) {
	    continue;
	}

	Tcl_AppendElement(interp,
	 inet_ntoa(((struct sockaddr_in *)&ifc.ifc_req->ifr_addr)->sin_addr));
    }	
    (void) close(s);

    return TCL_OK;
}

#include <unameit_init.h>
#include "bootstrap.h"

static int
AppInit(Tcl_Interp *interp)
{
    struct Inits	*initPtr;
    char		**procdef;

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

    Tcl_CreateCommand(interp, "lock_pw_file", Lock_PW_File, 0, 0);
    Tcl_CreateCommand(interp, "unlock_pw_file", Unlock_PW_File, 0, 0);
    Tcl_CreateCommand(interp, "get_ip_addrs", Get_IP_Addresses, 0, 0);

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
