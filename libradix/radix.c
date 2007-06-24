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
static char rcsid[] = "$Id: radix.c,v 1.4.58.4 1997/09/21 23:42:32 viktor Exp $";

#include <uconfig.h>
#include "radix.h"

static char radix64[] =
    "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

void
Udb_Radix64_Encode(const unsigned char in[RDATA], char out[R64])
{
    register int i;

    assert(in);
    assert(out);

    memset(out, 0, R64);

    for (i = 0; i < RDATA; ++i) {
	int i_div_6 = (i<<3)/6;
        int i_mod_6 = (i<<3)%6;

	/*
	 * When inserting on right shift = 8 - bit count
	 *		(using bit count leftmost bits)
	 * When inserting on left  shift = 6 - bit count
	 *		(using bit count rightmost bits)
	 *
	 * If i_mod_6 != 5,
	 *	6 - i_mod_6 in right of first slot and
	 *  	2 + i_mod_6 in left  of next slot
	 * else
	 *	1 bit	    in right of first slot and
	 *	6 bits	    in whole of next slot and
	 *      1 bit	    in left  of slot after that
	 *
 	 * Our bit offset is always even,  so only first case applies
	 *
	 */
	out[i_div_6] |= (in[i] >> (2+i_mod_6)) & 0x3f;
#if 1
	out[++i_div_6] |= (in[i] << (4-i_mod_6)) & 0x3f;
#else
	out[++i_div_6] |= (in[i] >> 1) & 0x3f;
	out[++i_div_6] |= (in[i] << 5) & 0x3f;
#endif
    }

    for (i = 0; i < (R64-1); ++i) {
	out[i] = radix64[(unsigned int)out[i]];
    }
}

int
Udb_Radix64_Decode(const char in[R64], unsigned char out[RDATA])
{
    unsigned char *cp = (unsigned char *)in;
    register int i;

    assert(in);
    assert(out);

    memset((char *)out, 0, RDATA);

    for (i = 0; i < (R64-1); ++i) {
	int i_div_8 = ((i<<2) + (i<<1)) >> 3;
	int i_mod_8 = ((i<<2) + (i<<1)) & 07;
	int digit64;

	/*
	 * In ASCII '.', '/' and '0' are consecutive
	 */
	if (*cp >= '.' && *cp <= '9') {
	    digit64 = *cp - '.';
	} else if (*cp >= 'A' && *cp <= 'Z') {
	    digit64 = *cp + 12 - 'A';
	} else if (*cp >= 'a' && *cp <= 'z') {
	    digit64 = *cp + 38 - 'a';
	} else {
	    return 1;
	}

	++cp;

	if (i_mod_8 < 3) {
	    out[i_div_8] |= digit64 << (2-i_mod_8);
	} else {
	    unsigned carry = (digit64 << (10 - i_mod_8)) & 0xff;

	    out[i_div_8] |= digit64 >> (i_mod_8-2);

	    if (++i_div_8 < RDATA) {
		out[i_div_8] |= carry;
	    } else if (carry != 0) {
		return 1;
	    }
	}
    }
    if (*cp == '\0') {
	return 0;
    }
    /*
     * Input string is too long
     */
    return 1;
}

static const char radix16[] = "0123456789abcdef";

void
Udb_Radix16_Encode(const unsigned char in[], int octets, char out[])
{
    assert(in);
    assert(out);

    while(--octets >= 0)
    {
	*out++ = radix16[*in>>4 & 0xf];
	*out++ = radix16[*in++  & 0xf];
    }
    *out = '\0';
}

int
Udb_Radix16_Decode(const char in[], unsigned int octets, unsigned char out[])
{
    register unsigned char	*p = (unsigned char *)in;
    register unsigned char	*end = p + (octets<<1);
    register int		nibble;

    assert(in);
    assert(out);

    for (nibble = 0; *p && p < end; ++p, ++nibble)
    {
	register int		hex;

	if ('0' <= *p && *p <= '9')
	{
	    hex = *p - '0';
	}
	else if ('A' <= *p && *p <= 'F')
	{
	    hex = *p - 'A' + 10;
	}
	else if ('a' <= *p && *p <= 'f')
	{
	    hex = *p - 'a' + 10;
	}
	else
	{
	    return 1;
	}

	if (nibble & 01)
	{
	    /*
	     * Add low order (odd) nibble and move on to next byte
	     */
	    *out++ |= hex;
	}
	else
	{
	    /*
	     * Add high order (even) nibble and wait for low order nibble.
	     */
	    *out = hex << 4;
	}
    }

    /*
     * Check that input string length was correct.
     */
    if (*p || p != end)
    {
	return 1;
    }

    return 0;
}
