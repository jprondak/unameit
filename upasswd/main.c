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
static char rcsid[] = "$Id: main.c,v 1.11.18.3 1997/09/21 23:43:09 viktor Exp $";

#include <uconfig.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>

#ifdef HAVE_CRYPT_H
#include <crypt.h>
#endif

/*
 * Use socket based RPC
 */
#define PORTMAP
#include <rpc/rpc.h>
#include <rpcsvc/ypclnt.h>
#include <rpcsvc/yp_prot.h>
#include <rpc/pmap_clnt.h>
#include "yppasswd.h"

#include <unameit_init.h>

#include "bootstrap.h"

/*
 * All the packages that are statically linked against upasswd should
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
	{"Uclient", Uclient_Init, NULL, 1},
	{"Auth", Auth_Init, Auth_Init, 1},
	{"Upasswd", Upasswd_Init, Upasswd_Init, 1},
	{"Ucanon", Ucanon_Init, Ucanon_Init, 1},
	{NULL, NULL, NULL, 0}
    };


static int
update_yp(Tcl_Interp *interp, struct yppasswd *yp_pwd)
{
    char *yphost;
    int rpc_error;
    u_short port;
    int ok;
    char *domain = NULL;
    char *ypdata = NULL;
    int yplen = 0;
    struct sockaddr_in sain;
    struct hostent *hp;

    yp_get_default_domain(&domain);

    if (domain == NULL)
    {
	Tcl_SetResult(interp, "Could not get NIS domain name", TCL_STATIC);
	return TCL_ERROR;
    }

    yp_match(domain, "passwd.byname", yp_pwd->newpw.pw_name,
	strlen(yp_pwd->newpw.pw_name), &ypdata, &yplen);

    if (ypdata == NULL)
    {
	Tcl_SetResult(interp, "Password entry not in NIS", TCL_STATIC);
	return TCL_ERROR;
    }

    if (yp_master(domain, "passwd.byname", &yphost) != 0)
    {
	Tcl_SetResult(interp, "No master for yp map 'passwd.byname'",
	    TCL_STATIC);
	return TCL_ERROR;
    }

    if ((hp = gethostbyname(yphost)) == NULL || hp->h_addrtype != AF_INET)
    {
	Tcl_AppendResult(interp, "No IP address for ", yphost, (char *)NULL);
	return TCL_ERROR;
    }
	
    memset(&sain, 0, sizeof(sain));
    sain.sin_family = AF_INET;
    sain.sin_port = 0;
    memcpy(&sain.sin_addr, hp->h_addr, hp->h_length);

    port = pmap_getport(&sain, YPPASSWDPROG, YPPASSWDVERS, IPPROTO_UDP);

    if (port == 0)
    {
	Tcl_AppendResult(interp,
		"Warning: No yppasswd daemon on ", yphost, (char *)NULL);
	return TCL_ERROR;
    }

    if (port >= IPPORT_RESERVED || port < 512)
    {
	Tcl_AppendResult(interp, "Bad IP port for yppasswd daemon on ", yphost,
	    (char *)NULL);
	return TCL_ERROR;
    }

    rpc_error = callrpc(yphost, YPPASSWDPROG, YPPASSWDVERS,
	YPPASSWDPROC_UPDATE, xdr_yppasswd, (caddr_t)yp_pwd, xdr_int,
	(caddr_t)&ok);

    if (rpc_error != 0)
    {
	Tcl_AppendResult(interp, "RPC call to NIS passwd daemon failed: ",
		clnt_sperrno(rpc_error), (char *)NULL);
	return TCL_ERROR;
    }
    else if (ok != 0)
    {
	Tcl_SetResult(interp, "NIS entry not changed", TCL_STATIC);
	return TCL_ERROR;
    }
    else
    {
	Tcl_AppendResult(interp, "NIS entry changed on ", yphost,
			 (char *)NULL);
	return TCL_OK;
    }
}


static int
Yp_Change_Passwd(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    int  chshell = (int)d;
    char *login;
    char *oldpass;
    char *oldval;
    char *newval;
    struct passwd *pwd;
    static struct yppasswd yp_pwd;

    if (argc != 4)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " login oldpass newvalue\"", (char *)0);
	return TCL_ERROR;
    }

    login = argv[1];
    oldpass = argv[2];
    newval = argv[3];

    pwd = getpwnam(login) ;

    if (pwd == NULL)
    {
	Tcl_AppendResult(interp, login, " not in passwd file", (char *)NULL);
	return TCL_ERROR;
    }

    yp_pwd.oldpass = oldpass;
    yp_pwd.newpw = *pwd;

    if (!chshell)
    {
	oldval = crypt(oldpass, newval);
	yp_pwd.newpw.pw_passwd = newval;
    }
    else
    {
	oldval = yp_pwd.newpw.pw_shell;
	yp_pwd.newpw.pw_shell = newval;
    }

    if (strcmp(oldval, newval) == 0)
    {
	/*
	 * NOOP:  "yppasswdd" complains about non-changes,  so just
	 * skip the update
	 */
	return TCL_OK;
    }
    return update_yp(interp, &yp_pwd);
}


static int
GetPass(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
     if (argc !=2)
     {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" prompt\"", (char *)NULL);
	return TCL_ERROR;
     }
     Tcl_SetResult(interp, getpass(argv[1]), TCL_VOLATILE);
     return TCL_OK;
}

static int
AppInit(Tcl_Interp *interp)
{
    char		**procdef;
    struct Inits	*initPtr;

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

    (void) Tcl_CreateCommand(interp, "getpass", GetPass, 0, 0);
    (void) Tcl_CreateCommand(interp, "yp_change_passwd", Yp_Change_Passwd,
			     0, 0);
    (void) Tcl_CreateCommand(interp, "yp_change_shell", Yp_Change_Passwd,
			     (ClientData)1, 0);

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
    /*
     * We should not really get here
     */
    ckfree((char *)new_argv);
    exit(1);
}
