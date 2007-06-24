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
static char rcsid[] = "$Id: schema.c,v 1.26.14.5 1997/10/04 00:35:50 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>

#include "schema.h"
#include "lookup.h"
#include "errcode.h"
#include "transaction.h"
#include "metaproc.h"

/*
 * This code runs against a volatile schema.  Do not use
 * cached schema access functions from lookup.c
 */
#define UMETA_VERSION "2.0"

typedef enum
    {
	InstanceAttribute, ClassAttribute, SharedAttribute
    }
    AttributeType;

/*
 * Get attribute domain from schema stripped of any multiplicity
 */
static int
Pointer_Domain(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    char		*class_name;
    char		*attr_name;
    char		*result;
    DB_ATTRIBUTE	*attr_desc;
    DB_OBJECT		*class_obj;
    DB_TYPE		type;
    DB_DOMAIN		*domain;

    assert(interp);
    assert(argv);
    assert(argc >= 1);

    if (argc != 3)
    {
	panic("Illegal arguments for `%s'", argv[0]);
    }

    class_name = argv[1];
    attr_name = argv[2];
    
    check(class_obj = db_find_class(class_name));

    check(attr_desc = db_get_attribute(class_obj, attr_name));

    check(domain = db_attribute_domain(attr_desc));
    type = db_domain_type(domain);

    /*
     * If attribute is list valued get underlying element type.
     */
    switch (type)
    {
    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	check(domain = db_domain_set(domain));
	type = db_domain_type(domain);
	break;
    default:
	break;
    }
    /*
     * If attribute type is not DB_TYPE_OBJECT
     */
    if (type == DB_TYPE_OBJECT)
    {
	check(class_obj = db_domain_class(domain));
	result = (char *)db_get_class_name(class_obj);
	Tcl_SetResult(interp, result, TCL_VOLATILE);
    }
    return TCL_OK;
}


static int
Has_Index(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT   *class;
    DB_CONSTRAINT *index;

    assert(interp);
    check (argc == 2);
    
    check(class = db_find_class(argv[1]));
    index = db_get_constraints(class);

    while (index)
    {
	if (db_constraint_type(index) == DB_CONSTRAINT_INDEX)
	{
	    break;
	}
	index = db_constraint_next(index);
    }
    sprintf(interp->result, "%d", (index != NULL));
    return TCL_OK;
}


/*
 * Schema modification functions
 */
static int
Drop_Class(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT   *class;

    assert(interp);
    check (argc == 2);
    
    check(class = db_find_class(argv[1]));
    check (db_drop_class(class) == NOERROR);
    return TCL_OK;
}


static int
Add_Index(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT *class;

    assert(interp);
    assert (argc >= 3);

    check(class = db_find_class(*++argv));

    /*
     * argv[2] ... is NULL terminated list of instance attribute names
     */
    check(db_add_constraint(class, DB_CONSTRAINT_INDEX, (char *)NULL,
			     (const char **)++argv, 0) == NOERROR);

    /*
     * Mark database as updated
     */
    (void) Udb_Finish_Object(NULL, NULL, FALSE);

    return TCL_OK;
}


#if 0
static int
Cluster_Classes(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJLIST	*classlist;
    int		i;

    assert(interp && argc >= 3);

    ++argv, --argc;

    classlist = (DB_OBJLIST *)ckalloc(sizeof(*classlist) * argc);

    for (i = 0; i < argc; ++i)
    {
	classlist[i].op = db_find_class(argv[i]);
	classlist[i].next = &classlist[i+1];
    }
    classlist[argc-1].next = NULL;

    check(db_cluster(classlist) == NOERROR);

    ckfree((char *)classlist);

    return TCL_OK;
}
#endif


/*
 * The functions below use a static schema modification template to
 * edit the attributes of a class.
 */
static DB_CTMPL  *ctmpl = NULL;
static char	 *class_name;


static int
Create_Class(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    assert(interp);
    assert (argc == 2);

    check(ctmpl == NULL);

    class_name = ckalloc(strlen(argv[1]) + 1);
    (void) strcpy(class_name, argv[1]);
    
    check(ctmpl = dbt_create_class(argv[1]));
    return TCL_OK;
}


static int
Edit_Class(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    DB_OBJECT	*class;

    assert(interp);
    assert (argc == 2);

    check(ctmpl == NULL);

    check(class = db_find_class(argv[1]));
    class_name = ckalloc(strlen(argv[1]) + 1);
    (void) strcpy(class_name, argv[1]);

    check(ctmpl = dbt_edit_class(class));
    return TCL_OK;
}


static int
Add_Superclass(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT	*superclass;

    assert(interp);
    assert (argc == 2);
    
    check(superclass = db_find_class(argv[1]));
    check(dbt_add_super(ctmpl, superclass) == NOERROR);

    return TCL_OK;
}


static int
Drop_Superclass(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_OBJECT	*superclass;

    assert(interp);
    assert(argc == 2);

    check(superclass = db_find_class(argv[1]));
    check(dbt_drop_super(ctmpl, superclass) == NOERROR);

    return TCL_OK;
}


static int
Add_Attribute(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    char	*aname;
    char	*multiplicity;
    char	*domain;
    DB_VALUE	v;
    DB_COLLECTION *empty_set = NULL;

    assert(interp);
    assert(argc >= 4 && argc <= 5);

    check(ctmpl);

    aname = argv[1];
    multiplicity = argv[2];
    domain = argv[3];

    if (Equal(multiplicity, "Scalar"))
    {
	/*
	 * We only support explicit defaults
	 * for scalar string or integer attributes.
	 */
	char *defstring = argv[4];

	if (defstring == NULL)
	{
	    DB_MAKE_NULL(&v);
	}
	else
	{
	    switch (*defstring++)
	    {
	    case 'I':
		DB_MAKE_INTEGER(&v, 0);
		check(db_value_put(&v, DB_TYPE_C_CHAR,
				   defstring, strlen(defstring)) == NOERROR);
		break;

	    case 'S':
		DB_MAKE_STRING(&v, defstring);
		break;

	    default:
		DB_MAKE_STRING(&v, --defstring);
		break;
	    }
	}
    }
    else if (Equal(multiplicity, "Set"))
    {
	/*
	 * Sets default to empty value:
	 */
	assert (argc == 4);
	empty_set = db_col_create(DB_TYPE_SET, 0, NULL);
	DB_MAKE_COLLECTION(&v, empty_set);
    }
    else if (Equal(multiplicity, "Sequence"))
    {
	/*
	 * Sequences default to empty value:
	 */
	assert (argc == 4);
	empty_set = db_col_create(DB_TYPE_SEQUENCE, 0, NULL);
	DB_MAKE_COLLECTION(&v, empty_set);
    }
    else
    {
	panic("Illegal attribute multiplicity %s.%s = %s",
	      class_name, aname, multiplicity);
    }

    switch ((int)d)
    {
    case InstanceAttribute:
	check(dbt_add_attribute(ctmpl, aname, domain, &v) == NOERROR);
	break;

    case ClassAttribute:
	check(dbt_add_class_attribute(ctmpl, aname, domain, &v) == NOERROR);
	break;

    case SharedAttribute:
	check(dbt_add_shared_attribute(ctmpl, aname, domain, &v) == NOERROR);
	break;

    default:
	panic("Illegal Attribute type: %d", d);
	break;
    }

    if (empty_set != NULL)
    {
	/*
	 * Free any created empty set or sequence
	 */
	db_col_free(empty_set);
    }
    return TCL_OK;
}


static int
Rename_Attribute(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    assert(interp);
    check(argc == 3);

    check(ctmpl);

    check(dbt_rename(ctmpl, argv[1], (DB_INT32)0, argv[2]) == NOERROR);

    return TCL_OK;
}


static int
Drop_Attribute(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    assert(interp);
    assert (argc == 2);

    check(ctmpl);

    check(dbt_drop_attribute(ctmpl, argv[1]) == NOERROR);
    return TCL_OK;
}


static int
Constrain_Unique(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    assert(interp);
    assert (argc >= 3);

    check(ctmpl);

    /*
     * argv[1] is the constraint name
     * argv[2] ... is NULL terminated list of instance attribute names
     */
    check(dbt_add_constraint(ctmpl, DB_CONSTRAINT_UNIQUE, argv[1],
			     (const char **)&argv[2], 0) == NOERROR);

    /*
     * Mark database as updated
     */
    (void) Udb_Finish_Object(NULL, NULL, FALSE);

    return TCL_OK;
}


static int
Finish_Class(
    ClientData d,
    Tcl_Interp *interp,
    int argc,
    char *argv[]
)
{
    assert(interp);
    assert (argc == 1);

    check(ctmpl != NULL);
    check(dbt_finish_class(ctmpl) != NULL);
    ckfree(class_name);
    ctmpl = NULL;

    return TCL_OK;
}


int
Umeta_Init(Tcl_Interp *interp)
{
    char 	**procPtr;

    assert(interp);

    /*
     * Get domain (value class) of pointer attribute
     */
    Tcl_CreateCommand(interp, "umeta_pointer_domain", Pointer_Domain,
		      (ClientData)0, NULL);

    /*
     * Does class have any indexed attributes (UNIQUE constraints are not
     * considered)
     */
    Tcl_CreateCommand(interp, "umeta_has_index", Has_Index,
		      (ClientData)0, NULL);

    /*
     * Manipulate class objects
     */
    Tcl_CreateCommand(interp, "umeta_drop_class", Drop_Class,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "umeta_add_index", Add_Index,
		      NULL, NULL);
#if 0
    Tcl_CreateCommand(interp, "umeta_cluster", Cluster_Classes,
		      NULL, NULL);
#endif

    /*
     * Edit the schema of a class
     */
    Tcl_CreateCommand(interp, "umeta_create_class", Create_Class,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "umeta_edit_class", Edit_Class,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "umeta_add_superclass", Add_Superclass,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "umeta_drop_superclass", Drop_Superclass,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "umeta_add_attribute", Add_Attribute,
		      (ClientData)InstanceAttribute, NULL);
    Tcl_CreateCommand(interp, "umeta_add_class_attribute", Add_Attribute,
		      (ClientData)ClassAttribute, NULL);
    Tcl_CreateCommand(interp, "umeta_add_shared_attribute", Add_Attribute,
		      (ClientData)SharedAttribute, NULL);
    Tcl_CreateCommand(interp, "umeta_rename_attribute", Rename_Attribute,
		      (ClientData)0, NULL);
    Tcl_CreateCommand(interp, "umeta_drop_attribute", Drop_Attribute,
		      (ClientData)0, NULL);
    Tcl_CreateCommand(interp, "umeta_constrain_unique", Constrain_Unique,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "umeta_finish_class", Finish_Class,
		      NULL, NULL);

    for (procPtr = metaproc; *procPtr; ++procPtr)
    {
	if (Tcl_Eval(interp, *procPtr) != TCL_OK)
	{
	    return TCL_ERROR;
	}
    }

    Tcl_PkgProvide(interp, "Umeta", UMETA_VERSION);
    return TCL_OK;
}
