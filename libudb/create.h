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
/* $Id: create.h,v 1.5 1996/08/18 01:48:14 viktor Exp $ */
#ifndef _CREATE_H
#define _CREATE_H
#include <tcl.h>

extern Tcl_CmdProc Udb_Create;
extern Tcl_CmdProc Udb_Undelete;
#endif