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
/* $Id: nit4.c,v 1.4 1996/11/12 01:07:07 viktor Exp $ */

#include <sys/file.h>			/* O_RDWR */
#include <sys/types.h>			/* NIOCBIND (u_long) */
#include <sys/time.h>			/* NIOCBIND (timeval) */
#include <sys/ioctl.h>			/* SIOCGIFADDR */
#include <sys/socket.h>			/* ifreq (sockaddr) */
#include <net/if.h>			/* ifreq */
#include <net/nit_if.h>			/* NIOCBIND */
#include <string.h>			/* memcpy */

#include <tcl.h>
#include "ether.h"

#ifndef NIT_DEV
#define NIT_DEV "/dev/nit"
#endif


int
/*ARGSUSED*/
ether_addr(const char *name, int ifIndex, ether_addr_t *address)
{
    int fd;
    struct ifreq ifr;

    if ((fd = open (NIT_DEV, O_RDWR)) < 0)
    {
	return TCL_ERROR;
    }

    (void) strncpy (ifr.ifr_name, name, sizeof (ifr.ifr_name));

    if (ioctl(fd, NIOCBIND, (char *) &ifr) < 0)
    {
	(void) close(fd);
	return TCL_ERROR;
    }

    ifr.ifr_addr.sa_family = AF_NIT;
    if (ioctl (fd, SIOCGIFADDR, (char *) &ifr) < 0)
    {
	(void) close(fd);
	return TCL_ERROR;
    }
    (void) close(fd);

    memcpy((char *)address, ifr.ifr_addr.sa_data, sizeof(ether_addr_t));
    return TCL_OK;
}
