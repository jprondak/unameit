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
static char rcsid[] = "$Id: arith_types.c,v 1.3.58.3 1997/09/21 23:42:07 viktor Exp $";

#include <assert.h>
#include <stdio.h>
#include <stdarg.h>

void
panic(const char *fmt, ...)
{
    va_list arg;
    /*
     * Can't assert in Panic,  since assert calls panic!
     */
    va_start(arg, fmt);
    vfprintf(stderr, fmt, arg);
    va_end(arg);

    exit(1);
}

#define MEASURE_PROC(type) \
static int \
get_##type##_size() \
{ \
    unsigned type c = ~0; \
    int i = 0; \
 \
    do { \
	++i; \
	/* Turn off the low bit, in case right shift wraps. */ \
	c ^= 1; \
	/* Shift one to the right */ \
	c >>= 1; \
    } while (c); \
 \
    return i; \
}

MEASURE_PROC(char)
MEASURE_PROC(short)
MEASURE_PROC(int)
MEASURE_PROC(long)

#ifdef HAVE_LONG_LONG
static int
get_long_long_size()
{
    unsigned long long c = ~0;
    int i = 0;

    do {
	++i;
	c >>= 1;
    } while (c);

    return i;
}
#endif

int
main()
{
    int char_size = get_char_size();
    int short_size = get_short_size();
    int int_size = get_int_size();
    int long_size = get_long_size();
#ifdef HAVE_LONG_LONG
    int long_long_size = get_long_long_size();
#endif

    assert(char_size == 8);
    assert(short_size == 16 || int_size == 16);
    assert(int_size == 32 || long_size == 32);

    printf ("#ifndef _ARITH_TYPES_H\n");
    printf ("#define _ARITH_TYPES_H\n");
    printf ("#ifndef WIN32\n");
    printf ("#include <sys/types.h>\n");
    printf ("#include <netinet/in.h>\n");

    printf("typedef unsigned char unsigned%d;\n", char_size);
    printf("typedef signed char signed%d;\n", char_size);

    if (short_size > char_size)
    {
	printf("typedef unsigned short unsigned%d;\n", short_size);
	printf("typedef short signed%d;\n", short_size);
    }

    if (int_size > short_size)
    {
	printf("typedef unsigned int unsigned%d;\n", int_size);
	printf("typedef int signed%d;\n", int_size);
    }

    if (long_size > int_size)
    {
	printf("typedef unsigned long unsigned%d;\n", long_size);
	printf("typedef long signed%d;\n", long_size);
    }

#ifdef HAVE_LONG_LONG
    if (long_long_size > long_size)
    printf("typedef long long signed%d;\n", long_long_size),
    printf("typedef unsigned long long unsigned%d;\n", long_long_size);
#endif

    printf ("#define unsigned32_hton htonl\n");
    printf ("#define unsigned32_ntoh ntohl\n");
    printf ("#define unsigned16_hton htons\n");
    printf ("#define unsigned16_ntoh htons\n");

    printf ("#endif /* WIN32 */\n");
    printf ("#endif /* _ARITH_TYPES_H */\n");
    exit(0);
}
