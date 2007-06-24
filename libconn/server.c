/*
 * Copyright (c) 1995-1997 Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: server.c,v 1.20.16.4 1997/09/21 23:42:27 viktor Exp $";

#include <termios.h>

#include <conn.h>
#include <auth.h>
#include <uuid.h>

#include "server.h"

#ifndef USERVER_VERSION
#define USERVER_VERSION "2.0"
#endif

static Tcl_Interp *serverInterp;

static void catchsig(int sig) {}

static void logit(int ecode, int priority, const char *fmt, va_list arg)
{
    char	s[4096];
    (void)vsprintf(s, fmt, arg);
    (void)vfprintf(stderr, fmt, arg);
    (void)putc('\n', stderr);
    syslog(priority, "%s", s);
    if (ecode)
    {
	abort();
	/* And if that fails */
	exit(ecode);
    }
}
static void elogit(int ecode, int priority, const char *fmt, va_list arg)
{
    char	s[4096];
    (void)vsprintf(s, fmt, arg);
    (void)vfprintf(stderr, fmt, arg);
    (void)fputs(": ", stderr);
    (void)perror("");
    syslog(priority, "%s: %m", s); /* %m is errno message in syslog */
    if (ecode)
    {
	abort();
	/* And if that fails */
	exit(ecode);
    }
}

static int
/*ARGSUSED*/
daemon_fork(
    ClientData not_used,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    sigset_t mask;
    sigset_t oldmask;
    int childpid;
    int pid;
    int i;
    int numfds;

    if (argc != 1)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"",
		argv[0], "\"", (char *) NULL);
	return TCL_ERROR;
    }

    (void) umask(022);

    if (getppid() == 1)
	return TCL_OK;

    pid = getpid();

    /*
     * Block signals before fork,  in case child signals before
     * we get a chance to catch
     */
    sigemptyset(&mask);
    sigaddset(&mask, SIGUSR1);
    sigaddset(&mask, SIGCHLD);
    check(sigprocmask(SIG_BLOCK, &mask, &oldmask) == 0);

    if ((childpid = fork()) < 0)	/* error */
    {
	Tcl_AppendResult(interp, "fork: ", Tcl_PosixError(interp),
	    (char *)NULL);
	return TCL_ERROR;
    }
    else if (childpid > 0)		/* parent */
    {

	signal(SIGUSR1, catchsig);
	signal(SIGCHLD, catchsig);

	sigfillset(&mask);
	sigdelset(&mask, SIGUSR1);
	sigdelset(&mask, SIGCHLD);

	(void) sigsuspend(&mask);
	_exit(0);
    }

    /*
     * Close all descriptors >= 3,  Close stdio handles later, in
     * daemon_mode.
     */
    numfds = sysconf(_SC_OPEN_MAX);
    for (i = 3; i < numfds; ++i)
    {
	(void) close(i);
    }
    sigprocmask(SIG_SETMASK, &oldmask, NULL);

    return TCL_OK;
}


static int
/*ARGSUSED*/
daemon_mode(
    ClientData not_used,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    int ppid;
    int i;

    if (argc != 1)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"",
		argv[0], "\"", (char *) NULL);
	return TCL_ERROR;
    }

    (void) signal(SIGCLD, SIG_IGN);

    if ((ppid = getppid()) != 1) {
	(void) kill(getppid(), SIGUSR1);
    }

    (void) setsid();

    /*
     * Bind standard descriptors to "/",  so they don't get reused
     * for files we care about
     */
    for (i = 0; i < 3; ++i)
    {
	int fd = open("/", O_RDONLY, 0);
	if (fd != i)
	{
	    (void) dup2(fd, i);
	    (void) close(fd);
	}
    }

    return TCL_OK;
}

static void
SlaveRecordFree(ClientData ptr, Tcl_Interp *interp)
{
    if (ptr != NULL)
	ckfree(ptr);
}


static int
SlaveRecord(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_InterpDeleteProc	*delProc;
    Tcl_Interp			*slave;
    char			*value;

    if (argc < 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " slave key ?value1? ...\"",
			 (char *)NULL);
	return TCL_ERROR;
    }

    if ((slave = Tcl_GetSlave(interp, argv[1])) == NULL)
    {
	Tcl_AppendResult(interp, "Slave not found: \"", argv[1], "\"",
			 (char *)NULL);
	return TCL_ERROR;
    }

    if ((value = (char *)Tcl_GetAssocData(slave, argv[2], &delProc)) != NULL)
    {
	if (delProc != SlaveRecordFree)
	{
	    Tcl_AppendResult(interp, "Reserved key for slave \"", argv[1],
			     "\", key \"", argv[2], "\"", (char *)NULL);
	    return TCL_ERROR;
	}

	if (argc == 3)
	{
	    Tcl_SetResult(interp, value, TCL_VOLATILE);
	    return TCL_OK;
	}

	SlaveRecordFree(value, interp);
    }
    else if (argc == 3)
    {
	Tcl_AppendResult(interp, "Data not found for slave \"", argv[1],
			 "\", key \"", argv[2], "\"", (char *)NULL);
	return TCL_ERROR;
    }

    Tcl_SetAssocData(slave, argv[2], SlaveRecordFree,
		     (ClientData)Tcl_Merge(argc-3, argv+3));
    return TCL_OK;
}


static void
Conn_Execute(conn_t *conn)
{
    unsigned32  len;
    unsigned32  ret_code;
    int		result = TCL_ERROR;
    char	*script;
    Tcl_DString	cmd;
    Tcl_DString	slave_path;
    Tcl_Interp  *interp;
    static char commitCmd[] = "unameit_commit";
    static char abortCmd[] = "unameit_abort";
    static char micErrorCmd[] = "error {Message integrity check failed} "
				"{} {UNAMEIT CONN EBADMIC}";
    static char lenErrorCmd[] = "error {Truncated Tcl script} {} "
				"{} {UNAMEIT CONN ESHORT}";

    /*
     * Should have a valid client handle
     */
    interp = conn->conn_interp;
    assert(interp != NULL && interp != serverInterp);

    /*
     * Just in case
     */
    Tcl_ResetResult(interp);

    /*
     * This gives us ownership of the underlying memory!
     * We must free it as soon as ready to do so.
     */
    script = Unameit_Conn_Read(conn, &len, &ret_code);

    if (conn->conn_errno)
    {
	if (script)
	    ckfree((char *)script);

	return;
    }

    /*
     * Check the message integrity 
     */
    if (conn->conn_message.read_crypto.mic_ok != 1)
    {
	ckfree((char *)script);
	/*
	 * Arrange for the client to be dropped
	 */
	Tcl_DeleteInterp(interp);
	conn->conn_interp = NULL;
	/*
	 * Session is corrupted: Return diagnostic to client
	 */
	Tcl_Eval(serverInterp, micErrorCmd);
	Unameit_Conn_Interp_Reply(conn, serverInterp, TCL_ERROR);
	return;
    }

    /*
     * Check that the script has the indicated length
     *
     * XXX: could in the future,  allow binary data after command script
     */
    if (len != (unsigned32)strlen(script))
    {
	ckfree((char *)script);

	Tcl_Eval(serverInterp, lenErrorCmd);
	Unameit_Conn_Interp_Reply(conn, serverInterp, TCL_ERROR);
	return;
    }

    /*
     * Tell master interpreter who is about to run.
     */
    check(Tcl_GetInterpPath(serverInterp, interp) == TCL_OK);
    Tcl_DStringInit(&slave_path);
    Tcl_DStringGetResult(serverInterp, &slave_path);
    Tcl_DStringInit(&cmd);
    Tcl_DStringAppend(&cmd, "unameit_begin", -1);
    Tcl_DStringAppendElement(&cmd, Tcl_DStringValue(&slave_path));
    Tcl_DStringFree(&slave_path);
    result = Tcl_Eval(serverInterp, Tcl_DStringValue(&cmd));
    Tcl_DStringFree(&cmd);

    if (result != TCL_OK)
    {
	/*
	 * Rejected: Arrange for the client to be dropped
	 */
	Tcl_DeleteInterp(interp);
	conn->conn_interp = NULL;
	Unameit_Conn_Interp_Reply(conn, serverInterp, result);
	return;
    }

    /* printf ("evaling: '%s'\n", script); */

    result = Tcl_Eval(interp, script);
    ckfree(script);

    if (result == TCL_OK)
    {
	if ((result = Tcl_Eval(serverInterp, commitCmd)) != TCL_OK)
	{
	    interp = serverInterp;
	}
    }
    else
    {
	if (Tcl_Eval(serverInterp, abortCmd) != TCL_OK)
	{
	    interp = serverInterp;
	}
    }
    Unameit_Conn_Interp_Reply(conn, interp, result);
}



/* 
 * If there is an authorization type present, this is a login
 * request.
 * 
 * If there is no authorization type present, and an interpreter exists,
 * then execute the command. If no interpreter is present the 
 * connection is unauthenticated (i.e. not logged in), which is an
 * error.
 */
static void
Read_Done(conn_t *conn)
{
    int		result;
    conn_auth_t auth_type = conn->conn_message.auth_type;
    static char errorCmd[] = 
	"error {Not logged in} {} {UNAMEIT AUTH ENOLOGIN}";

    if (auth_type == CONN_AUTH_ID_NONE)
    {
	if (conn->conn_interp != NULL)
	{
	    Conn_Execute(conn);
	    return;
	}
	result = Tcl_Eval(serverInterp, errorCmd);
    }
    else
    {
	/*
	 * Reauthenticating: Release old client handle
	 */
	if (conn->conn_interp)
	{
	    Tcl_DeleteInterp(conn->conn_interp);
	    conn->conn_interp = NULL;
	}

	/*
	 * Create a command and eval it. This is required for error
	 * processing, since the Tcl_Eval code checks the error info
	 * that may be set by authorization routines or procs.
	 */
	(void) Tcl_CreateCommand(serverInterp, "unameit_read_auth", Auth_Read,
				 (ClientData)conn, NULL);
 	result = Tcl_Eval(serverInterp, "unameit_read_auth");
 	if (result == TCL_OK)
	{
	    /*
	     * If all went well, save session handle 
	     */
	    conn->conn_interp = Tcl_GetSlave (serverInterp,
					      serverInterp->result);
	    assert(conn->conn_interp);
	    Tcl_SetAssocData(conn->conn_interp, CONN_ASSOC_KEY,
			     NULL, (ClientData)conn);
	    Tcl_SetResult(serverInterp, (char *) Uuid_StringCreate(), TCL_VOLATILE);
	}
    }

    Unameit_Conn_Interp_Reply(conn, serverInterp, result);
}


static void
Server_Iodone(conn_t *conn, conn_state_t state)
{
    if (conn->conn_errno)
	return;

    if (state == CONN_NEW)
    {
	conn->conn_message.maxlen = MAX_REQUEST;
	Unameit_Conn_Poll(conn);
	return;
    }
    else if (state == CONN_READING)
    {
	Read_Done(conn);
	return;
    }
    else if (state == CONN_WRITING)
    {
	/*
	 * Reset for read unless client is to be dropped
	 */
	if (conn->conn_interp != NULL)
	{
	    Unameit_Conn_Poll(conn);
	}
	return;
    }
    conn->conn_errno = ERR_CONN_INVAL;
}


/*
 * Used both as TCL_CmdProc and signal handler
 */
/* ARGSUSED */
static int
EndLoop(ClientData sig, Tcl_Interp *interp, int argc, char *argv[])
{
    Unameit_Conn_Terminate();
    return TCL_OK;
}

static int
/*ARGSUSED*/
ClientLoop(ClientData not_used, Tcl_Interp *interp, int argc, char *argv[])
{
    char *port;
    struct sigaction sa, old_int_sa, old_term_sa;
    int  idle_timeout;
    int	 result;

    if (argc != 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"",
	    argv[0], " port idle_timeout\"", (char *) NULL);
	return TCL_ERROR;
    }

    port = argv[1];
    if (Tcl_GetInt(interp, argv[2], &idle_timeout) != TCL_OK)
	return TCL_ERROR;

    /*
     * signal() has no portable semantics
     * sigaction gives `reliable' signals on all systems
     */
    memset((char *)&sa, 0, sizeof(sa));
    sa.sa_handler = (void (*)(int))EndLoop;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags  = 0;

    (void) sigaction(SIGINT, &sa, &old_int_sa);
    (void) sigaction(SIGTERM, &sa, &old_term_sa);

    Tcl_DeleteCommand(interp, "unameit_client_loop");
    Tcl_CreateCommand(interp, "unameit_end_loop", EndLoop,
	(ClientData)0, (Tcl_CmdDeleteProc *)NULL);

    result = Unameit_Conn_Loop(interp, port, Server_Iodone, idle_timeout);

    Tcl_DeleteCommand(interp, "unameit_end_loop");
    Tcl_CreateCommand(interp, "unameit_client_loop", ClientLoop,
	(ClientData)0, (Tcl_CmdDeleteProc *)NULL);

    /*
     * Restore signal handlers
     */
    (void) sigaction(SIGINT, &old_int_sa, (struct sigaction *)NULL);
    (void) sigaction(SIGTERM, &old_term_sa, (struct sigaction *)NULL);

    return result;
}

int
Userver_Init(Tcl_Interp *interp)
{
    int result;

    serverInterp = interp;

    Unameit_Set_Error_Funcs(logit, elogit);
    Tcl_SetPanicProc((void (*)(char *, ...))Unameit_Panic);

    Tcl_CreateCommand(interp, "unameit_slave_record", SlaveRecord,
	(ClientData)0, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "unameit_daemon_fork", daemon_fork,
	(ClientData)0, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "unameit_daemon_mode", daemon_mode,
	(ClientData)0, (Tcl_CmdDeleteProc *)NULL);
    Tcl_CreateCommand(interp, "unameit_client_loop", ClientLoop,
	(ClientData)0, (Tcl_CmdDeleteProc *)NULL);

    if ((result = Tcl_PkgProvide(interp, "Userver", USERVER_VERSION)) !=
	TCL_OK) {
	return result;
    }

    return TCL_OK;
}
