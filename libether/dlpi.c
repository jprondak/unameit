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
static char rcsid[] = "$Id: dlpi.c,v 1.5.50.3 1997/09/21 23:42:29 viktor Exp $";

#include <uconfig.h>
#include <stropts.h>			/* putmsg() / getmsg() */
#include <errno.h>			/* EMFILE/EINVAL */
#include <sys/file.h>			/* O_RDWR */
#include <sys/stropts.h>		/* RMSGD */
#include <net/if.h>			/* ifreq */
#include <sys/dlpi.h>			/* DLPI stuff */

#include "ether.h"

#define DBLLEN	2048
#define SLASHDEV "/dev/"

static int
dlpi_fd(const char *name, int *unit)
{
    int fd;

    if ((fd = open("/dev/dlpi", O_RDWR, 0)) >= 0)
    {
	++*unit;
    }
    else if (errno == ENOENT)
    {
	char ifdev[IFNAMSIZ+sizeof(SLASHDEV)];
	char *ifdevp;

	memcpy(ifdev, SLASHDEV, sizeof(SLASHDEV));
	ifdevp = &ifdev[sizeof(SLASHDEV)-1];
	while (!isdigit(*ifdevp++ = *name++))
	  ;
	*--ifdevp = '\0';

	*unit = atoi(--name);
	fd = open(ifdev, O_RDWR, 0);
    }
    return fd;
}

int
/*ARGSUSED*/
ether_addr(const char *name, int unit, ether_addr_t *address)
{
    int fd, flags;
    struct strbuf stc;
    long ctl[DBLLEN];
    union DL_primitives *d = (union DL_primitives *)ctl;

    assert(address);

    stc.maxlen = sizeof(long)*DBLLEN;
    stc.buf = (char *)d;


    if ((fd = dlpi_fd(name, &unit)) < 0)
    {
	return TCL_ERROR;
    }

    /*
     * Attach the device
     */
    d->dl_primitive = DL_ATTACH_REQ;
    d->attach_req.dl_ppa = unit;
    stc.len = DL_ATTACH_REQ_SIZE;
    if (putmsg(fd, &stc, 0, RS_HIPRI) < 0)
    {

	(void) close(fd);
	return TCL_ERROR;
    }
    stc.len = 0;
    flags = 0;
    if (getmsg(fd, &stc, 0, &flags) < 0)
    {
	(void) close(fd);
	return TCL_ERROR;
    }
    if (d->dl_primitive != DL_OK_ACK)
    {
	(void) close(fd);
	return TCL_ERROR;
    }

    /*
     * Get the address
     */

    d->dl_primitive = DL_PHYS_ADDR_REQ;
    d->physaddr_req.dl_addr_type = DL_FACT_PHYS_ADDR;
    stc.len = DL_PHYS_ADDR_REQ_SIZE;
    if (putmsg(fd, &stc, 0, RS_HIPRI) < 0)
    {
	(void) close(fd);
	return TCL_ERROR;
    }
    stc.len = 0;
    flags = 0;
    if (getmsg(fd, &stc, 0, &flags) < 0)
    {
	(void) close(fd);
	return TCL_ERROR;
    }
    if (d->dl_primitive != DL_PHYS_ADDR_ACK)
    {
	(void) close(fd);
	return TCL_ERROR;
    }

    (void) close(fd);
    
    assert(d->physaddr_ack.dl_addr_length == sizeof(ether_addr_t));

    memcpy((char *)address,
	   (char *)d+d->physaddr_ack.dl_addr_offset,
	   sizeof (ether_addr_t));

    return TCL_OK;
}
