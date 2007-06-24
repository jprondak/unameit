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
/* $Id: tcl_mem.h,v 1.6 1996/07/13 02:03:32 viktor Exp $ */
#ifndef _TCL_MEM_H
#define _TCL_MEM_H
#include <dbi.h>
#include <tcl.h>

extern void Udb_Delay_Fetch(
    Tcl_HashTable *streamTbl,
    DB_OBJECT *object
);

extern void
Udb_Store_Value(
    Tcl_HashTable *streamTbl,
    DB_OBJECT *object,
    char *aname,
    DB_VALUE *value
);

extern int Udb_Stream_Encode(
    Tcl_Interp *interp,
    Tcl_HashTable *streamTbl,
    int nameFields,
    int streamFlag,
    int deletedFlag
);

extern void Udb_Delete_Stream_Table(Tcl_HashTable *streamTbl);

#endif
