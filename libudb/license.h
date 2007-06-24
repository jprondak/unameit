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
/* $Id: license.h,v 1.5 1996/08/14 07:23:59 viktor Exp $ */
#ifndef LICENSE_H
#define LICENSE_H
#include <tcl.h>

/*
 * Returns start and duration of license,  current unit count, and limit
 */
extern Tcl_CmdProc Udb_License_Info;

/*
 * Validate and initialize license info,  exits on error.
 */
extern void Udb_Init_License(Tcl_Interp *interp);

/*
 * Incrementally maintain and check license counts
 */
extern void Udb_Adjust_License_Count(DB_OBJECT *class, DB_INT32 count);
extern void Udb_Update_License_Limits(void);
extern void Udb_Rollback_License_Limits(void);
extern int Udb_Over_License_Count(void);

#endif
