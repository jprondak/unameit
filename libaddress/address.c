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
static char rcsid[] = "$Id: address.c,v 1.1.2.4 1997/10/01 23:30:09 viktor Exp $";

#include <uconfig.h>
#include <common_bits.h>

#define UADDRESS_VERSION "1.0"

typedef enum {Bitwise_And, Bitwise_Or, Bitwise_Xor, Bitwise_Mask} Bitwise_Op;

/*
 * extern,  used also in libudb/inet.c
 */
int
Unameit_Common_Bits(char *as, char *bs)
{
    register int bit_count = 0;
    register int a = 0;
    register int b = 0;
    register int i;

    assert(as);
    assert(bs);

    for (bit_count = 0; *as; ++as, ++bs)
    {
	if (*as >= '0' && *as <= '9')
	{
	    a = *as - '0';
	}
	else if (*as >= 'a' && *as <= 'f')
	{
	    a = *as - 'a' + 10;
	}
	else
	{
	    return -1;
	}

	if (*bs >= '0' && *bs <= '9')
	{
	    b = *bs - '0';
	}
	else if (*bs >= 'a' && *bs <= 'f')
	{
	    b = *bs - 'a' + 10;
	}
	else
	{
	    return -1;
	}

	if (a != b)
	{
	    break;
	}
	bit_count+=4;
    }

    if (!*as)
    {
	return (!*bs) ? bit_count : -1;
    }

    i = a<<4 | b;
    
    if (Common_Bits_Table[i] == -1)
    {
	return -1;
    }

    bit_count += Common_Bits_Table[i];

    for(++as, ++bs; *as; ++as, ++bs)
    {
	if (*as != '0') {
	    return -1;
	}
	if (*bs != 'f') {
	    return -1;
	}
    }
    return (!*bs) ? bit_count : -1;
}


static int
Common_BitsCmd(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    if (argc != 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" address1 address2\"", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EUSAGE", argv[0], (char *)NULL);
	return TCL_ERROR;
    }

    sprintf(interp->result, "%d", Unameit_Common_Bits(argv[1], argv[2]));
    return TCL_OK;
}


static int
Mask_Bits(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    int	ones_count = 0;
    char *s;

    if (argc != 2)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" mask\"", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EUSAGE", argv[0], (char *)NULL);
	return TCL_ERROR;
    }

    for (s = argv[1]; *s == 'f'; s++)
    {
	ones_count += 4;
    }

    if (*s == 'e')
    {
	ones_count += 3;
	++s;
    }
    else if (*s == 'c')
    {
	ones_count += 2;
	++s;
    }
    else if (*s == '8')
    {
	++ones_count;
	++s;
    }

    while (*s == '0') ++s;

    if (*s)
    {
	/*
	 * Error, want end of string
	 */
	 ones_count = -1;
    }
    sprintf(interp->result, "%d", ones_count);
    return TCL_OK;
}


static int
Bitwise(ClientData opdata, Tcl_Interp *interp, int argc, char *argv[])
{
    Bitwise_Op  op = (Bitwise_Op)opdata;
    int		i = 0;
    int		c;
    int		i1;
    int		i2;
    int		len;
    char	*result;

    if (argc != 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" address1 address2\"", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EUSAGE", argv[0], (char *)NULL);
	return TCL_ERROR;
    }

    /*
     * Make sure both addresses are valid
     */
    i1 = Unameit_Common_Bits(argv[1], argv[1]);
    if (i1 < 0 || i1 & 07)
    {
	Tcl_AppendResult(interp, "Malformed address: \"", argv[1], "\"",
		(char *)NULL);
	return TCL_ERROR;
    }
    i2 = Unameit_Common_Bits(argv[2], argv[2]);
    if (i2 < 0 || i2 & 07)
    {
	Tcl_AppendResult(interp, "Malformed address: \"", argv[2], "\"",
		(char *)NULL);
	return TCL_ERROR;
    }
    if (i2 != i1)
    {
	Tcl_AppendResult(interp, "Address lengths differ: \"", argv[1],
			 "\" \"", argv[2], "\"", (char *)NULL);
	return TCL_ERROR;
    }

    /*
     * Get string length from bit count.
     */
    len = i1 >> 2;

    if ( (result = ckalloc(len+1)) == NULL)
    {
	panic("Out of memory");
    }
    result[len] = '\0';

    for (c = 0; c < len; ++c)
    {
	i1 = (argv[1][c] > '9') ? (argv[1][c] - 'a' + 10) : (argv[1][c] - '0');
	i2 = (argv[2][c] > '9') ? (argv[2][c] - 'a' + 10) : (argv[2][c] - '0');
	switch (op)
	{
	case Bitwise_And:
	    i = i1 & i2;
	    break;
	case Bitwise_Mask:
	    i = i1 & (~i2 & 0xf);
	    break;
	case Bitwise_Or:
	    i = i1 | i2;
	    break;
	case Bitwise_Xor:
	    i = i1 ^ i2;
	    break;
	}
	result[c] = (i > 9) ? ('a' + i - 10) : ('0' + i);
    }
    Tcl_SetResult(interp, result, TCL_DYNAMIC);
    return TCL_OK;
}


static int
Decrement(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    char	*cp;
    char	*result;

    if (argc != 2)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" address\"", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EUSAGE", argv[0], (char *)NULL);
	return TCL_ERROR;
    }

    if ((result = ckalloc(strlen(argv[1])+1)) == NULL)
    {
	panic("Out of memory");
    }
    (void) strcpy(result, argv[1]);

    for (cp = &result[strlen(result)-1]; cp >= result; --cp)
    {
	/*
	 * Decrement a byte and return unless carrying
	 */
	if (*cp == 'a')
	{
	    *cp = '9';
	    break;
	}
	if (*cp == '0')
	{
	    *cp = 'f';
	    continue;
	}
	--*cp;
	break;
    }
    Tcl_SetResult(interp, result, TCL_DYNAMIC);
    return TCL_OK;
}


static int
Increment(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    char	*cp;
    char	*result;

    if (argc != 2)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" address\"", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EUSAGE", argv[0], (char *)NULL);
	return TCL_ERROR;
    }

    if ((result = ckalloc(strlen(argv[1])+1)) == NULL)
    {
	panic("Out of memory");
    }
    (void) strcpy(result, argv[1]);

    for (cp = &result[strlen(result)-1]; cp >= result; --cp)
    {
	/*
	 * Increment a byte and return unless carrying
	 */
	if (*cp == '9')
	{
	    *cp = 'a';
	    break;
	}
	if (*cp == 'f')
	{
	    *cp = '0';
	    continue;
	}
	++*cp;
	break;
    }
    Tcl_SetResult(interp, result, TCL_DYNAMIC);
    return TCL_OK;
}


static int
Make_Mask(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    static char	left_bits[] = {'0', '8', 'c', 'e'};
    static char	right_bits[] = {'0', '1', '3', '7'};
    char	*result;
    char	*p;
    int		uniform_bytes;
    int		byte_count;
    int		i;
    int		len;
    int		bits;
    int		left;
    
    if (argc != 3)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"", argv[0],
		" length numbits\"", (char *)NULL);
	Tcl_SetErrorCode(interp, "UNAMEIT", "EUSAGE", argv[0], (char *)NULL);
	return TCL_ERROR;
    }

    if (Tcl_GetInt(interp, argv[1], &len) != TCL_OK)
    {
	return TCL_ERROR;
    }

    if (len < 0)
    {
	Tcl_AppendResult(interp, "Bad address length \"", argv[1], "\"",
	    (char *)NULL);
	return TCL_ERROR;
    }

    if (Tcl_GetInt(interp, argv[2], &bits) != TCL_OK)
    {
	return TCL_ERROR;
    }

    if (bits >= 0)
    {
	left = 1;
    }
    else
    {
	left = 0;
	bits = -bits;
    }

    if (bits > len * 8)
    {
	Tcl_AppendResult(interp, "Bad numbits > length \"", argv[2], "\"",
	    (char *)NULL);
	return TCL_ERROR;
    }

    uniform_bytes = bits/4;

    /*
     * Convert to len to nibble (hex digit or character) count
     */
    len *= 2;

    if ((result = ckalloc(len+1)) == NULL)
    {
	panic("Out of memory");
    }

    /*
     * Set uniform left bytes of string to f's or 0's as appropriate
     */
    byte_count = (left ? uniform_bytes : len - uniform_bytes - 1);

    for (i = 0, p = result; i < byte_count; ++i)
    {
	*p++ = (left ? 'f' : '0');
    }

    /*
     * If not all bits are set,  there is a boundary character
     */
    if (uniform_bytes != len)
    {
	/*
	 * Set boundary character
	 */
	*p++ = (left ? left_bits[bits & 0x3] : right_bits[bits & 0x3]);
    }

    /*
     * Set uniform right bytes of string to f's or 0's as appropriate
     */
    byte_count = (left ? len - uniform_bytes - 1 : uniform_bytes);
    for (i = 0; i < byte_count; ++i)
    {
	*p++ = (left ? '0' : 'f');
    }
    *p = '\0';

    Tcl_SetResult(interp, result, TCL_DYNAMIC);
    return TCL_OK;
}


int
Uaddress_Init(Tcl_Interp *interp)
{
    int	result;

    Tcl_CreateCommand(interp, "unameit_address_common_bits",
	Common_BitsCmd, 0, 0);
    Tcl_CreateCommand(interp, "unameit_address_and", Bitwise,
	(ClientData)Bitwise_And, 0);
    Tcl_CreateCommand(interp, "unameit_address_mask", Bitwise,
	(ClientData)Bitwise_Mask, 0);
    Tcl_CreateCommand(interp, "unameit_address_or", Bitwise,
	(ClientData)Bitwise_Or, 0);
    Tcl_CreateCommand(interp, "unameit_address_xor", Bitwise,
	(ClientData)Bitwise_Xor, 0);
    Tcl_CreateCommand(interp, "unameit_address_decrement", Decrement, 0, 0);
    Tcl_CreateCommand(interp, "unameit_address_increment", Increment, 0, 0);
    Tcl_CreateCommand(interp, "unameit_address_make_mask", Make_Mask, 0, 0);
    Tcl_CreateCommand(interp, "unameit_address_mask_bits", Mask_Bits, 0, 0);

    if ((result = Tcl_PkgProvide(interp, "Uaddress", UADDRESS_VERSION)) !=
	TCL_OK) {
	return result;
    }
    return TCL_OK;
}
