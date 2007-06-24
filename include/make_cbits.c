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
static char rcsid[] = "$Id: make_cbits.c,v 1.4.58.2 1997/09/21 23:42:09 viktor Exp $";

#include <stdio.h>

/*
 * Legal pairs of hex digits and bits in common
 */
static unsigned char table[15][2] = {
    {0x0F, 0},
    {0x07, 1}, {0x8F, 1},
    {0x03, 2}, {0x47, 2}, {0x8B, 2}, {0xCF, 2},
    {0x01, 3}, {0x23, 3}, {0x45, 3}, {0x67, 3},
    {0x89, 3}, {0xAB, 3}, {0xCD, 3}, {0xEF, 3}
};


int
main ()
{
    int i, j;
    signed char T[256];

    for (i=0; i<256; i++)
	T[i]=-1;

    for (j=0; j<15; j++) {
	T[table[j][0]] = table[j][1];
    }
    printf ("#ifndef _CBITS_H\n#define _CBITS_H\n");
    printf ("static signed char Common_Bits_Table[256] = {");
    for (i=0; i<256; i++) {
	if (i%16 == 0)
	    fputs("\n   ", stdout);
	printf (" %2d,", T[i]);
    }
    printf ("\n};\n#endif /* _CBITS_H */\n");

    if (fclose(stdout) == EOF)
	exit(1);
    exit(0);
}
