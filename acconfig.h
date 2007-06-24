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
#ifndef _config_h_
#define _config_h_
/*
 * We always compile with TCL_MEM_DEBUG.
 */
#define TCL_MEM_DEBUG 1

#ifdef WIN32
#include <winconfig.h>
#else
@TOP@

/* Define this if long long is legit. */
#undef HAVE_LONG_LONG

@BOTTOM@

typedef unsigned int SOCKET;

#ifndef SOCKET_ERROR
#define SOCKET_ERROR ((SOCKET)-1)
#endif

#ifndef INVALID_SOCKET
#define INVALID_SOCKET ((SOCKET)~0)
#endif

#endif /* end of unix section */

#endif /* _config_h_ */
