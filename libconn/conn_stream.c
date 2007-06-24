/*
 * Copyright (c) 1994-1997 Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: conn_stream.c,v 1.11.4.3 1997/09/21 23:42:22 viktor Exp $";

#include <conn_stream.h>


#ifdef USE_FIONBIO
#define ASYNC_FLAG O_NDELAY
#else
#define ASYNC_FLAG O_NONBLOCK
#endif

/*
 * Returns nio if >= 0. 
 * Returns -2 if operation would block.
 * Returns -1 on any other error.
 */
#ifdef WIN32
int Check_Io (int nio)
{
    int reason;
    if (nio >= 0)
	return nio;
    
    reason = WSAGetLastError();
    switch(reason)
    {
    case WSAEWOULDBLOCK :
	return -2;
    }
    return -1;
}

#else

int Check_Io (int nio)
{
    if (nio >= 0)
	return nio;

    switch (errno)
    {
#ifdef EWOULDBLOCK
    case EWOULDBLOCK:
#endif
#ifdef EAGAIN
#  if EAGAIN != EWOULDBLOCK
    case EAGAIN:
#  endif
#endif
    case EINTR:
	return -2;
    }
    return -1;
}
#endif

/*
 * This is our own scatter-gather read implementation.
 * Some systems do not have readv and some systems have buggy readv.
 * We just do multiple reads.
 */
int
Unameit_Stream_Readv(int stream, struct iovec *iov, int nvec)
{
    assert(nvec >= 1);

    if (nvec == 1)
    {
	return (Check_Io (recv(stream, iov->iov_base, iov->iov_len, 0)));
    }
    else
    {
	int i;
	int total = 0;
	for (i=0; i < nvec; ++i)
	{
	    int n = recv(stream, iov->iov_base, iov->iov_len, 0);
	    if (n < 0)
	    {
		return total ? total : Check_Io (n);
	    }
	    total += n;
	    if (n != iov->iov_len)
	    {
		return total;
	    }
	    ++iov;
	}
	return total;
    }
}

#define MAX_COPY_SIZE ((4 * 1024) + 16)
/*
 * This is our own scatter-gather write implementation.
 * Some systems do not have writev and some systems have buggy writev.
 * If there is only one chunk to write, do so. If the first chunk is
 * larger than MAX_COPY_SIZE, just try to send the first chunk. Otherwise,
 * copy chunks into the buffer until it is full, then send it.
 * This routine returns the number of bytes written or a negative 
 * number for an error. This return value can be:
 *
 * 	>= 0	normal
 *	-1	error
 *	-2	would block (try again later)
 */
int
Unameit_Stream_Writev(int stream, struct iovec *iov, int nvec)
{
    char buf[MAX_COPY_SIZE];
    int i;
    int total;
    char *to;
    
    assert(nvec >= 1);

    if ((nvec == 1) || (iov->iov_len > MAX_COPY_SIZE))
    {
	return (Check_Io (send (stream, iov->iov_base, iov->iov_len, 0)));
    }

    for (i=total=0, to=buf; (i < nvec) && (total < MAX_COPY_SIZE); ++i, ++iov)
    {
	int ncopy = MAX_COPY_SIZE - total;
	if (iov->iov_len < ncopy)
	    ncopy = iov->iov_len;
	if (ncopy == 0)
	    continue;
	memcpy (to, iov->iov_base, ncopy);
	total += ncopy;
	to += ncopy;
    }

    return (Check_Io (send (stream, buf, total, 0)));
}


int
Unameit_Stream_Connect(
    Tcl_Interp *interp,
    int *stream,
    const char *hostname,
    const char *portname
)
{
    struct sockaddr_in	s_in;
    struct hostent	*hp;
    struct servent	*service;
    int			sock;
    long   		portnum;
    unsigned short   	port;
    char   		*endint;
    int 		result;

    memset((char *)&s_in, 0, sizeof(s_in));
    s_in.sin_family = AF_INET;

    /*
     * Connect socket using name specified by "hostname"
     */
    if (!isdigit(hostname[0]) || 
	(s_in.sin_addr.s_addr = inet_addr(hostname)) == INADDR_BROADCAST)
    {
	hp = gethostbyname(hostname);
	if (hp == NULL) 
	{
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "No such host or address: ", hostname,
			     (char *)NULL);
	    return TCL_ERROR;
	}
	memcpy((char *)&s_in.sin_addr, (char *)hp->h_addr, hp->h_length);
    }

    if (!isdigit(portname[0]) ||
	(portnum = strtol(portname, &endint, 0)) <= 0 ||
	portnum > 0xFFFF || *endint != '\0')
    {
	if ((service = getservbyname(portname, "tcp")) != NULL)
	{
	    port = service->s_port;
	}
	else
	{
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "Service unknown:", portname, "/tcp",
		(char *)NULL);
	    return TCL_ERROR;
	}
    }
    else
    {
	port = htons((unsigned short)portnum);
    }
    s_in.sin_port = port;

    sock = socket(PF_INET, SOCK_STREAM, 0);

    if (sock < 0)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, "Could not create TCP socket: ",
		Tcl_PosixError(interp), (char *)NULL);
	return TCL_ERROR;
    }

#if defined HAVE_FCNTL
    result = (fcntl(sock, F_SETFL, ASYNC_FLAG) != -1);
#elif defined HAVE_IOCTLSOCKET
    {
	int one = 1;
	result = (ioctlsocket (sock, FIONBIO, &one) == 0);
    }
#else
#error  Can not make sockets non blocking
#endif

    if (!result)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp,
	    "Could not make client stream nonblocking: ",
	    Tcl_PosixError(interp), (char *)NULL);
	return TCL_ERROR;
    }

    result = connect(sock, (struct sockaddr *)&s_in, sizeof s_in);
    /*
     * We are making a non-blocking connect, so the connect will
     * usually fail. We must check the failure to determine if 
     * something is really wrong, or if the connect will eventually
     * complete.
     */
    if (result != 0) 
    {
	int reason = errno;
#ifdef HAVE_WSAGETLASTERROR
	reason = WSAGetLastError();
#endif
	switch(reason)
	{
	case ETIMEDOUT:		/* Temporary problems... */
	case ENETUNREACH:
	case ECONNREFUSED:
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "connect: ", hostname, ":", portname,
			     ": ", Tcl_PosixError(interp), (char *)NULL);
	    Tcl_SetErrorCode(interp, "UNAMEIT", "CONN", "EAGAIN", (char *)NULL);
	    (void) close(sock);
	    return TCL_ERROR;

	    /*
	     * Should only happen for non blocking connect
	     */
	case EINPROGRESS:	
	    break;

	default:		/* More serious... */
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "Could not connect to ",
		hostname, ":", portname, " because: ",
		Tcl_PosixError(interp), (char *)NULL);
	    return TCL_ERROR;
	}
    }

#ifndef HAVE_SYS_UIO_H
    /*
     * When we write the header and data
     * separately,  we get pathetic performance without TCP_NODELAY
     */
    {
	int    	on = 1;
	(void) setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char *)&on,
			  sizeof(on));
    }
#endif
    
    *stream = sock;

    return TCL_OK;
}


int
Unameit_Stream_Peer(int stream, char **hostname, int *port)
{
    struct sockaddr_in s;
    size_t s_len = sizeof(s);
    struct hostent *hp;

    if (getpeername(stream, (struct sockaddr *)&s, &s_len) < 0)
    {
	return TCL_ERROR;
    }

    if (hostname == NULL)
    {
	/*
	 * Just checking that a peer exists!
	 */
	return TCL_OK;
    }

    assert(s.sin_family == AF_INET);

    hp = gethostbyaddr((char *)&s.sin_addr, sizeof(s.sin_addr), AF_INET);

    if (hp == NULL)
    {
	*hostname = inet_ntoa(s.sin_addr);
    }
    else
    {
	*hostname = hp->h_name;
    }

    if (port != NULL)
    {
	*port = ntohs(s.sin_port);
    }

    return TCL_OK;
}


int
Unameit_Stream_Listen(
    Tcl_Interp *interp,
    int *stream,
    const char *portname
)
{
    struct servent	*sv;
    struct sockaddr_in	s_in;
    int			sock;
    long		portnum;
    unsigned short	port;
    char		*endint;

    /*
     * If port is a number between 1 and 65535 use that
     * else use getservbyname()
     */
    if (!isdigit(portname[0]) ||
	(portnum = strtol(portname, &endint, 0)) <= 0 ||
	portnum > 0xFFFF || *endint != '\0')
    {
	if ((sv = getservbyname(portname, "tcp")) != NULL)
	{
	    port = sv->s_port;
	}
	else
	{
	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "Service Unknown: ", portname, "/tcp",
	    	(char *)NULL);
	    return TCL_ERROR;
	}
    }
    else
    {
	port = htons((unsigned short)portnum);
    }

    sock = socket(PF_INET, SOCK_STREAM, 0);

    if (sock < 0)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, "Could not create TCP socket: ",
		Tcl_PosixError(interp), (char *)NULL);
	return TCL_ERROR;
    }

    memset((char *)&s_in, 0, sizeof(s_in));
    s_in.sin_family = AF_INET;
    s_in.sin_addr.s_addr = INADDR_ANY;
    s_in.sin_port   = port;

#ifdef SO_REUSEADDR
    {
	int	on = 1;
	(void) setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, (char *)&on,
			  sizeof(on));
    }
#endif

    if (bind(sock, (struct sockaddr *)&s_in, sizeof(s_in)) < 0)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, "Could bind port ", portname, "/tcp: ",
	    Tcl_PosixError(interp), (char *)NULL);
	(void) close(sock);
	return TCL_ERROR;
    }

    if (listen(sock, 256) == -1)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, "Could not listen on port ",
		portname, "/tcp: ", Tcl_PosixError(interp), (char *)NULL);
	(void) close(sock);
	return TCL_ERROR;
    }

    *stream = sock;
    return TCL_OK;
}


int
Unameit_Stream_Accept(
    Tcl_Interp *interp,
    int *stream,
    int server
)
{
    SOCKET   sock;
    struct   sockaddr_in from;
    int      fromlen = sizeof(from);
    int	     result;

    memset((char *)&from, 0, sizeof(from));
    sock = accept(server, (struct sockaddr *)&from, &fromlen);

    if (sock == SOCKET_ERROR)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, "Could not accept new connection: ",
		Tcl_PosixError(interp), (char *)NULL);
	return TCL_ERROR;
    }

    assert (from.sin_family == AF_INET);

#if defined HAVE_FCNTL
    result = (fcntl(sock, F_SETFL, ASYNC_FLAG) != -1);
#elif defined HAVE_IOCTLSOCKET
    {
	int one = 1;
	result = (ioctlsocket (sock, FIONBIO, &one) == 0);
    }
#else
#error  Can not make sockets non blocking
#endif

    if (!result)
    {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp,
	    "Could not make client stream non blocking: ",
	    Tcl_PosixError(interp), (char *)NULL);
	(void) close(sock);
	return TCL_ERROR;
    }

#ifndef HAVE_SYS_UIO_H
    /*
     * When the we write the small header and data
     * separately,  we get pathetic performance without TCP_NODELAY
     */
    {
	int      on = 1;
	(void) setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char *)&on,
			  sizeof(on));
    }
#endif

    *stream = sock;
    return TCL_OK;
}
