/*
 * Copyright (c) 1995,  Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: lookup.c,v 1.42.18.7 1997/10/11 00:55:13 viktor Exp $";

/*
 * Contains lookup routines for uuid string and class names to object
 * pointers. Contains code to hash values.
 */

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "uuid.h"
#include "misc.h"
#include "lookup.h"
#include "transaction.h"
#include "errcode.h"

/*
 * Cache objects, drop cache on transaction rollback
 */
static Tcl_HashTable	itemCache;
static Tcl_HashTable	newobjCache;
static Tcl_HashTable	rootCache;
static int		rootCacheDirty = FALSE;

/*
 * Cache schema metadata,  drop cache on successful schema changes.
 */
static Tcl_HashTable	classCache;
static Tcl_HashTable	classNameCache;
static Tcl_HashTable	subClassCache;
static Tcl_HashTable	domainCache;
static Tcl_HashTable	relAttributeCache;
static Tcl_HashTable	nameAttributeCache;
static Tcl_HashTable	refintCache;
static DB_OBJECT	*item_class;
static DB_OBJECT	*prot_item_class;
static DB_OBJECT	*data_class;
static DB_OBJECT	*cell_class;
static DB_OBJECT	*host_class;
static DB_OBJECT	*person_class;

#define ITEM_CLASS\
    (item_class ? item_class : (item_class = Udb_Get_Class("unameit_item")))

#define PROT_ITEM_CLASS\
    (prot_item_class ? prot_item_class :\
	(prot_item_class = Udb_Get_Class("unameit_protected_item")))

#define DATA_CLASS\
    (data_class ? data_class :\
     (data_class = Udb_Get_Class("unameit_data_item")))

#define CELL_CLASS\
    (cell_class ? cell_class : (cell_class = Udb_Get_Class("cell")))

#define HOST_CLASS\
    (host_class ? host_class : (host_class = _Udb_Get_Class("host")))

#define PERSON_CLASS\
    (person_class ? person_class :\
	(person_class = _Udb_Get_Class("person")))


/*
 * Cache current principal object,  drop cache on database disconnect.
 */
static DB_OBJECT 	*current_principal;


/*
 * Wrapper for deleting a table with dynamic values.
 * It is the values that are dynamic.  The table itself may be static.
 *
 * This allows the functions that clean up tables
 * to be called with either static or dynamic top level tables,  it
 * is the caller that frees the main table if necessary.
 *
 * `dockfree' controls whether we free the data,
 * freeProc deals with recursive cleanup, typically
 * of dynamically allocated subtables.
 */
void
Udb_Free_Dynamic_Table(
    Tcl_HashTable *table,
    Tcl_FreeProc *freeProc,
    int dockfree
)
{
    Tcl_HashEntry *ePtr;
    Tcl_HashSearch search;

    for (ePtr = Tcl_FirstHashEntry(table, &search);
	 ePtr;
	 ePtr = Tcl_NextHashEntry(&search))
    {
	register char *data = Tcl_GetHashValue(ePtr);
	if (data)
	{
	    if (freeProc)
	    {
		freeProc(data);
	    }
	    if (dockfree == TRUE)
	    {
		ckfree((char *)data);
	    }
	}
    }
    Tcl_DeleteHashTable(table);
}


void
Udb_Free_Static_Table_Table(Tcl_HashTable *table)
{
    Udb_Free_Dynamic_Table(table, (Tcl_FreeProc *)Tcl_DeleteHashTable, TRUE);
}


void
Udb_Init_Cache(void) 
{
    static int done;

    if (done)
    {
	panic("Udb_Init_Cache() called twice!");
    }

    Tcl_InitHashTable(&itemCache, TCL_STRING_KEYS);
    Tcl_InitHashTable(&newobjCache, TCL_ONE_WORD_KEYS);
    Tcl_InitHashTable(&rootCache, TCL_ONE_WORD_KEYS);

    Tcl_InitHashTable(&classCache, TCL_STRING_KEYS);
    Tcl_InitHashTable(&classNameCache, TCL_ONE_WORD_KEYS);
    Tcl_InitHashTable(&subClassCache, TCL_ONE_WORD_KEYS);
    Tcl_InitHashTable(&domainCache, TCL_ONE_WORD_KEYS);
    Tcl_InitHashTable(&relAttributeCache, TCL_ONE_WORD_KEYS);
    Tcl_InitHashTable(&nameAttributeCache, TCL_ONE_WORD_KEYS);
    Tcl_InitHashTable(&refintCache, TCL_ONE_WORD_KEYS);

    done = 1;
}


/*
 * Transaction rollback should uncache all items,  but
 * schema caches are still ok
 */
void
Udb_Uncache_Items(int rollback, int shutdown)
{
    Udb_Free_Dynamic_Table(&itemCache, NULL, TRUE);
    Tcl_InitHashTable(&itemCache, TCL_STRING_KEYS);

    Tcl_DeleteHashTable(&newobjCache);
    Tcl_InitHashTable(&newobjCache, TCL_ONE_WORD_KEYS);

    if ((rollback == TRUE && rootCacheDirty == TRUE) || shutdown == TRUE)
    {
	Tcl_DeleteHashTable(&rootCache);
	Tcl_InitHashTable(&rootCache, TCL_ONE_WORD_KEYS);
    }
    rootCacheDirty = FALSE;
}


/*
 * Committed schema changes should uncache schema info,  but
 * item cache is still ok.
 */
void
Udb_Uncache_Schema(void)
{
    Tcl_DeleteHashTable(&classCache);
    Tcl_InitHashTable(&classCache, TCL_STRING_KEYS);

    Udb_Free_Static_Table_Table(&domainCache);
    Tcl_InitHashTable(&domainCache, TCL_ONE_WORD_KEYS);

    Udb_Free_Dynamic_Table(&classNameCache, NULL, TRUE);
    Tcl_InitHashTable(&classNameCache, TCL_ONE_WORD_KEYS);

    Udb_Free_Static_Table_Table(&subClassCache);
    Tcl_InitHashTable(&subClassCache, TCL_ONE_WORD_KEYS);

    Udb_Free_Dynamic_Table(&relAttributeCache, NULL, TRUE);
    Tcl_InitHashTable(&relAttributeCache, TCL_ONE_WORD_KEYS);

    Udb_Free_Dynamic_Table(&nameAttributeCache, NULL, TRUE);
    Tcl_InitHashTable(&nameAttributeCache, TCL_ONE_WORD_KEYS);

    Udb_Free_Static_Table_Table(&refintCache);
    Tcl_InitHashTable(&refintCache, TCL_ONE_WORD_KEYS);

    Tcl_DeleteHashTable(&rootCache);
    Tcl_InitHashTable(&rootCache, TCL_ONE_WORD_KEYS);
    rootCacheDirty = FALSE;

    item_class = NULL;
    prot_item_class = NULL;
    data_class = NULL;
    cell_class = NULL;
    host_class = NULL;
    person_class = NULL;
}

/*
 * Used on database disconnect,  which invalidates all object pointers.
 */
void
Udb_Uncache(void)
{
    Udb_Uncache_Items(TRUE, TRUE);
    Udb_Uncache_Schema();
    current_principal = NULL;
}


DB_OBJECT *
_Udb_Get_Class(const char *name) 
{
    Tcl_HashEntry	*ePtr;
    DB_OBJECT		*class;
    int			new;

    assert(name);

    if ((ePtr = Tcl_FindHashEntry(&classCache, (char *)name)) != NULL)
    {
	return (DB_OBJECT *)Tcl_GetHashValue(ePtr);
    }
    if ((class = db_find_class(name)) != NULL)
    {
	ePtr = Tcl_CreateHashEntry(&classCache, (char *)name, &new);
	Tcl_SetHashValue(ePtr, (ClientData)class);
	return class;
    }
    return NULL;
}


DB_OBJECT *
Udb_Get_Class(const char *name) 
{
    DB_OBJECT	*result;

    assert(name);

    if (!(result = _Udb_Get_Class(name))) {
	panic("Class %s doesn't exist in the database", name);
    }
    return result;
}


int
Udb_ISA(DB_OBJECT *class, DB_OBJECT *super) 
{
    int new;
    int isa;
    Tcl_HashTable *sTbl;
    Tcl_HashEntry *ePtr;

    assert(class);
    assert(super);

    if (class == super) return 1;

    ePtr = Tcl_CreateHashEntry(&subClassCache, (ClientData)super, &new);

    if (new)
    {
	sTbl = (Tcl_HashTable *)ckalloc(sizeof(*sTbl));
	Tcl_InitHashTable(sTbl, TCL_ONE_WORD_KEYS);
	Tcl_SetHashValue(ePtr, (ClientData)sTbl);
    }
    else
    {
	sTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }

    ePtr = Tcl_CreateHashEntry(sTbl, (ClientData)class, &new);

    if (!new)
    {
	return (int)Tcl_GetHashValue(ePtr);
    }

    isa = db_is_subclass(class, super);

    Tcl_SetHashValue(ePtr, (ClientData)isa);
    return isa;
}


int
Udb_Is_Item_Class(DB_OBJECT *class)
{
    return Udb_ISA(class, ITEM_CLASS);
}


int
Udb_Is_Data_Class(DB_OBJECT *class)
{
    return Udb_ISA(class, DATA_CLASS);
}


int
Udb_Is_Host_Class(DB_OBJECT *class)
{
    register DB_OBJECT *h = HOST_CLASS;
    return (h != NULL && Udb_ISA(class, h));
}


int
Udb_Is_Person_Class(DB_OBJECT *class)
{
    register DB_OBJECT *u = PERSON_CLASS;
    return (u != NULL && Udb_ISA(class, u));
}


int
Udb_Attr_Is_Protected(Tcl_Interp *interp, const char *aname) 
{
    if (Tcl_GetVar2(interp, "UNAMEIT_PROTECTED_ATTRIBUTE", (char *)aname,
		    TCL_GLOBAL_ONLY))
    {
	return TRUE;
    }
    return FALSE;
}


int
Udb_Attr_Is_Nullable(
    Tcl_Interp *interp,
    const char *cname,
    const char *aname
)
{
    char	*str;
    Tcl_DString	key;

    Tcl_DStringInit(&key);
    Tcl_DStringAppend(&key, (char *)cname, -1);
    Tcl_DStringAppend(&key, ".", -1);
    Tcl_DStringAppend(&key, (char *)aname, -1);
    str = Tcl_DStringValue(&key);

    str = Tcl_GetVar2(interp, "UNAMEIT_NULLABLE", str, TCL_GLOBAL_ONLY);

    Tcl_DStringFree(&key);

    return str != NULL;
}


/*
 * Store reference to object,  and transaction that deleted it.
 */
typedef struct {
    DB_OBJECT	*object;
    int		deleted;
} CachedObject;


/*
 * Find object with given UUID,  deleted or otherwise!
 */
DB_OBJECT *
_Udb_Find_Object(const char *uuid) 
{
    Tcl_HashEntry	*ePtr;
    CachedObject	*cobj;

    assert(uuid && Uuid_Valid(uuid));

    /*
     * Lookup an object in the cache.  Fetch from database if not in cache.
     */
    if ((ePtr = Tcl_FindHashEntry(&itemCache, (char *)uuid)) == NULL)
    {
	DB_VALUE	value;
	DB_OBJECT	*object;
	int		new;

	DB_MAKE_STRING(&value, uuid);

	if ((object = db_find_unique(ITEM_CLASS, "uuid", &value)) == NULL)
	{
	    return NULL;
	}

	check(db_get(object, "deleted", &value) == NOERROR);

	cobj = (CachedObject *)ckalloc(sizeof(CachedObject));
	cobj->object = object;
	cobj->deleted = !DB_IS_NULL(&value);

	db_value_clear(&value);

	ePtr = Tcl_CreateHashEntry(&itemCache, (char *)uuid, &new);
	Tcl_SetHashValue(ePtr, (ClientData)cobj);
    }
    else
    {
	cobj = (CachedObject *)Tcl_GetHashValue(ePtr);
    }
    return cobj->object;
}


/*
 * Find undeleted object with given UUID
 */
DB_OBJECT *
Udb_Find_Object(const char *uuid)
{
    Tcl_HashEntry	*ePtr;
    CachedObject 	*cobj;

    assert(uuid && Uuid_Valid(uuid));

    /*
     * Lookup an object in the cache.  Fetch from database if not in cache.
     */
    if ((ePtr = Tcl_FindHashEntry(&itemCache, (char *)uuid)) == NULL)
    {
	DB_VALUE	value;
	DB_OBJECT	*object;
	int		new;

	DB_MAKE_STRING(&value, uuid);

	if ((object = db_find_unique(ITEM_CLASS, "uuid", &value)) == NULL)
	{
	    return NULL;
	}

	check(db_get(object, "deleted", &value) == NOERROR);

	cobj = (CachedObject *)ckalloc(sizeof(CachedObject));
	cobj->object = object;
	cobj->deleted = !DB_IS_NULL(&value);

	db_value_clear(&value);

	ePtr = Tcl_CreateHashEntry(&itemCache, (char *)uuid, &new);
	Tcl_SetHashValue(ePtr, (ClientData)cobj);
    }
    else
    {
	cobj = (CachedObject *)Tcl_GetHashValue(ePtr);
    }
    return (cobj->deleted) ? NULL : cobj->object;
}


/*
 * Add object with given uuid and deletion status to cache
 */
void
Udb_Cache_Object(const char *uuid, DB_OBJECT *object, int deleted) 
{
    Tcl_HashEntry	*ePtr;
    CachedObject	*cobj;
    int			new;

    assert(uuid && Uuid_Valid(uuid));

    /*
     * Create or locate cache slot
     */
    ePtr = Tcl_CreateHashEntry(&itemCache, (char *)uuid, &new);

    if (new)
    {
	cobj = (CachedObject *)ckalloc(sizeof(CachedObject));
	Tcl_SetHashValue(ePtr, (ClientData)cobj);
    }
    else
    {
	cobj = (CachedObject *)Tcl_GetHashValue(ePtr);
    }
    cobj->object = object;
    cobj->deleted = deleted;
}


void
Udb_New_Object(const char *uuid, DB_OBJECT *object) 
{
    int new;
    /*
     * Add to new object table
     */
    check(Tcl_CreateHashEntry(&newobjCache, (ClientData)object, &new));
    /*
     * Add to cache as not deleted object
     */
    Udb_Cache_Object(uuid, object, FALSE);
}


int
Udb_Is_New(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT	*object;
    char	*uuid;

    if (argc != 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "item", (char *)NULL);
    }

    uuid = argv[1];

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }

    if ((object = _Udb_Find_Object(uuid)) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
    }

    if (Tcl_FindHashEntry(&newobjCache, (ClientData)object) != NULL)
    {
	interp->result[0] = '1';
    }
    else
    {
	interp->result[0] = '0';
    }
    interp->result[1] = '\0';

    return TCL_OK;
}


char *
Udb_Get_Uuid(DB_OBJECT *object, char *buf) 
{
    static char	static_buf[UDB_UUID_SIZE];
    DB_VALUE	value;

    assert(object);
    if (buf == NULL)
	buf = static_buf;

    Udb_Get_Value(object, "uuid", DB_TYPE_STRING, &value);
    (void) strncpy(buf, DB_GET_STRING(&value), UDB_UUID_SIZE);
    db_value_clear(&value);

    return buf;
}


char *
Udb_Get_Oid(DB_OBJECT *object, char *buf) 
{
    static char		static_buf[64];
    DB_IDENTIFIER	*oid;

    assert(object);

    if (buf == NULL)
	buf = static_buf;

    check(oid = db_identifier(object));
    (void) sprintf(buf, "%x.%lx.%x",
		   (unsigned int)oid->volid,
		   (unsigned long)oid->pageid,
		   (unsigned int)oid->slotid);
    return buf;
}


DB_OBJECT *
Udb_Decode_Oid(char *buf) 
{
    unsigned int	volid;
    unsigned long	pageid;
    unsigned int	slotid;
    DB_IDENTIFIER	oid;
    DB_OBJECT		*object;

    assert(buf);

    if (sscanf(buf, "%x.%lx.%x", &volid, &pageid, &slotid) != 3)
    {
	return NULL;
    }

    oid.volid = (DB_INT16)volid;
    oid.pageid = (DB_INT32)pageid;
    oid.slotid = (DB_INT16)slotid;

    check(object = db_object(&oid));
    return object;
}


static void
Protect_Object(DB_OBJECT *object)
{
    DB_VALUE	value;

    DB_MAKE_OBJECT(&value, object);

    if (db_find_unique(PROT_ITEM_CLASS, "item", &value) == NULL)
    {
	DB_OTMPL	*template;
	check(template = dbt_create_object(PROT_ITEM_CLASS));
	check(dbt_put(template, "item", &value) == NOERROR);
	check(Udb_Finish_Object(NULL, template, FALSE));
    }
}


int
/*ARGSUSED*/
Udb_Protect_Items(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT	*object;
    int		i;

    if (argc < 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "uuid ...", (char *)NULL);
    }

    for (i = 1; i < argc; ++i)
    {
	if (!Uuid_Valid(argv[i]))
	{
	    return Udb_Error(interp, "ENOTUUID", argv[i], (char *)NULL);
	}

	if ((object = Udb_Find_Object(argv[i])) == NULL)
	{
	    return Udb_Error(interp, "ENXITEM", argv[i], (char *)NULL);
	}

	Protect_Object(object);
    }
    return TCL_OK;
}


int
/*ARGSUSED*/
Udb_Item_Protected(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT	*object;
    DB_VALUE	value;
    assert(interp);

    if (argc != 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "uuid", (char *)NULL);
    }

    if (!Uuid_Valid(argv[1]))
    {
	return Udb_Error(interp, "ENOTUUID", argv[1], (char *)NULL);
    }

    if ((object = _Udb_Find_Object(argv[1])) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", argv[1], (char *)NULL);
    }

    DB_MAKE_OBJECT(&value, object);

    if (db_find_unique(PROT_ITEM_CLASS, "item", &value) == NULL)
    {
	(void) strcpy(interp->result, "0");
    }
    else
    {
	(void) strcpy(interp->result, "1");
    }
    return TCL_OK;
}


DB_DOMAIN *
Udb_Attribute_Domain(DB_OBJECT *class, char *aname)
{
    Tcl_HashTable *aTbl;
    Tcl_HashEntry *ePtr;
    DB_ATTRIBUTE *attribute;
    DB_DOMAIN *domain;
    int	 new;

    ePtr = Tcl_CreateHashEntry(&domainCache, (ClientData)class, &new);

    if (new)
    {
	aTbl = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
	Tcl_InitHashTable(aTbl, TCL_STRING_KEYS);
	Tcl_SetHashValue(ePtr, (ClientData)aTbl);
    }
    else
    {
	aTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }

    ePtr = Tcl_CreateHashEntry(aTbl, aname, &new);

    if (!new)
    {
	return (DB_DOMAIN *)Tcl_GetHashValue(ePtr);
    }

    if ((attribute = db_get_attribute(class, aname)) == NULL)
    {
	Tcl_DeleteHashEntry(ePtr);
	return NULL;
    }

    check(domain = db_attribute_domain(attribute));
    Tcl_SetHashValue(ePtr, (ClientData)domain);
    return domain;
}


DB_ATTRIBUTE *
Udb_Get_Attributes(DB_OBJECT *class)
{
    return db_get_attributes(class);
}


char **
Udb_Get_Relattributes(Tcl_Interp *interp, DB_OBJECT *class)
{
    Tcl_HashEntry	*ePtr;
    int			new;
    Tcl_DString		alist;
    int			argc;
    char		**argv;
    DB_ATTRIBUTE	*attrs;

    ePtr = Tcl_CreateHashEntry(&relAttributeCache, (ClientData)class, &new);

    if (!new)
    {
	return (char **)Tcl_GetHashValue(ePtr);
    }


    Tcl_DStringInit(&alist);

    for(attrs = Udb_Get_Attributes(class);
	attrs;
	attrs = db_attribute_next(attrs))
    {
	char		*aname;
	DB_DOMAIN	*domain;
	DB_TYPE		type;
	char		*action;
	
	check(aname = (char *)db_attribute_name(attrs));
	check(domain = Udb_Attribute_Domain(class, aname));

	switch (type = db_domain_type(domain))
	{
	case DB_TYPE_SET:
	case DB_TYPE_SEQUENCE:
	    type = db_domain_type(domain = db_domain_set(domain));
	    break;
	default:
	    break;
	}

	if (type != DB_TYPE_OBJECT || db_domain_class(domain) == NULL)
	{
	    continue;
	}
	action = Udb_Get_Relaction(interp, class, aname);
	if (Equal(action, "Network"))
	{
	    continue;
	}
	Tcl_DStringAppendElement(&alist, aname);
    }

    check(Tcl_SplitList(NULL, Tcl_DStringValue(&alist),
			&argc, &argv) == TCL_OK);

    Tcl_DStringFree(&alist);

    Tcl_SetHashValue(ePtr, (ClientData)argv);

    return argv;
}


DB_OBJECT *
Udb_Relation_Class(char *aname)
{
    Tcl_DString relcname;
    DB_OBJECT	*relclass;

    assert(aname);

    Tcl_DStringInit(&relcname);
    Tcl_DStringAppend(&relcname, "relation/", -1);
    Tcl_DStringAppend(&relcname, aname, -1);

    relclass = Udb_Get_Class(Tcl_DStringValue(&relcname));

    Tcl_DStringFree(&relcname);
    return relclass;
}


char *
Udb_Relation_Attribute(DB_OBJECT *relclass)
{
    char	*relcname;
    char	*aname;

    assert(relclass);
    relcname = Udb_Get_Class_Name(relclass);
    aname = strchr(relcname, '/');
    assert(aname);
    return ++aname;
}


char **
Udb_Get_Name_Attributes(Tcl_Interp *interp, DB_OBJECT *class)
{
    Tcl_HashEntry *ePtr;
    int	 new;
    char *class_name;
    char *alist;
    int  list_argc;
    char **list_argv;

    ePtr = Tcl_CreateHashEntry(&nameAttributeCache, (ClientData)class, &new);

    if (!new)
    {
	return (char **)Tcl_GetHashValue(ePtr);
    }

    class_name = Udb_Get_Class_Name(class);

    alist = Tcl_GetVar2(interp, "UNAMEIT_NAME_ATTRIBUTES", class_name,
			TCL_GLOBAL_ONLY);

    if (alist == NULL)
    {
	return NULL;
    }

    check(Tcl_SplitList(NULL, alist, &list_argc, &list_argv) == TCL_OK);
    Tcl_SetHashValue(ePtr, (ClientData)list_argv);

    return list_argv;
}


char *
Udb_Get_Class_Name(DB_OBJECT *class) 
{
    Tcl_HashEntry	*ePtr;
    int			new;
    char		*name;
    char		*copy;

    assert(class);

    ePtr = Tcl_CreateHashEntry(&classNameCache, (ClientData)class, &new);

    if (!new)
    {
	return Tcl_GetHashValue(ePtr);
    }

    check(name = (char *)db_get_class_name(class));

    copy = ckalloc(strlen(name) + 1);
    (void) strcpy(copy, name);
    Tcl_SetHashValue(ePtr, copy);

    return copy;
}


DB_OTMPL *
Udb_Edit_Free_Object(DB_OBJECT *class)
{
    DB_OTMPL		*template;

    assert(class);

    /*
     * When restoring the free list is always empty
     */
    if (Udb_Restore_Mode(NULL) == NORESTORE)
    {
	DB_OBJECT	*o;
	DB_VALUE	v;

	Udb_Get_Value(class, "nextfree", DB_TYPE_OBJECT, &v);

	if ((o = DB_GET_OBJECT(&v)) != NULL)
	{
	    /*
	     * Set new freelist head to successor of current head
	     */
	    Udb_Get_Value(o, "nextfree", DB_TYPE_OBJECT, &v);
	    check(db_put(class, "nextfree", &v) == NOERROR);

	    /*
	     * Return a template for the free object.
	     */
	    check(template = dbt_edit_object(o));
	    return template;
	}
    }
    check(template = dbt_create_object(class));
    return template;
}


void
Udb_Append_Free_List(DB_OBJECT *class, DB_OTMPL *templ, const char *key)
{
    DB_OBJECT	*o;
    DB_VALUE	v;

    assert(class && templ);

    /*
     * Clear (unique?) key attribute if any
     */
    if (key != NULL)
    {
	DB_MAKE_NULL(&v);
	check(dbt_put(templ, key, &v) == NOERROR);
    }

    /*
     * Set nextfree of new head to previous head object.
     */
    Udb_Get_Value(class, "nextfree", DB_TYPE_OBJECT, &v);
    check(dbt_put(templ, "nextfree", &v) == NOERROR);
    check((o = Udb_Finish_Object(NULL, templ, FALSE)) != NULL);

    /*
     * Update class with new list head
     */
    DB_MAKE_OBJECT(&v, o);
    check(db_put(class, "nextfree", &v) == NOERROR);
}


int
Udb_Attribute_Is_Printable(DB_DOMAIN *domain) 
{
    DB_TYPE	type;

    assert(domain);

    type = db_domain_type(domain);

    switch (type)
    {
    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	domain = db_domain_set(domain);
	type = db_domain_type(domain);
	break;
    default:
	break;
    }

    if (type == DB_TYPE_STRING || type == DB_TYPE_INTEGER)
    {
	return TRUE;
    }

    if (type == DB_TYPE_OBJECT)
    {
	DB_OBJECT *class;
	if ((class = db_domain_class(domain)) != NULL)
	{
	    return Udb_ISA(class, ITEM_CLASS);
	}
    }
    return FALSE;
}


DB_OBJECT *
Udb_Get_Cell(
    Tcl_Interp *interp,
    DB_OBJECT *object,
    DB_OBJECT *loopobj,
    int get_org
)
{
    DB_VALUE	value;
    DB_OBJECT	*class;
    int		is_cell;

    /*
     * Recursively lookup owner until we find a cell,
     * input object may be NULL, or may not have any cells above it.
     */
    while (object)
    {
	class = db_get_class(object);

	is_cell = Udb_ISA(class, CELL_CLASS);

	if (is_cell)
	{
	    DB_OBJECT *org;
	    if (!get_org) return object;
	    Udb_Get_Value(object, "cellorg", DB_TYPE_OBJECT, &value);
	    /*
	     * Return org if not NULL,  else return cell
	     */
	    return (org = DB_GET_OBJECT(&value)) ? org : object;
	}

	if (loopobj == object)
	{
	    return NULL;
	}

	/*
	 * Objects whose owner is based on "topology" are not in any
	 * cell or organization
	 */
	if (Equal(Udb_Get_Relaction(interp, class, "owner"), "Network"))
	{
	    return NULL;
	}

	Udb_Get_Value(object, "owner", DB_TYPE_OBJECT, &value);

	object = DB_GET_OBJECT(&value);
    }
    return NULL;
}


int
Udb_Cell_Of_Cmd(ClientData get_org, Tcl_Interp *interp, int argc, char *argv[])
{
    char *uuid;
    DB_OBJECT *object;
    DB_OBJECT *cell;

    if (argc != 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "item", (char *)NULL);
    }

    uuid = argv[1];

    if (!Uuid_Valid(uuid))
    {
	return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
    }

    if ((object = _Udb_Find_Object(uuid)) == NULL)
    {
	return Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
    }

    if (!Udb_Is_Data_Class(db_get_class(object)))
    {
	return Udb_Error(interp, "ENOATTR", uuid, "owner", (char *)NULL);
    }

    cell = Udb_Get_Cell(interp, object, NULL, (int)get_org);

    /*
     * Save a database call if we can
     */
    if (cell == object)
	strcpy(interp->result, uuid);
    else
	Udb_Get_Uuid(cell, interp->result);

    return TCL_OK;
}


DB_OBJECT *
Udb_Get_Root(DB_OBJECT *class)
{
    Tcl_HashEntry *ePtr;
    int new;
    DB_VALUE value;
    DB_OBJECT *root_object;
    
    ePtr = Tcl_CreateHashEntry(&rootCache, (ClientData)class, &new);

    if (!new)
    {
	return (DB_OBJECT *)Tcl_GetHashValue(ePtr);
    }

    Udb_Get_Value(class, "root_object", DB_TYPE_OBJECT, &value);
    root_object =  DB_GET_OBJECT(&value);

    Tcl_SetHashValue(ePtr, root_object);
    return root_object;
}


int
Udb_Get_RootCmd(
    ClientData nused,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    DB_OBJECT *root_object;
    DB_OBJECT *class;
    assert(interp);

    if (argc != 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "class", (char *)NULL);
    }

    if ((class = _Udb_Get_Class(argv[1])) == NULL)
    {
	return Udb_Error(interp, "ENXCLASS", argv[1], (char *)NULL);
    }

    if ((root_object = Udb_Get_Root(class)) != NULL)
    {
	Udb_Get_Uuid(root_object, interp->result);
    }
    return TCL_OK;
}


void
Udb_Set_Root(DB_OBJECT *class, DB_OBJECT *root_object)
{
    Tcl_HashEntry *ePtr;
    int new;
    DB_VALUE value;

    /*
     * Protect root items
     */
    if (Udb_ISA(db_get_class(root_object), ITEM_CLASS))
    {
	Protect_Object(root_object);
    }

    DB_MAKE_OBJECT(&value, root_object);
    check(db_put(class, "root_object", &value) == NOERROR);

    /*
     * We have changed the database, commit is needed.
     */
    Udb_Finish_Object(NULL, NULL, FALSE);

    ePtr = Tcl_CreateHashEntry(&rootCache, (ClientData)class, &new);
    Tcl_SetHashValue(ePtr, root_object);
    rootCacheDirty = TRUE;
}


int
Udb_Set_RootCmd(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT *class;
    DB_OBJECT *root_object;

    if (argc != 3)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "class uuid",
			 (char *)NULL);
    }

    if ((class = _Udb_Get_Class(argv[1])) == NULL)
    {
	return Udb_Error(interp, "ENXCLASS", argv[1], (char *)NULL);
    }

    if (Udb_Get_Root(class) != NULL)
    {
	return Udb_Error(interp, "EROOTSET", argv[1], (char *)NULL);
    }

    if (!Uuid_Valid(argv[2]))
    {
	return Udb_Error(interp, "ENOTUUID", argv[2], (char *)NULL);
    }
    root_object = Udb_Find_Object(argv[2]);

    if (root_object == NULL)
    {
	return Udb_Error(interp, "ENXITEM", argv[2], (char *)NULL);
    }

    Udb_Set_Root(class, root_object);
    return TCL_OK;
}


static char *legal_action[] = {"Block", "Cascade", "Nullify", "Network", NULL};

/*
 * Get Relaction for the given attribute of the given class.
 * If to_class is given,  make sure it is a subclass of the attribute domain.
 */
char *
Udb_Get_Relaction(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    char      *attributeName
)
{
    char		*class_name;
    int			new;
    Tcl_HashEntry	*ePtr;
    Tcl_HashTable	*cTbl;
    Tcl_DString		dstr;
    char		*action;
    int			i;


    ePtr = Tcl_CreateHashEntry(&refintCache, (ClientData)class, &new);

    if (new)
    {
	cTbl = (Tcl_HashTable *)ckalloc(sizeof(Tcl_HashTable));
	Tcl_InitHashTable(cTbl, TCL_STRING_KEYS);
	Tcl_SetHashValue(ePtr, (ClientData)cTbl);
    }
    else
    {
	cTbl = (Tcl_HashTable *)Tcl_GetHashValue(ePtr);
    }

    ePtr = Tcl_CreateHashEntry(cTbl, attributeName, &new);

    if (!new)
    {
	return Tcl_GetHashValue(ePtr);
    }

    class_name = Udb_Get_Class_Name(class);

    Tcl_DStringInit(&dstr);
    Tcl_DStringAppend(&dstr, class_name, -1);
    Tcl_DStringAppend(&dstr, ".", -1);
    Tcl_DStringAppend(&dstr, attributeName, -1);

    check(action = Tcl_GetVar2(interp, "UNAMEIT_REF_INTEGRITY",
			       Tcl_DStringValue(&dstr), TCL_GLOBAL_ONLY));
    Tcl_DStringFree(&dstr);

    for (i = 0; legal_action[i] != NULL; ++i)
    {
	if (Equal(action, legal_action[i]))
	{
	    action = legal_action[i];
	    break;
	}
    }
    if (legal_action[i] == NULL)
    {
	panic("Illegal referential integrity action for %s.%s: %s",
	      class_name, attributeName, action);
    }
    Tcl_SetHashValue(ePtr, action);
    return action;
}


DB_OBJECT *
Udb_Current_Principal(void)
{
    return current_principal;
}


void
Udb_Server_Principal(void)
{
    current_principal = NULL;
}


int
/*ARGSUSED*/
Udb_PrincipalCmd(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    char *uuid;

    if (argc < 1 || argc > 2)
    {
	return Udb_Error(interp, "EUSAGE", argv[0], "?principal?",
			 (char *)NULL);
    }

    if (argc == 1)
    {
	/*
	 * Compute the uuid of the current principal
	 */
	if (current_principal)
	{
	    (void) Udb_Get_Uuid(current_principal, interp->result);
	}
    }
    else
    {
	DB_OBJECT *uuid_principal;
	uuid = argv[1];

	if (Equal(argv[1], ""))
	{
	    Udb_Server_Principal();
	    return TCL_OK;
	}

	if (!Uuid_Valid(argv[1]))
	{
	    return Udb_Error(interp, "ENOTUUID", uuid, (char *)NULL);
	}

	uuid_principal = Udb_Find_Object(uuid);
	if (uuid_principal == NULL)
	{
	    return Udb_Error(interp, "ENXITEM", uuid, (char *)NULL);
	}

	current_principal = uuid_principal;
    }
    return TCL_OK;
}


int
Udb_Class_Is_Readonly(Tcl_Interp *interp, DB_OBJECT *class)
{
    char *name = Udb_Get_Class_Name(class);

    return
	Tcl_GetVar2(interp, "UNAMEIT_CLASS_RO", name,
		    TCL_GLOBAL_ONLY) != NULL;
}


DB_OBJECT *
Udb_Get_Promoted_Owner(
    Tcl_Interp *interp,
    DB_OBJECT *owner,
    char *promotion_type
)
{
    assert(owner);
    assert(promotion_type);
    
    if (Equal(promotion_type, "Global"))
    {
	return Udb_Get_Root(CELL_CLASS);
    }
    if (Equal(promotion_type, "Org"))
    {
	return Udb_Get_Cell(interp, owner, NULL, 1);
    }
    if (Equal(promotion_type, "Cell"))
    {
	return Udb_Get_Cell(interp, owner, NULL, 0);
    }
    if (Equal(promotion_type, "Local"))
    {
	return owner;
    }
    if (!Equal(promotion_type, "None"))
    {
	panic("Bad promotion type %s", promotion_type);
    }
    return NULL;
}
