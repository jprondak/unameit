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
static char rcsid[] = "$Id: main.c,v 1.2.20.2 1997/09/21 23:42:30 viktor Exp $";

#include <uconfig.h>
#include "ether.h"


int
main(int argc, char *argv[])
{
    ether_addr_t	ea;

    if (Uuid_Get_Macaddress(&ea) != TCL_OK)
    {
	perror("Can't read MAC address");
	exit(1);
    }

    /*
     * Sanity check: address should not be a multicast address
     */
    assert((ea.addr[0] & 1) == 0);

    (void) printf("%x:%x:%x:%x:%x:%x\n",
		  ea.addr[0], ea.addr[1], ea.addr[2],
		  ea.addr[3], ea.addr[4], ea.addr[5]);

    exit(0);
}
