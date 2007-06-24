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
static char rcsid[] = "$Id: tcl_mem.c,v 1.19.20.3 1997/09/21 23:42:53 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "uuid.h"
#include "tcl_mem.h"
#include "misc.h"
#include "lookup.h"
#include "convert.h"

typedef struct {
    DB_TYPE	type;
    union {
	DB_INT32	intValue;
	DB_OBJECT	*objectValue;
	char		stringValue[1];
	DB_OBJECT	*objectList[1];
    } data;
} Value, *ValuePtr;


void
Udb_Delay_Fetch(
    Tcl_HashTable *streamTbl,
    DB_OBJECT *object
)
{
    int new;
    Tcl_HashTable *fetchTbl;
    Tcl_HashEntry *ePtr;

    assert(streamTbl);
    assert(object);

    /*
     * Trick: if object has the `uuid' attribute,  it has either already
     * been fetched,  or need not be fetched.
     */
    if ((ePtr = Tcl_FindHashEntry(streamTbl, (ClientData)object)) != NULL)
    {
	Tcl_HashTable *oTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	if (Tcl_FindHashEntry(oTbl, "uuid"))
	{
	    /*
	     * Object has been fetched
	     */
	    return;
	}
    }

    /*
     * Locate or create delay fetch table (NULL index on master table)
     */
    ePtr = Tcl_CreateHashEntry(streamTbl, (ClientData)NULL, &new);

    if (new)
    {
	/*
	 * New: Initialize it 
	 */
	fetchTbl = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
	Tcl_InitHashTable(fetchTbl, TCL_ONE_WORD_KEYS);
	Tcl_SetHashValue(ePtr, (ClientData)fetchTbl);
    }
    else
    {
	/*
	 * Not new, cast from hash entry
	 */
	fetchTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }
    /*
     * `Append' object to delay fetch table
     */
    (void) Tcl_CreateHashEntry(fetchTbl, (ClientData)object, &new);
}


void
Udb_Store_Value(
    Tcl_HashTable *streamTbl,
    DB_OBJECT *object,
    char *aname,
    DB_VALUE *value
)
{
    Tcl_HashEntry *ePtr;
    int		  new;
    Tcl_HashTable *oTbl;
    DB_DOMAIN	  *domain;
    DB_TYPE	  type;
    char	  *cbuf;
    int		  clen;
    DB_OBJECT	  *o;
    DB_COLLECTION *col;
    int		  colSize;
    int		  i;
    Tcl_DString   dstr;
    ValuePtr	  aValPtr = NULL;

    assert(streamTbl);
    assert(object);
    assert(value);

    ePtr = Tcl_CreateHashEntry(streamTbl, (ClientData)object, &new);

    if (new)
    {
	oTbl = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
	Tcl_InitHashTable(oTbl, TCL_STRING_KEYS);
	Tcl_SetHashValue(ePtr, (ClientData)oTbl);
    }
    else
    {
	oTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }

    /*
     * aname == NULL iff value is class object
     */
    ePtr = Tcl_CreateHashEntry(oTbl, aname ? aname : "Class", &new);

    if ((!new && Tcl_GetHashValue(ePtr)) || DB_IS_NULL(value))
    {
	/*
	 * We have already stored the attribute for this object
	 */
	return;
    }

    switch (type = DB_VALUE_DOMAIN_TYPE(value))
    {
    case DB_TYPE_INTEGER:
	aValPtr = (ValuePtr)ckalloc(sizeof(Value));
	aValPtr->type = DB_TYPE_INTEGER;
	aValPtr->data.intValue = DB_GET_INTEGER(value);
	break;

    case DB_TYPE_STRING:
	cbuf = DB_GET_STRING(value);
	aValPtr = (ValuePtr)ckalloc(sizeof(Value) + strlen(cbuf));
	aValPtr->type = DB_TYPE_STRING;
	strcpy(aValPtr->data.stringValue, cbuf);
	break;

    case DB_TYPE_OBJECT:
	o = DB_GET_OBJECT(value);
	aValPtr = (ValuePtr)ckalloc(sizeof(Value));
	aValPtr->type = DB_TYPE_OBJECT;
	aValPtr->data.objectValue = o;

	if (aname && o)
	{
	    Udb_Delay_Fetch(streamTbl, o);
	}
	break;

    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	col = DB_GET_COLLECTION(value);
	colSize = db_col_size(col);
	check(domain = db_col_domain(col));
	check(domain = db_domain_set(domain));

	switch(type = db_domain_type(domain))
	{
	case DB_TYPE_STRING:
	case DB_TYPE_INTEGER:
	    Tcl_DStringInit(&dstr);
	    for (i = 0; i < colSize; ++i)
	    {
		DB_VALUE colValue;
		Udb_Get_Collection_Value(col, i, type, &colValue);
		Udb_Stringify_Value(&dstr, &colValue);
		db_value_clear(&colValue);
	    }
	    cbuf = Tcl_DStringValue(&dstr);
	    clen = strlen(cbuf);
	    aValPtr = (ValuePtr)ckalloc(sizeof(Value) + clen);
	    aValPtr->type = DB_TYPE_STRING;
	    strcpy(aValPtr->data.stringValue, cbuf);
	    Tcl_DStringFree(&dstr);
	    break;

	case DB_TYPE_OBJECT:
	    aValPtr = (ValuePtr)
		ckalloc(sizeof(Value) + colSize * sizeof(DB_OBJECT *));
	    aValPtr->type = DB_TYPE_LIST;
	    for (i = 0; i < colSize; ++i)
	    {
		DB_VALUE elemValue;
		Udb_Get_Collection_Value(col, i, DB_TYPE_OBJECT, &elemValue);
		Udb_Delay_Fetch(streamTbl,
		    aValPtr->data.objectList[i] = DB_GET_OBJECT(&elemValue));
	    }
	    aValPtr->data.objectList[colSize] = NULL;
	    break;

	default:
	    panic("Unupported set element type: %s, attribute %s",
		  db_get_type_name(type), aname);
	    break;
	}
	break;

    default:
	panic("Unupported data type: %s, attribute %s",
	      db_get_type_name(type), aname);
	break;
    }
    Tcl_SetHashValue(ePtr, (ClientData)aValPtr);
    return;
}


static void
Do_Fetch(
    Tcl_Interp *interp,
    Tcl_HashTable *streamTbl,
    DB_OBJECT **oArray,
    int oCount,
    int	nameFields,
    int deletedFlag
)
{
    Tcl_HashEntry *ePtr;
    int		  new;
    int 	  i;

    oArray[oCount] = NULL;

    if ((i = db_fetch_array(oArray, DB_FETCH_READ, 0)) != NOERROR)
    {
#ifdef FETCH_ARRAY_COMPLAIN
	Unameit_Complain("db_fetch_array returned %d: %s", i,
			 db_error_string(1));
#endif
    }

    for(i = 0; i < oCount; ++i)
    {
	DB_VALUE	value;
	DB_OBJECT	*o;
	DB_OBJECT	*class;
	Tcl_HashTable	*oTbl;
	char		**alist;
	char		**anamePtr;
	ValuePtr	aValPtr;

	o = oArray[i];

	check(ePtr = Tcl_FindHashEntry(streamTbl, (ClientData)o));
	oTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);

	ePtr = Tcl_CreateHashEntry(oTbl, "uuid", &new);

	if (new)
	{
	    DB_VALUE value;
	    Udb_Get_Value(o, "uuid", DB_TYPE_STRING, &value);
	    check(!DB_IS_NULL(&value));
	    Udb_Store_Value(streamTbl, o, "uuid", &value);
	    db_value_clear(&value);
	}

	if (nameFields == TRUE)
	{
	    ePtr = Tcl_CreateHashEntry(oTbl, "Class", &new);
	}
	else
	{
	    ePtr = Tcl_FindHashEntry(oTbl, "Class");
	}

	if (!ePtr)
	{
	    /*
	     * If not fetching class,  also not fetching any name
	     * attributes
	     */
	    continue;
	}

	aValPtr = (ValuePtr)Tcl_GetHashValue(ePtr);
	/*
	 * NULL values are stored as NULL pointers!
	 */
	if (aValPtr != NULL)
	{
	    check(aValPtr->type == DB_TYPE_OBJECT);
	    check(class = aValPtr->data.objectValue);
	}
	else
	{
	    DB_VALUE classValue;
	    DB_MAKE_OBJECT(&classValue, class = db_get_class(o));

	    Udb_Store_Value(streamTbl, o, NULL, &classValue);
	}

	if (deletedFlag == TRUE)
	{
	    ePtr = Tcl_CreateHashEntry(oTbl, "deleted", &new);

	    if (new)
	    {
		DB_VALUE value;
		Udb_Get_Value(o, "deleted", DB_TYPE_STRING, &value);
		Udb_Store_Value(streamTbl, o, "deleted", &value);
		db_value_clear(&value);
	    }
	}

	if (nameFields == FALSE) continue;

	alist = Udb_Get_Name_Attributes(interp, class);
	if (alist == NULL) continue;

	for (anamePtr = alist; *anamePtr != NULL; ++anamePtr)
	{
	    if (!(ePtr = Tcl_FindHashEntry(oTbl, *anamePtr)))
	    {
		check(db_get(o, *anamePtr, &value) == NOERROR);
		Udb_Store_Value(streamTbl, o, *anamePtr, &value);
		db_value_clear(&value);
	    }
	}
    }
}

#define FETCH_COUNT 64

static void
Fetch_Objects(
    Tcl_Interp	  *interp,
    Tcl_HashTable *streamTbl,
    int		  nameFields,
    int		  deletedFlag
)
{
    Tcl_HashEntry  *fetchPtr;
    Tcl_HashTable  *fetchTbl;
    Tcl_HashEntry  *ePtr;
    Tcl_HashSearch search;
    int	  	   new;
    DB_OBJECT	   *oArray[FETCH_COUNT];
    int		   oCount = 0;
    char	   **anamePtr;
    DB_OBJECT	   *class;
    char	   **alist;

    fetchPtr = Tcl_FindHashEntry(streamTbl, NULL);

    if (fetchPtr == NULL)
    {
	return;
    }

    /*
     * Process partially fetched objects and then delete the
     * corresponding hash table
     */
    fetchTbl = (Tcl_HashTable *)Tcl_GetHashValue(fetchPtr);

    /*
     * Fetch UUID or Class of all objects for which we do not yet have
     * (and need) a UUID or class
     */
    while (1)
    {
	while ((ePtr = Tcl_FirstHashEntry(fetchTbl, &search)) != NULL)
	{
	    int			need_more;
	    Tcl_HashTable	*oTbl;
	    DB_OBJECT		*o;
	    ValuePtr		aValPtr;

	    
	    o = (DB_OBJECT *)Tcl_GetHashKey(fetchTbl, ePtr);
	    
	    Tcl_DeleteHashEntry(ePtr);

	    ePtr = Tcl_CreateHashEntry(streamTbl, (ClientData)o, &new);

	    if (new)
	    {
		oTbl = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
		Tcl_InitHashTable(oTbl, TCL_STRING_KEYS);
		Tcl_SetHashValue(ePtr, (ClientData)oTbl);
	    }
	    else
	    {
		oTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	    }

	    /*
	     * Do we have a UUID yet?
	     */
	    need_more = (Tcl_FindHashEntry(oTbl, "uuid") == NULL);

	    if (!need_more)
	    {
		if (nameFields == TRUE)
		{
		    ePtr = Tcl_CreateHashEntry(oTbl, "Class", &new);
		}
		else
		{
		    ePtr = Tcl_FindHashEntry(oTbl, "Class");
		}
	    }
	    if (!need_more && ePtr && deletedFlag == TRUE)
	    {
		/*
		 * We need to fetch the class and any name attributes
		 * or deleted status.
		 */
		if (Tcl_FindHashEntry(oTbl, "deleted") == NULL)
		{
		    need_more = 1;
		}
	    }
	    if (!need_more && ePtr &&
		(aValPtr = (ValuePtr)Tcl_GetHashValue(ePtr)))
	    {
		/*
		 * We know the class,  if do not need name attributes,
		 * done.
		 */
		if (nameFields == FALSE) continue;

		assert(aValPtr->type == DB_TYPE_OBJECT);
		check(class = aValPtr->data.objectValue);

		alist = Udb_Get_Name_Attributes(interp, class);
		if (alist == NULL) continue;
		for (anamePtr = alist; *anamePtr != NULL; ++anamePtr)
		{
		    if ((ePtr = Tcl_FindHashEntry(oTbl, *anamePtr)) == NULL)
		    {
			break;
		    }
		}
		if (*anamePtr == NULL)
		{
		    /*
		     * All name attributes are already known
		     */
		    continue;
		}
	    }

	    oArray[oCount++] = o;

	    if (oCount == FETCH_COUNT)
	    {
		Do_Fetch(interp, streamTbl, oArray, oCount,
			 nameFields, deletedFlag);
		oCount = 0;
	    }
	}
	if (oCount > 0)
	{
	    Do_Fetch(interp, streamTbl, oArray, oCount,
		     nameFields, deletedFlag);
	    oCount = 0;
	}
	else
	{
	    break;
	}
    }
    Tcl_DeleteHashTable(fetchTbl);
    ckfree((char *)fetchTbl);
    Tcl_DeleteHashEntry(fetchPtr);
}


int
Udb_Stream_Encode(
    Tcl_Interp *interp,
    Tcl_HashTable *streamTbl,
    int nameFields,
    int streamFlag,
    int deletedFlag
)
{
    Tcl_DString    dstr;
    Tcl_HashEntry  *ePtr;
    Tcl_HashSearch search;

    assert(interp);
    assert(streamTbl);

    Fetch_Objects(interp, streamTbl, nameFields, deletedFlag);

    if (streamFlag == TRUE)
    {
	/*
	 * The interpreter result constains the matching UUID list
	 * move it to a DString,  then append the encoded objects,  put
	 * back into interpreter result when done.
	 */
	Tcl_DStringInit(&dstr);
	Tcl_DStringGetResult(interp, &dstr);
    }

    for(ePtr = Tcl_FirstHashEntry(streamTbl, &search);
	ePtr;
	ePtr = Tcl_NextHashEntry(&search))
    {
	Tcl_HashSearch	attrSearch;
	char		*uuid;
	DB_OBJECT	*o;
	DB_OBJECT	*class;
	char		*class_name;
	Tcl_HashTable	*oTbl;
	ValuePtr	cValPtr;

	o = (DB_OBJECT *)Tcl_GetHashKey(streamTbl, ePtr);
	oTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);

	if ((ePtr = Tcl_FindHashEntry(oTbl, "Class")) == NULL)
	{
	    /*
	     * No class -> no other attributes, and no name fields
	     * This object has no serializable contents
	     */
	    continue;
	}

	/*
	 * Process class now,  to avoid special casing below
	 */
	cValPtr = (ValuePtr)Tcl_GetHashValue(ePtr);
	assert(cValPtr->type == DB_TYPE_OBJECT);
	class = cValPtr->data.objectValue;
	class_name = Udb_Get_Class_Name(class);
	ckfree((char *)cValPtr);
	Tcl_DeleteHashEntry(ePtr);

	check(ePtr = Tcl_FindHashEntry(oTbl, "uuid"));
	uuid = ((ValuePtr)Tcl_GetHashValue(ePtr))->data.stringValue;

	if (streamFlag == TRUE)
	{
	    /*
	     * Append uuid and start attribute/value sublist.  Can't drop
	     * from hash table, may be needed by referencing objects.
	     */
	    Tcl_DStringAppendElement(&dstr, uuid);
	    Tcl_DStringStartSublist(&dstr);
	    Tcl_DStringAppendElement(&dstr, "Class");
	    Tcl_DStringAppendElement(&dstr, class_name);
	}
	else
	{
	    if (Tcl_SetVar2(interp, uuid, "Class", class_name,
			    TCL_LEAVE_ERR_MSG) == NULL)
	    {
		return TCL_ERROR;
	    }
	}

	/*
	 * Do the fields
	 */
	for (ePtr = Tcl_FirstHashEntry(oTbl, &attrSearch);
	     ePtr;
	     ePtr = Tcl_NextHashEntry(&attrSearch))
	{
	    char  	  *aname;
	    ValuePtr	  aValPtr;
	    char	  ibuf[32];
	    char	  *cbuf;
	    DB_OBJECT	  *refobj;
	    Tcl_HashTable *uTbl;
	    ValuePtr	  uuidValPtr;
	    DB_OBJECT	  **oPtr;
	    
	    aname = Tcl_GetHashKey(oTbl, ePtr);

	    /*
	     * For us "uuid" is OID not data, processed above.
	     */
	    if (Equal(aname, "uuid")) continue;

	    if (streamFlag == TRUE)
	    {
		Tcl_DStringAppendElement(&dstr, aname);
	    }

	    if ((aValPtr = (ValuePtr)Tcl_GetHashValue(ePtr)) == NULL)
	    {
		if (streamFlag == TRUE)
		{
		    Tcl_DStringAppendElement(&dstr, "");
		}
		else
		{
		    if (Tcl_SetVar2(interp, uuid, aname, "",
				    TCL_LEAVE_ERR_MSG) == NULL)
		    {
			return TCL_ERROR;
		    }
		}
		continue;
	    }

	    switch(aValPtr->type)
	    {
	    case DB_TYPE_INTEGER:
		sprintf(ibuf, "%ld", (long)aValPtr->data.intValue);
		if (streamFlag == TRUE)
		{
		    Tcl_DStringAppendElement(&dstr, ibuf);
		}
		else
		{
		    if (Tcl_SetVar2(interp, uuid, aname, ibuf,
				    TCL_LEAVE_ERR_MSG) == NULL)
		    {
			return TCL_ERROR;
		    }
		}
		break;

	    case DB_TYPE_STRING:
		cbuf = aValPtr->data.stringValue;
		if (streamFlag == TRUE)
		{
		    Tcl_DStringAppendElement(&dstr, cbuf);
		}
		else
		{
		    if (Tcl_SetVar2(interp, uuid, aname, cbuf,
				    TCL_LEAVE_ERR_MSG) == NULL)
		    {
			return TCL_ERROR;
		    }
		}
		break;

	    case DB_TYPE_OBJECT:
		/*
		 * Get saved object pointer
		 */
		refobj = aValPtr->data.objectValue;
		/*
		 * Find corresponding attribute table
		 */
		ePtr = Tcl_FindHashEntry(streamTbl, (ClientData)refobj);
		uTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
		/*
		 * Find "uuid" entry
		 */
		ePtr = Tcl_FindHashEntry(uTbl, "uuid");
		/*
		 * Read string value
		 */
		uuidValPtr = (ValuePtr)Tcl_GetHashValue(ePtr);
		check(uuidValPtr->type == DB_TYPE_STRING);
		cbuf = uuidValPtr->data.stringValue;

		if (streamFlag == TRUE)
		{
		    Tcl_DStringAppendElement(&dstr, cbuf);
		}
		else
		{
		    if (Tcl_SetVar2(interp, uuid, aname, cbuf,
				    TCL_LEAVE_ERR_MSG) == NULL)
		    {
			return TCL_ERROR;
		    }
		}
		break;

	    case DB_TYPE_LIST:
		if (streamFlag == TRUE)
		{
		    Tcl_DStringStartSublist(&dstr);
		}
		else
		{
		    if (Tcl_SetVar2(interp, uuid, aname, "",
				    TCL_LEAVE_ERR_MSG) == NULL)
		    {
			return TCL_ERROR;
		    }
		}
		for(oPtr = aValPtr->data.objectList; *oPtr; ++oPtr)
		{
		    ePtr = Tcl_FindHashEntry(streamTbl, (ClientData)*oPtr);
		    uTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
		    ePtr = Tcl_FindHashEntry(uTbl, "uuid");
		    uuidValPtr = (ValuePtr)Tcl_GetHashValue(ePtr);
		    assert(uuidValPtr->type == DB_TYPE_STRING);
		    cbuf = uuidValPtr->data.stringValue;

		    if (streamFlag == TRUE)
		    {
			Tcl_DStringAppendElement(&dstr, cbuf);
		    }
		    else
		    {
			if (Tcl_SetVar2(interp, uuid, aname, cbuf,
					TCL_LIST_ELEMENT|
					TCL_APPEND_VALUE|
					TCL_LEAVE_ERR_MSG) == NULL)
			{
			    return TCL_ERROR;
			}
		    }
		}
		if (streamFlag == TRUE)
		{
		    Tcl_DStringEndSublist(&dstr);
		}
		break;

	    default:
		panic("Illegal data type: %s",
		      db_get_type_name(aValPtr->type));
		break;
	    }
        }
	if (streamFlag == TRUE)
	{
	    Tcl_DStringEndSublist(&dstr);
	}
    }
    if (streamFlag == TRUE)
    {
	Tcl_DStringResult(interp, &dstr);
    }
    return TCL_OK;
}


void
Udb_Delete_Stream_Table(Tcl_HashTable *streamTbl)
{
    Tcl_HashEntry  *ePtr;
    Tcl_HashSearch search;

    assert(streamTbl);

    while((ePtr = Tcl_FirstHashEntry(streamTbl, &search)) != NULL)
    {
	Tcl_HashTable *oTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
	DB_OBJECT *o = (DB_OBJECT *)Tcl_GetHashKey(streamTbl, ePtr);
	Tcl_DeleteHashEntry(ePtr);

	if (o != NULL)
	{
	    /*
	     * This is an attribute/value table for an object.
	     * Free all remaining fields.  They should all have been ckalloced.
	     */
	    Udb_Free_Dynamic_Table(oTbl, NULL, TRUE);
	}
	else
	{
	    /*
	     * o == NULL is the delay fetch table, no hash values
	     */
	    Tcl_DeleteHashTable(oTbl);
	}
	ckfree((char *)oTbl);
    }
    Tcl_DeleteHashTable(streamTbl);
    return;
}
