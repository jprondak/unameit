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
static char rcsid[] = "$Id: inet.c,v 1.25.20.16 1997/10/11 00:55:12 viktor Exp $";

#include <dbi.h>

#include <uconfig.h>
#include <arith_types.h>
#include <radix.h>
#include <uuid.h>

#include "inet.h"
#include "misc.h"
#include "lookup.h"
#include "errcode.h"
#include "transaction.h"

typedef struct
    {
	unsigned int	bits;
	DB_OBJECT	*block;
    }
    InetBlock;

typedef struct
    {
	unsigned int	bits;
	unsigned char	*octets;
    }
    InetPrefix;

typedef enum
    {
	NoneBest, ZeroBest, OtherBest
    }
    InetBest;

typedef enum
    {
	InetNet,
	InetNode,
	InetRange
    }
    InetObjType;

typedef struct
    {
	InetObjType	objType;
	union
	    {
		struct
		    {
			const char	*address;
		    }
		    node;
		struct
		    {
			const char	*start;
			int		bits;
			const char	*mask;
			const char	*type;
		    }
		    net;
		struct
		    {
			const char	*start;
			const char	*end;
			const char	*type;
			DB_COLLECTION	*devices;
		    }
		    range;
	    } 
	    objInfo;
    }
    InetInfo;


/*
 * Subblock sizes are on the next 4 bit boundary
 * after parent network or block.  NSHIFT *MUST* divide into 8!
 */
#define NSHIFT		4

#define SUB_BITS(b) (NSHIFT - ((b)->bits & (NSHIFT - 1)))
#define SUB_MASK(b) ((1 << SUB_BITS(b)) - 1)
#define SUB_SHIFT(b) (8 - ((b)->bits & 7) - SUB_BITS(b))
#define SUB_INDEX(p, b) \
	(((p)->octets[(b)->bits >> 3] >> SUB_SHIFT(b)) & SUB_MASK(b))

/*
 * Maximum time stamp value applies to occupied node slots or
 * net/range blocks all of whose subnodes are full.
 *
 * Mininum time stamp value applies to net/range blocks having no
 * nodes (full or empty) under them.
 */
#define INET_MAX_STAMP		0x7fffffff
#define INET_MIN_STAMP		0

#define INET_SUPER		"super"
#define INET_BITS		"bits"
#define INET_STAMP		"stamp"
#define INET_BLOCK_NETS		"nets"
#define INET_SLOT_NODES		"nodes"
#define INET_BLOCK_SUBS		"subs"
#define INET_BLOCK_RANGES	"ranges"

#define INET_BLOCK		"inet/block"
#define INET_NET_RANGES		"net_ranges"
#define INET_NET_NODES		"net_nodes"
#define INET_NET_ANODE		"net_anode"
#define INET_NET_ASUBNET	"net_asubnet"
#define INET_NET_SUBNETS	"net_subnets"

/*
 * Macros for accessing attributes of generic blocks and slots.
 */
#define BITS(block) 		Inet_Int(block, INET_BITS)
#define SUPER(block) 		Inet_Object(block, INET_SUPER)
#define SUBS(block) 		Inet_Sequence(block, INET_BLOCK_SUBS)
#define ITEMS(block, type)	Inet_Sequence(block, Inet_List_Name(type))
#define SET_SUPER(b, s)		Inet_Set_Object(b, INET_SUPER, s)

/*
 * Macros for access to information in block of net about objects in net.
 */
#define ITEM_BLOCK(i)		Inet_Object(i, INET_BLOCK)
#define SET_ITEM_BLOCK(i, b)	Inet_Set_Object(i, INET_BLOCK, b)
#define NET_RANGES(b)		Inet_Sequence(b, INET_NET_RANGES)
#define SET_NODECOUNT(o, n, i)	Inet_Update_Block_Count(o, n, i,\
				    INET_NET_NODES, INET_NET_ANODE)
#define SET_NETCOUNT(o, n, i)	Inet_Update_Block_Count(o, n, i,\
				    INET_NET_SUBNETS, INET_NET_ASUBNET)

/*
 * Macros for accessing user visible attributes
 */
#define NODE_ADDRESS(n)		Inet_String(n, inet_node_address_attribute)

#define NET_START(n)		Inet_String(n, inet_net_start_attribute)
#define NET_BITS(n)		Inet_Int(n, inet_net_bits_attribute)
#define NET_MASK(n)		Inet_String(n, inet_net_mask_attribute)
#define NET_TYPE(n)		Inet_String(n, inet_net_type_attribute)
#define NET_END(n)		Inet_String(n, inet_net_end_attribute)

#define RANGE_DEVICES(r)	Inet_Set(r, inet_range_devices_attribute)
#define RANGE_START(r)		Inet_String(r, inet_range_start_attribute)
#define RANGE_TYPE(r)		Inet_String(r, inet_range_type_attribute)
#define RANGE_END(r)		Inet_String(r, inet_range_end_attribute)

#define NETOF(item, type)	Inet_Object(item, Inet_Netof_Aname(type))
#define SET_NETOF(item, t, n) 	Inet_Set_Object(item, Inet_Netof_Aname(t), n)

/*
 * Address family parameters
 */
static const char	*inet_fname;
static int		inet_bits;
static int		inet_octets;

/*
 * Classes and special objects
 */
static DB_OBJECT	*inet_block_class;
static DB_OBJECT	*inet_slot_class;
static DB_OBJECT	*inet_node_class;
static DB_OBJECT	*inet_net_class;
static DB_OBJECT	*inet_range_class;
static DB_OBJECT	*inet_root_block;
static DB_OBJECT	*inet_universe;

/*
 * User visible Attribute names
 */
static char		*inet_node_netof_attribute;
static char 		*inet_node_address_attribute;

static char 		*inet_net_netof_attribute;
static char 		*inet_net_start_attribute;
static char 		*inet_net_bits_attribute;
static char 		*inet_net_end_attribute;
static char 		*inet_net_mask_attribute;
static char 		*inet_net_type_attribute;

static char 		*inet_range_netof_attribute;
static char 		*inet_range_start_attribute;
static char 		*inet_range_end_attribute;
static char 		*inet_range_type_attribute;
static char 		*inet_range_devices_attribute;

/*
 * Integrity hash tables
 */
static Tcl_HashTable	itemCheckTable;
static Tcl_HashTable	blockCheckTable;

/*
 * Macros for metadata access
 */
#define INET_GET_OCTETS(interp, fname)\
     (Inet_Metadata(interp, fname, "octets"))

#define INET_GET_ATTR(interp, fname, key)\
    (inet_##key##_attribute = Inet_Metadata(interp, fname, #key))

#define INET_GET_CLASS(interp, fname, key)\
    do {\
	char *cname = Inet_Metadata(interp, fname, #key);\
	inet_##key = cname ? Udb_Get_Class(cname) : NULL;\
    } while (0)


static char *
Inet_Metadata(Tcl_Interp *interp, const char *fname, const char *key)
{
    Tcl_DString dstr;
    char *result;

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, (char *)fname, -1);
    Tcl_DStringAppend(&dstr, ".", 1);
    Tcl_DStringAppend(&dstr, (char *)key, -1);
    result = Tcl_GetVar2(interp, "UNAMEIT_INET_INFO",
			 Tcl_DStringValue(&dstr), TCL_GLOBAL_ONLY);
    Tcl_DStringFree(&dstr);
    return result;
}


static int
Inet_Set_Family(
    Tcl_Interp *interp,
    const char *fname,
    InetObjType type,
    DB_OBJECT *object
)
{
    Tcl_DString fcname;
    const char	*oString;

    assert(fname);

    oString = INET_GET_OCTETS(interp, fname);

    if (oString == NULL)
    {
	return Udb_Error(interp, "EINETNOFAMILY", fname, (char *)NULL);
    }

    check(Tcl_GetInt(interp, (char *)oString, &inet_octets) == TCL_OK);
    assert(inet_octets > 0);
    inet_bits = inet_octets << 3;

    /*
     * Construct class name for net blocks.
     */
    Tcl_DStringInit(&fcname);
    Tcl_DStringAppend(&fcname, "family/", -1);
    Tcl_DStringAppend(&fcname, (char *)fname, -1);
    Tcl_DStringAppend(&fcname, "/block", -1);
    inet_block_class = Udb_Get_Class(Tcl_DStringValue(&fcname));
    Tcl_DStringFree(&fcname);

    /*
     * Construct class name for node slots.
     */
    Tcl_DStringInit(&fcname);
    Tcl_DStringAppend(&fcname, "family/", -1);
    Tcl_DStringAppend(&fcname, (char *)fname, -1);
    Tcl_DStringAppend(&fcname, "/slot", -1);
    inet_slot_class = Udb_Get_Class(Tcl_DStringValue(&fcname));
    Tcl_DStringFree(&fcname);

    INET_GET_CLASS(interp, fname, node_class);
    INET_GET_CLASS(interp, fname, net_class);
    INET_GET_CLASS(interp, fname, range_class);

    check(
	  inet_node_class != NULL &&
	  inet_net_class != NULL &&

    	  INET_GET_ATTR(interp, fname, node_netof) != NULL &&
    	  INET_GET_ATTR(interp, fname, node_address) != NULL &&

	  INET_GET_ATTR(interp, fname, net_netof) != NULL &&
	  INET_GET_ATTR(interp, fname, net_start) != NULL &&
	  INET_GET_ATTR(interp, fname, net_bits) != NULL &&
    	  INET_GET_ATTR(interp, fname, net_end) != NULL &&
    	  INET_GET_ATTR(interp, fname, net_mask) != NULL &&
    	  INET_GET_ATTR(interp, fname, net_type) != NULL
	  );

    if (inet_range_class != NULL)
    {
	check(
	    INET_GET_ATTR(interp, fname, range_netof) != NULL &&
	    INET_GET_ATTR(interp, fname, range_start) != NULL &&
	    INET_GET_ATTR(interp, fname, range_end) != NULL &&
	    INET_GET_ATTR(interp, fname, range_type) != NULL &&
	    INET_GET_ATTR(interp, fname, range_devices) != NULL
	);
    }
    
    if (object)
    {
        DB_OBJECT *object_class = db_get_class(object);

	switch (type)
	{
	case InetNode:
	    if (!Udb_ISA(object_class, inet_node_class))
	    {
		return Udb_Error(interp, "EINETNOTNODE",
				 Udb_Get_Uuid(object, NULL), fname, (char *)0);
	    }
	    break;

	case InetNet:
	    if (!Udb_ISA(object_class, inet_net_class))
	    {
		return Udb_Error(interp, "EINETNOTNODE",
				 Udb_Get_Uuid(object, NULL), fname, (char *)0);
	    }
	    break;

	case InetRange:
	    check(inet_range_class != NULL);
	    if (!Udb_ISA(object_class, inet_range_class))
	    {
		return Udb_Error(interp, "EINETNOTNODE",
				 Udb_Get_Uuid(object, NULL), fname, (char *)0);
	    }
	    break;
	}
    }

    inet_root_block = Udb_Get_Root(inet_block_class);
    inet_universe = Udb_Get_Root(inet_net_class);

    inet_fname = fname;
    return TCL_OK;
}

/*
 * Attribute access functions
 */
static int
Inet_Int(DB_OBJECT *object, const char *aname)
{
    DB_VALUE v;
    Udb_Get_Value(object, aname, DB_TYPE_INTEGER, &v);
    check(!DB_IS_NULL(&v));
    return DB_GET_INT(&v);
}


static void
Inet_Set_Int(DB_OBJECT *o, const char *aname, DB_INT32 i)
{
    DB_VALUE v;
    DB_MAKE_INTEGER(&v, i);
    check(db_put(o, aname, &v) == NOERROR);
}


static DB_OBJECT *
Inet_Object(DB_OBJECT *object, const char *aname)
{
    DB_VALUE v;
    Udb_Get_Value(object, aname, DB_TYPE_OBJECT, &v);
    return DB_GET_OBJECT(&v);
}


static void
Inet_Set_Object(DB_OBJECT *o, const char *aname, DB_OBJECT *to)
{
    DB_VALUE v;
    DB_MAKE_OBJECT(&v, to);
    check(db_put(o, aname, &v) == NOERROR);
}


static const char *
Inet_String(DB_OBJECT *object, const char *aname)
{
    DB_VALUE v;
    Udb_Get_Value(object, aname, DB_TYPE_STRING, &v);
    return DB_GET_STRING(&v);
}


static DB_COLLECTION *
Inet_Sequence(DB_OBJECT *object, const char *aname)
{
    DB_VALUE v;
    Udb_Get_Value(object, aname, DB_TYPE_LIST, &v);
    check(!DB_IS_NULL(&v));
    return DB_GET_COLLECTION(&v);
}


static DB_COLLECTION *
Inet_Set(DB_OBJECT *object, const char *aname)
{
    DB_VALUE		v;
    Udb_Get_Value(object, aname, DB_TYPE_SET, &v);
    check(!DB_IS_NULL(&v));
    return DB_GET_COLLECTION(&v);
}


static DB_OBJECT *
Inet_Nth(DB_COLLECTION *seq, DB_INT32 index)
{
    DB_VALUE	v;
    assert(seq && index >= 0);
    if (index >= db_col_size(seq))
    {
	return NULL;
    }
    check (db_col_get(seq, index, &v) == NOERROR);
    if (DB_IS_NULL(&v))
    {
	return NULL;
    }
    check(DB_VALUE_DOMAIN_TYPE(&v) == DB_TYPE_OBJECT);
    return DB_GET_OBJECT(&v);
}


static const char *
Inet_List_Name(InetObjType type)
{
    switch (type)
    {
    case InetNode:
	return INET_SLOT_NODES;
    case InetNet:
	return INET_BLOCK_NETS;
    case InetRange:
	return INET_BLOCK_RANGES;
    default:
	return NULL;
    }
}


static const char *
Inet_Netof_Aname(InetObjType type)
{
    switch (type)
    {
    case InetNode:
	return inet_node_netof_attribute;
    case InetNet:
	return inet_net_netof_attribute;
    case InetRange:
	return inet_range_netof_attribute;
    default:
	return NULL;
    }
}

/*
 * Commit time integrity code
 */
static void
Inet_Check(Tcl_HashTable *hPtr, DB_OBJECT *o, InetObjType type)
{
    int			new;
    Tcl_HashTable	*familyTablePtr;
    Tcl_HashEntry	*ePtr;

    ePtr = Tcl_CreateHashEntry(hPtr, (char *)inet_fname, &new);

    if (new)
    {
	familyTablePtr = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
	Tcl_InitHashTable(familyTablePtr, TCL_ONE_WORD_KEYS);
	Tcl_SetHashValue(ePtr, (ClientData)familyTablePtr);
    }
    else
    {
	familyTablePtr = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }

    ePtr = Tcl_CreateHashEntry(familyTablePtr, (ClientData)o, &new);
    Tcl_SetHashValue(ePtr, (ClientData)type);
}


static void
Inet_Uncheck(Tcl_HashTable *hPtr, DB_OBJECT *object)
{
    Tcl_HashSearch	familySearch;
    Tcl_HashEntry	*ePtr;

    for (ePtr = Tcl_FirstHashEntry(hPtr, &familySearch);
	 ePtr;
	 ePtr = Tcl_NextHashEntry(&familySearch))
    {
	Tcl_HashTable	*familyTable;

	familyTable = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	assert(familyTable != NULL);

	ePtr = Tcl_FindHashEntry(familyTable, (ClientData)object);

	if (ePtr != NULL)
	{
	    Tcl_DeleteHashEntry(ePtr);
	}
    }
}


int
Udb_Inet_Check_Integrity(Tcl_Interp *interp)
{
    int			ok = TCL_OK;
    Tcl_HashEntry	*ePtr;
    Tcl_HashSearch	familySearch;

    /*
     * First check for duplicate nodes or networks this is dirt cheap
     * and avoids the more complex item checks below if duplicates exist.
     */
    for (ePtr = Tcl_FirstHashEntry(&blockCheckTable, &familySearch);
	 ePtr && ok == TCL_OK;
	 ePtr = Tcl_NextHashEntry(&familySearch))
    {
	const char		*fname;
	Tcl_HashTable		*familyTable;
	Tcl_HashSearch		blockSearch;
	
	fname = Tcl_GetHashKey(&blockCheckTable, ePtr);
	check(Inet_Set_Family(interp, fname, InetNode, NULL) == TCL_OK);
	    
	familyTable = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	assert(familyTable != NULL);

	for (ePtr = Tcl_FirstHashEntry(familyTable, &blockSearch);
	     ePtr;
	     ePtr = Tcl_NextHashEntry(&blockSearch))
	{
	    DB_OBJECT		*block;
	    InetObjType		type;
	    DB_COLLECTION	*items;
	    DB_OBJECT		*item1;
	    DB_OBJECT		*item2;
	    char		uuid1[UDB_UUID_SIZE];
	    char		uuid2[UDB_UUID_SIZE];

	    block = (DB_OBJECT *)Tcl_GetHashKey(familyTable, ePtr);
	    type = (InetObjType)Tcl_GetHashValue(ePtr);

	    items = ITEMS(block, type);
	    check((item1 = Inet_Nth(items, 0)) != NULL);
	    check((item2 = Inet_Nth(items, 1)) != NULL);
	    (void) Udb_Get_Uuid(item1, uuid1);
	    (void) Udb_Get_Uuid(item2, uuid2);
	    db_col_free(items);

	    switch (type)
	    {
	    case InetNode:
		return Udb_Error(interp, "EINETDUPNODE", uuid1, uuid2,
				 inet_node_address_attribute, (char *)NULL);
	    case InetNet:
		return Udb_Error(interp, "EINETDUPNET", uuid1, uuid2,
				 inet_net_start_attribute,
				 inet_net_bits_attribute, (char *)NULL);
	    default:
		assert(0);
		return TCL_ERROR;
	    }
	}
    }

    /*
     * Check updated networks, ranges and nodes
     */
    for (ePtr = Tcl_FirstHashEntry(&itemCheckTable, &familySearch);
	 ePtr && ok == TCL_OK;
	 ePtr = Tcl_NextHashEntry(&familySearch))
    {
	const char		*fname;
	Tcl_HashTable	*familyTable;
	Tcl_HashSearch	itemSearch;
	int			check_nodes = 0;
	int			check_nets = 0;
	int			check_ranges = 0;
	Tcl_DString		nodeCmd;
	Tcl_DString		netCmd;
	Tcl_DString		rangeCmd;

	fname = Tcl_GetHashKey(&itemCheckTable, ePtr);
	check(Inet_Set_Family(interp, fname, InetNode, NULL) == TCL_OK);
	    
	familyTable = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	assert(familyTable != NULL);

	for (ePtr = Tcl_FirstHashEntry(familyTable, &itemSearch);
	     ePtr;
	     ePtr = Tcl_NextHashEntry(&itemSearch))
	{
	    DB_OBJECT	*item;

#define	CHECK_ITEM(type, item)\
	    {\
		Tcl_DString *dPtr = &##type##Cmd;\
		if (!check_##type##s)\
		{\
		    check_##type##s = 1;\
		    Tcl_DStringInit(dPtr);\
		    Tcl_DStringAppendElement(dPtr,\
					     "unameit_inet_check_"\
					     #type "s");\
		    Tcl_DStringAppendElement(dPtr, (char *)fname);\
		    Tcl_DStringStartSublist(dPtr);\
		}\
		Tcl_DStringAppendElement(dPtr, Udb_Get_Uuid(item, NULL));\
	    }

	    item = (DB_OBJECT *)Tcl_GetHashKey(familyTable, ePtr);

	    switch ((InetObjType)Tcl_GetHashValue(ePtr))
	    {
	    case InetNode:
		CHECK_ITEM(node, item);
		break;

	    case InetNet:
		CHECK_ITEM(net, item);
		break;

	    case InetRange:
		CHECK_ITEM(range, item);
		break;
	    }
	}

#define	CHECK_TYPE(type)\
	if (check_##type##s)\
	{\
	    Tcl_DString *dPtr = &##type##Cmd;\
	    if (ok == TCL_OK)\
	    {\
		Tcl_DStringEndSublist(dPtr);\
		ok = Tcl_Eval(interp, Tcl_DStringValue(dPtr));\
	    }\
	    Tcl_DStringFree(dPtr);\
	}

	CHECK_TYPE(net);
	CHECK_TYPE(range);
	CHECK_TYPE(node);
    }
    return ok;
}


void
Udb_Inet_Reset_Checks(void)
{
    /*
     * Clear stale data from tables
     */
    Udb_Free_Static_Table_Table(&itemCheckTable);
    Udb_Free_Static_Table_Table(&blockCheckTable);

    /*
     * Initialize tables for next transaction
     */
    Tcl_InitHashTable(&itemCheckTable, TCL_STRING_KEYS);
    Tcl_InitHashTable(&blockCheckTable, TCL_STRING_KEYS);
}

/*
 * Tree management functions
 */
static DB_INT32
Inet_Stamp(DB_OBJECT *block)
{
    DB_INT32 stamp;
    stamp = Inet_Int(block, INET_STAMP);
    check(stamp >= INET_MIN_STAMP && stamp <= INET_MAX_STAMP);
    return stamp;
}


static void
Inet_Set_Stamp(DB_OBJECT *block, DB_INT32 stamp)
{
    assert(stamp >= INET_MIN_STAMP && stamp <= INET_MAX_STAMP);
    Inet_Set_Int(block, INET_STAMP, stamp);
}


static void
Inet_Put(DB_COLLECTION *seq, DB_INT32 index, DB_OBJECT *o)
{
    DB_VALUE	v;
    DB_MAKE_OBJECT(&v, o);
    check(db_col_put(seq, index, &v) == NOERROR);
}


static DB_OBJECT *
Inet_First_Item(DB_OBJECT *block, InetObjType type)
{
    DB_COLLECTION	*items;
    DB_OBJECT		*item;
    items = ITEMS(block, type);
    item = Inet_Nth(items, 0);
    db_col_free(items);
    return item;
}


static void
Inet_Add(DB_OBJECT *block, InetObjType type, DB_OBJECT *item)
{
    DB_VALUE		v;
    DB_COLLECTION	*items;

    assert(item != NULL);
    items = ITEMS(block, type);

    DB_MAKE_OBJECT(&v, item);
    check(db_col_add(items, &v) == NOERROR);
    db_col_free(items);

    switch (type)
    {
    case InetNet:
    case InetNode:
	if (db_col_size(items) == 2)
	{
	    /*
	     * Block has a duplicate node or network,  arrange for
	     * commit time check
	     */
	    Inet_Check(&blockCheckTable, block, type);
	}
	break;

    default:
	/*
	 * Ranges are checked for overlaps elsewhere
	 */
	break;
    }
}


static DB_OBJECT *
Inet_Drop(DB_OBJECT *block, InetObjType type, DB_OBJECT *item)
{
    DB_VALUE		v;
    DB_COLLECTION	*items;
    DB_INT32		index;

    assert(item != NULL);
    items = ITEMS(block, type);

    DB_MAKE_OBJECT(&v, item);
    check(db_col_find(items, &v, 0, &index) == NOERROR);
    check(db_col_drop_element(items, index) == NOERROR);

    switch (type)
    {
    case InetNet:
    case InetNode:
	if (db_col_size(items) == 1)
	{
	    /*
	     * Block had duplicate entries,  but no longer does,
	     * cancel commit time check
	     */
	    Inet_Uncheck(&blockCheckTable, block);
	}
	break;

    default:
	/*
	 * Ranges are checked for overlaps elsewhere
	 */
	break;
    }

    /*
     * First element if any is preferred "object" of block
     */
    if (db_col_size(items) > 0)
    {
	Udb_Get_Collection_Value(items, 0, DB_TYPE_OBJECT, &v);
	item = DB_GET_OBJECT(&v);
    }
    else
    {
	item = NULL;
    }
    db_col_free(items);
    return item;
}


static void
Inet_Move_Range(DB_OBJECT *old, DB_OBJECT *new, DB_OBJECT *range)
{
    DB_VALUE		v;
    DB_COLLECTION	*list;
    int			i;
    const char		*start;
    int			cmp;
    DB_OBJECT		*o;

    assert(range != NULL);

    if (old == new) return;

    if (old != NULL)
    {
	list = NET_RANGES(old);
	DB_MAKE_OBJECT(&v, range);
	check(db_col_find(list, &v, 0, &i) == NOERROR);
	check(db_col_drop_element(list, i) == NOERROR);
	db_col_free(list);
    }

    if (new != NULL)
    {
	list = NET_RANGES(new);
	start = RANGE_START(range);
	for (cmp = 1, i = 0; (cmp > 0) && (o = Inet_Nth(list, i)); ++i)
	{
	    const char	*s  = RANGE_START(o);
	    cmp = strcmp(start, s);
	    db_string_free((char *)s);
	}
	db_string_free((char *)start);
	DB_MAKE_OBJECT(&v, range);
	check(db_col_insert(list, i, &v) == NOERROR);
	db_col_free(list);
    }
}


static void
Inet_Update_Block_Count(
    DB_OBJECT *old,
    DB_OBJECT *new,
    DB_OBJECT *item,
    const char *countAname,
    const char *itemAname
)
{
    DB_INT32 count;

    if (old == new) return;

    if (old != NULL)
    {
	Inet_Set_Int(old, countAname, count = Inet_Int(old, countAname) - 1);
	if (count == 0) Inet_Set_Object(old, itemAname, NULL);
    }

    if (new != NULL)
    {
	Inet_Set_Int(new, countAname, count = Inet_Int(new, countAname) + 1);
	if (count == 1) Inet_Set_Object(new, itemAname, item);
    }
}


static void
Inet_Set_Netof(
    DB_OBJECT *item,
    InetObjType type,
    DB_OBJECT *net
)
{
    DB_OBJECT	*oldBlock;
    DB_OBJECT	*newBlock;

    oldBlock = (oldBlock = NETOF(item, type)) ? ITEM_BLOCK(oldBlock) : NULL;
    newBlock = net ? ITEM_BLOCK(net) : NULL;

    switch (type)
    {
    case InetNode:
	SET_NODECOUNT(oldBlock, newBlock, item);
	break;

    case InetNet:
	SET_NETCOUNT(oldBlock, newBlock, item);
	break;

    case InetRange:
	Inet_Move_Range(oldBlock, newBlock, item);
	break;
    }

    if (net != NULL)
    {
	/*
	 * Arrange for commit time check.
	 */
	Inet_Check(&itemCheckTable, item, type);
    }
    else
    {
	/*
	 * Object no longer in network hierarchy,  drop any pending checks
	 */
	Inet_Uncheck(&itemCheckTable, item);
    }
    SET_NETOF(item, type, net);
}


static int
Inet_Reparent_Items(
    DB_OBJECT *block,
    InetObjType type,
    DB_OBJECT *net
)
{
    DB_COLLECTION	*items;
    DB_OBJECT		*item;
    DB_INT32		i;

    items = ITEMS(block, type);
    for (i = 0; (item = Inet_Nth(items, i)) != NULL; ++i)
    {
	Inet_Set_Netof(item, type, net);
    }
    db_col_free(items);
    return i;
}


/*
 * Reparents items in block,  and sub-blocks not crossing subnet boundaries.
 * Returns 0 if block is no longer in use 1 otherwise.
 */
static int
Inet_Reparent(
    InetBlock *blockPtr,
    DB_OBJECT *net,
    int skipNets
)
{
    int			i;
    DB_COLLECTION	*subs;
    int			inUse = 0;
    int			count;

    if (!skipNets)
    {
	if (blockPtr->bits == inet_bits)
	{
	    /*
	     * Block corresponds to a set of nodes reparent them.
	     * If block was empty, kept around to delay address
	     * reallocation,  no longer needed when parent network is
	     * changing (or being deleted).
	     */
	    return Inet_Reparent_Items(blockPtr->block, InetNode, net) != 0;
	}

	if (Inet_Reparent_Items(blockPtr->block, InetNet, net) > 0)
	{
	    /*
	     * Block corresponds to one or more subnets, we are done
	     */
	    return 1;
	}
    }

    /*
     * Reparent any ranges contained in this block
     */
    inUse |= Inet_Reparent_Items(blockPtr->block, InetRange, net);

    subs = SUBS(blockPtr->block);

    for (i = 0; i < db_col_size(subs); i += count)
    {
	DB_OBJECT	*o;
	InetBlock	sub;

	if ((o = Inet_Nth(subs, i)) == NULL)
	{
	    count = 1;
	    continue;
	}

	sub.block = o;
	sub.bits = BITS(o);
	count = 1 << (blockPtr->bits + SUB_BITS(blockPtr) - sub.bits);

	/*
	 * Reparent sub-block
	 */
	if (Inet_Reparent(&sub, net, 0) == 0)
	{
	    int	j;
	    /*
	     * Sub-block not in use:
	     * put it on free list and replace references with NULLs
	     */
	    Udb_Append_Free_List(sub.bits < inet_bits ?
				    inet_block_class : inet_slot_class,
				 dbt_edit_object(sub.block), NULL);
	    for (j = 0; j < count; ++j)
	    {
		Inet_Put(subs, i + j, NULL);
	    }
	}
	else
	{
	    inUse |= 1;
	}
    }

    if (inUse == 0)
    {
	/*
	 * Trim subs to an empty sequence
	 * Note: loop works even if "i" is unsigned.
	 */
	for (i = db_col_size(subs); i-- > 0; )
	{
	    check(db_col_drop_element(subs, i) == NOERROR);
	}
    }

    db_col_free(subs);
    return inUse;
}


/*
 * Locate block in network hierarchy given address and number of prefix bits.
 * Modifies contents of blockPtr.  Returns the network containing the block.
 */ 
static DB_OBJECT *
Inet_Find(InetPrefix *prefixPtr, InetBlock *blockPtr)
{
    DB_OBJECT		*net;

    blockPtr->bits = 0;
    blockPtr->block = inet_root_block;
    net = inet_universe;

    if (blockPtr->block != NULL)
    {
	while (blockPtr->bits < prefixPtr->bits)
	{
	    unsigned int	i;
	    DB_COLLECTION	*subs;
	    DB_OBJECT		*o;

	    i = SUB_INDEX(prefixPtr, blockPtr);
	    subs = SUBS(blockPtr->block);
	    o = Inet_Nth(subs, i);
	    db_col_free(subs);

	    if (o == NULL || (i = BITS(o)) > prefixPtr->bits)
	    {
		break;
	    }

	    blockPtr->block = o;

	    if ((blockPtr->bits = i) < inet_bits &&
		(o = Inet_First_Item(blockPtr->block, InetNet)) != NULL)
	    {
		/*
		 * Block starts a new network: record net object.
		 */
		net = o;
	    }
	}

	check(blockPtr->block != NULL);
	check(net != NULL);
    }
    else
    {
	assert(net == NULL);
    }
    return net;
}


static int
Inet_Node_Prefix(
    InetPrefix *prefixPtr,
    Tcl_Interp *interp,
    const char *uuid,
    const char *aname,
    const char *address
)
{
    assert(prefixPtr);
    assert(interp);
    assert(address);
    assert(uuid);

    /*
     * Universe net should already exist
     */
    if (inet_universe == NULL)
    {
	return Udb_Error(interp, "EINETNOROOT", uuid, inet_fname, (char *)0);
    }

    prefixPtr->bits = inet_bits;
    prefixPtr->octets = (unsigned8 *) ckalloc(inet_octets);

    /*
     * Make sure start address is syntactically correct of the right length
     */
    if (Udb_Radix16_Decode(address, inet_octets, prefixPtr->octets) != 0)
    {
	ckfree((char *)prefixPtr->octets);
	return Udb_Error(interp, "EINETNOTADDR", uuid,
			 aname, address, (char *)NULL);
    }
    return TCL_OK;
}


static int
Inet_Net_Prefix(
    InetPrefix *prefixPtr,
    Tcl_Interp *interp,
    const char *uuid,
    const char *start,
    unsigned int bits
)
{
    assert(prefixPtr);
    assert(interp);
    assert(uuid);
    assert(start);

    assert(bits < inet_bits);

    /*
     * Universe net should allow all possible addresses.
     */
    if (inet_universe == NULL && bits != 0)
    {
	return Udb_Error(interp, "EINETNOROOT", uuid, inet_fname, (char *)0);
    }

    prefixPtr->bits = bits;
    prefixPtr->octets = (unsigned8 *) ckalloc(inet_octets);

    /*
     * Make sure start address is syntactically correct of the right length
     */
    if (Udb_Radix16_Decode(start, inet_octets, prefixPtr->octets) != 0)
    {
	ckfree((char *)prefixPtr->octets);
	return Udb_Error(interp, "EINETNOTADDR", uuid,
			 inet_net_start_attribute, start, (char *)NULL);
    }

    /*
     * Make sure all bits after prefix are off
     */
    while (bits < inet_bits)
    {
	unsigned8 octet = prefixPtr->octets[bits >> 3];
	int shift = bits & 7;

	if ((octet << shift) & 0xff)
	{
	    char bitsString[32];
	    (void) sprintf(bitsString, "%d", bits);

	    ckfree((void *)prefixPtr->octets);

	    return Udb_Error(interp, "EINETBITS", uuid,
			     inet_net_bits_attribute, bitsString,
			     inet_net_start_attribute, start, (char *)0);
	}
	bits += 8 - shift;
    }

    return TCL_OK;
}


static int
Inet_Range_Prefix(
    InetPrefix *prefixPtr,
    Tcl_Interp *interp,
    const char *uuid,
    const char *start,
    const char *end
)
{
    InetPrefix	endPrefix;
    int		i;
    int 	bits;

    assert(prefixPtr);
    assert(interp);
    assert(start);
    assert(end);
    assert(uuid);

    if (strcmp(start, end) > 0)
    {
	/*
	 * Start is greater than end,  error
	 */
	return Udb_Error(interp, "EINETBOUNDS", uuid,
			 inet_range_start_attribute, start,
			 inet_range_end_attribute, end, (char *)NULL);
    }

    if (Inet_Node_Prefix(prefixPtr, interp, uuid,
			 inet_range_start_attribute, start) != TCL_OK)
    {
	return TCL_ERROR;
    }

    if (Inet_Node_Prefix(&endPrefix, interp, uuid,
			 inet_range_end_attribute, end) != TCL_OK)
    {
	ckfree((char *)prefixPtr->octets);
	return TCL_ERROR;
    }

    for (bits = i = 0; i < inet_octets; ++i)
    {
	/*
	 * Number of zero bits on left of integers from 0 to 15,
	 */
	static int left_zero[] = { 4, 3, 2, 2, 1, 1, 1, 1,
				   0, 0, 0, 0, 0, 0, 0, 0 };
	int	xor;
	
	xor  = prefixPtr->octets[i]; 
	xor ^= endPrefix.octets[i];

	if (xor == 0)
	{
	    bits += 8;
	}
	else
	{
	    bits += left_zero[xor >> 4] + ((xor >> 4) ? 0 : left_zero[xor]);
	    break;
	}
    }

    /*
     * Ranges should never go into node slots, so coerce bits < inet_bits.
     */
    prefixPtr->bits = (bits < inet_bits) ? bits : (bits - 1);
    return TCL_OK;
}


static void
Inet_Insert_Root(InetPrefix *prefixPtr, DB_OBJECT *universe)
{
    DB_OTMPL		*templ;
    DB_VALUE		v;
    DB_COLLECTION	*list;

    assert(inet_universe == NULL && inet_root_block == NULL);
    assert(prefixPtr->bits == 0);
    assert(universe != NULL);

    /*
     * The free list is empty when we are creating the universe.
     */
    check(templ = dbt_create_object(inet_block_class));

    DB_MAKE_INTEGER(&v, 0);
    check(dbt_put(templ, INET_BITS, &v) == NOERROR);
    check(dbt_put(templ, INET_NET_NODES, &v) == NOERROR);
    check(dbt_put(templ, INET_NET_SUBNETS, &v) == NOERROR);

    DB_MAKE_OBJECT(&v, (DB_OBJECT *)NULL);
    check(dbt_put(templ, INET_NET_ANODE, &v) == NOERROR);
    check(dbt_put(templ, INET_NET_ASUBNET, &v) == NOERROR);

    check((list = db_col_create(DB_TYPE_LIST, 0, NULL)) != NULL);

    DB_MAKE_OBJECT(&v, inet_universe = universe);
    check(db_col_add(list, &v) == NOERROR);

    DB_MAKE_COLLECTION(&v, list);
    check(dbt_put(templ, INET_BLOCK_NETS, &v) == NOERROR);
    db_col_free(list);

    inet_root_block = Udb_Finish_Object(NULL, templ, FALSE);

    /*
     * Link universe net to root block
     */
    SET_ITEM_BLOCK(universe, inet_root_block);

    Udb_Set_Root(inet_block_class, inet_root_block);
    Udb_Set_Root(inet_net_class, universe);
}


static void
Inet_New_Block(
    InetPrefix *prefixPtr,
    InetBlock *blockPtr
)
{
    unsigned int	index;
    unsigned int	count;
    int			i;
    DB_VALUE		v;
    DB_OTMPL		*templ;
    DB_COLLECTION	*pSubs;
    DB_COLLECTION	*subs = NULL;

    assert(prefixPtr != NULL && blockPtr != NULL);
    assert(prefixPtr->bits > 0);
    assert(prefixPtr->bits > blockPtr->bits);
    assert(blockPtr->block != NULL);
    assert(inet_universe != NULL && inet_root_block != NULL);

    /*
     * Compute insertion index of new block in
     * old block's sub-block list (before we change blockPtr->bits below!)
     */
    index = SUB_INDEX(prefixPtr, blockPtr);

    /*
     * Set prefix bit count of new block
     */
    if ((blockPtr->bits += SUB_BITS(blockPtr)) > prefixPtr->bits)
    {
	count = 1 << (blockPtr->bits - prefixPtr->bits);
	blockPtr->bits = prefixPtr->bits;
    }
    else 
    {
	count = 1;
    }

    if (blockPtr->bits == inet_bits)
    {
	/*
	 * Create new slot template.  Bits is a shared attribute of
	 * node slots == inet_bits so we do not set it.
	 */
	check(templ = Udb_Edit_Free_Object(inet_slot_class));

	/*
	 * The slot is being filled by a new node,  set stamp to max value
	 */
	DB_MAKE_INTEGER(&v, INET_MAX_STAMP);
	check(dbt_put(templ, INET_STAMP, &v) == NOERROR);
    }
    else
    {
	/*
	 * Create new block template
	 */
	check(templ = Udb_Edit_Free_Object(inet_block_class));

	DB_MAKE_INTEGER(&v, blockPtr->bits);
	check(dbt_put(templ, INET_BITS, &v) == NOERROR);

	DB_MAKE_INTEGER(&v, 0);
	check(dbt_put(templ, INET_NET_NODES, &v) == NOERROR);
	check(dbt_put(templ, INET_NET_SUBNETS, &v) == NOERROR);

	DB_MAKE_OBJECT(&v, (DB_OBJECT *)NULL);
	check(dbt_put(templ, INET_NET_ANODE, &v) == NOERROR);
	check(dbt_put(templ, INET_NET_ASUBNET, &v) == NOERROR);
    }

    /*
     * Set super-block link
     */
    DB_MAKE_OBJECT(&v, blockPtr->block);
    check(dbt_put(templ, INET_SUPER, &v) == NOERROR);

    /*
     * Get sub-block list of old block
     */
    pSubs = SUBS(blockPtr->block);

    if (blockPtr->bits < inet_bits)
    {
	/*
	 * Copy subsumed sub-blocks from sub-block list of parent block
	 */
	for (i = index; i < index + count; ++i)
	{
	    DB_OBJECT *o = Inet_Nth(pSubs, i);

	    if (o == NULL)
		continue;

	    /*
	     * If count is 1,  we fit inside an existing sub-block,
	     * and should have used it instead.
	     */
	    assert(count > 1);

	    if (subs == NULL)
	    {
		subs = db_col_create(DB_TYPE_LIST, 0, NULL);
		check(subs != NULL);
	    }

	    /*
	     * Our sub-block list is simply a repetion of *count*
	     * consecutive sub-blocks from the parent block.
	     * Adjust the index and copy.
	     */
	    Inet_Put(subs, i - index, o);
	}

	if (subs != NULL)
	{
	    /*
	     * Apply new subblock list to template.
	     */
	    DB_MAKE_COLLECTION(&v, subs);
	    check(dbt_put(templ, INET_BLOCK_SUBS, &v) == NOERROR);
	}
    }

    /*
     * Finish new block template
     */
    check(blockPtr->block = Udb_Finish_Object(NULL, templ, FALSE));

    /*
     * Reparent subsumed blocks under new block
     * Replace subsumed sub-blocks with references to new block
     */
    for (i = 0; i < count; ++i)
    {
	DB_OBJECT *o;

	if (subs != NULL && (o = Inet_Nth(subs, i)) != NULL)
	{
	    SET_SUPER(o, blockPtr->block);
	}
	Inet_Put(pSubs, i + index, blockPtr->block);
    }

    db_col_free(pSubs);

    if (subs != NULL)
    {
	db_col_free(subs);
    }
}


/*
 * Find insertion block,  and create sub-blocks as necessary
 * to accomodate the new prefix.
 * Returns the containing network,  and modifies *blockPtr.
 */
static void
Inet_Insert(
    InetPrefix *prefixPtr,
    InetObjType type,
    DB_OBJECT *o
)
{
    InetBlock	block;
    DB_OBJECT 	*net = Inet_Find(prefixPtr, &block);

    while (block.bits < prefixPtr->bits)
    {
	Inet_New_Block(prefixPtr, &block);
    }
    assert(prefixPtr->bits == block.bits);

    switch (type)
    {
    case InetNode:
	break;

    case InetNet:
	if (block.block == NULL)
	{
	    Inet_Insert_Root(prefixPtr, o);
	    return;
	}

	/*
	 * Must call before reparent, so net block is already set
	 * when nodes or subnets are added to it.
	 */
	SET_ITEM_BLOCK(o, block.block);

	if (Inet_First_Item(block.block, InetNet) == NULL)
	{
	    /*
	     * We are the new network for this block
	     */
	    Inet_Reparent(&block, o, 1);
	}
	else
	{
	    /*
	     * Get parent network of current network
	     */
	    net =  NETOF(net, InetNet);
	}
	break;

    case InetRange:
	SET_ITEM_BLOCK(o, block.block);
	break;
    }

    Inet_Set_Netof(o, type, net);
    Inet_Add(block.block, type, o);
}


/*
 * Recycle block if no sub-blocks, or not on a natural boundary
 */
static void
Inet_GC_Block(InetPrefix *prefixPtr, InetBlock *blockPtr)
{
    int			index;
    int			i;
    InetBlock		parent;
    DB_COLLECTION	*subs;
    DB_COLLECTION 	*pSubs;

    subs = SUBS(blockPtr->block);

    parent.block = SUPER(blockPtr->block);
    parent.bits = BITS(parent.block);

    index = SUB_INDEX(prefixPtr, &parent);

    if (parent.bits + SUB_BITS(&parent) > blockPtr->bits)
    {
	/*
	 * Block can be absorbed into parent block
	 */
	DB_OBJECT	*last;
	int		count;

	count = 1 << SUB_BITS(blockPtr);

	pSubs = SUBS(parent.block);

	/*
	 * Relink sub-blocks to parent block
	 */
	for (last = NULL, i = 0; i < count; ++i)
	{
	    DB_OBJECT *o = Inet_Nth(subs, i);

	    Inet_Put(pSubs, i + index, o);
	    Inet_Put(subs, i, NULL);

	    if (o != NULL && o != last)
	    {
		SET_SUPER(last = o, parent.block);
	    }
	}
    }
    else
    {
	/*
	 * Block can go if it has no sub-blocks
	 */
	if (db_col_cardinality(subs) > 0)
	{
	    db_col_free(subs);
	    return;
	}

	pSubs = SUBS(parent.block);
	Inet_Put(pSubs, index, NULL);
    }

    /*
     * Trim sub-block sequence to empty list
     * Note: loop works even if "i" is unsigned.
     */
    for (i = db_col_size(subs); i-- > 0; )
    {
	check(db_col_drop_element(subs, i) == NOERROR);
    }

    /*
     * Free set handles
     */
    db_col_free(pSubs);
    db_col_free(subs);

    /*
     * Put block on free list
     */
    Udb_Append_Free_List(inet_block_class,
			 dbt_edit_object(blockPtr->block), NULL);

    if (Inet_First_Item(parent.block, InetNet) != NULL ||
	Inet_First_Item(parent.block, InetRange) != NULL)
    {
	return;
    }

    /*
     * GC parent block
     */
    Inet_GC_Block(prefixPtr, &parent);
}


static void
Inet_Delete(
    InetPrefix *prefixPtr,
    InetObjType type,
    DB_OBJECT *o
)
{
    InetBlock	block;
    DB_OBJECT	*net;
    DB_OBJECT	*newNet;

    /*
     * Find the block for the prefix
     */
    net = Inet_Find(prefixPtr, &block);

    /*
     * Check for expected depth.  Block should be owned by some network.
     */
    check(block.bits == prefixPtr->bits);
    check(net != NULL);

    switch (type)
    {
    case InetNode:
	if (Inet_Drop(block.block, InetNode, o) == NULL)
	{
	    /*
	     * Granularity of minutes will suffice for > 3000 years
	     * avoiding 2038 problem,  once time_t is fixed in the OS.
	     */
	    Inet_Set_Stamp(block.block, time(NULL) / 60);
	}
	break;

    case InetRange:
	if (Inet_Drop(block.block, InetRange, o) == NULL &&
	    Inet_First_Item(block.block, InetNet) == NULL)
	{
	    /*
	     * Recycle block if no sub-blocks, or not on a natural boundary
	     */
	    Inet_GC_Block(prefixPtr, &block);
	}
	SET_ITEM_BLOCK(o, NULL);
	break;

    case InetNet:
	/*
	 * Make sure we are not deleting the universe net
	 * (Should be protected!)
	 */
	assert(o != inet_universe);

	newNet = Inet_Drop(block.block, type, o);

	if (o != net)
	{
	    /*
	     * No real change.
	     */
	    assert(newNet == net);
	}
	else if (newNet == NULL)
	{
	    /*
	     * Reparent subnets under our former parent.
	     */
	    if (Inet_Reparent(&block, NETOF(o, InetNet), 1) == 0)
	    {
		/*
		 * The block is not use,  recycle block and recursively
		 * any consequentially empty blocks.
		 */
		Inet_GC_Block(prefixPtr, &block);
	    }
	}
	else
	{
	    /*
	     * Block was under this network,  but is now under a new network
	     */
	    (void) Inet_Reparent(&block, newNet, 1);
	}
	/*
	 * Must call after reparent, so net block is still set
	 * when nodes or subnets are deleted from it.
	 */
	SET_ITEM_BLOCK(o, NULL);
	break;
    }

    /*
     * Clear the objects network pointer, but not before
     * it used in Inet_Reparent above!
     */
    Inet_Set_Netof(o, type, NULL);
}


/*
 * Transforms (in place!) block prefix to prefix for ith sub-block.
 * Must work top down or bottom up,  so it is important not to touch
 * bits on either side of the bits we are setting.
 */
static void
Inet_Sub_Prefix(
    InetPrefix *prefixPtr,
    InetBlock *blockPtr,
    int bitIncr,
    int index
)
{
    register int shift = SUB_BITS(blockPtr) - bitIncr;
    register int mask  = ((1 << bitIncr) - 1) << shift;
    register unsigned8 *octet = &prefixPtr->octets[blockPtr->bits >> 3];
    
    assert(bitIncr > 0 && shift >= 0);
    assert(index == (index & mask));

    *octet &= ~(mask << SUB_SHIFT(blockPtr));		
    *octet |= index << SUB_SHIFT(blockPtr);		
}

/*
 * Insertion/Deletion code
 */
static int
Inet_Info_Prefix(
    InetPrefix *prefixPtr,
    Tcl_Interp *interp,
    const char *uuid,
    InetInfo *info
)
{
    switch (info->objType)
    {
    case InetNode:
	return Inet_Node_Prefix(prefixPtr, interp, uuid,
				inet_node_address_attribute,
				info->objInfo.node.address);
    case InetNet:
	return Inet_Net_Prefix(prefixPtr, interp, uuid,
			       info->objInfo.net.start,
			       info->objInfo.net.bits);
    case InetRange:
	return Inet_Range_Prefix(prefixPtr, interp, uuid,
				 info->objInfo.range.start,
				 info->objInfo.range.end);
    default:
	assert(0);
	/* NOTREACHED */
	return TCL_ERROR;
    }
}


static void
Inet_Free_Info(InetInfo *info)
{
    assert(info);

    switch (info->objType)
    {
    case InetNode:
	if (info->objInfo.node.address)
	    db_string_free((char *)info->objInfo.node.address);
	break;

    case InetNet:
	if (info->objInfo.net.start)
	    db_string_free((char *)info->objInfo.net.start);
	if (info->objInfo.net.mask)
	    db_string_free((char *)info->objInfo.net.mask);
	if (info->objInfo.net.type)
	    db_string_free((char *)info->objInfo.net.type);
	break;

    case InetRange:
	if (info->objInfo.range.start)
	    db_string_free((char *)info->objInfo.range.start);
	if (info->objInfo.range.end)
	    db_string_free((char *)info->objInfo.range.end);
	if (info->objInfo.range.type)
	    db_string_free((char *)info->objInfo.range.type);
	if (info->objInfo.range.devices)
	    db_col_free(info->objInfo.range.devices);
	break;

    default:
	panic("%s:%d Invalid InetObjType: %d", rcsid, __LINE__, info->objType);
	break;
    }
    ckfree((char *)info);
}


static int
Inet_Insert_Object(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object,
    InetInfo *info
)
{
    InetPrefix	prefix;

    if (Inet_Info_Prefix(&prefix, interp, uuid, info) != TCL_OK)
    {
	return TCL_ERROR;
    }

    Inet_Insert(&prefix, info->objType, object);

    ckfree((char *)prefix.octets);
    return TCL_OK;
}


static int
Inet_Delete_Object(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object,
    InetInfo *info
)
{
    InetPrefix	prefix;

    if (Inet_Info_Prefix(&prefix, interp, uuid, info) != TCL_OK)
    {
	return TCL_ERROR;
    }

    Inet_Delete(&prefix, info->objType, object);

    ckfree((char *)prefix.octets);
    return TCL_OK;
}


static void
Inet_Populate_Table(
    Tcl_Interp *interp,
    Tcl_HashTable *table,
    const char *fname,
    DB_OBJECT *object,
    InetObjType type
)
{
    int			new;
    Tcl_HashEntry	*ePtr;
    InetInfo		*info = NULL;
    const char		*addr = NULL;

    check(Inet_Set_Family(interp, fname, type, object) == TCL_OK);

    switch (type)
    {
    case InetNode:
	if ((addr = NODE_ADDRESS(object)) != NULL)
	{
	    info = (InetInfo *)ckalloc(sizeof(InetInfo));
	    info->objInfo.node.address = addr;
	}
	break;

    case InetNet:
	if ((addr = NET_START(object)) != NULL)
	{
	    info = (InetInfo *)ckalloc(sizeof(InetInfo));
	    info->objInfo.net.start = addr;
	    info->objInfo.net.bits  = NET_BITS(object);
	    info->objInfo.net.type  = NET_TYPE(object);
	    info->objInfo.net.mask  = NET_MASK(object);
	}
	break;

    case InetRange:
	if ((addr = RANGE_START(object)) != NULL)
	{
	    DB_COLLECTION	*devices;
	    info = (InetInfo *)ckalloc(sizeof(InetInfo));
	    info->objInfo.range.start = addr;
	    info->objInfo.range.end   = RANGE_END(object);
	    info->objInfo.range.type  = RANGE_TYPE(object);
	    /*
	     * Sets have to copied since they are returned by reference
	     */
	    info->objInfo.range.devices  =
		(db_col_size(devices = RANGE_DEVICES(object)) > 0) ?
		    db_col_copy(devices) : NULL;
	    db_col_free(devices);
	}
	break;
    }

    if (info)
    {
	info->objType = type;
	ePtr = Tcl_CreateHashEntry(table, (char *)fname, &new);
	assert(new);
	Tcl_SetHashValue(ePtr, (ClientData)info);
    }
}


void
Udb_Inet_Free_Table(Tcl_HashTable *table)
{
    Udb_Free_Dynamic_Table(table, (Tcl_FreeProc *)Inet_Free_Info, FALSE);
}


void
Udb_Inet_Populate_Tables(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    Tcl_HashTable *table
)
{
    DB_OBJECT		*class;
    char		*cname;
    char		*f;

    check(class = db_get_class(object));
    cname = Udb_Get_Class_Name(class);

    f = Tcl_GetVar2(interp, "UNAMEIT_NODE_OF", cname, TCL_GLOBAL_ONLY);

    if (f != NULL)
    {
	int		famArgc;
	char		**famArgv;
	int		i;
	
	check(Tcl_SplitList(NULL, f, &famArgc, &famArgv) == TCL_OK);

	/*
	 * Loop over each address family of which this class models a node.
	 */
	for (i = 0; i < famArgc; ++i)
	{
	    Inet_Populate_Table(interp, table, famArgv[i], object, InetNode);
	}

	ckfree((char *)famArgv);

	/*
	 * Nodes cannot also be networks or ranges of any address family.
	 */
	return;
    }

    /*
     * Can only be a network object for one address family
     */
    f = Tcl_GetVar2(interp, "UNAMEIT_NET_OF", cname, TCL_GLOBAL_ONLY);

    if (f != NULL)
    {
	Inet_Populate_Table(interp, table, f, object, InetNet);

	/*
	 * Networks cannot also be ranges of any address family.
	 */
	return;
    }

    /*
     * Can only be a range object for one address family
     */
    f = Tcl_GetVar2(interp, "UNAMEIT_RANGE_OF", cname, TCL_GLOBAL_ONLY);

    if (f != NULL)
    {
	Inet_Populate_Table(interp, table, f, object, InetRange);
    }
}


int
Udb_Inet_Update(
    Tcl_Interp *interp,
    const char *uuid,
    DB_OBJECT *object,
    Tcl_HashTable *old_table,
    Tcl_HashTable *new_table
)
{
    Tcl_HashEntry	*oldPtr;
    Tcl_HashEntry	*newPtr;
    Tcl_HashSearch	search;
    char		*fname;
    InetInfo		*oldInfo;
    InetInfo		*newInfo;
    
    assert(object);

    if (old_table)
    {
	/*
	 * Each key in hash table is an address family name
	 * For each family,  check new and old addresses.
	 */
	for (oldPtr = Tcl_FirstHashEntry(old_table, &search); oldPtr;
	     oldPtr = Tcl_NextHashEntry(&search))
	{
	    int reinsert = FALSE;

	    fname = Tcl_GetHashKey(old_table, oldPtr);
	    oldInfo = (InetInfo *)Tcl_GetHashValue(oldPtr);

	    check(Inet_Set_Family(interp, fname,
				  oldInfo->objType, object) == TCL_OK);

	    newPtr = new_table ? Tcl_FindHashEntry(new_table, fname) : NULL;

	    if (newPtr == NULL)
	    {
		check(Inet_Delete_Object(interp, uuid,
					 object, oldInfo) == TCL_OK);
		continue;
	    }

	    newInfo = Tcl_GetHashValue(newPtr);
	    assert(newInfo->objType == oldInfo->objType);

	    switch (oldInfo->objType)
	    {
	    case InetNode:
	        if (!Equal(oldInfo->objInfo.node.address,
			   newInfo->objInfo.node.address))
	        {
		    reinsert = TRUE;
		}
	        break;

	    case InetNet:
	        if (oldInfo->objInfo.net.bits != newInfo->objInfo.net.bits ||
		    !Equal(oldInfo->objInfo.net.start,
			   newInfo->objInfo.net.start))
	        {
		    reinsert = TRUE;
		}
		else if (!Equal(oldInfo->objInfo.net.mask,
				newInfo->objInfo.net.mask) ||
			 !Equal(oldInfo->objInfo.net.type,
				newInfo->objInfo.net.type))
		{
		    Inet_Check(&itemCheckTable, object, InetNet);
		}
		break;

	    case InetRange:
	        if (!Equal(oldInfo->objInfo.range.start,
			   newInfo->objInfo.range.start) ||
		    !Equal(oldInfo->objInfo.range.end,
			   newInfo->objInfo.range.end))
	        {
		    reinsert = TRUE;
		}
		else if (!Equal(oldInfo->objInfo.range.type,
				newInfo->objInfo.range.type) ||
			 !Udb_Col_Equal(oldInfo->objInfo.range.devices,
					newInfo->objInfo.range.devices))
		{
		    Inet_Check(&itemCheckTable, object, InetRange);
		}
		break;

	    default:
	          panic("%s:%d Invalid InetObjType: %d", rcsid, __LINE__,
			oldInfo->objType);
		  break;
	    }


	    if (reinsert == TRUE)
	    {
		check(Inet_Delete_Object(interp, uuid,
					 object, oldInfo) == TCL_OK);

	        if (Inet_Insert_Object(interp, uuid,
				       object, newInfo) != TCL_OK)
		{
		    return TCL_ERROR;
		}
	    }

	    /*
	     * Drop entry from new table, so that at end of loop over
	     * old data,  the new table contains only new entries.
	     */ 
	    Inet_Free_Info(newInfo);
	    Tcl_DeleteHashEntry(newPtr);
	}
    }
    if (new_table)
    {
	for (newPtr = Tcl_FirstHashEntry(new_table, &search); newPtr;
	     newPtr = Tcl_NextHashEntry(&search))
	{
	    fname = Tcl_GetHashKey(new_table, newPtr);
	    newInfo = (InetInfo *)Tcl_GetHashValue(newPtr);

	    check(Inet_Set_Family(interp, fname,
				  newInfo->objType, object) == TCL_OK);

	    if (Inet_Insert_Object(interp, uuid,
				   object, newInfo) != TCL_OK)
	    {
		return TCL_ERROR;
	    }
	}
    }
    return TCL_OK;
}

/*
 * Tcl Interface Commands
 */
static int
Inet_NetofCmd(
    ClientData type,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    InetInfo	info;
    char	parentUuid[UDB_UUID_SIZE];
    char	*uuid;			/* UUID of object to locate */
    InetPrefix	prefix;			/* Prefix structure */
    InetBlock	block;			/* Insertion block */
    DB_OBJECT	*net;
    int		bits;
    int		bound;

    switch (info.objType = (InetObjType)type)
    {
    case InetNode:
	if (argc != 4)
	{
	    return Udb_Error(interp, "EUSAGE", argv[0],
			     "family", "uuid", "address", (char *)NULL);
	}
	break;

    case InetRange:
	if (argc != 5)
	{
	    return Udb_Error(interp, "EUSAGE", argv[0],
			     "family", "uuid", "start", "end", (char *)NULL);
	}
	break;

    case InetNet:
	if (argc != 5)
	{
	    return Udb_Error(interp, "EUSAGE", argv[0],
			     "family", "uuid", "start", "bits", (char *)NULL);
	}
	break;
    }

    /*
     * We are not validating any node,  so can use any type
     * for 3rd argument of Inet_Set_Family below.
     */
    if (Inet_Set_Family(interp, argv[1], InetNode, NULL) != TCL_OK)
    {
	return TCL_ERROR;
    }

    /*
     * uuid of new net object
     */
    uuid = argv[2];
    if (strlen(uuid) && !Uuid_Valid(uuid))
    {
	Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
	return TCL_ERROR;
    }

    switch (info.objType)
    {
    case InetNode:
	info.objInfo.node.address = argv[3];
	break;

    case InetRange:
	info.objInfo.range.start = argv[3];
	info.objInfo.range.end = argv[4];
	break;

    case InetNet:
	if (Tcl_GetInt(interp, argv[4], &bits) != TCL_OK)
	{
	    return TCL_ERROR;
	}
	if (bits < (bound = 0) || bits > (bound = inet_bits - 1))
	{
	    char limit[32];
	    char *code = bits < bound ? "ETOOSMALL" : "ETOOBIG";
	    (void) sprintf(limit, "%d", bound);
	    return Udb_Error(interp, code, uuid,
			     inet_net_bits_attribute, argv[4], limit,
			     (char *)NULL);
	}
	info.objInfo.net.start = argv[3];
	info.objInfo.net.bits = bits;
	break;
    }


    if (Inet_Info_Prefix(&prefix, interp, uuid, &info) != TCL_OK)
    {
	return TCL_ERROR;
    }

    /*
     * Search for insertion block
     */
    net = Inet_Find(&prefix, &block);

    if ((InetObjType)type != InetNet)
    {
	Tcl_SetResult(interp, Udb_Get_Uuid(net, NULL), TCL_VOLATILE);
    }
    else
    {
	/*
	 * If insertion block directly corresponds to a network
	 * get its parent.
	 */
	if (net != NULL &&
	    block.bits == prefix.bits &&
	    Inet_First_Item(block.block, InetNet) != NULL)
	{
	    net = NETOF(net, InetNet);
	}

	/*
	 * If parent is same as new item, it will be deleted before
	 * reinsertion.  We need to find the network for the prefix
	 * that would result with the network deleted.  But since
	 * there may (temporarily) be other networks with the same
	 * prefix this is harder than might first appear.
	 */
	if (net != NULL && Equal(uuid, Udb_Get_Uuid(net, parentUuid)))
	{
	    DB_COLLECTION *nets;
	    DB_OBJECT	  *next;

	    /*
	     * Get current bit prefix.
	     */
	    bits = NET_BITS(net);

	    /*
	     * Walk up to currently occupied block
	     */
	    while (block.bits > bits)
	    {
		block.block = SUPER(block.block);
		block.bits = BITS(block.block);
	    }
	    check(block.bits == bits);

	    /*
	     * Get list of nets with current prefix
	     */
	    nets = ITEMS(block.block, InetNet);

	    /*
	     * Inet_Find should have returned the first one
	     */
	    assert(net == Inet_Nth(nets, 0));

	    /*
	     * When this net shifts down the second one along if any
	     * may become its parent.  Otherwise use the current parent.
	     */
	    if ((next = Inet_Nth(nets, 1)) != NULL)
	    {
		net = next;
	    }
	    else
	    {
		net = NETOF(net, InetNet);
	    }
	    db_col_free(nets);
	}

	if (net != NULL)
	{
	    Tcl_SetResult(interp, Udb_Get_Uuid(net, NULL), TCL_VOLATILE);
	}
    }

    ckfree(prefix.octets);
    return TCL_OK;
}


static InetBest
Inet_Auto_Net(
    InetPrefix *prefixPtr,
    InetBlock *blockPtr,
    InetBest best,
    int wantBits,
    int baseBits,
    int blockLeftBits
)
{
    InetBest		result = NoneBest;
    DB_OBJECT		*last = NULL;
    InetBlock		subBlock;
    int			count;
    int			subcount;
    int			sbits;
    int			i;
    int			cmpBits;
    int			leftBits;
    DB_COLLECTION	*subs;

    /*
     * Make sure we have sensible input data
     */
    assert(prefixPtr);
    assert(blockPtr);

    /*
     * Each block is divided into 2**SUB_BITS(blockPtr) sub-blocks
     */
    sbits = SUB_BITS(blockPtr);
    count = 1 << sbits;

    if (blockPtr->bits + sbits > wantBits)
    {
	/*
	 * Need subcount consecutive empty sub-blocks to make an empty block
	 * with the desired prefix.  Will not recurse,  since any sub-block
	 * is either too small or occupied.
	 */
	subcount = 1 << (blockPtr->bits + sbits - wantBits);

	/*
	 * Each group of subcount blocks adds "sbits" bits to block bit prefix.
	 */
	sbits = (wantBits - blockPtr->bits);
    }
    else
    {
	/*
	 * Each sub-block is big enough to allocate the desired prefix
	 */
	subcount = 1;
    }

    subs = SUBS(blockPtr->block);

    for (i = 0; i < count; i += subcount)
    {
	DB_OBJECT	*o = NULL;
	int	 	j;

	/*
	 * Check for subcount consecutive empty blocks
	 */
	for (j = 0; j < subcount; ++j)
	{
	    if ((o = Inet_Nth(subs, i + j)) != NULL)
	    {
		break;
	    }
	}

	if (i)
	{
	    /*
	     * Zero bits on right of integers from 0 to (2**NSHIFT - 1)
	     */
	    static int	right_zero[] = { 4, 0, 1, 0, 2, 0, 1, 0,
					 3, 0, 1, 0, 2, 0, 1, 0 };
	    cmpBits = leftBits =
		blockPtr->bits + SUB_BITS(blockPtr) - right_zero[i];
	}	
	else
	{
	    if ((cmpBits = leftBits = blockLeftBits) == baseBits)
	    {
		cmpBits = blockPtr->bits + sbits;
	    }
	}

	if (o == NULL)
	{
	    /*
	     * All empty we have a vacant block, use it if better bit count
	     * Or same block count and block 0 was Best
	     */
	    if (cmpBits < prefixPtr->bits || best == NoneBest ||
		(best == ZeroBest && cmpBits == prefixPtr->bits))
	    {
		result = best = (leftBits == baseBits) ? ZeroBest : OtherBest;

		prefixPtr->bits = cmpBits;
		Inet_Sub_Prefix(prefixPtr, blockPtr, sbits, i);
	    }
	}
	else if (blockPtr->bits + sbits < wantBits)
	{
	    InetBest subBest;

	    /*
	     * When subcount > 1 blockPtr->bits + sbits == wantBits
	     */
	    assert(subcount == 1);

	    /*
	     * Skip sub-blocks that contain ranges or networks.
	     * All other sub-blocks have a "natural" bit count (do not
	     * subsume consecutive parent indices, since "unnatural" blocks
	     * are caused by a corresponding network or range).
	     */
	    if (o != last &&
		Inet_First_Item(last = o, InetNet) == NULL &&
		Inet_First_Item(o, InetRange) == NULL)
	    {
		/*
		 * Try the sub-block,  if it yields a better prefix
		 * copy the bits contributed at this level into
		 * bestPrefixPtr->octets (below).
		 */
		subBlock.block = o;
		subBlock.bits = blockPtr->bits + sbits;

		subBest = Inet_Auto_Net(prefixPtr, &subBlock, best,
					   wantBits, baseBits, leftBits);

		if (subBest != NoneBest)
		{
		    result = best = subBest;
		    Inet_Sub_Prefix(prefixPtr, blockPtr, sbits, i);
		}
	    }
	}
    }

    db_col_free(subs);
    return result;
}


static int
Inet_Auto_NetCmd(
    ClientData nused,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    const char	*subuuid;		/* UUID of subnet */
    const char	*fname;			/* Name of address family */
    char	*netuuid;		/* UUID of parent net */
    const char	*bitstring;		/* String Prefix bits for new net */
    DB_OBJECT	*net;			/* OBJECT handle for parent net */
    const char	*net_start;		/* Address of parent net */
    int		net_bits;		/* Prefix bits of parent net */
    InetPrefix	prefix;			/* Prefix structure for new subnet */
    InetBlock	block;			/* Insertion block */
    int		bits;			/* Prefix bit count */
    int		bound;			/* Limit for bits */
    int		ok = TCL_OK;		/* Return code */

    if (argc != 5)
    {
	Udb_Error(interp, "EUSAGE", argv[0],
		  "family", "net", "bits", "subnet", (char *)NULL);
	return TCL_ERROR;
    }

    fname = argv[1];
    netuuid = argv[2];
    bitstring = argv[3];
    subuuid = argv[4];

    /*
     * Check uuid of new net object (for errors only),  it typically does
     * not yet exist as an object.
     */
    if (!Uuid_Valid(subuuid))
    {
	return Udb_Error(interp, "ENOTUUID", subuuid, (char *)NULL);
    }

    /*
     * Check uuid of parent net object
     */
    if (!Uuid_Valid(netuuid))
    {
	return Udb_Error(interp, "ENOTUUID", netuuid, (char *)NULL);
    }

    if (Tcl_GetInt(interp, (char *)bitstring, &bits) != TCL_OK)
    {
	return TCL_ERROR;
    }

    net = Udb_Find_Object(netuuid);
    if (net == NULL)
    {
	return Udb_Error(interp, "ENXITEM", netuuid, (char *)NULL);
    }

    /*
     * Validate family,  set up attribute names,  and make sure
     * the given network is indeed a network object for this address family.
     */
    if (Inet_Set_Family(interp, fname, InetNet, net) != TCL_OK)
    {
	return TCL_ERROR;
    }

    /*
     * Validate bit count,  can only do this after Set_Family has
     * initialized "inet_bits".
     */
    if (bits < (bound = 0) || bits > (bound = inet_bits - 1))
    {
	char limit[32];
	char *code = bits < bound ? "ETOOSMALL" : "ETOOBIG";
	(void) sprintf(limit, "%d", bound);
	return Udb_Error(interp, code, subuuid,
			 inet_net_bits_attribute, bitstring, limit,
			 (char *)NULL);
    }

    /*
     * Make sure parent net has a non NULL starting address.
     */
    if ((net_start = NET_START(net)) == NULL)
    {
	return Udb_Error(interp, "EINETNOTNODE", netuuid, fname, (char *)0);
    }

    net_bits = NET_BITS(net);

    /*
     * Initialize prefix structure as parent network
     */
    check (Inet_Net_Prefix(&prefix, interp, netuuid,
			   net_start, net_bits) == TCL_OK);

    /*
     * Search for insertion block
     */
    (void) Inet_Find(&prefix, &block);

    /*
     * Make sure the block we found matches net prefix bit count
     */
    check(block.bits == prefix.bits);

    /*
     * Find unused aligned block with prefix bits count == "bits" or less
     * and the specified net as parent.  The prefix octet string will
     * be modified in place to contain the prefix of the unused block.
     * The bits in the octet string after the prefix are garbage,  and
     * will have to be trimmed by the caller.
     */
    if (bits > net_bits &&
	Inet_Auto_Net(&prefix, &block, NoneBest,
			 bits, net_bits, net_bits) != NoneBest)
    {
	Tcl_DString result;
	/*
	 * Reencode binary prefix in hex, append left bit count
	 * and return as interpreter result
	 */
	Tcl_DStringInit(&result);
	Tcl_DStringSetLength(&result, inet_octets + 10);
	Udb_Radix16_Encode(prefix.octets, inet_octets,
			   Tcl_DStringValue(&result));
	(void) sprintf(Tcl_DStringValue(&result) + 2 * inet_octets,
		       " %d", prefix.bits);
	Tcl_DStringResult(interp, &result);
    }
    else
    {
	ok = Udb_Error(interp, "EINETFULL", subuuid,
		       inet_net_netof_attribute, netuuid, (char *)NULL);
    }

    /*
     * Free net_start string allocated from DB workspace
     */
    db_string_free((char *)net_start);

    /*
     * Free prefix octet string allocated by ckalloc in Inet_Net_Prefix
     */
    ckfree((char *)prefix.octets);

    return ok;
}


static int
Inet_Net_ItemsCmd(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    InetObjType		type = (InetObjType)d;
    const char		*fname;
    const char		*netuuid;
    DB_OBJECT		*net;
    DB_OBJECT		*block;
    DB_OBJECT		*item;
    DB_COLLECTION	*items;
    int			i;

    if (argc != 3)
    {
	Udb_Error(interp, "EUSAGE", argv[0], "family", "net", (char *)0);
	return TCL_ERROR;
    }

    fname = argv[1];
    netuuid = argv[2];

    /*
     * Check uuid of parent net object
     */
    if (!Uuid_Valid(netuuid))
    {
	return Udb_Error(interp, "ENOTUUID", netuuid, (char *)NULL);
    }
    if ((net = Udb_Find_Object((char *)netuuid)) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", netuuid, (char *)NULL);
    }

    /*
     * Validate family,  set up attribute names,  and make sure
     * the given network is indeed a network object for this address family.
     */
    if (Inet_Set_Family(interp, fname, InetNet, net) != TCL_OK)
    {
	return TCL_ERROR;
    }

    if ((block = ITEM_BLOCK(net)) == NULL)
    {
	return Udb_Error(interp, "EINETNOTNODE", netuuid, fname, (char *)0);
    }

    switch (type)
    {
    case InetNode:
	if ((item = Inet_Object(block, INET_NET_ANODE)) != NULL)
	{
	    Tcl_SetResult(interp, Udb_Get_Uuid(item, NULL), TCL_VOLATILE);
	}
	break;

    case InetNet:
	if ((item = Inet_Object(block, INET_NET_ASUBNET)) != NULL)
	{
	    Tcl_SetResult(interp, Udb_Get_Uuid(item, NULL), TCL_VOLATILE);
	}
	break;

    case InetRange:
	items = NET_RANGES(block);
	for (i = 0; (item = Inet_Nth(items, i)) != NULL; ++i)
	{
	    Tcl_AppendElement(interp, Udb_Get_Uuid(item, NULL));
	}
	db_col_free(items);
	break;
    }
    return TCL_OK;
}


static DB_OBJECT *
Inet_Search_Block(
    InetPrefix *startPtr,
    InetPrefix *endPtr,
    InetBlock *blockPtr,
    int	left,
    int right
)
{
    static int 		carry;
    DB_COLLECTION	*subs;
    DB_OBJECT		*node;
    int			min;
    int			max;
    int			i;
    int			count;

    /*
     * Clear the carry bit
     */
    carry = 0;

    /*
     * Nothing left to search
     */
    if (blockPtr->block == NULL)
    {
	return NULL;
    }

    /*
     * Descend to a block for which start and end are not both
     * in the same sub-block,  or return singleton node.
     */
    for (;;)
    {
	if (blockPtr->bits == inet_bits)
	{
	    /*
	     * We have a singleton
	     */
	    carry = 1;
	    return Inet_First_Item(blockPtr->block, InetNode);
	}

	min = left ? SUB_INDEX(startPtr, blockPtr) : 0;
	max = right ? SUB_INDEX(endPtr, blockPtr) : SUB_MASK(blockPtr);

	subs = SUBS(blockPtr->block);

	if (min < max)
	{
	    break;
	}

	blockPtr->block = Inet_Nth(subs, min);
	db_col_free(subs);

	if (blockPtr->block == NULL)
	{
	    return NULL;
	}

	blockPtr->bits = BITS(blockPtr->block);
    }

    /*
     * Search the sub-blocks
     */
    for (node = NULL, i = min; i <= max; i += count)
    {
	InetBlock	sub;

	if ((sub.block = Inet_Nth(subs, i)) == NULL)
	{
	    count = 1;
	    continue;
	}

	sub.bits = BITS(sub.block);
	count = 1 << (blockPtr->bits + SUB_BITS(blockPtr) - sub.bits); 

	node = Inet_Search_Block(startPtr, endPtr, &sub,
				 left && i == min, right && i == max);
	if (node != NULL)
	{
	    /*
	     * Adjust start prefix to 1 past node as we unwind
	     * Handle the carry bit at each level.
	     */
	    if (carry && (carry = (++i > max)) != 0)
	    {
		i = 0;
	    }
	    Inet_Sub_Prefix(startPtr, blockPtr, sub.bits - blockPtr->bits, i);
	    break;
	}
    }
    db_col_free(subs);
    return node;
}


static int
Inet_Check_RangeCmd(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    const char		*fname;
    const char		*uuid;
    DB_OBJECT		*range;
    const char		*start;
    const char		*end;
    InetPrefix 		startPrefix;
    InetPrefix 		endPrefix;
    InetBlock 		rangeBlock;
    Tcl_HashTable	ok;
    int			i;
    DB_OBJECT		*node;

#define BUILD_RANGE_PREFIX(which)\
    \
    which = Inet_String(range, inet_range_##which##_attribute);\
    check(which != NULL);\
    check(Inet_Node_Prefix(&##which##Prefix, interp, uuid,\
			   inet_range_##which##_attribute,\
			   which) == TCL_OK);\
    db_string_free((char *)which)

    if (argc < 3)
    {
	return Udb_Error(interp, "EUSAGE", argv[0],
			 "family", "uuid", "?class ...?", (char *)0);
    }

    fname = argv[1];
    uuid  = argv[2];

    if ((range = _Udb_Find_Object(uuid)) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", uuid, (char *)0);
    }

    if (Inet_Set_Family(interp, fname, InetRange, range) != TCL_OK)
    {
	return TCL_ERROR;
    }

    if ((rangeBlock.block = ITEM_BLOCK(range)) == NULL)
    {
	return Udb_Error(interp, "EINETNOTNODE", uuid, fname);
    }
    check((rangeBlock.bits = BITS(rangeBlock.block)) < inet_bits);

    BUILD_RANGE_PREFIX(start);
    BUILD_RANGE_PREFIX(end);

    Tcl_InitHashTable(&ok, TCL_ONE_WORD_KEYS);

    for (i = 5; i < argc; ++i)
    {
	DB_OBJECT *class;
	int	   new;

	if ((class = _Udb_Get_Class(argv[i])) == NULL)
	{
	    Tcl_DeleteHashTable(&ok);
	    return Udb_Error(interp, "ENXCLASS", argv[i], (char *)0);
	}
	(void) Tcl_CreateHashEntry(&ok, (ClientData)class, &new);
    }

    while((node = Inet_Search_Block(&startPrefix, &endPrefix,
				    &rangeBlock, 1, 1)) != NULL)
    {
	DB_OBJECT 	*o = node;
	DB_OBJECT 	*c = db_get_class(o);
	Tcl_HashEntry	*ePtr;

	/*
	 * If the owner of an InetNode is still an InetNode,  try that
	 * recursively  (e.g. treat router interfaces as routers!)
	 */
	while((ePtr = Tcl_FindHashEntry(&ok, (ClientData)c)) == NULL &&
	      (o = Inet_Object(o, "owner")) != NULL &&
	      Udb_ISA(c = db_get_class(o), inet_node_class)) /* Nothing */;

	if (ePtr == NULL)
	{
	    break;
	}
    }

    if (node)
    {
	Tcl_SetResult(interp, Udb_Get_Uuid(node, NULL), TCL_VOLATILE);
    }

    Tcl_DeleteHashTable(&ok);
    ckfree((char *)startPrefix.octets);
    ckfree((char *)endPrefix.octets);

    return TCL_OK;
}

/*
 * Command management
 */
typedef struct InetCommandInfo
    {
	const char	*name;
	Tcl_CmdProc	*proc;
	ClientData	data;
    }
    InetCommandInfo;

static InetCommandInfo InetCommands[] =
    {
        { "udb_inet_netof_node",  Inet_NetofCmd, (ClientData)InetNode },
	{ "udb_inet_netof_net",   Inet_NetofCmd, (ClientData)InetNet },
	{ "udb_inet_netof_range", Inet_NetofCmd, (ClientData)InetRange },
	{ "udb_inet_net_anode",   Inet_Net_ItemsCmd, (ClientData)InetNode },
	{ "udb_inet_net_asubnet", Inet_Net_ItemsCmd, (ClientData)InetNet },
	{ "udb_inet_net_ranges",  Inet_Net_ItemsCmd, (ClientData)InetRange },
	{ "udb_inet_auto_net",    Inet_Auto_NetCmd, NULL },
	{ "udb_inet_check_range", Inet_Check_RangeCmd, NULL },
	{ NULL, NULL, NULL }
    };


int
Udb_Inet_Create_Commands(Tcl_Interp *interp, int create)
{
    InetCommandInfo	*cmd;

    if (create)
    {
	/*
	 * Initialize Integrity Hash Tables
	 */
	Tcl_InitHashTable(&itemCheckTable, TCL_STRING_KEYS);
	Tcl_InitHashTable(&blockCheckTable, TCL_STRING_KEYS);

	/*
	 * Create commands
	 */
	for (cmd = InetCommands; cmd->name; ++cmd)
	{
	    Tcl_CreateCommand(interp, (char *)cmd->name,
			      cmd->proc, cmd->data, NULL);
	}
    }
    else
    {
	for (cmd = InetCommands; cmd->name; ++cmd)
	{
	    Tcl_DeleteCommand(interp, (char *)cmd->name);
	}
    }
    return TCL_OK;
}
