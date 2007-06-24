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
/* $Id: name_cache.h,v 1.7.58.2 1997/09/19 18:38:29 viktor Exp $ */
#ifndef _NAME_CACHE_H
#define _NAME_CACHE_H

#define NORMAL_TABLE 0
#define CELL_TABLE 1
#define ORG_TABLE 2
#define GLOBAL_TABLE 3
#define INET_TABLE 4
#define RANGE_TABLE 5
#define LAST_TABLE RANGE_TABLE

#define NCACHE_TABLES	(LAST_TABLE+1)

extern void Udb_Populate_Caches(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *tables
);

extern int Udb_Update_Caches(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object, 
    Tcl_HashTable *old_tables,
    Tcl_HashTable *new_tables
);

extern void Udb_Delete_All_Caches(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object
);

extern void Udb_Free_Cache_Tables(Tcl_HashTable *tables);

extern void Udb_Add_Unique_Check(DB_OBJECT *object);
extern void Udb_Drop_Unique_Check(DB_OBJECT *object);
extern void Udb_Reset_Unique_Checks(void);
extern int Udb_Do_Unique_Checks(Tcl_Interp *interp);

#endif
