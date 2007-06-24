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
/* $Id: inet.h,v 1.7.58.8 1997/10/09 01:10:31 viktor Exp $ */
#ifndef _INET_H
#define _INET_H

/*
 * Reset inet integrity tables
 */
extern void Udb_Inet_Reset_Checks(void);

/*
 * Check inet integrity
 */
extern int Udb_Inet_Check_Integrity(Tcl_Interp *interp);

/*
 * Create or delete inet Tcl command procs
 */
extern int Udb_Inet_Create_Commands(Tcl_Interp *interp, int create);

/*
 * Free inet table contents
 */
extern void Udb_Inet_Free_Table(Tcl_HashTable *table);

/*
 * Save object state for comparison around modification
 */
extern void Udb_Inet_Populate_Tables(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *table
);

/*
 * Update object in inet tree based on old and new state tables
 */
extern int Udb_Inet_Update(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object,
    Tcl_HashTable *old_table,
    Tcl_HashTable *new_table
);

#endif
