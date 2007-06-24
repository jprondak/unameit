/*
 * Copyright (c) 1995 Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: krb4.c,v 1.21.8.6 1997/09/21 23:42:24 viktor Exp $";

#include <uconfig.h>
#include <auth.h>
#include <md5.h>
#include <arith_types.h>

#ifdef SOCKET_ERROR
#undef SOCKET_ERROR
#endif

#define DEFINE_SOCKADDR

#define des_key_sched mit_des_key_sched
#define des_ecb_encrypt mit_des_ecb_encrypt

#include <kerberosIV/krb.h>
#include <kerberosIV/krb4-proto.h>

#define UK4_VERSION "2.0"

#include "krb4tcl.h"
#include "krb4err.h"

#define Uk4_BadArgs() Uk4_Error (interp, 0, "EBADARGS", (char *)NULL)

static void
Unameit_DesMd5_Mic_Enable(
    conn_t *conn,
    void *key,
    conn_state_t state,
    int seqno
);

static void
Unameit_DesMd5_Update_Mic(conn_t *conn, int reset);


typedef struct
{
    char *srvtab; 		/* set by Uk4_set_service */
    char *server_principal;	/* set by Uk4_set_server */
    char *server_instance;	/* set by Uk4_set_server */
    char *server_realm;		/* set by Uk4_set_server */
    char *client_principal;	/* set by Uk4_kinit or Uk4_set_service */
    char *client_instance;	/* set by Uk4_kinit or Uk4_set_service */
    char *client_realm;		/* set by Uk4_kinit or Uk4_set_service */
    char *ccache_type;		/* set by Uk4_set_ccache */
    char *ccache_name;		/* set by Uk4_set_ccache */
    Auth_MasterFunctions *functions;
}
Uk4_Context;


static int
Uk4_Error (Tcl_Interp *interp, int k_err, const char *code, ...)
{
    va_list 	ap;
    char	*s = "none";

    assert(code);
    if (k_err != 0)
	s = (char *)krb_err_txt[k_err];

    Tcl_ResetResult (interp);

    Tcl_SetErrorCode (interp, "UNAMEIT", AUTH_ERROR,
		      CONN_AUTH_KRB4, s, code, (char *)NULL);

    va_start(ap, code);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}


static void
stringset (char **ps, const char *s)
{
    assert (ps);
    if (*ps)
	ckfree(*ps);
    if (s)
    {
	*ps = ckalloc (strlen(s) + 1);
	(void) strcpy (*ps, s);
    }
    else
    {
	*ps = NULL;
    }
}


static char *
make_principal(const char *pname)
{
    static char		buf[ANAME_SZ];
    register char	*cp;

    for (cp = buf; *pname && cp < &buf[sizeof(buf) - 1]; ++cp, ++pname)
    {
	*cp = *pname;
    }

    *cp = '\0';
    return buf;
}


static char *
make_instance(const char *inst)
{
    static char		buf[INST_SZ];
    register char	*cp;

    for (cp = buf;
	 *inst && *inst != '.' && cp < &buf[sizeof(buf) - 1];
	 ++cp, ++inst)
    {
	*cp = *inst;
    }

    *cp = '\0';
    return buf;
}


static char *
make_realm(Tcl_Interp *interp, const char *realm)
{
    static char		buf[REALM_SZ];
    register char	*cp;

    if (!*realm)
    {
	int k_err;
	if ((k_err = krb_get_lrealm (buf, 1)) != 0)
	{
	    Uk4_Error(interp, k_err, "ELREALM", (char *)0);
	    return NULL;
	}
	return buf;
    }

    for (cp = buf; *realm && cp < &buf[sizeof(buf) - 1]; ++cp, ++realm)
    {
	*cp = *realm;
    }

    *cp = '\0';
    return buf;
}


/*
 * Generate a message for authenticating to the server.
 * No arguments are used.
 * This routine sends the message and sets the connection authentication.
 */
static int
Uk4_write_auth (ClientData ctx, conn_t *conn, Tcl_Interp *interp, int argc, char **argv)
{
    Uk4_Context	*uk4 = (Uk4_Context *)ctx;
    unsigned32  len;
    CREDENTIALS creds;
    struct      ktext ktext;
    int		k_err;

    assert(uk4);
    assert(conn);

    if (!uk4->server_principal || !uk4->server_instance || !uk4->server_realm)
    {
	return Uk4_Error(interp, 0, "NOSETSERVER");
    }

    if ((k_err = krb_mk_req (&ktext,
			     uk4->server_principal,
			     uk4->server_instance,
			     uk4->server_realm,
			     (unsigned32)0)) != KSUCCESS)
    {
	return Uk4_Error (interp, k_err, "MKREQ",
			  uk4->server_principal, uk4->server_instance,
			  uk4->server_realm, (char *)NULL);
    }

    len = ktext.length;
    /*
     * Extract shared key from ticket cache,  so we can turn crypto
     * MIC code.  But the authentication exchange will arrive using
     * the status-quo crypto handshake (initially none).
     */
    if ((k_err = krb_get_cred (uk4->server_principal,
			       uk4->server_instance,
			       uk4->server_realm,
			       &creds)) != GC_OK)
    {
	return Uk4_Error(interp, k_err, "GETCRED", (char *)NULL);
    }

    /*
     * We have a shared key, install it for next read.
     * Continue writing with whatever crypto handshake existed before.
     */
    Unameit_DesMd5_Mic_Enable(conn, creds.session, CONN_READING, 0);

    uk4->functions->Unameit_Conn_Write(conn, ktext.dat, len,
				       CONN_AUTH_ID_KRB4, 0, TCL_VOLATILE);
    return TCL_OK;
}


/*
 * Process an authentication request after receiving it.
 * The read has already been done by the caller (Auth_Read).
 * This routine must set in the interpreter the realm and name of the principal
 * requesting authentication.
 */
static int
Uk4_read_auth (ClientData 	ctx,
	       conn_t 		*conn,
	       Tcl_Interp 	*interp,
	       char 		*buf,
	       unsigned32  	len)
{
    Uk4_Context *uk4 = (Uk4_Context *)ctx;
    struct      ktext ktext;
    int		k_err;
    AUTH_DAT 	ad;
    char	*client_type = AUTH_NORMAL;
    int		result;
    Tcl_DString	cmd;

    assert(uk4);
    assert(conn);

    if (!uk4->client_principal || !uk4->client_instance ||
	!uk4->client_realm || !uk4->srvtab)
    {
	return Uk4_Error(interp, 0, "NOSETSERVICE");
    }

    if (len > sizeof(ktext.dat))
    {
	return Uk4_Error (interp, 0, "APINVAL", (char *)NULL);
    }

    ktext.length = len;
    memcpy(ktext.dat, buf, len);

    k_err = krb_rd_req (&ktext, uk4->client_principal,
			uk4->client_instance, 0L, &ad, uk4->srvtab);
    if(k_err != RD_AP_OK)
    {
	return Uk4_Error (interp, k_err, "RDREQ", (char *)NULL);
    }

    /*
     * We have a shared key, install it for next write.
     * Since we have just finished reading, the key will take effect
     * right away.
     */
    Unameit_DesMd5_Mic_Enable(conn, ad.session, CONN_WRITING, 0);

    /*
     * Determine if this is a special client.
     */
    if (strcmp (ad.prealm, uk4->client_realm) == 0 &&
        strcmp (ad.pname, uk4->client_principal) == 0 &&
        strcmp (ad.pinst, uk4->client_instance) == 0)
    {
	client_type = AUTH_PRIVILEGED;
    }

    Tcl_DStringInit(&cmd);

    Tcl_DStringAppendElement(&cmd, "unameit_login_ukrbiv");
    Tcl_DStringAppendElement(&cmd, client_type);
    Tcl_DStringAppendElement(&cmd, ad.prealm);
    Tcl_DStringAppendElement(&cmd, ad.pname);

    if (*ad.pinst)
    {
	Tcl_DStringAppendElement(&cmd, ad.pinst);
    }

    result = Tcl_Eval(interp, Tcl_DStringValue(&cmd));
    Tcl_DStringFree(&cmd);
    return result;
}


/*
 * Store service info. Used by servers.
 */
static int
Uk4_set_service (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk4_Context *uk4 = (Uk4_Context *)ctx;

    if (argc != 7)
    {
	Uk4_BadArgs();
	return TCL_ERROR;
    }

    stringset (&uk4->client_realm, make_realm(interp, argv[5]));
    if (uk4->client_realm == NULL)
    {
	return TCL_ERROR;
    }

    stringset (&uk4->client_principal, make_principal(argv[3]));
    stringset (&uk4->client_instance, make_instance(argv[4]));
    stringset (&uk4->srvtab, argv[6]);

    return TCL_OK;
}


/*
 * Store server info. Used by clients.
 */
static int
Uk4_set_server (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk4_Context *uk4 = (Uk4_Context *)ctx;

    if (argc != 6)
    {
	Uk4_BadArgs();
	return TCL_ERROR;
    }

    stringset (&uk4->server_realm, make_realm(interp, argv[5]));
    if (uk4->server_realm == NULL)
    {
	return TCL_ERROR;
    }

    stringset (&uk4->server_principal, make_principal(argv[3]));
    stringset (&uk4->server_instance, make_instance(argv[4]));

    return TCL_OK;
}


/*
 * Change the credential cache (known as the ticket file in k4).
 */
static int
Uk4_set_ccache (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk4_Context *uk4 = (Uk4_Context *)ctx;

    assert(uk4);

    if (argc != 5)
    {
	return Uk4_BadArgs();
    }

    stringset (&uk4->ccache_type, argv[3]);
    stringset (&uk4->ccache_name, argv[4]);

    if (!strcmp ("default", argv[3]))
    {
	krb_set_tkt_string ("");
    }
    else if (!strcmp ("file", argv[3]))
    {
	krb_set_tkt_string (argv[4]);
    }
    else if (!strcmp ("temporary", argv[3]))
    {
	char *ccache_name = tempnam (NULL, "uk4_");
	if (!ccache_name)
	    panic ("tempnam failed");
	krb_set_tkt_string (ccache_name);
	stringset (&uk4->ccache_name, ccache_name);
	free (ccache_name);
    }
    else
    {
	Uk4_Error(interp, 0, "CCACHETYPE",
		  argv[3], (char *)NULL);
	return TCL_ERROR;
    }

    return TCL_OK;
}


static int
Uk4_kinit(ClientData unused, Tcl_Interp *interp, int argc, char **argv)
{
    char	*name;
    char	*inst;
    char	*realm;
    char 	*password;
    int  	k_err;
    int  	life = 255;

    if (argc != 7)
    {
	return Uk4_BadArgs();
    }

    realm = make_realm(interp, argv[5]);
    if (realm == NULL)
    {
	return TCL_ERROR;
    }
    name = make_principal(argv[3]);
    inst = make_instance(argv[4]);
    password = argv[6];

    if (strlen (password) < 1)
    {
	return Uk4_Error (interp, 0, "NOPASSWORD", (char *)NULL);
    }

    if ((k_err = krb_get_pw_in_tkt (name, inst, realm, "krbtgt", realm,
				    life, password)) != KSUCCESS)
    {
	Uk4_Error (interp, k_err, "KINIT",
		   name, inst, realm, (char *)NULL);
	return TCL_ERROR;
    }
    return TCL_OK;
}

/*
 * This version uses the srvtab file to get the key.
 */
static int
Uk4_ksinit(ClientData unused, Tcl_Interp *interp, int argc, char **argv)
{
    int  k_err;
    int  life = 1;
    char *name;
    char *inst;
    char *realm;
    char *srvtab;

    if (argc != 7)
    {
	return Uk4_BadArgs();
    }

    realm = make_realm(interp, argv[5]);
    if (realm == NULL)
    {
	return TCL_ERROR;
    }

    name = make_principal(argv[3]);
    inst = make_instance(argv[4]);
    srvtab = argv[6];

    if ((k_err = krb_get_svc_in_tkt (name, inst, realm, "krbtgt",
				     realm, life, srvtab)) != KSUCCESS)
    {
	Uk4_Error (interp, k_err, "KSINIT",
		   srvtab, name, inst, realm, (char *)NULL);
	return TCL_ERROR;
    }
    return TCL_OK;
}

/*
 * Close the credential cache and destroy it.
 */
static int
Uk4_kdestroy(ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk4_Context *uk4 = (Uk4_Context *)ctx;
    int k_err = 0;

    if (argc != 3)
    {
	return Uk4_BadArgs();
    }

    if (!uk4->ccache_name)
    {
	return TCL_OK;
    }

    k_err = dest_tkt ();

    if (k_err != 0)
    {
	return Uk4_Error (interp, k_err, "CCACHENOTDEST",
			  uk4->ccache_type, uk4->ccache_name, (char *)NULL);
    }
    stringset(&uk4->ccache_type, (char *)NULL);
    stringset(&uk4->ccache_name, (char *)NULL);

    return TCL_OK;
}


int
Ukrbiv_Init(Tcl_Interp *interp)
{
    char	**procPtr;

    static Uk4_Context uk4;

    static cmd_entry commands[] =
    {
	{"set_server", &uk4, Uk4_set_server,
		"service server_instance server_realm"},
	{"set_ccache", &uk4, Uk4_set_ccache, "ccache_type ccache_name"},
	{"kinit", &uk4, Uk4_kinit,
	    "client_principal client_instance client_realm password"},
	{"ksinit", &uk4, Uk4_ksinit,
	    "client_principal client_instance client_realm srvtab"},
	{"kdestroy", &uk4, Uk4_kdestroy, ""},
	{"set_service", &uk4, Uk4_set_service,
	    "service client_instance client_realm srvtab"},
	{NULL, NULL}
    };

    static Auth_Functions calls =
    {
	CONN_AUTH_KRB4,
	CONN_AUTH_ID_KRB4,
	Uk4_read_auth, &uk4,
	Uk4_write_auth, &uk4,
	commands
    };

    if (Tcl_PkgRequire (interp, AUTH_NAME, AUTH_VERSION, 0) == NULL)
    {
	Tcl_AppendResult (interp,
			  "\ncould not load kerberos 4 module without ",
			  AUTH_NAME, " ", AUTH_VERSION, NULL);
	return TCL_ERROR;
    }

    for (procPtr = krb4err; *procPtr; ++procPtr)
    {
	if (Tcl_Eval (interp, *procPtr) != TCL_OK)
	    return TCL_ERROR;
    }

    uk4.functions = (Auth_MasterFunctions *)
	Tcl_GetAssocData (interp, AUTH_MASTER_FUNCTIONS_KEY, NULL);
    
    assert (uk4.functions != NULL);
    assert (uk4.functions->Auth_Register != NULL);

    if (uk4.functions->Auth_Register (interp, &calls, krb4tcl) != TCL_OK)
    {
	Tcl_AppendResult (interp,
			  "\ncould not initialize kerberos 4 module",
			  NULL);
	return TCL_ERROR;
    }

    return (Tcl_PkgProvide (interp, CONN_AUTH_KRB4, UK4_VERSION));
}

#include "desmd5.c"
