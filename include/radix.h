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
/* $Id: radix.h,v 1.3.58.2 1997/09/16 01:01:40 viktor Exp $ */
#ifndef _RADIX64_H
#define _RADIX64_H

#define	RDATA	16	/* Binary data without trailing NUL */
#define R64     23	/* Including NUL trailing byte */
#define R16     33	/* Including NUL trailing byte */

/*
 * We encode 128 bit uuids in radix 64.  This uses 22 + 1 = 23 bytes
 */
#define UDB_UUID_LEN (R64-1)
#define UDB_UUID_SIZE R64

extern void
Udb_Radix64_Encode(const unsigned char in[RDATA], char out[R64]);

extern int
Udb_Radix64_Decode(const char in[R64], unsigned char out[RDATA]);

extern void
Udb_Radix16_Encode(const unsigned char in[], int octets, char out[]);

extern int
Udb_Radix16_Decode(const char in[], unsigned int octets, unsigned char out[]);

#endif /* _RADIX64_H */
