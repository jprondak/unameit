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
/*
 * The YPPASSWD protocol uses an obsolete passwd structure
 * no longer in agreement with the actual definition in <pwd.h>
 * This file was generated from a pruned struct passwd definition
 * and then edited to include the system <pwd.h>
 * This will have the effect of encoding/decoding only the
 * minimal fields in the obsolete passwd structure.
 * All remaining fields will remain untouched.
 */
#include <rpc/rpc.h>
#include "yppasswd.h"

bool_t
xdr_passwd(xdrs, objp)
	XDR *xdrs;
	struct passwd *objp;
{
	int ival;
	if (!xdr_string(xdrs, &objp->pw_name, ~0)) {
		return (FALSE);
	}
	if (!xdr_string(xdrs, &objp->pw_passwd, ~0)) {
		return (FALSE);
	}
	ival = objp->pw_uid;
	if (!xdr_int(xdrs, &ival)) {
		return (FALSE);
	}
	objp->pw_uid = ival;
	ival = objp->pw_gid;
	if (!xdr_int(xdrs, &ival)) {
		return (FALSE);
	}
	objp->pw_gid = ival;
	if (!xdr_string(xdrs, &objp->pw_gecos, ~0)) {
		return (FALSE);
	}
	if (!xdr_string(xdrs, &objp->pw_dir, ~0)) {
		return (FALSE);
	}
	if (!xdr_string(xdrs, &objp->pw_shell, ~0)) {
		return (FALSE);
	}
	return (TRUE);
}

bool_t
xdr_yppasswd(xdrs, objp)
	XDR *xdrs;
	yppasswd *objp;
{
	if (!xdr_string(xdrs, &objp->oldpass, ~0)) {
		return (FALSE);
	}
	if (!xdr_passwd(xdrs, &objp->newpw)) {
		return (FALSE);
	}
	return (TRUE);
}
