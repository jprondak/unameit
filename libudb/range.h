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
/* $Id: range.h,v 1.7 1996/09/10 21:02:26 viktor Exp $ */
#ifndef RANGE_H
#define RANGE_H
#include <tcl.h>

/*
 * Insert object.aname == ival into range structures.
 */
extern void Udb_Add_Range_Entry(
    DB_OBJECT *owner,
    char *aname,
    DB_INT32 ival,
    DB_OBJECT *object
);

/*
 * Delete object.aname == ival from range structures.
 */
extern void Udb_Delete_Range_Entry(
    DB_OBJECT *owner,
    char *aname,
    DB_INT32 ival,
    DB_OBJECT *object
);

/*
 * Get the next integer in a range. It takes three parameters: the uuid of
 * the class which contains the ranges, the name of the attribute in that
 * class that contains the ranges and the start integer value
 */
extern Tcl_CmdProc Udb_Auto_Integer;

#endif
