/*
 * Copyright (c) 1996 Enterprise Systems Management Corp.
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
/* $Id: nit3.c,v 1.3 1996/11/12 01:07:06 viktor Exp $ */

#include <sys/types.h>			/* ifreq (u_short) */
#include <sys/time.h>			/* timeval */
#include <sys/socket.h>			/* AF_NIT */
#include <sys/ioctl.h>			/* ioctl */
#include <net/nit.h>			/* sockaddr_nit */
#include <net/if.h>			/* ifreq */
#include <string.h>			/* memcpy */

#include <tcl.h>
#include "ether.h"

int
/*ARGSUSED*/
ether_addr(const char *name, int ifIndex, ether_addr_t *address)
{
    int fd;
    struct ifreq ifr;

    if ((fd = socket (AF_NIT, SOCK_RAW, NITPROTO_RAW)) < 0)
    {
	return TCL_ERROR;
    }

    ifr.ifr_addr.sa_family = AF_NIT;
    if (ioctl (fd, SIOCGIFADDR, (char *) &ifr) < 0)
    {
	close(fd);
	return TCL_ERROR;
    }
    (void) close(fd);

    memcpy((char *)address, ifr.ifr_addr.sa_data, sizeof(ether_addr_t));
    return TCL_OK;
}
