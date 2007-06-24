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
#ifndef _UUID_H
#define _UUID_H
/* $Id: uuid.h,v 1.5.20.2 1997/09/19 21:13:44 simpson Exp $ */
#include <arith_types.h>
#include <tcl.h>
#include <radix.h>		/* Needed for R64 const below */

/*
 * Universal Unique Identifier (UUID) types.
 */
typedef struct 
{
    unsigned32          time_low;
    unsigned16          time_mid;
    unsigned16          time_hi_and_version;
    unsigned8           clock_seq_hi_and_reserved;
    unsigned8           clock_seq_low;
    unsigned8           node[6];
}
uuid_t;

/*
 * Max size of a uuid string standard DCE encoding
 * Note: this includes the implied '\0'
 */
#define UUID_C_UUID_STRING_MAX          37

/*
 * Check whether s has the syntax of a valid uuid.
 */
extern int Uuid_Valid(const char *s);
extern const char *Uuid_StringCreate(void);

/*
 * Provides 'C' Binding for "uuidgen" and "uuidok" commands
 */
int Uuid_Init(Tcl_Interp *interp);

#endif
