/*
 * Copyright (c) 1994, 1995, 1996, 1997 Enterprise Systems Management Corp.
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
#ifndef line
static char rcsid[] = "$Id: conn.c,v 1.12.20.4 1997/10/09 01:04:56 viktor Exp $";
#endif

#include <conn.h>

static void
iov_init_trailer(conn_message_t *message, conn_state_t state)
{
    register int vec = 0;
    if (message->header.offset < sizeof(message->header.data)) ++vec;
    if (message->offset < message->length) ++vec;

    /*
     * Do MIC if one is expected.
     */
    if ((state == CONN_READING && message->read_crypto.update_mic) ||
	(state == CONN_WRITING && message->write_crypto.update_mic))
    {
	message->trailer.offset = 0;
	message->iov[vec].iov_base = message->trailer.mic;
	message->iov[vec].iov_len  = MIC_LEN;
	++vec;
    }
    message->nvec = vec;
}


static void
iov_init_data(conn_message_t *message, conn_state_t state)
{
    register int vec = 0;
    if (message->header.offset < sizeof(message->header.data)) ++vec;

    message->offset = 0;
    message->iov[vec].iov_base = (caddr_t) message->data;

    if (message->length > CONN_PKT_LEN - sizeof(message->header.data))
    {
	/*
	 * Process first packet of message.  Align on PKT boundary.
	 * Can't do trailer until finish data.
	 */
	message->iov[vec].iov_len = CONN_PKT_LEN-sizeof(message->header.data);
	message->nvec = ++vec;
    }
    else
    {
	message->iov[vec].iov_len = message->length;
	iov_init_trailer(message, state);
    }
}


static void
iov_init_header(conn_message_t *message, conn_state_t state)
{
    message->header.offset = 0;
    message->iov[0].iov_base = (caddr_t) &message->header.data;
    message->iov[0].iov_len  = sizeof(message->header.data);
    message->nvec = 1;

    if (state == CONN_WRITING)
    {
	iov_init_data(message, state);
    }
}

/*
 * The header defines 4 byte arrays for transporting unsigned32
 * values. This routine copies the data to a buffer and applies
 * ntohl (or equivalent) to the buffer.
 */
static unsigned32 ntoh_copy (void *p)
{
    unsigned32 tmp;
    memcpy (&tmp, p, sizeof tmp);
    return (unsigned32_ntoh (tmp));
}


static void
alloc_data(conn_t *conn)
{
    register conn_message_t *message = &conn->conn_message;
    unsigned32 magic;
    unsigned32 datalen;

    magic = ntoh_copy (message->header.data.magic);
    /*
     * Test the magic number
     */
    if (magic != CONN_MAGIC)
    {
	conn->conn_errno = ERR_CONN_MAGIC;
	return;
    }

    datalen = ntoh_copy (message->header.data.datalen);
    if (message->maxlen && (message->maxlen < datalen))
    {
	conn->conn_errno = ERR_CONN_SIZE;
	return;
    }

    message->length = datalen;
    message->auth_type = 
	(conn_auth_t) ntoh_copy (message->header.data.auth_type);
    
    message->data = ckalloc(datalen + 1);
    if (message->data == NULL)
    {
	panic("Out of memory");
    }
    /*
     * NUL terminate the data
     */
    message->data[datalen] = '\0';
    message->free = TCL_DYNAMIC;
}


static void
slide_window(conn_t *conn, int nio)
{
    register conn_message_t *message = &conn->conn_message;
    conn_state_t state = conn->conn_state;
    int tail;

    if (message->header.offset < sizeof(message->header.data))
    {
	tail = sizeof(message->header.data) - message->header.offset - nio;

	if (tail > 0)
	{
	    message->header.offset += nio;
	    message->iov->iov_base += nio;
	    message->iov->iov_len  -= nio;
	    return;
	}
	nio = -tail;
	message->header.offset = sizeof(message->header.data);

	if (state == CONN_READING)
	{
	    /*
	     * We should have been reading the header only,  and only
	     * sizeof(header) bytes.
	     */
	    assert(message->nvec ==1 && nio == 0);
	    alloc_data(conn);
	}
	/*
	 * We have finished the header, point iovec at data
	 */
	iov_init_data(message, state);
    }
    if (nio == 0) return;

    if (message->offset < message->length)
    {
	tail = message->length - message->offset - nio;
	if (tail > 0)
	{
	    message->offset 	   += nio;
	    message->iov->iov_base += nio;
	    if (tail > CONN_PKT_LEN)
	    {
		message->iov->iov_len = CONN_PKT_LEN;
	    }
	    else
	    {
		message->iov->iov_len = tail;
		/*
		 * We might finish data, on the next I/O
		 * append trailer iovec if any.
		 */
		iov_init_trailer(message, state);
	    }
	    return;
	}
	nio = -tail;
	message->offset =  message->length;
	/*
	 * We just finished the data, update iovec to start at
	 * the trailer for the next I/O if any.
	 */
	iov_init_trailer(message, state);
    }
    if (nio == 0) return;

    if (message->nvec == 0)
    {
	/*
	 * There is no trailer, and the I/O is done
	 */
	return;
    }

    tail = MIC_LEN - message->trailer.offset - nio;

    if (tail > 0)
    {
	message->trailer.offset += nio;
	message->iov->iov_base  += nio;
	message->iov->iov_len   -= nio;
	return;
    }
    /*
     * The I/O is done
     */
    assert (tail == 0);
    message->trailer.offset = MIC_LEN;
    message->nvec = 0;
    return;
}


static void
newstate(conn_t *conn, conn_state_t state)
{
    /*
     * MUST clear the message data unconditionally since
     * our caller may be overwriting it,  not clearing would cause
     * a memory leak.
     *
     * We set errno at the end if the clear happened at an illegal time
     */
    if (conn->conn_message.data) 
    {
	if (conn->conn_message.free == TCL_DYNAMIC ||
	    conn->conn_message.free == (Tcl_FreeProc *)free)
	{
	    ckfree(conn->conn_message.data);
	}
	else if (conn->conn_message.free != TCL_STATIC)
	{
	    (conn->conn_message.free)(conn->conn_message.data);
	}
    }
    conn->conn_message.data = NULL;
    conn->conn_message.free = TCL_STATIC;

    if (conn->conn_errno)
    {
	return;
    }

    /*
     * It is an error to change state in the middle of an I/O operation.
     * It is ok to reenter the same state if no I/O has taken place.
     */
    if (conn->conn_state != CONN_IODONE)
    {
	if (conn->conn_message.header.offset != 0 || conn->conn_state != state)
	{
	    conn->conn_errno = ERR_CONN_INVAL;
	}
    }
    conn->conn_state = state;

    conn->conn_message.length = 0;
    conn->conn_message.offset = 0;
    conn->conn_message.header.offset = 0;
}


static void
server_accept(
    Tcl_Interp *interp,
    int server,
    conn_t *connQueue,
    conn_callback_t callback
)
{
    SOCKET 	stream;
    conn_t	*conn;

    assert (connQueue);
    
    if (Unameit_Stream_Accept(interp, &stream, server) != TCL_OK)
    {
	Unameit_Complain(interp->result);
	return;
    }

    conn = (conn_t *)ckalloc(sizeof(conn_t));

    if (conn == (conn_t *)0)
    {
	panic("Out of memory");
    }
    memset(conn, 0, sizeof(*conn));

    conn->conn_interp = (Tcl_Interp *)NULL;
    conn->conn_state	= CONN_IODONE;
    conn->conn_stream   = stream;
    conn->conn_callback = callback;
    (void) time(&conn->conn_lastio);

    /*
     * insque(conn, connQueue)
     *
     * The SunOS 4.1.3 insque appears broken,  and in any case
     * this code is simple enough to be inlined.
     */
    conn->q_forw = connQueue->q_forw;
    conn->q_back = connQueue;
    if (connQueue->q_forw)
	connQueue->q_forw->q_back = conn;
    connQueue->q_forw = conn;

    callback(conn, CONN_NEW);
}


static void
server_progress(conn_t *conn)
{
    Unameit_Conn_Progress(conn);

    if (conn->conn_errno)
    {
	char *name;
	int port;
	if (Unameit_Stream_Peer(conn->conn_stream, &name, &port) == TCL_OK)
	{
	    Unameit_Complain("Corrupted connection with %s:%d", name, port);
	}
	Unameit_Conn_Reap(conn);
	return;
    }
    if (conn->conn_state == CONN_EOF)
    {
	Unameit_Conn_Reap(conn);
    }
}


static int conn_terminate_flag;


void
Unameit_Conn_Terminate(void)
{
    conn_terminate_flag = 1;
}


int
Unameit_Conn_Loop(
    Tcl_Interp *interp,
    const char *portname,	/* The name of the TCP port to listen on */
    conn_callback_t callback,	/* Upcall for new connections */
    int hours			/* The idle connection timeout in hours */
)
{
    SOCKET	stream;		/* The listening socket */
    conn_t	connQueue;	/* The queue head */
    conn_t	*conn;		/* Pointer to queue element */
    int		timeout;
    int		result = TCL_ERROR;

    if (hours > 0)
	timeout = hours * 3600;
    else
	timeout = (time_t)0;

    if (Unameit_Stream_Listen(interp, &stream, portname) != TCL_OK)
    {
	return TCL_ERROR;
    }

    /*
     * The queue head is not a valid connection
     */
    connQueue.conn_errno  = ERR_CONN_INVAL;
    connQueue.q_forw = connQueue.q_back = (conn_t *)NULL;
    connQueue.conn_stream = INVALID_SOCKET;
    connQueue.conn_interp = (Tcl_Interp *)NULL;

    /*
     * Don't want to die just because some random client
     * bellies up unexpectedly.
     */
#ifndef NO_SIGPIPE
    (void) signal(SIGPIPE, SIG_IGN);
#endif

    /*
     * Initialize conn_terminate_flag to 0
     * This makes it possible to reenter conn_srv_loop after an interrupt.
     *
     * Terminate before blocking or replying,  since we want
     * to shutdown without replying to "unameit_shutdown" or
     * processing any other client requests.
     */
    for (conn_terminate_flag = 0; conn_terminate_flag == 0; /* Nothing */)
    {
	SOCKET		maxfd = stream;
	int 		nready;
	fd_set		readFDs;
	fd_set		writeFDs;
	time_t		now;
	conn_t		*next;

	FD_ZERO(&readFDs);
	FD_ZERO(&writeFDs);
	FD_SET(stream, &readFDs);

	now = time(NULL);

	conn = connQueue.q_forw;
	for (conn = connQueue.q_forw; conn; conn = next)
	{
	    next = conn->q_forw;

	    /*
	     * Clean up stuck connections (Idle for over timeout hours!)
	     */
	    if (timeout > 0)
	    {
		if ((now - conn->conn_lastio) > timeout)
		{
		    Unameit_Conn_Reap(conn);
		    continue;
		}
	    }

	    /*
	     * They must eat everything before they can ask for more!
	     * (We operate half-duplex).
	     */
	    switch (conn->conn_state)
	    {
	    case CONN_WRITING:
		FD_SET(conn->conn_stream, &writeFDs);
		break;

	    case CONN_READING:
		FD_SET(conn->conn_stream, &readFDs);
		break;

	    default:
		/*
		 * This connection is done.  Just reap it.
		 */
		Unameit_Conn_Reap(conn);
		continue;
	    }
	    maxfd = (conn->conn_stream > maxfd) ? conn->conn_stream : maxfd;
	}

	nready = select(maxfd+1, &readFDs, &writeFDs,
			(fd_set *)0, (struct timeval *)0);

	switch (nready)
	{
	case -1:
	    if (errno == EINTR)
		continue;
	    Tcl_AppendResult(interp, "select: ", Tcl_PosixError(interp),
		(char *)NULL);
	    conn_terminate_flag = 1;
	    continue;

        case 0:
	    Tcl_SetResult(interp, "select timed out unexpectedly", TCL_STATIC);
	    conn_terminate_flag = 1;
	    continue;
	}

	if (FD_ISSET(stream, &readFDs))
	{
	    server_accept(interp, stream, &connQueue, callback);
	    --nready;
	}
	
	/*
	 * In order to reduce latency we always attempt to flush
	 * results,  before trying to read new requests.
	 */
	conn = connQueue.q_forw;
	while (nready && conn)
	{
	    /*
	     * Must grab the next pointer now
	     * Since we may reap in server_progress()
	     */
	    conn_t *next = conn->q_forw;

	    if (FD_ISSET(conn->conn_stream, &writeFDs))
	    {
		conn->conn_lastio = time(NULL);
		server_progress(conn);
		--nready;
	    }
	    conn = next;
	}

	/*
	 * Now process inbound data
	 */
	conn = connQueue.q_forw;
	while (nready && conn && conn_terminate_flag == 0)
	{
	    conn_t *next = conn->q_forw;

	    if (FD_ISSET(conn->conn_stream, &readFDs))
	    {
		conn->conn_lastio = time(NULL);
		server_progress(conn);
		--nready;
	    }
	    conn = next;
	}
    }

    /*
     * Stop listening for incoming requests do this first,  so shutdown
     * does not return until the server socket is closed.
     */
    (void) close(stream);

    /*
     * Tear down all connections.
     */
    while((conn = connQueue.q_forw) != NULL)
    {
	Unameit_Conn_Reap(conn);
    }
    return result;
}


/*
 * Allocate, fill in, and return a connection structure with a valid
 * stream. NULL is returned if the stream cannot be created.
 */
conn_t *
Unameit_Conn_Connect(
    Tcl_Interp *interp,
    const char *hostname,
    const char *portname
)
{
    int		stream;
    int		ok;
    conn_t	*conn;

    ok = Unameit_Stream_Connect(interp, &stream, hostname, portname);

    if ((ok != TCL_OK) || (stream < 0))
    {
	return NULL;
    }

    conn = (conn_t *)ckalloc(sizeof(conn_t));

    if (conn == (conn_t *)0)
    {
	panic("Out of memory");
    }
    memset(conn, 0, sizeof(*conn));

    conn->q_forw = conn->q_back = (conn_t *)NULL;
    conn->conn_interp = NULL;
    conn->conn_state  = CONN_IODONE;
    conn->conn_stream = stream;
    conn->conn_errno  = 0;
    conn->conn_callback = NULL;		/* Must be set by the caller */

    return conn;
}


void
Unameit_Conn_Progress(conn_t *conn)
{
    int		nio;
    int		packets = 0;
    SOCKET	stream;
    conn_message_t *message = &conn->conn_message;

    /*
     * Don't process broken connections
     */
    if (conn->conn_errno)
	return;

    /*
     * Callback function must be set before we do any I/O
     */
    if (!conn->conn_callback)
    {
	conn->conn_errno = ERR_CONN_INVAL;
	return;
    }

    switch (conn->conn_state)
    {
    case CONN_WRITING:
    case CONN_READING:
	stream = conn->conn_stream;
	break;
    default:
	conn->conn_errno = ERR_CONN_INVAL;
	return;
    }

    while(message->nvec > 0)
    {
	if (conn->conn_state == CONN_WRITING)
	{
	    /*
	     * Incrementally compute trailer checksum
	     */
	    if (message->write_crypto.update_mic)
	    {
		message->write_crypto.update_mic(conn, 0);
	    }
	    nio = Unameit_Stream_Writev(stream, message->iov, message->nvec);
	}
	else
	{
	    nio = Unameit_Stream_Readv(stream, message->iov, message->nvec);
	}
	if (nio == 0)
	{
	    /*
	     * When reading this is EOF
	     * When writing,  this is I/O that would block on some SYSVs
	     */
	    if (conn->conn_state == CONN_READING)
	    {
		if (message->header.offset == 0)
		{
		    /*
		     * EOF on message boundary,  is normal
		     */
		    conn->conn_state = CONN_EOF;
		    return;
		}
		/*
		 * EOF in middle of message is problematic
		 */
		if (message->header.offset < sizeof(message->header.data) ||
		    message->offset < message->length||
		    message->trailer.offset > 0)
		{
		    conn->conn_errno = ERR_CONN_SHORT;
		    return;
		}
		/*
		 * EOF just before trailer, is caused by failed key exchange
		 * simulate receiving empty trailer.
		 */
		memset(message->trailer.mic, 0, MIC_LEN);
		nio = MIC_LEN;
	    }
	    else
	    {
		return;
	    }
	}
	switch (nio) 
	{
	    /* Operation would have blocked, but it is not an error. */
	case -2 : 
	    return;
	    
	    /* Error occurred. */
	case -1 :
	    conn->conn_errno = (conn->conn_state == CONN_READING) ?
		ERR_CONN_READ : ERR_CONN_WRITE;
	    return;
	}
	slide_window(conn, nio);

	if (conn->conn_state == CONN_READING)
	{
	    /*
	     * Can't checksum header until we have finished reading it
	     */
	    if (message->header.offset < sizeof(message->header.data))
	    {
		return;
	    }
	    /*
	     * Incrementally compute trailer checksum
	     */
	    if (message->read_crypto.update_mic)
	    {
		message->read_crypto.update_mic(conn, 0);
	    }
	}
	/*
	 * Give other connections a chance
	 */
	if (++packets > 16)
	    break;
    }

    /*
     * If not yet done, return
     */
    if (message->nvec > 0)
	return;

    /*
     * We have received or sent a complete message,  Invoke the callback.
     *
     * The callback is invoked on all state transitions.  It takes the old
     * state as its second argument.
     */
    {
	conn_state_t prev_state = conn->conn_state;

	/*
	 * If messages are checksummed,  checksum is always ok
	 */
	if (prev_state == CONN_READING &&
	    message->read_crypto.update_mic == NULL)
	{
	    message->read_crypto.mic_ok = 1;
	}

	conn->conn_state = CONN_IODONE;
	conn->conn_callback(conn, prev_state);
    }
}


/*
 * Tear down the connection on error or end of file.
 */
void
Unameit_Conn_Reap(conn_t *conn)
{
    /*
     * This frees the data
     */
    newstate(conn, CONN_IODONE);

    /*
     * Reap the underlying stream
     */
    if (conn->conn_stream != INVALID_SOCKET)
    {
	(void) close(conn->conn_stream);
    }
    conn->conn_stream = INVALID_SOCKET;
    
    /*
     * Free crypto handles
     */
    if (conn->conn_message.read_crypto.context)
    {
	ckfree((char *)conn->conn_message.read_crypto.context);
    }
    if (conn->conn_message.write_crypto.context)
    {
	ckfree((char *)conn->conn_message.write_crypto.context);
    }

    /*
     * Free the slave interpeter
     */
    if (conn->conn_interp)
    {
	Tcl_DeleteInterp(conn->conn_interp);
    }

    /*
     * When created with connQueue == NULL
     * connections are not on a queue
     * This happens iff conn->q_back == NULL
     */
    if (conn->q_back)
    {
	/*
	 * remque(conn)
	 *
	 * The SunOS 4.1.3 insque() appears broken,  and in any case
	 * this code is simple enough to be inlined.
	 */
	conn->q_back->q_forw = conn->q_forw;
	if (conn->q_forw)
	    conn->q_forw->q_back = conn->q_back;
    }
    conn->q_forw = conn->q_back = (conn_t *)NULL;

    (void) ckfree((char *)conn);
}


/*
 * Return a pointer to the just received data
 * Can only be called in CONN_IODONE state.
 */
char *
Unameit_Conn_Read(conn_t *conn, unsigned32 *lenP, unsigned32 *ret_code)
{
    char	*data;

    if (conn->conn_errno)
	return NULL;

    if (lenP == (unsigned32 *)NULL)
    {
	conn->conn_errno = ERR_CONN_INVAL;
	return NULL;
    }

    /*
     * After conn_getmsg() the application manages the associated storage.
     */
    data  = conn->conn_message.data;
    *lenP = conn->conn_message.length;
    memcpy((char *)ret_code,
	   (char *)conn->conn_message.header.data.result, sizeof(unsigned32));
    *ret_code = unsigned32_ntoh(*ret_code);
    
    conn->conn_message.data = (char *)NULL;
    conn->conn_message.free = TCL_STATIC;

    newstate(conn, CONN_IODONE);

    return data;
}


/*
 * Initialize the message buffer for writing.
 */
void
Unameit_Conn_Write(
    conn_t *conn,
    char *data,
    unsigned32 len,
    conn_auth_t auth_type,
    unsigned32 result,
    Tcl_FreeProc *free_proc
)
{
    unsigned32 magic = unsigned32_hton(CONN_MAGIC);
    unsigned32 atype = unsigned32_hton((unsigned32) auth_type);
    
    /*
     * We do not check conn->conn_errno until we have installed the
     * new data,   since returning early will cause a memory leak.
     */

    newstate(conn, CONN_WRITING);

    if (free_proc == TCL_VOLATILE)
    {
	char *buf = ckalloc(len);
	if (buf == NULL)
	{
	    panic("Out of memory");
	}
	memcpy(buf, data, len);
	data = buf;
	free_proc = TCL_DYNAMIC;
    }

    conn->conn_message.data = data;
    conn->conn_message.free = free_proc;

    if (conn->conn_errno)
	return;

    conn->conn_message.length = len;

    len = unsigned32_hton(len);
    result = unsigned32_hton(result);

    memcpy((char *)conn->conn_message.header.data.magic,
	   (char *)&magic, sizeof magic);
    memcpy((char *)conn->conn_message.header.data.datalen,
	   (char *)&len, sizeof len);
    memcpy((char *)conn->conn_message.header.data.auth_type,
	   (char *)&atype, sizeof atype);
    memcpy((char *)conn->conn_message.header.data.result,
	   (char *)&result, sizeof result);

    iov_init_header(&conn->conn_message, CONN_WRITING);

    /*
     * Reset crypto state to beginning of message
     */
    if (conn->conn_message.write_crypto.update_mic)
	conn->conn_message.write_crypto.update_mic(conn, 1);

    return;
}


void
Unameit_Conn_Poll(conn_t *conn)
{
    if (conn->conn_errno)
	return;

    newstate(conn, CONN_READING);

    if (conn->conn_errno)
	return;

    iov_init_header(&conn->conn_message, CONN_READING);

    /*
     * Reset crypto state to beginning of message
     */
    if (conn->conn_message.read_crypto.update_mic)
	conn->conn_message.read_crypto.update_mic(conn, 1);

    return;
}
