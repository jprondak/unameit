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
/* $Id: conn_stream.h,v 1.4.58.1 1997/08/28 18:26:39 viktor Exp $ */
#ifndef UNAMEIT_CONN_STREAM_H
#define UNAMEIT_CONN_STREAM_H

#include <uconfig.h>

#include <errno.h>
#include <fcntl.h>

extern int
Unameit_Stream_Readv(int stream, struct iovec *iov, int nvec);

extern int
Unameit_Stream_Writev(int stream, struct iovec *iov, int nvec);

extern int
Unameit_Stream_Connect(
    Tcl_Interp *interp,
    int *stream,
    const char *host,
    const char *port
);

/*
 * The hostname and port are set to VOLATILE static data
 */
extern int
Unameit_Stream_Peer(int stream, char **hostname, int *port);

extern int
Unameit_Stream_Listen(
    Tcl_Interp *interp,
    int *stream,
    const char *portname
);

extern int
Unameit_Stream_Accept(
    Tcl_Interp *interp,
    int *stream,
    int server
);

#endif /* UNAMEIT_CONN_STREAM_H */
