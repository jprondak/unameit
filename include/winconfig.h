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
#ifndef _winconfig_h_
#define _winconfig_h_

#undef HAVE_SYS_UIO_H
#undef HAVE_UNISTD_H
#undef HAVE_NETINET_IN_H
#undef HAVE_LONG_LONG
#undef HAVE_SYS_TIME_H
#undef HAVE_SYSLOG_H
#undef HAVE_FCNTL
#undef HAVE_CRYPT_H
#define HAVE_IOCTLSOCKET 1
#define NO_SIGPIPE 1
#define HAVE_SYS_TYPES_H 1

#include <tcl.h>
#include <wtypes.h>
#include <time.h>
#include <errno.h>
#include <io.h>

#define close _close
#define open _open

/*
 * Keys used to get values from the registry.
 */
#define SOFTWARE_KEY "SOFTWARE"
#define ESM_KEY "Enterprise Systems Management"
#define UNAMEIT_KEY "UNameIt"
#define BS "\\"
#define TOP_KEY SOFTWARE_KEY BS ESM_KEY BS UNAMEIT_KEY 

/* Socket stuff. */
#define HAVE_WSAGETLASTERROR 1

#define EINPROGRESS WSAEWOULDBLOCK
#define ETIMEDOUT WSAETIMEDOUT
#define ENETUNREACH WSAENETUNREACH
#define ECONNREFUSED WSAECONNREFUSED

typedef unsigned char *caddr_t;
typedef unsigned hyper unsigned64;
typedef hyper signed64;
typedef unsigned long unsigned32;
typedef long signed32;
typedef unsigned short unsigned16;
typedef short signed16;
typedef unsigned char unsigned8;
typedef signed char signed8;
#define unsigned32_hton htonl
#define unsigned32_ntoh ntohl
#define unsigned16_hton htons
#define unsigned16_ntoh htons

#endif
