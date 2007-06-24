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
static char rcsid[] = "$Id: license.c,v 1.7.12.3 1997/09/21 23:42:42 viktor Exp $";

#include <uconfig.h>
#include <error.h>
#include <time.h>
#include <md5.h>

#include "uuid.h"
#include "convert.h"
#include "misc.h"
#include "init.h"
#include "license.h"
#include "lookup.h"
#include "ether.h"
#include "errcode.h"

static char	expired_msg[] = "UName*It license expired\0\0""0123456789abcdef";
static char 	item_query[] = "select count(x) "
			       "from all named_item x "
			       "where x.\"deleted\" IS NULL";
static char 	host_query[] = "select count(x) "
			       "from all host x "
			       "where x.\"deleted\" IS NULL";
static char 	person_query[] = "select count(x) "
			       "from all person x "
			       "where x.\"deleted\" IS NULL";

static DB_INT32	license_start;
static DB_INT32	license_end;
static DB_INT32	license_host_units;
static DB_INT32	license_person_units;

static DB_INT32	current_item_units;	
static DB_INT32	current_host_units;	
static DB_INT32	current_person_units;	

static DB_INT32 delta_item_units;
static DB_INT32 delta_host_units;
static DB_INT32 delta_person_units;

typedef enum {Host_Units, Person_Units, License_Start, License_End} lparam_t;


static void
Decode_And_Cksum_Param(
    MD5_CTX *ctx,
    Tcl_Interp *interp,
    char *param,
    DB_INT32 *valPtr
)
{
    char *val = Tcl_GetVar2(interp, "unameitPriv", param, TCL_GLOBAL_ONLY);

    if (val == NULL ||
	(valPtr && Udb_String_To_Int32(interp, val, valPtr) != TCL_OK))
    {
	fputs(expired_msg, stderr);
	putc('\n', stderr);
	exit(1);
    }
    MD5Update(ctx, val, strlen(val)+1);
}


/*
 * Security through obscurity
 */
static DB_INT32
Udb_License_Param(Tcl_Interp *interp, lparam_t what)
{
    register int 	i;
    MD5_CTX		ctx;
    char		*lkey;
    ether_addr_t	ethernet_address;
    char		ether_addr_buf[13];

    union
    {
	unsigned char buf[16];
	struct
	{
	    unsigned32	i1;
	    unsigned32	i2;
	    unsigned32	i3;
	    unsigned32	i4;
	} iarr;
    } iun;

    MD5Init(&ctx);

    MD5Update(&ctx, expired_msg, sizeof(expired_msg));
    MD5Update(&ctx, item_query, sizeof(item_query));
    MD5Update(&ctx, host_query, sizeof(host_query));
    MD5Update(&ctx, person_query, sizeof(person_query));
    
    if (Uuid_Get_Macaddress(&ethernet_address) != TCL_OK)
    {
	fputs("Can't read MAC address\n", stderr);
	exit(1);
    }
    (void)sprintf(ether_addr_buf, "%02x%02x%02x%02x%02x%02x",
		  ethernet_address.addr[0], ethernet_address.addr[1],
		  ethernet_address.addr[2], ethernet_address.addr[3],
		  ethernet_address.addr[4], ethernet_address.addr[5]);
    MD5Update(&ctx, ether_addr_buf, strlen(ether_addr_buf)+1);

    Decode_And_Cksum_Param(&ctx, interp, "license_type",
			   NULL);
    Decode_And_Cksum_Param(&ctx, interp, "license_host_units",
			   &license_host_units);
    Decode_And_Cksum_Param(&ctx, interp, "license_person_units",
			   &license_person_units);
    Decode_And_Cksum_Param(&ctx, interp, "license_start",
			   &license_start);
    Decode_And_Cksum_Param(&ctx, interp, "license_end",
			   &license_end);
    MD5Final(&ctx);

    lkey = Tcl_GetVar2(interp, "unameitPriv", "license_key", TCL_GLOBAL_ONLY);

    if (lkey == NULL ||
	Udb_Radix16_Decode(lkey, sizeof(iun.buf), iun.buf) != 0)
    {
	fputs(expired_msg, stderr);
	putc('\n', stderr);
	exit(1);
    }

    /*
     * XOR out the checksum before converting to host byte order!
     */
    for (i = 0; i < 16; ++i)
    {
	iun.buf[i] ^= ctx.digest[i];
    }

    switch (what)
    {
    case Host_Units:
	return (DB_INT32) unsigned32_ntoh(iun.iarr.i1);
    case Person_Units:
	return (DB_INT32) unsigned32_ntoh(iun.iarr.i2);
    case License_Start:
	return (DB_INT32) unsigned32_ntoh(iun.iarr.i3);
    case License_End:
	return (DB_INT32) unsigned32_ntoh(iun.iarr.i4);
    default:
	return 0;
    }
}


/*
 * Return license usage
 */
int
Udb_License_Info(ClientData unused, Tcl_Interp *interp, int argc, char *argv[])
{
    if (argc != 1)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], (char *)NULL);
    }
    (void) sprintf(interp->result, "%ld %ld",
		   (long)current_host_units, (long)current_person_units);
    return TCL_OK;
}


static DB_INT32
Get_Count(const char *query)
{
    DB_SESSION		*sess_id;
    DB_QUERY_RESULT	*cursor;
    DB_VALUE		value;
    DB_INT32		result;
    DB_ERROR		rows;

    rows = Udb_Run_Query(query, &sess_id, &cursor, 0, NULL, 0);

    if (rows < 0)
    {
	return 0;
    }

    check(rows == 1 && db_query_column_count(cursor) == 1);

    check(db_query_first_tuple(cursor) == DB_CURSOR_SUCCESS);
    check(db_query_get_tuple_value(cursor, 0, &value) == NOERROR);
    check(!DB_IS_NULL(&value));
    check(DB_VALUE_DOMAIN_TYPE(&value) == DB_TYPE_INTEGER);
    result = DB_GET_INTEGER(&value);
    db_query_end(cursor);
    db_close_session(sess_id);
    return result;
}

/*
 * Verify the license token and initialize current usage.
 */
void
Udb_Init_License(Tcl_Interp *interp)
{
    unsigned32		license_start;
    unsigned32		license_end;
    time_t		now;

    /* 
     * Check to see if license expired. As a side effect, the routine
     * Udb_License_Param sets the static variables
     * license_start, license_end, license_host_units and
     * license_person_units. These are the values from the .license file.
     * It also computes the checksum and xors it with the begin/end dates and
     * host/person counts to get back the original begin/end date and
     * host/person count values.
     *
     * If the customer perturbs the .license, the md5 checksum will come out
     * random and when we xor the values, we will get mismatched host/person
     * units or begin/end dates. These bogus values are returned by
     * Udb_License_Param().
     */

    license_start = Udb_License_Param(interp, License_Start);
    license_end = Udb_License_Param(interp, License_End);

    if (license_start != license_start ||
	license_end != license_end)
	
    {
	fputs(expired_msg, stderr);
	putc('\n', stderr);
	exit(1);
    }

    now = time(NULL);

    if ((license_end != -1 && now > license_end) ||
	(license_start != -1 && now < license_start))
    {
	fputs(expired_msg, stderr);
	putc('\n', stderr);
	exit(1);
    }


    if (license_host_units != Udb_License_Param(interp, Host_Units) ||
	license_person_units != Udb_License_Param(interp, Person_Units))
    {
	fputs(expired_msg, stderr);
	putc('\n', stderr);
	exit(1);
    }

    if (_Udb_Get_Class("named_item") == NULL)
    {
	fputs("Database not initialized\n", stderr);
	exit(1);
    }

    current_host_units = current_person_units = current_item_units =
	Get_Count(item_query);

    if (current_item_units > 0)
    {
	current_host_units = Get_Count(host_query);
	current_person_units = Get_Count(person_query);
    }

    delta_host_units = 0;
    delta_person_units = 0;
    delta_item_units = 0;
}


void
Udb_Adjust_License_Count(DB_OBJECT *class, DB_INT32 count)
{
    if (!Udb_Is_Data_Class(class))
    {
	return;
    }

    delta_item_units += count;

    if (Udb_Is_Host_Class(class))
    {
	delta_host_units += count;
    }
    else if (Udb_Is_Person_Class(class))
    {
	delta_person_units += count;
    }
}


void
Udb_Update_License_Limits(void)
{
    current_item_units += delta_item_units;
    current_host_units += delta_host_units;
    current_person_units += delta_person_units;

    delta_item_units = delta_host_units = delta_person_units = 0;
}


void
Udb_Rollback_License_Limits(void)
{
    delta_item_units = delta_host_units = delta_person_units = 0;
}


int
Udb_Over_License_Count(void)
{
    return
	(current_host_units + delta_host_units > license_host_units ||
	 current_person_units + delta_person_units > license_person_units ||
	 current_item_units + delta_item_units >
	     10 * (license_host_units + license_person_units));
}
