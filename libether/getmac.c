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
#include <uconfig.h>
#if 0
#include <sys/types.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

#include <string.h>
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>

#endif
#include <tcl.h>
#include <net/if.h>
#include "ether.h"

#define MAX_IFR 16

int
Uuid_Get_Macaddress(ether_addr_t *ea)
{
    struct ifreq   ifr[MAX_IFR];
    struct ifconf  ifc;
    int		   ifIndex;
    int 	   s;

    if ( (s = socket(AF_INET, SOCK_DGRAM, 0)) == -1 )
    {
	return TCL_ERROR;
    }

    ifc.ifc_req=ifr;
    ifc.ifc_len=sizeof(ifr);

    if (ioctl(s, SIOCGIFCONF, &ifc)==-1)
    {
	(void) close(s);
	return TCL_ERROR;
    }

    ifc.ifc_len /= sizeof(ifr[0]);

    for (ifIndex = 0; ifIndex < ifc.ifc_len; ++ifIndex)
    {
	if (ioctl(s, SIOCGIFFLAGS, (char *)&ifc.ifc_req[ifIndex]) < 0)
	    continue;

#define BITS_ON   (IFF_BROADCAST | IFF_UP | IFF_RUNNING)
#define BITS_OFF (IFF_NOARP | IFF_LOOPBACK)

	if (((ifc.ifc_req[ifIndex].ifr_flags & BITS_ON) != BITS_ON) ||
	    ((ifc.ifc_req[ifIndex].ifr_flags & BITS_OFF) != 0))
	    continue;

    	if (ether_addr(ifc.ifc_req[ifIndex].ifr_name, ifIndex, ea) == TCL_OK)
	{
	    (void) close(s);
	    return TCL_OK;
	}
    }	
    (void) close(s);
    return TCL_ERROR;
}
