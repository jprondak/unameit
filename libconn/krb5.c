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
static char rcsid[] = "$Id: krb5.c,v 1.8.6.6 1997/09/21 23:42:25 viktor Exp $";

#include <uconfig.h>
#include <auth.h>
#include <md5.h>
#include <arith_types.h>

#ifdef SOCKET_ERROR
#undef SOCKET_ERROR
#endif
#include <krb5.h>
#include <com_err.h>

#define UK5_VERSION "2.0"

/* tcl procedures */
#include "krb5tcl.h"
#include "krb5err.h"

typedef enum {Init_Keytab, Init_Password} Init_t;

static void
Unameit_DesMd5_Mic_Enable(
    conn_t *conn,
    void *key,
    conn_state_t state,
    int seqno
);

static void
Unameit_DesMd5_Update_Mic(conn_t *conn, int reset);

/*
 * The strings are the user's input parameter, and are
 * saved for error reporting.
 */
typedef struct
{
    krb5_context context;	/* set in initialization */
    krb5_ccache ccache; 	/* set by Uk5_set_ccache */
    krb5_principal server;	/* set by Uk5_set_server */
    krb5_principal me;		/* set by Uk5_set_service */
    krb5_keytab keytab; 	/* set by Uk5_set_service */
    char *ccache_type; 	 	/* set by Uk5_set_ccache */
    char *ccache_name;	 	/* set by Uk5_set_ccache */
    Auth_MasterFunctions *functions;
}
Uk5_Context;

 
/*
 * TBD - remove this when Kerberos Unix catches up to Windows.
 */
#ifndef _WIN32
static void
krb5_free_data_contents (krb5_context context, 
                         krb5_data *data)
{
    free (data->data);
}
#endif

static void
stringset (char **ps, const char *s)
{
    assert (ps);
    if (*ps)
    {
	ckfree(*ps);
    }
    if (s != NULL)
    {
	*ps = ckalloc (strlen (s) + 1);
	strcpy (*ps, s);
    }
    else
    {
	*ps = NULL;
    }
}


static int
Uk5_Error (Tcl_Interp *interp, krb5_error_code k_err, const char *code, ...)
{
    va_list 	ap;
    char	*s = "none";

    assert(code);
    if (k_err != 0)
	s = (char *) error_message (k_err);

    Tcl_SetResult (interp, "Kerberos 5 error", TCL_STATIC);

    Tcl_SetErrorCode (interp, "UNAMEIT", AUTH_ERROR,
		      CONN_AUTH_KRB5, s, code, (char *)NULL);

    va_start(ap, code);
    while (NULL != (s = va_arg(ap, char *)))
    {
	Tcl_SetVar2(interp, "errorCode", NULL, s,
		    TCL_GLOBAL_ONLY|TCL_LIST_ELEMENT|TCL_APPEND_VALUE);
    }
    va_end(ap);
    return TCL_ERROR;
}


#define Uk5_BadArgs() Uk5_Error (interp, 0, "BADARGS", (char *)NULL)


static int
Uk5_resolve_keytab(
    krb5_context context,
    krb5_keytab *k,
    Tcl_Interp *interp,
    char *keytab
)
{
    krb5_error_code	k_err;

    if (*k)
    {
	krb5_kt_close(context, *k);
	*k = NULL;
    }

    if (*keytab)
    {
	k_err = krb5_kt_resolve (context, keytab, k);
    }
    else
    {
	k_err = krb5_kt_default (context, k);
    }

    if (k_err)
    {
	return Uk5_Error(interp, k_err, "KEYTAB", keytab, (char *)NULL);
    }
    return TCL_OK;
}


static int
Uk5_build_principal(
    krb5_context context,
    krb5_principal *p,
    Tcl_Interp *interp,
    char *name,
    char *inst,
    char *realm
)
{
    char		*defrealm = NULL;
    krb5_error_code	k_err;
    int			result = TCL_OK;

    if (*p)
    {
	krb5_free_principal(context, *p);
	*p = NULL;
    }

    if (!*realm)
    {
	k_err = krb5_get_default_realm (context, &defrealm);
	if (k_err)
        {
	    return Uk5_Error(interp, k_err, "DEFREALM", (char *)NULL);

	}
	realm = defrealm;
    }

    /* Special hack for TGS where instance == realm */
    if (inst == NULL)
    {
	inst = realm;
    }

    k_err = krb5_build_principal(context, p, strlen(realm), realm,
				 name, *inst ? inst : (char *)NULL,
				 (char *)NULL);

    if (k_err)
    {
	result = Uk5_Error(interp, k_err, "BADPRINCIPAL",
			   name, inst, realm, (char *)NULL);
    }

    if (defrealm)
	free(defrealm);

    return result;
}


static void
Uk5_Principal_Unknown(
    krb5_context context,
    Tcl_Interp *interp,
    krb5_error_code k_err,
    krb5_principal p
)
{
    char *pname;
    krb5_unparse_name(context, p, &pname);
    Uk5_Error(interp, k_err, "PRINCIPAL_UNKNOWN", pname, (char *)NULL);
    free(pname);
}


static int
Uk5_Req_Error(
    Uk5_Context *uk5,
    Tcl_Interp *interp,
    krb5_error_code k_err,
    krb5_principal me,
    krb5_principal server,
    char *defcode
)
{
    switch (k_err)
    {
    case KRB5KDC_ERR_C_PRINCIPAL_UNKNOWN :
	Uk5_Principal_Unknown(uk5->context, interp, k_err, me);
	break;

    case KRB5KDC_ERR_S_PRINCIPAL_UNKNOWN :
	Uk5_Principal_Unknown(uk5->context, interp, k_err, server);
	break;

    case KRB5KRB_AP_ERR_BAD_INTEGRITY :
	Uk5_Error(interp, k_err, "BADPASSWORD", (char *)NULL);
	break;

    case KRB5_FCC_NOFILE :
	Uk5_Error(interp, k_err, "FCC_NOFILE",
		  uk5->ccache_type, uk5->ccache_name, (char *)NULL);
	break;

    default :
	Uk5_Error(interp, k_err, defcode, (char *)NULL);
    }
    return TCL_ERROR;
}


static int
Uk5_mk_req(
    Uk5_Context         * uk5,
    Tcl_Interp		* interp,
    krb5_auth_context   * auth_context,
    krb5_data 		* outbuf
)
{
    krb5_error_code 	  retval;
    krb5_creds 		* credsp = NULL;
    krb5_creds 		  creds;

    /* obtain ticket & session key */
    memset(&creds, 0, sizeof(creds));
    creds.server = uk5->server;
    creds.client = NULL;

    retval = krb5_cc_get_principal(uk5->context, uk5->ccache, &creds.client);
    if (retval)
	goto cleanup;

    retval = krb5_get_credentials(uk5->context, 0, uk5->ccache,
				  &creds, &credsp);
    if (retval)
	goto cleanup;

    retval = krb5_mk_req_extended(uk5->context, auth_context, 0, 
				      NULL, credsp, outbuf);
    
cleanup:
    if (creds.client)
	krb5_free_principal(uk5->context, creds.client);
    if (credsp)
	krb5_free_creds(uk5->context, credsp);

    if (retval)
	return Uk5_Req_Error(uk5, interp, retval, creds.client,
			     creds.server, "MKREQ");

    return TCL_OK;
}


static int
Uk5_set_service (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk5_Context		*uk5 = (Uk5_Context *)ctx;
    int			pr_ok;
    int			kt_ok;

    if (argc != 7)
    {
	return Uk5_BadArgs();
    }

    kt_ok = Uk5_resolve_keytab(uk5->context, &uk5->keytab, interp,
			       argv[6] /* keytab name */);

    pr_ok = Uk5_build_principal(uk5->context, &uk5->me, interp,
				argv[3], /* name */
				argv[4], /* instance */
				argv[5]  /* realm */
				);

    if (kt_ok == TCL_OK && pr_ok == TCL_OK)
    {
	return TCL_OK;
    }
    return TCL_ERROR;
}


static int
Uk5_set_server (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk5_Context		*uk5 = (Uk5_Context *)ctx;

    if (argc != 6)
    {
	return Uk5_BadArgs();
    }

    return Uk5_build_principal(uk5->context, &uk5->server, interp,
			       argv[3], /* name */
			       argv[4], /* instance */
			       argv[5]  /* realm */
			       );
}


/*
 * Store ccache info. Used by either host or client.
 */
static int
Uk5_set_ccache (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk5_Context		*uk5 = (Uk5_Context *)ctx;
    char		ccache_name[MAXPATHLEN+8];
    krb5_error_code	k_err = 0;

    if (argc != 5)
    {
	return Uk5_BadArgs();
    }

    if (uk5->ccache)
    {
	krb5_cc_close (uk5->context, uk5->ccache);
	uk5->ccache = NULL;
    }

    ccache_name[0] = 0;

    if (!strcmp ("default", argv[3]))
    {
	k_err = krb5_cc_default (uk5->context, &uk5->ccache);
    }
    else if (!strcmp ("file", argv[3]))
    {
	sprintf (ccache_name, "FILE:%.*s", MAXPATHLEN, argv[4]);
	k_err = krb5_cc_resolve (uk5->context, ccache_name, &uk5->ccache);
    }
    else if (!strcmp ("temporary", argv[3]))
    {
	sprintf (ccache_name, "MEMORY:%.*s", MAXPATHLEN, argv[4]);
	k_err = krb5_cc_resolve (uk5->context, ccache_name, &uk5->ccache);
    }
    else
    {
	return Uk5_Error(interp, 0, "CCACHETYPE",
			 argv[3], (char *)NULL);
    }
    if (k_err)
    {
	return Uk5_Error(interp, k_err, "CCACHERESOLVE",
			 argv[3], argv[4], (char *)NULL);
    }

    stringset (&uk5->ccache_type, argv[3]);
    stringset (&uk5->ccache_name, argv[4]);

    return TCL_OK;
}

/*
 * Generate a message for authenticating to the server.
 */

static int
Uk5_write_auth (
    ClientData ctx,
    conn_t *conn,
    Tcl_Interp *interp,
    int argc,
    char **argv
)
{
    Uk5_Context		*uk5 = (Uk5_Context *)ctx;
    krb5_auth_context	auth_context = NULL;
    int			result;
    krb5_data		out_data;
    krb5_keyblock	*kb = NULL;

    if (!uk5->server)
    {
	return Uk5_Error(interp, 0, "NOSETSERVER", (char *)NULL);
    }

    if (!uk5->ccache)
    {
	return Uk5_Error(interp, 0, "NOSETCCACHE", (char *)NULL);
    }

    memset (&out_data, 0, sizeof (out_data));

    result = Uk5_mk_req(uk5, interp, &auth_context, &out_data);

    if (result != TCL_OK)
	goto cleanup;

    /*
     * Extract shared key so we can turn on crypto
     * MIC code.  But the authentication exchange will arrive using
     * the status-quo crypto handshake (initially none).
     */
    check(krb5_auth_con_getkey (uk5->context, auth_context, &kb) == 0);

    /*
     * We have a shared key, install it for next read.
     * Continue writing with whatever crypto handshake existed before.
     */
    Unameit_DesMd5_Mic_Enable (conn, kb->contents, CONN_READING, 0);


    uk5->functions->Unameit_Conn_Write (conn,
					out_data.data, out_data.length,
					CONN_AUTH_ID_KRB5, 0, TCL_VOLATILE);

cleanup:
    if (out_data.data)
	krb5_free_data_contents (uk5->context, &out_data);
    if (kb)
	krb5_free_keyblock (uk5->context, kb);
    if (auth_context)
	krb5_auth_con_free (uk5->context, auth_context);

    return result;
}

/*
 * Little utility routine to append a krb5_data string (which might not
 * be NULL-terminated) to a Tcl dynamic string.
 */
static void append_data (Tcl_DString	*ds,
			 krb5_data 	*kd)

{
    char *s = ckalloc (kd->length + 1);
    if (!s)
	panic ("Out of memory");
    memcpy (s, kd->data, kd->length);
    s[kd->length] = 0;
    Tcl_DStringAppendElement (ds, s);
    ckfree (s);
}

/*
 * Process an authentication request after receiving it.
 * The read has already been done by the caller (Auth_Read).
 * This routine invokes unameit_login_ukrbv with
 * the realm and name of the principal requesting authentication.
 */

static int
Uk5_read_auth (
    ClientData 	ctx,
    conn_t 	*conn,
    Tcl_Interp 	*interp,
    char 	*buf,
    unsigned32  len
)
{
    Uk5_Context		*uk5 = (Uk5_Context *)ctx;
    krb5_error_code	k_err = 0;
    krb5_keyblock	*kb = NULL;
    krb5_auth_context	auth_context = NULL;
    krb5_authenticator	*authenticator = NULL;
    krb5_data		in_data;
    krb5_data		*pr;
    Tcl_DString		cmd;
    char		*client_type = AUTH_NORMAL;
    int			i;
    int			result;

    Tcl_ResetResult (interp);

    assert(conn);
    assert(uk5);

    if (!uk5->me || !uk5->keytab)
    {
	return Uk5_Error(interp, 0, "NOSETSERVICE", (char *)NULL);
    }

    in_data.length = len;
    in_data.data = buf;

    k_err = krb5_rd_req (uk5->context, &auth_context, &in_data,
			 uk5->me, uk5->keytab, 0, NULL);
    if (k_err)
    {
	result = Uk5_Error(interp, k_err, "RDREQ", (char *)NULL);
	goto cleanup;
    }

    /* get the key */
    check(krb5_auth_con_getkey (uk5->context, auth_context, &kb) == 0);

    /*
     * We have a shared key, install it for next write.
     * Since we have just finished reading, the key will take effect
     * right away.
     */
    Unameit_DesMd5_Mic_Enable (conn, kb->contents, CONN_WRITING, 0);

    /*
     * We need to return the name of the principal that just connected.
     * This should not fail.
     */
    check(krb5_auth_con_getauthenticator (uk5->context,
					    auth_context,
					    &authenticator) == 0);
    /*
     * See if this is the same principal as the server.
     */
    if (krb5_principal_compare (uk5->context, authenticator->client, uk5->me))
    {
	client_type = AUTH_PRIVILEGED;
    }

    Tcl_DStringInit(&cmd);
    Tcl_DStringAppend(&cmd, "unameit_login_ukrbv", -1);
    Tcl_DStringAppendElement(&cmd, client_type);

    pr = krb5_princ_realm (uk5->context, authenticator->client);
    append_data (&cmd, pr);
    for (i = 0; i < krb5_princ_size (uk5->context, authenticator->client); i++)
    {
	 append_data (&cmd,
		      krb5_princ_component (uk5->context,
					    authenticator->client,
					    i));
    }
    result = Tcl_Eval (interp, Tcl_DStringValue(&cmd));
    Tcl_DStringFree(&cmd);

cleanup:
    if (kb)
	krb5_free_keyblock (uk5->context, kb);
    if (auth_context)
	krb5_auth_con_free (uk5->context, auth_context);
    if (authenticator)
	krb5_free_authenticator (uk5->context, authenticator);

    return result;
}


static int
Uk5_Generic_Init(
    Uk5_Context *uk5,
    Tcl_Interp *interp,
    int argc,
    char *argv[],
    Init_t type,
    void *param
)
{
    krb5_error_code	k_err;
    krb5_creds		my_creds;
    krb5_principal	me = NULL;
    krb5_principal	tgs = NULL;
    char		*name;
    char		*inst;
    char		*realm;
    int 		result;


    if (!uk5->ccache)
    {
	return Uk5_Error(interp, 0, "NOSETCCACHE", (char *)NULL);
    }

    result = Uk5_build_principal(uk5->context, &me, interp,
				 name = argv[3],
				 inst = argv[4],
				 realm = argv[5]);
    if (result == TCL_OK)
    {
	result = Uk5_build_principal(uk5->context, &tgs, interp,
				     KRB5_TGS_NAME, NULL, realm);
    }

    if (result != TCL_OK)
	goto cleanup;

    /* initialize credential cache */
    k_err = krb5_cc_initialize (uk5->context, uk5->ccache, me);
    if (k_err)
    {
	result = Uk5_Error(interp, k_err, "CCACHEINIT",
			   uk5->ccache_type, uk5->ccache_name, (char *)NULL);
	goto cleanup;
    }

    /* set credentials */
    memset(&my_creds, 0, sizeof(my_creds));
    my_creds.client = me;
    my_creds.server = tgs;

    switch (type)
    {
    case Init_Keytab:
	k_err = krb5_get_in_tkt_with_keytab (uk5->context, 0,
					     NULL, NULL, NULL,
					     (krb5_keytab)param,
					     uk5->ccache, &my_creds, NULL);
	break;
    case Init_Password:
	k_err = krb5_get_in_tkt_with_password(uk5->context, 0,
					      NULL, NULL, NULL,
					      (char *)param,
					      uk5->ccache, &my_creds, NULL);
	break;
    }

    if (k_err != 0)
    {
	result = Uk5_Req_Error(uk5, interp, k_err, me, tgs,
			       (type == Init_Password) ? "KINIT" : "KSINIT");
	goto cleanup;
    }
    result = TCL_OK;

cleanup:
    if (me)
	krb5_free_principal (uk5->context, me);
    if (tgs)
	krb5_free_principal (uk5->context, tgs);

    return result;
}


/*
 * This routine gets an initial ticket from krbtgt in the default
 * realm.
 */
static int
Uk5_kinit(ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    if (argc != 7)
    {
	Uk5_BadArgs();
	return TCL_ERROR;
    }

    if (strlen (argv[6]) < 1)
    {
	Uk5_Error(interp, 0, "NOPASSWORD", (char *)NULL);
	return TCL_ERROR;
    }

    return Uk5_Generic_Init((Uk5_Context *)ctx, interp, argc, argv,
			    Init_Password, (void *)argv[6]);
}

/*
 * This routine gets an initial ticket from krbtgt in the default
 * realm.
 */
static int
Uk5_ksinit (ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk5_Context		*uk5 = (Uk5_Context *)ctx;
    int			result;
    krb5_keytab		kt = NULL;

    if (argc != 7)
    {
	Uk5_BadArgs();
	return TCL_ERROR;
    }

    if (Uk5_resolve_keytab(uk5->context, &kt, interp, argv[6]) != TCL_OK)
	return TCL_ERROR;

    result = Uk5_Generic_Init(uk5, interp, argc, argv,
			      Init_Keytab, (void *)kt);

    krb5_kt_close(uk5->context, kt);

    return result;
}


/*
 * Close the credential cache and destroy it.
 */
static int
Uk5_kdestroy(ClientData ctx, Tcl_Interp *interp, int argc, char **argv)
{
    Uk5_Context	*uk5 = (Uk5_Context *)ctx;
    int		k_err = 0;

    if (!uk5->ccache)
    {
	return TCL_OK;
    }

    if (argc != 3)
    {
	return Uk5_BadArgs();
    }

    k_err = krb5_cc_destroy (uk5->context, uk5->ccache);

    if (k_err != 0)
    {
	Uk5_Error(interp, k_err, "CCACHENOTDEST",
		  uk5->ccache_type, uk5->ccache_name, (char *)NULL);
    }

    uk5->ccache = NULL;
    stringset(&uk5->ccache_type, NULL);
    stringset(&uk5->ccache_name, NULL);

    return !k_err ? TCL_OK : TCL_ERROR;
}

/*
 * This library supports only one krb5 connection.
 * This routine inits memory based credential caches for temporary tickets.
 */
#ifdef _MSC_VER	 
__declspec(dllexport)
#endif
int
Ukrbv_Init(Tcl_Interp *interp)
{
    krb5_error_code	k_err;
    extern krb5_cc_ops 	krb5_mcc_ops;
    static Uk5_Context  uk5;
    char		**procPtr;
    
    static cmd_entry commands[] =
    {
	{"set_server", (ClientData) &uk5, Uk5_set_server,
	    "service server_instance server_realm"},
	{"set_ccache", (ClientData) &uk5, Uk5_set_ccache, 
	    "ccache_type ccache_name"},
	{"kinit", (ClientData) &uk5, Uk5_kinit,
	    "client_principal client_instance client_realm password"},
	{"ksinit", (ClientData) &uk5, Uk5_ksinit,
	    "client_principal client_instance client_realm keytab"},
	{"kdestroy",(ClientData)  &uk5, Uk5_kdestroy, ""},
	{"set_service", (ClientData) &uk5, Uk5_set_service,
	    "service client_instance client_realm keytab"},
	{NULL, NULL, NULL, NULL}
    };

    static Auth_Functions calls =
    {
	CONN_AUTH_KRB5,
	CONN_AUTH_ID_KRB5,
	Uk5_read_auth, (ClientData) &uk5,
	Uk5_write_auth, (ClientData) &uk5,
	commands
    };

    if (Tcl_PkgRequire (interp, AUTH_NAME, AUTH_VERSION, 0) == NULL)
    {
	return TCL_ERROR;
    }


    for (procPtr = krb5err; *procPtr; ++procPtr)
    {
	if (Tcl_Eval (interp, *procPtr) != TCL_OK)
	    return TCL_ERROR;
    }

    k_err = krb5_init_context (&uk5.context);

    if (!k_err)
	k_err = krb5_cc_register (uk5.context, &krb5_mcc_ops, 1);

    if (k_err)
    {
	return Uk5_Error(interp, k_err, "INIT", (char *)NULL);
    }

    uk5.functions = (Auth_MasterFunctions *)
	Tcl_GetAssocData (interp, AUTH_MASTER_FUNCTIONS_KEY, NULL);
    assert (uk5.functions != NULL);
    assert (uk5.functions->Auth_Register != NULL);

    if (uk5.functions->Auth_Register(interp, &calls, krb5tcl) != TCL_OK)
    {
	return TCL_ERROR;
    }

    return (Tcl_PkgProvide (interp, CONN_AUTH_KRB5, UK5_VERSION));
}

#include "desmd5.c"
