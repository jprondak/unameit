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
static char rcsid[] = "$Id: clntcall.c,v 1.17.20.4 1997/09/21 23:42:21 viktor Exp $";

#include <conn.h>
#include <auth.h>

#ifndef UCLIENT_VERSION
#define UCLIENT_VERSION "2.0"
#endif

static void
file_proc(ClientData dummy, int mask);

/*
 * The serverState indicates whether the connection to the server
 * is in use (BUSY) or not (IDLE). If there is no connection at all,
 * server (the connection) will be NULL.
 */
typedef enum {IDLE, BUSY} serverState;

typedef struct ServerInfo
{
    Tcl_Interp  *interp;
    conn_t	*server;
    Tcl_Channel	channel;
    Tcl_Channel file;
    serverState	state;
    int		result;
    char 	*value;
    char	*einfo;
    char	*ecode;
    Tcl_FreeProc *free;
}	ServerInfo, *ServerInfoPtr;

static ServerInfo serverInfo =
    {NULL, NULL, NULL, NULL, IDLE, TCL_ERROR, NULL, NULL, NULL, NULL};


static char *progName;

/* ARGSUSED */
static void logit(int ecode, int priority, const char *fmt, va_list arg)
{
    if (progName)
	fprintf(stderr, "%s: ", progName);
    vfprintf(stderr, fmt, arg);
    fprintf(stderr, "\n");
    fflush(stderr);
    if (ecode)
    {
	exit(ecode);
    }
}
/* ARGSUSED */
static void elogit(int ecode, int priority, const char *fmt, va_list arg)
{
    if (progName)
	fprintf(stderr, "%s: ", progName);
    vfprintf(stderr, fmt, arg);
    fputs(": ", stderr);
    perror("");
    fflush(stderr);
    if (ecode)
    {
	exit(ecode);
    }
}


/* 
 * Delete the channel handler and close the channel and the stream.
 * Closing the channel also closes the socket so we mark it invalid. 
 * serverInfo.server is set to NULL to indicate 'no connection'.
 */
static void
do_close(void)
{
    if (serverInfo.server)
    {
	Tcl_Close(NULL, serverInfo.file);
	serverInfo.server->conn_stream = INVALID_SOCKET;
	
	Unameit_Conn_Reap(serverInfo.server);
	serverInfo.server = NULL;
    }
    serverInfo.state = IDLE;
}


/*
 * Arguments *MUST* be static strings
 */
static void
make_error(char *result, char *errcode)
{
    serverInfo.value = result;
    serverInfo.ecode = errcode;
    serverInfo.result = TCL_ERROR;
    serverInfo.free = TCL_STATIC;
    return;
}


/*
 * Arguments *MUST* be static strings
 */
static void
break_conn(char *result, char *errcode)
{
    make_error(result, errcode);
    do_close();
    return;
}


static void
file_proc(ClientData dummy, int mask)
{
    register conn_t *server = serverInfo.server;

    if (mask & TCL_READABLE)
    {
	if (server->conn_state == CONN_READING)
	{
	    Unameit_Conn_Progress(server);
	    switch (server->conn_errno)
	    {
	    case ERR_CONN_OK:
		if (server->conn_state == CONN_EOF)
		    break_conn("No server response", "UNAMEIT CONN EIO");
		break;
	    case ERR_CONN_SHORT:
		break_conn("Truncated server response", "UNAMEIT CONN EIO");
		break;
	    default:
		break_conn("Read from server failed", "UNAMEIT CONN EIO");
		break;
	    }
	    return;
	}
	if (server->conn_state == CONN_IODONE)
	{
	    break_conn("Disconnected from server", "UNAMEIT CONN EIO");
	    return;
	}
    }
    if (mask & TCL_WRITABLE)
    {
	if (server->conn_state == CONN_WRITING)
	{
	    Unameit_Conn_Progress(server);
	    if (server->conn_errno)
	    {
		break_conn("Write to server failed", "UNAMEIT CONN EIO");
	    }
	    else if (server->conn_state == CONN_IODONE)
	    {
		/*
		 * Finished a request,  let's wait for a reply!
		 */
		Unameit_Conn_Poll(server);
		Tcl_CreateChannelHandler(serverInfo.file, TCL_READABLE,
					 file_proc, 0);
	    }
	    return;
	}
	else if (server->conn_state == CONN_NEW)
	{
	    char *h;
	    int p;
	    if (Unameit_Stream_Peer(server->conn_stream, &h, &p) == TCL_OK)
	    {
		/*
		 * Put connection in IODONE state after a successful connect()
		 * and turn off BUSY flag so that io_wait will return.
		 * Turn off write notification on connection
		 */
		server->conn_state = CONN_IODONE;
		serverInfo.state = IDLE;
		serverInfo.result = TCL_OK;
		Tcl_CreateChannelHandler(serverInfo.file, TCL_READABLE,
					 file_proc, 0);
	    }
	    else
	    {
		break_conn("Could not connect to server", "UNAMEIT CONN EAGAIN");
	    }
	    return;
	}
    }
    break_conn("Lost connection with server", "UNAMEIT CONN EIO");
}

/*
 * Tcl_DoOneEvent will invoke file_proc until the complete response
 * returns or an error occurs. file_proc (or something it calls), will
 * set the state back to IDLE. At that point we process the results
 * in serverInfo. This could be either results from the server or
 * results from the Disconnect command.
 */
static int
io_wait()
{
    while (serverInfo.state == BUSY)
	Tcl_DoOneEvent(0);

    if (serverInfo.value)
    {
	/*
	 * The calls to AddErrorInfo, SetResult and Tcl_SetErrorCode
	 * must remain in the order below.  This avoids duplication of the
	 * error message in the stack trace,  and prevents the loss of
	 * the error code after SetResult.
	 */
	if (serverInfo.result != TCL_OK)
	{
	    if (serverInfo.einfo)
	    {
		Tcl_AddErrorInfo(serverInfo.interp, serverInfo.einfo);
	    }
	}

	Tcl_SetResult(serverInfo.interp, serverInfo.value, serverInfo.free);

	if (serverInfo.result != TCL_OK)
	{
	    if (serverInfo.ecode)
	    {
		Tcl_SetErrorCode(serverInfo.interp, (char *)0);
		Tcl_SetVar2(serverInfo.interp, "errorCode", (char *)0,
			    serverInfo.ecode, TCL_GLOBAL_ONLY);
	    }
	}
	serverInfo.value =
	serverInfo.ecode = NULL;
    }
    return serverInfo.result;
}


static int
Send_Auth(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    conn_t	*server = serverInfo.server;
    int		result;

    if (server == NULL)
    {
	Tcl_SetResult(interp, "Not connected to server", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "ENOCONN", (char *)NULL);
	return TCL_ERROR;
    }

    if (serverInfo.state != IDLE)
    {
	Tcl_SetResult(interp, "Connection busy", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EBUSY", (char *)NULL);
	return TCL_ERROR;
    }

    if (server->conn_errno)
    {
	Tcl_SetResult(interp, "Connection is in an error state", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EINTERNAL", (char *)NULL);
	return TCL_ERROR;
    }

    result = Auth_Write ((ClientData)server, interp, argc, argv);

    /*
     * Only wait for a reply if we queued a request
     */
    if (result != TCL_OK)
    {
	return TCL_ERROR;
    }

    if (server->conn_errno)
    {
	Tcl_SetResult(interp, "Could not send to server", TCL_STATIC);
	Tcl_SetErrorCode(interp, "AUTH", "ESEND", (char *)NULL);
	return TCL_ERROR;
    }
    serverInfo.state = BUSY;

    Tcl_CreateChannelHandler(serverInfo.file, TCL_READABLE | TCL_WRITABLE, 
			     file_proc, 0);
    return io_wait();
}


static int
probable_error_message(char *msg, unsigned32 len)
{
    register unsigned char *cp = (unsigned char *)msg;
    int null_count = 1;

    /*
     * error messages with bad checksums occur usually after 
     * a failed authentication/key exchange and should not be very long
     */
    if (len > 256)
	return FALSE;

    for (;len--; ++cp) {
	if (*cp == '\0') {
	    ++null_count;
	} else if (!isprint(*cp) && !isspace(*cp)) {
	    return FALSE;
	}
    }
    return (null_count == 3);
}

static int
Is_Valid_Message(char *data, unsigned32 len, int expected_nulls)
{
    int null_count = 1;

    while (len--) {
	if (*data++ == '\0') {
	    null_count++;
	}
    }
    if (null_count != expected_nulls) {
	return FALSE;
    }
    return TRUE;
}

static void
iodone(conn_t *conn, conn_state_t state)
{
    unsigned32		len, ret_code;
    char		*value;

    if (conn->conn_errno) {
	return;
    }

    switch (state) {
    case CONN_READING:
	value = Unameit_Conn_Read(conn, &len, &ret_code);
	/*
	 * conn library NULL terminates incoming data.
	 */
	assert(value[len] == '\0');

	if (conn->conn_message.read_crypto.mic_ok != 1) {
	    if (probable_error_message(value, len)) {
		serverInfo.result=TCL_ERROR;
		serverInfo.value=value;
		serverInfo.einfo=&serverInfo.value[strlen(serverInfo.value)+1];
		serverInfo.ecode=&serverInfo.einfo[strlen(serverInfo.einfo)+1];
		serverInfo.free = TCL_DYNAMIC;
		do_close ();
	    } else {
		ckfree(value);
		break_conn("Message Checksum Error", "UNAMEIT CONN EBADMIC");
	    }
	    return;
	}

	if (ret_code == TCL_OK) {
	    if (serverInfo.channel == NULL) {
		if (!Is_Valid_Message(value, len, 1)) {
		    break_conn("Malformed message", "UNAMEIT CONN EMALFORMED");
		    ckfree(value);
		    return;
		}
		serverInfo.value = value;
		serverInfo.free  = TCL_DYNAMIC;
	    } else {
		int bytes_written;
		/*
		 * When writing to a channel, we do not save the command
		 * result in the serverInfo structure, so when used with
		 * Tk, the return value when writing to a channel is not
		 * reliable. The exception code is reliable however.
		 */
		bytes_written = Tcl_Write(serverInfo.channel, value, len);
		if ((bytes_written < 0) || 
				((unsigned32) bytes_written != len)) {
		    ret_code = TCL_ERROR;
		} else {
		    ret_code = TCL_OK;
		}
		ckfree(value);
	    }
	} else {
	    if (!Is_Valid_Message(value, len, 3)) {
		break_conn("Malformed message", "UNAMEIT CONN EMALFORMED");
		ckfree(value);
		return;
	    }
	    serverInfo.value = value;
	    serverInfo.einfo = &value[strlen(value)+1];
	    serverInfo.ecode = &serverInfo.einfo[strlen(serverInfo.einfo)+1];
	    serverInfo.free  = TCL_DYNAMIC;
	}
	serverInfo.result = ret_code;
	serverInfo.state = IDLE;
	break;
    case CONN_WRITING:
	break;
    default:
	/*
	 * Should not happen
	 */
	break_conn("Unexpected state in iodone", "UNAMEIT CONN EIODONE");
	return;
    }
}


static int
Send(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    unsigned32	len;
    conn_t 	*server = serverInfo.server;
    char	*script;

    Tcl_ResetResult(interp);

    if (argc < 2) {
usage:
	Tcl_AppendResult(interp, "wrong # args: should be '", argv[0],
			 " ?fd? command'",
			 (char *)NULL);
	return TCL_ERROR;
    }

    if (server == NULL) {
	Tcl_SetResult(interp, "Not connected to server", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "ENOCONN", (char *)NULL);
	return TCL_ERROR;
    }

    if (serverInfo.state != IDLE) {
	Tcl_SetResult(interp, "Connection busy", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EBUSY", (char *)NULL);
	return TCL_ERROR;
    }

    if (server->conn_errno) {
	Tcl_SetResult(interp, "Connection is in an error state", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EINTERNAL", (char *)NULL);
	return TCL_ERROR;
    }

    if (argc != 2 && argc != 3) {
	goto usage;
    }

    if (argc == 3) {
	int channel_mode = TCL_WRITABLE;
	if (!(serverInfo.channel = Tcl_GetChannel(interp, argv[1],
						  &channel_mode))) {
	    Tcl_SetResult(interp, "Channel name doesn't exist", TCL_STATIC);
	    Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EBADCHANNEL", argv[1],
			     (char *)NULL);
	    return TCL_ERROR;
	}
	script = argv[2];
    } else {
	serverInfo.channel = NULL;
	script = argv[1];
    }
    len = strlen(script);

    Unameit_Conn_Write(server, script, len, CONN_AUTH_ID_NONE, 0, TCL_STATIC);

    if (server->conn_errno) {
	Tcl_SetResult(interp, "Could not send to server", TCL_STATIC);
	Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "ESEND", (char *)NULL);
	return TCL_ERROR;
    }
    serverInfo.state = BUSY;

    Tcl_CreateChannelHandler(serverInfo.file, TCL_READABLE | TCL_WRITABLE,
			     file_proc, 0);
    return io_wait();
}

/* ARGSUSED */
static int
Connect(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    char *host;
    char *port;
    conn_t *server;

    if (argc != 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
			 " host port\"",
			 (char *)NULL);
	return TCL_ERROR;
    }

    if (serverInfo.server != NULL)
    {
	switch (serverInfo.state)
	{
	case IDLE:
	    return TCL_OK;
	default:
	    Tcl_SetResult(interp, "Connection busy", TCL_STATIC);
	    Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EBUSY", (char *)NULL);
	    return TCL_ERROR;
	}
    }

    host= argv[1];
    port= argv[2];

    server = Unameit_Conn_Connect(interp, host, port);

    if ((serverInfo.server = server) == NULL)
    {
	return TCL_ERROR;
    }
    serverInfo.interp = interp;
    serverInfo.state = BUSY;
    server->conn_callback = iodone;

    serverInfo.file = 
	Tcl_MakeTcpClientChannel ((ClientData)server->conn_stream);
    
    /*
     * We are connecting asynchronously:
     * IMPORTANT:  File event mask *must* be TCL_WRITABLE!
     * For a newly completed connection TCL_READABLE selects exactly
     * once,  and is typically lost by Tk.  TCL_WRITABLE selects
     * indefinitely many times. On Windows it must also be TCL_READABLE.
     */
    Tcl_CreateChannelHandler(serverInfo.file, 
			     TCL_WRITABLE | TCL_READABLE, 
			     file_proc, 
			     0);
    server->conn_state = CONN_NEW;

    /*
     * Process events until authentication is finished.
     * This does not really return right away...
     */
    return io_wait();
}

/*
 * If there is a connection, break it. If it is BUSY, mark the operation
 * as cancelled so that the operation in progress unwinds (it will notice
 * this in io_wait).
 */
static int
Disconnect(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    if (serverInfo.server != NULL)
    {
	switch (serverInfo.state)
	{
	case BUSY:
	    make_error("Connection closed", "UNAMEIT OPCANCELED");
	    break;
	    
	default:
	    break;
	}
	do_close();
    }

    return TCL_OK;
}


int
Uclient_Init(Tcl_Interp *interp)
{
    Tcl_Interp  *master;
    Tcl_Interp  *mi;
    char	*argv0;
    int		result;

#ifndef NO_SIGPIPE
    (void) signal(SIGPIPE, SIG_IGN);
#endif

    master = interp;

    while((mi = Tcl_GetMaster(master)) != NULL)
    {
	master = mi;
    }

    argv0 = Tcl_GetVar2(master, "argv0", NULL, TCL_GLOBAL_ONLY);

    if (argv0)
    {
	char *tail = strrchr(argv0, '/');
	if (tail)
	{
	    argv0 = ++tail;
	}
	if (progName)
	{
	    ckfree(progName);
	}
	progName = ckalloc(strlen(argv0) + 1);
	(void) strcpy(progName, argv0);
    }

    Unameit_Set_Error_Funcs(logit, elogit);
    Tcl_SetPanicProc((void (*)(char *, ...))Unameit_Panic);

    Tcl_CreateCommand(interp, "unameit_connect", Connect, NULL, NULL);
    Tcl_CreateCommand(interp, "unameit_send_auth", Send_Auth, NULL, NULL);
    Tcl_CreateCommand(interp, "unameit_send", Send, NULL, NULL);
    Tcl_CreateCommand(interp, "unameit_disconnect", Disconnect, NULL, NULL);

    if ((result = Tcl_PkgProvide(interp, "Uclient", UCLIENT_VERSION))
	!= TCL_OK) {
	return result;
    }
    return TCL_OK;
}
