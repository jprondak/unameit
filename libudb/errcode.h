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
#ifndef _ERRCODE_H
#define _ERRCODE_H
#include <stdarg.h>
#include <error.h>

/*
 * Generic `varargs' error.  All errors where string parameters
 * are readily accessible should use this function
 */
extern int Udb_Error(Tcl_Interp *interp, const char *code, ...);

/*
 * Referential integrity error
 */
extern int Udb_EREFINTEGRITY(Tcl_Interp *interp, const char *ecode);

/*
 * Direct collision on a single set of attributes
 */
extern int Udb_EDIRECTUNIQ(
    Tcl_Interp *Interp,
    DB_OBJECT *cache_entry,
    DB_COLLECTION *items,
    int     item_count
);

/*
 * Promoted collision involving an object and forbidden overrides in
 * lower regions.
 */
extern int Udb_EINDIRUNIQ(
    Tcl_Interp *interp,
    DB_OBJECT *cache_entry,
    DB_COLLECTION *globals,
    DB_COLLECTION *locals,
    int     local_count
);

/*
 * Too many rows in qbe result
 */
extern int Udb_EROWCOUNT(Tcl_Interp *interp, int rowcount, int maxcount);

#endif /* _ERRCODE_H */
