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
static char rcsid[] = "$Id: qbe.c,v 1.39.20.4 1997/10/11 00:55:15 viktor Exp $";

#include <uconfig.h>
#include <dbi.h>
#include <error.h>
#include <signal.h>

#include "uuid.h"
#include "convert.h"
#include "lookup.h"
#include "misc.h"
#include "tcl_mem.h"
#include "errcode.h"
#include "qbe.h"

/*
 * There are two different types of parse nodes. ATTR_NODEs are the
 * nodes used for regular comparison tuples. QBE_NODEs are used for nested
 * QBEs. The top level node is always a QBE node.
 */
typedef enum ParseNodeType {ATTR_NODE, QBE_NODE} ParseNodeType;

/*
 * A parse tree node.
 */
typedef struct ParseNode {
    struct ParseNode	*next;		/* Next sibling */
    ParseNodeType	node_type;
    char		*aname;		/* Attribute name */
    unsigned		column;		/* SQL column of value */
    /*
     * The following fields aren't used for ATTR_NODEs
     */
    DB_OBJECT		*class;		/* NULL unless known a priori */
    int			all;		/* Does query span subclasses */
    struct ParseNode 	*children;	/* Linked list of children */
    unsigned		column_count;	/* Total columns for this subtree */
} ParseNode, *ParseNodePtr;

/*
 * Initial size of push array if not NULL
 */
#define PUSH_ARRAY_SZ 8

typedef struct qbe_context {
	Tcl_Interp	*interp;
	Tcl_DString	spart;
	Tcl_DString	fpart;
	Tcl_DString	wpart;
	int		class_counter;
	int		oidOnly;
	int		delFlag;
	ParseNodePtr	parseTree;
	/*
	 * Pointer to array of db_values
	 * holding values for "?" placeholders in query.
	 * Used in db_push_values() call.
	 */
	DB_VALUE	*pushList;
	int		pushMaxElems;
	int		pushNumElems;
} QBE_Context;

/* Frees a parse tree. */
static void Free_Tree(ParseNodePtr parseNode);

/*
 * Adds a child to a parse tree node.
 * !!!: Parent's column count should
 * be incremented only after the child (and recursively its subnodes)
 * have been initialized.
 */
static ParseNodePtr Create_Sub_Node(
    ParseNodePtr parentNode,
    char	 *aname,
    int		 *new
);

/*
 * Recursively constructs a query string
 */
static int 
Construct_Query(
    QBE_Context *qbe_ctx,
    char *path_prefix,
    ParseNodePtr parseNode,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    int  spec_argc,
    char **spec_argv
);

/*
 * Constructs the expression part of a query. Recursively calls
 * Construct_Query if the "qbe" operator is used.
 */
static int Add_Expression(
    QBE_Context *qbe_ctx,
    char *path_prefix,
    ParseNodePtr parseNode,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    char *qbe_spec
);

/*
 * This routine handle filling in the `where' part of the SLQ/X query
 * for all operators other than qbe and any.
 */
static int Handle_Other_Operators(
    QBE_Context *qbe_ctx,
    char *path_prefix,
    DB_DOMAIN *domain,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    char *qbe_spec,
    int  spec_argc,
    char **spec_argv
);


static void
Free_PushList(QBE_Context *qbe_ctx)
{
    int i;

    for (i = 0; i < qbe_ctx->pushNumElems; ++i)
    {
	DB_VALUE *value = &qbe_ctx->pushList[i];
	if (DB_IS_NULL(value)) continue;
	switch (DB_VALUE_DOMAIN_TYPE(value))
	{
	case DB_TYPE_OBJECT:
	case DB_TYPE_INTEGER:
	    /*
	     * No storage to reclaim
	     */
	    break;
	case DB_TYPE_STRING:
	    /*
	     * Free string literal
	     */
	    ckfree(DB_GET_STRING(value));
	    break;
	case DB_TYPE_SET:
	case DB_TYPE_SEQUENCE:
	    /*
	     * Free set and contents
	     */
	    db_col_free(DB_GET_COLLECTION(value));
	    break;
	default:
	    panic("Illegal data type: %s",
		  db_get_type_name(DB_VALUE_DOMAIN_TYPE(value)));
	    break;
	}
    }
    ckfree((char *)qbe_ctx->pushList);
}


static void
Free_QBE_Context(QBE_Context *qbe_ctx)
{
    assert(qbe_ctx);

    Free_Tree(qbe_ctx->parseTree);

    Tcl_DStringFree(&qbe_ctx->spart);

    if (qbe_ctx->pushList)
    {
	Free_PushList(qbe_ctx);
    }

    ckfree((char *)qbe_ctx);
}


static void
Vappend(Tcl_DString *buf, ...)
{
    va_list 	ap;
    char	*s;

    va_start(ap, buf);
    while ((s = va_arg(ap, char *)) != NULL)
    {
	Tcl_DStringAppend(buf, s, -1);
    }
    va_end(ap);
}


static void
Add_Constraint(Tcl_DString *buf, ...)
{
    va_list 	ap;
    char	*s;

    assert(buf);

    if (Tcl_DStringLength(buf) == 0)
    {
	Tcl_DStringAppend(buf, " where ", -1);
    }
    else
    {
	Tcl_DStringAppend(buf, " and ", -1);
    }

    va_start(ap, buf);
    while ((s = va_arg(ap, char *)) != NULL)
    {
	Tcl_DStringAppend(buf, s, -1);
    }
    va_end(ap);
}


/*
 * Append from and where parts to select part of query
 */
static void
Combine_Query_Parts(QBE_Context *qbe_ctx)
{
    char	*select_buf;
    int		select_len;
    char	*from_buf;
    int		from_len;
    char	*where_buf;
    int		where_len;

    /*
     * Compute lengths before we enlarge select buffer.
     */
    select_len = Tcl_DStringLength(&qbe_ctx->spart);
    from_len   = Tcl_DStringLength(&qbe_ctx->fpart);
    where_len  = Tcl_DStringLength(&qbe_ctx->wpart);

    /*
     * Enlarge select buffer,  this may reallocate it,
     * so get the address *after* enlarging the buffer.
     */
    Tcl_DStringSetLength(&qbe_ctx->spart, select_len + from_len + where_len);

    select_buf = Tcl_DStringValue(&qbe_ctx->spart);
    from_buf   = Tcl_DStringValue(&qbe_ctx->fpart);
    where_buf  = Tcl_DStringValue(&qbe_ctx->wpart);

    /*
     * Use memcpy to insert from and where clauses *into* expanded select
     * buffer.  Tcl_DStringAppend would append *after* expanded buffer!
     */
    (void) memcpy(select_buf + select_len, from_buf, from_len);
    (void) memcpy(select_buf + select_len + from_len, where_buf, where_len);

    /*
     * Free from and where parts,  they are no longer needed.
     */
    Tcl_DStringFree(&qbe_ctx->fpart);
    Tcl_DStringFree(&qbe_ctx->wpart);

    /*
     * Make it a harmless (though still a) mistake,
     * to use the from and where parts again.
     */
    Tcl_DStringInit(&qbe_ctx->fpart);
    Tcl_DStringInit(&qbe_ctx->wpart);
}


static QBE_Context *
New_QBE_Context(
    Tcl_Interp	*interp,
    int		existsOnly,
    int		allFlag,
    int		delFlag,
    int		oidOnly,
    char	*qbe_cname,
    int		spec_argc,
    char	**spec_argv
)
{
    QBE_Context	*qbe_ctx;
    DB_OBJECT   *qbe_class;
    int		ok;

    assert(interp);
    assert(allFlag == TRUE || allFlag == FALSE);
    assert(delFlag == TRUE || delFlag == FALSE);
    assert(oidOnly == TRUE || oidOnly == FALSE);
    assert(qbe_cname);
    assert(spec_argc >= 0 && spec_argv);

    if ((qbe_class = _Udb_Get_Class(qbe_cname)) == NULL ||
	!Udb_Is_Item_Class(qbe_class))
    {
	(void) Udb_Error(interp, "ENXCLASS", qbe_cname, (char *)NULL);
	return NULL;
    }

    if (existsOnly)
    {
	oidOnly = TRUE;
    }

    qbe_ctx = (QBE_Context *)ckalloc(sizeof(QBE_Context));

    qbe_ctx->interp = interp;
    qbe_ctx->class_counter = 1;

    qbe_ctx->parseTree = (ParseNodePtr)ckalloc(sizeof(ParseNode));
    qbe_ctx->parseTree->next = NULL;
    qbe_ctx->parseTree->node_type = QBE_NODE;
    qbe_ctx->parseTree->aname = NULL;
    qbe_ctx->parseTree->column = 0;
    qbe_ctx->parseTree->class = qbe_class;
    qbe_ctx->parseTree->all = allFlag;
    qbe_ctx->parseTree->children = NULL;
    qbe_ctx->parseTree->column_count = (oidOnly == FALSE) ? 2 : 1;

    qbe_ctx->pushList = NULL;
    qbe_ctx->oidOnly = oidOnly;
    qbe_ctx->delFlag = delFlag;

    Tcl_DStringInit(&qbe_ctx->spart);
    Tcl_DStringInit(&qbe_ctx->fpart);
    Tcl_DStringInit(&qbe_ctx->wpart);

    if (existsOnly)
    {
	Vappend(&qbe_ctx->spart,
		"select 1 from class unameit_item where exists(", /*)*/
		(char *)NULL);
    }

    Vappend(&qbe_ctx->spart,
	    "select c#0", (oidOnly == FALSE) ? ", c#0.uuid" : "",
	    (char *)NULL);

    Vappend(&qbe_ctx->fpart, (allFlag == TRUE) ? " from all \"" : " from \"",
	    qbe_cname, "\" c#0", (char *)NULL);

    if (delFlag == FALSE)
    {
	Add_Constraint(&qbe_ctx->wpart,
		       "c#0.\"deleted\" IS NULL", (char *)NULL);
    }

    ok = Construct_Query(qbe_ctx, "c#0", qbe_ctx->parseTree,
			 qbe_class, qbe_cname, spec_argc, spec_argv);

    Combine_Query_Parts(qbe_ctx);

    if (existsOnly)
    {
	Vappend(&qbe_ctx->spart, /*(*/ ")", (char *)NULL);
    }

    if (ok != TCL_OK)
    {
	Free_QBE_Context(qbe_ctx);
	qbe_ctx = NULL;
    }

    return qbe_ctx;
}


static QBE_Context *
Nested_QBE_Context(
    QBE_Context *parentContext,
    char	*path_prefix,
    int		allFlag,
    int		needSelector,
    DB_OBJECT	*qbe_class,
    char	*qbe_cname,
    int		spec_argc,
    char	**spec_argv
)
{
    char	var1[64];
    char	var2[64];
    int		class_counter;
    QBE_Context	*qbe_ctx;
    int		ok;

    assert(parentContext);
    assert(path_prefix);
    assert(allFlag == TRUE || allFlag == FALSE);
    assert(needSelector == TRUE || needSelector == FALSE);
    assert(qbe_class && qbe_cname);
    assert(spec_argc >= 0 && spec_argv);

    qbe_ctx = (QBE_Context *)ckalloc(sizeof(QBE_Context));
    /*
     * Nested selects are used only in the "where" clause,
     * so we keep the column count to a minimum
     */
    qbe_ctx->oidOnly = TRUE;

    qbe_ctx->interp = parentContext->interp;
    qbe_ctx->delFlag = parentContext->delFlag;
    /*
     * Must update parent when done.
     */
    qbe_ctx->pushList = parentContext->pushList;
    qbe_ctx->pushMaxElems = parentContext->pushMaxElems;
    qbe_ctx->pushNumElems = parentContext->pushNumElems;
    class_counter = parentContext->class_counter;

    qbe_ctx->parseTree = (ParseNodePtr)ckalloc(sizeof(ParseNode));
    qbe_ctx->parseTree->next = NULL;
    qbe_ctx->parseTree->node_type = QBE_NODE;
    qbe_ctx->parseTree->aname = NULL;
    qbe_ctx->parseTree->column = 0;
    qbe_ctx->parseTree->class = qbe_class;
    qbe_ctx->parseTree->all = allFlag;
    qbe_ctx->parseTree->children = NULL;
    qbe_ctx->parseTree->column_count = needSelector ? 1 : 2;

    Tcl_DStringInit(&qbe_ctx->spart);
    Tcl_DStringInit(&qbe_ctx->fpart);
    Tcl_DStringInit(&qbe_ctx->wpart);

    sprintf(var1, "c#%d", class_counter);
    sprintf(var2, "c#%d", ++class_counter);

    Vappend(&qbe_ctx->spart, "select ", var2, (char *)NULL);

    Vappend(&qbe_ctx->fpart, " from table(", path_prefix, ")"
	    " as ", var1, "(", var2, ")", (char *)NULL);

    if (needSelector == FALSE)
    {
	path_prefix = var2;
    }
    else
    {
	sprintf(var1, "c#%d", ++class_counter);
	path_prefix = var1;

	Vappend(&qbe_ctx->spart, ", ", var2, "[", var1, "].uuid",
		(char *)NULL);

	Vappend(&qbe_ctx->fpart, (allFlag) ? ", all \"" : ", \"",
		qbe_cname, "\" ", var1, (char *)NULL);
    }

    qbe_ctx->class_counter = ++class_counter;

    ok = Construct_Query(qbe_ctx, path_prefix, qbe_ctx->parseTree,
			 qbe_class, qbe_cname, spec_argc, spec_argv);

    Combine_Query_Parts(qbe_ctx);

    /*
     * Update class_counter and pushList of parent QBE context
     */
    parentContext->class_counter = qbe_ctx->class_counter;
    parentContext->pushList = qbe_ctx->pushList;
    parentContext->pushMaxElems = qbe_ctx->pushMaxElems;
    parentContext->pushNumElems = qbe_ctx->pushNumElems;
    /*
     * We give the push list back to the parent context,
     * make it NULL here,  so as not to free it with the nested context.
     */
    qbe_ctx->pushList = NULL;

    if (ok != TCL_OK)
    {
	/*
	 * Note: we have to (and did) give the pushList back to the parent
	 * before freeing the nested context!
	 */
	Free_QBE_Context(qbe_ctx);
	qbe_ctx = NULL;
    }

    return qbe_ctx;
}


static DB_COLLECTION *
Convert_List(
    QBE_Context *qbe_ctx,
    DB_DOMAIN *domain,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    char *aname,
    char *qbe_spec,
    char *list
)
{
    DB_COLLECTION	*col;
    DB_DOMAIN		*elem_domain;
    DB_TYPE		elem_type;
    DB_OBJECT		*elem_class = NULL;
    int			elem_argc;
    char		**elem_argv;
    DB_INT32		index;
    DB_VALUE		value;
    DB_OBJECT		*item;

    /*
     * Convert Tcl list to free collection
     */
    if (Tcl_SplitList(NULL, list, &elem_argc, &elem_argv) != TCL_OK)
    {
	(void) Udb_Error(qbe_ctx->interp, "EQBENOTSET", qbe_cname, aname,
			 list, qbe_spec, (char *)NULL);
	return NULL;
    }

    check(col = db_col_create(db_domain_type(domain), elem_argc, domain));

    elem_domain = db_domain_set(domain);

    if ((elem_type = db_domain_type(elem_domain)) == DB_TYPE_OBJECT)
    {
	elem_class = db_domain_class(elem_domain);
    }

    for(index = 0; index < elem_argc; ++index)
    {
	char *elem = elem_argv[index];

	switch(elem_type)
	{
	case DB_TYPE_INTEGER:
	    if (Udb_String_To_Int32_Value(&value, elem) != NOERROR ||
		DB_IS_NULL(&value))
	    {
		db_col_free(col);
		(void) Udb_Error(qbe_ctx->interp, "EQBENOTINT", qbe_cname,
				 aname, elem, qbe_spec, (char *)NULL);
		ckfree((char *)elem_argv);
		return NULL;
	    }
	    break;

	case DB_TYPE_STRING:
	    DB_MAKE_STRING(&value, elem);
	    break;

	case DB_TYPE_OBJECT:
	    /*
	     * Convert UUID to object and validate domain
	     */
	    if (!Uuid_Valid(elem))
	    {
		db_col_free(col);
		(void) Udb_Error(qbe_ctx->interp, "EQBENOTUUID",
				 qbe_cname, aname,
				 elem, qbe_spec, (char *)NULL);
		ckfree((char *)elem_argv);
		return NULL;
	    }

	    item = _Udb_Find_Object(elem);

	    if (item == NULL)
	    {
		db_col_free(col);
		(void) Udb_Error(qbe_ctx->interp, "EQBENXITEM",
				 qbe_cname, aname,
				 elem, qbe_spec, (char *)NULL);
		ckfree((char *)elem_argv);
		return NULL;
	    }
	    /*
	     * UniSQL/X 3.x will not do queries which look for
	     * objects with an incompatible domain
	     */
	    if (!Udb_ISA(db_get_class(item), elem_class))
	    {
		const char *elem_cname = Udb_Get_Class_Name(elem_class);

		db_col_free(col);
		(void) Udb_Error(qbe_ctx->interp, "EQBEDOMAIN",
				 elem, elem_cname, qbe_spec, (char *)NULL);
		ckfree((char *)elem_argv);
		return NULL;
	    }
	    DB_MAKE_OBJECT(&value, item);
	    break;
	    
	default:
	    panic("Illegal set element data type: %s",
		  db_get_type_name(elem_type));
	    break;
	}
	check(db_col_add(col, &value) == NOERROR);
    }
    ckfree((char *)elem_argv);
    return col;
}


static void
Push_Value(QBE_Context *qbe_ctx, DB_VALUE *value)
{
    size_t newsize;

    if (qbe_ctx->pushList == NULL)
    {
	qbe_ctx->pushNumElems = 0;
	newsize = (qbe_ctx->pushMaxElems = PUSH_ARRAY_SZ);

	qbe_ctx->pushList = (DB_VALUE *)
	    ckalloc(newsize * sizeof(DB_VALUE));
    }
    if (qbe_ctx->pushNumElems >= qbe_ctx->pushMaxElems)
    {
	newsize = (qbe_ctx->pushMaxElems += (qbe_ctx->pushMaxElems >> 1) + 1);

	qbe_ctx->pushList = (DB_VALUE *)
	    ckrealloc((char *)qbe_ctx->pushList, newsize * sizeof(DB_VALUE));
    }
    qbe_ctx->pushList[qbe_ctx->pushNumElems++] = *value;
}


static void
Push_Glob(QBE_Context *qbe_ctx, char *s) 
{
    Tcl_DString	dstr;
    DB_VALUE	value;
    char 	*p;
    char	*copy;
    int		backslashed;
    
    assert(qbe_ctx);
    assert(s);

    Tcl_DStringInit(&dstr);

    for (p = s, backslashed = 0; *p; p++)
    {
	switch (*p)
	{
	case '_':
	    Tcl_DStringAppend(&dstr, "\\_", -1);
	    backslashed = 0;
	    break;
	case '*':
	    Tcl_DStringAppend(&dstr, backslashed ? "*" : "%", -1);
	    backslashed = 0;
	    break;
	case '%':
	    Tcl_DStringAppend(&dstr, "\\%", -1);
	    backslashed = 0;
	    break;
	case '?':
	    Tcl_DStringAppend(&dstr, backslashed ? "?" : "_", -1);
	    backslashed = 0;
	    break;
	case '\\':
	    if (backslashed)
	    {
		Tcl_DStringAppend(&dstr, "\\\\", -1);
	    }
	    backslashed = ~backslashed;
	    break;
	default:
	    Tcl_DStringAppend(&dstr, p, 1);
	    backslashed = 0;
	}
    }
    /*
     * Treat a trailing backslash as literal
     */
    if (backslashed)
    {
	Tcl_DStringAppend(&dstr, "\\\\", -1);
    }

    copy = ckalloc(Tcl_DStringLength(&dstr)+1);
    strcpy(copy, Tcl_DStringValue(&dstr));
    Tcl_DStringFree(&dstr);

    DB_MAKE_STRING(&value, copy);
    Push_Value(qbe_ctx, &value);
}

/*
 * Recursively constructs a query string
 */
static int 
Construct_Query(
    QBE_Context *qbe_ctx,
    char *path_prefix,
    ParseNodePtr parseNode,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    int spec_argc,
    char **spec_argv
)
{
    int		i;

    assert(qbe_ctx && qbe_ctx->interp);
    assert(path_prefix);
    assert(parseNode);
    assert(qbe_class && qbe_cname);
    assert(spec_argc >= 0 && spec_argv);

    if (spec_argc == 1 && Equal(spec_argv[0], "*"))
    {
	DB_ATTRIBUTE *attrs;
	/*
	 * Return all fields
	 */
	for (attrs = db_get_attributes(qbe_class); attrs;
	     attrs = db_attribute_next(attrs))
	{
	    char	*aname =  (char *)db_attribute_name(attrs);
	    DB_DOMAIN	*domain = Udb_Attribute_Domain(qbe_class, aname);
	    /*
	     * Don't return unprintable and protected fields
	     */
	    if (!Udb_Attribute_Is_Printable(domain) ||
		Udb_Attr_Is_Protected(qbe_ctx->interp, aname))
	    {
		continue;
	    }
	    if (Add_Expression(qbe_ctx, path_prefix, parseNode,
			       qbe_class, qbe_cname, aname) != TCL_OK)
	    {
		return TCL_ERROR;
	    }
	}
    }
    else
    {
	/*
	 * Process each attribute specification in turn
	 */
	for (i = 0; i < spec_argc; ++i)
	{
	    if (Add_Expression(qbe_ctx, path_prefix, parseNode,
			       qbe_class, qbe_cname, spec_argv[i]) != TCL_OK)
	    {
		return TCL_ERROR;
	    }
	}
    }
    return TCL_OK;
}


static int Add_Expression(
    QBE_Context *qbe_ctx,
    char *path_prefix,
    ParseNodePtr parseNode,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    char *qbe_spec
)
{
    int			spec_argc;
    char		**spec_argv;
    char		*aname;
    char		*operator;
    DB_TYPE		attr_type;
    DB_TYPE		elem_type = DB_TYPE_NULL;
    DB_OBJECT		*domain_class = NULL;
    DB_OBJECT		*sub_class;
    DB_DOMAIN		*domain;
    DB_DOMAIN		*elem_domain;
    int			need_selector;
    int			nested_all = FALSE;
    Tcl_DString		new_path_prefix;
    ParseNodePtr	sub_node;
    int			new_node;

    assert(qbe_ctx && qbe_ctx->interp);
    assert(path_prefix);
    assert(parseNode);
    assert(qbe_class && qbe_cname);
    assert(qbe_spec);

    if (Tcl_SplitList(NULL, qbe_spec, &spec_argc, &spec_argv) != TCL_OK)
    {
	(void) Udb_Error(qbe_ctx->interp, "EQBEPARSE", qbe_spec, (char *)NULL);
	return TCL_ERROR;
    }

    if (spec_argc < 1)
    {
	ckfree((char *)spec_argv);
	(void) Udb_Error(qbe_ctx->interp, "EQBEPARSE", qbe_spec, (char *)NULL);
	return TCL_ERROR;
    }

    aname = spec_argv[0];

    if ((domain = Udb_Attribute_Domain(qbe_class, aname)) == NULL ||
	!Udb_Attribute_Is_Printable(domain))
    {
	(void) Udb_Error(qbe_ctx->interp, "ENOATTR",
			 qbe_cname, aname, (char *)NULL);
	ckfree((char *)spec_argv);
	return TCL_ERROR;
    }

    switch(attr_type = db_domain_type(domain))
    {
    case DB_TYPE_OBJECT:
	check((domain_class = db_domain_class(domain)) != NULL);
	break;

    case DB_TYPE_INTEGER:
    case DB_TYPE_STRING:
	break;

    case DB_TYPE_SET:
    case DB_TYPE_SEQUENCE:
	check((elem_domain = db_domain_set(domain)) != NULL);
	switch(elem_type = db_domain_type(elem_domain))
	{
	case DB_TYPE_OBJECT:
		domain_class = db_domain_class(elem_domain);
		break;
	case DB_TYPE_INTEGER:
	case DB_TYPE_STRING:
		break;
	default:
	    panic("unknown type SET_OF %s for class %s attribute %s",
		  db_get_type_name(elem_type), qbe_cname, aname);
	}
	break;

    default:
	panic("Unsupported type %s for class %s attribute %s",
	      db_get_type_name(attr_type), qbe_cname, aname);
    }

    operator = spec_argv[1];

    if (operator && Equal(operator, "qbe"))
    {
	char *sub_cname;
	int  sub_spec_argc;
	char **sub_spec_argv;
	char selector[32];

	/*
	 * aname qbe ?-all? class ?spec? ...
	 */
	if (spec_argc < 3)
	{
syntax:
	    ckfree((char *)spec_argv);
	    return Udb_Error(qbe_ctx->interp, "EQBEPARSE",
			     qbe_spec, (char *)NULL);
	}
	sub_cname = spec_argv[2];
	sub_spec_argc = spec_argc-3;
	sub_spec_argv = spec_argv+3;

	if (Equal(sub_cname, "-all"))
	{
	    if (spec_argc < 4)
		goto syntax;

	    nested_all = TRUE;
	    sub_cname = spec_argv[3];
	    --sub_spec_argc;
	    ++sub_spec_argv;
	}

	/*
	 * We can only do QBE on objects or sets of objects.
	 */
	switch (attr_type)
	{
	case DB_TYPE_OBJECT:
	    break;

	case DB_TYPE_SET:
	case DB_TYPE_SEQUENCE:
	    if (elem_type == DB_TYPE_OBJECT)
		break;
	    /* FALLTHROUGH */

	default:
	    (void) Udb_Error(qbe_ctx->interp, "EOPINVAL",
			     qbe_cname, aname, operator,
			     (char *)NULL);
	    ckfree((char *)spec_argv);
	    return TCL_ERROR;
	}

	if (Equal(sub_cname, ""))
	{
	    /*
	     * The empty sub_class means use domain of attribute
	     */
	    sub_class = domain_class;
	    sub_cname = Udb_Get_Class_Name(sub_class);
	    need_selector = FALSE;
	}
	else
	{
	    /*
	     * Otherwise we need selector variable to constrain to subclass
	     * but first lets make sure it is a subclass.
	     */
	    if ((sub_class = _Udb_Get_Class(sub_cname)) == NULL)
	    {
		(void) Udb_Error(qbe_ctx->interp, "ENXCLASS",
				 sub_cname, (char *)NULL);
		ckfree((char *)spec_argv);
		return TCL_ERROR;
	    }
	    if (!Udb_ISA(sub_class, domain_class))
	    {
		const char *domain_name = Udb_Get_Class_Name(domain_class);

		(void) Udb_Error(qbe_ctx->interp, "ENOTSUBCLASS",
				 sub_cname, domain_name,
				 qbe_spec, (char *)NULL);
		ckfree((char *)spec_argv);
	        return TCL_ERROR;
	    }
	    need_selector = TRUE;
	}

	sub_node = Create_Sub_Node(parseNode, aname, &new_node);

	if (!new_node)
	{
	    /*
	     * Multiple QBE specs for the same attribute do not make
	     * sense,  or need to be merged.
	     */
	    ckfree((char *)spec_argv);
	    return Udb_Error(qbe_ctx->interp, "EQBECONFLICT",
			     qbe_cname, aname, qbe_spec, (char *)NULL);
	}

	/*
	 * Initialize QBE node
	 * Set valued nodes look like ATTR_NODEs,  since they print as
	 * as set field,  not as a subtree.
	 */
	if (attr_type == DB_TYPE_OBJECT)
	{
	    sub_node->node_type = QBE_NODE;
	    if (qbe_ctx->oidOnly == FALSE)
		sub_node->column_count = 2;
	    else
		sub_node->column_count = (need_selector ? 1 : 0);
	}
	else
	{
	    sub_node->node_type = ATTR_NODE;
	    if (qbe_ctx->oidOnly == FALSE)
		sub_node->column_count = 1;
	    else
		sub_node->column_count = 0;
	}

	sub_node->class = sub_class;
	sub_node->all = (!need_selector || nested_all);

	Tcl_DStringInit(&new_path_prefix);

	if (attr_type == DB_TYPE_OBJECT && need_selector)
	{
	    (void)sprintf(selector, "c#%d", qbe_ctx->class_counter++);
	    Tcl_DStringAppend(&new_path_prefix, selector, -1);
	}
	else
	{
	    /*
	     * Just append the attribute to the path expression
	     */
	    Vappend(&new_path_prefix, path_prefix, ".\"", aname, "\"",
		    (char *)NULL);
	}
	if (qbe_ctx->oidOnly == FALSE)
	{
	    Vappend(&qbe_ctx->spart, ", ", Tcl_DStringValue(&new_path_prefix),
		    (char *)NULL);
	}

	if (attr_type == DB_TYPE_OBJECT)
	{	
	    /*
	     * Normally our path expressions will just be:
	     * top_class.attr1.attr2. ...
	     *
	     * Selector variables require us to introduce a new `from' class,
	     * use top_class.attr1[x].attr2, x.attr3, ....
	     * for some as yet unused SQL/X identifier.
	     * The new identifier becomes the path prefix for all nodes below
	     * this node.
	     */
	    if (need_selector == TRUE)
	    {	
		/*
		 * Add ", ?all? <sub_class> <selector>"
		 * to from_part of query
		 */
		Vappend(&qbe_ctx->fpart, (nested_all) ? ", all \"" : ", \"",
			sub_cname, "\" ", selector, (char *)NULL);

		/*
		 * Add ", path_prefix.<aname>[selector].uuid"
		 * to select part
		 */
		Vappend(&qbe_ctx->spart, ", ", path_prefix, ".\"", aname,
			"\"[", selector, "].uuid", (char *)NULL);
	    }
	    else if (qbe_ctx->oidOnly == FALSE)
	    {
		/*
		 * Add ", new_path_prefix.uuid"
		 * to select part
		 */
		Vappend(&qbe_ctx->spart, ", ",
			Tcl_DStringValue(&new_path_prefix), ".uuid",
			(char *)NULL);
	    }
	    if (Construct_Query(qbe_ctx, Tcl_DStringValue(&new_path_prefix),
				sub_node, sub_class, sub_cname,
				sub_spec_argc, sub_spec_argv) != TCL_OK)
	    {
		Tcl_DStringFree(&new_path_prefix);
		ckfree((char *)spec_argv);
		return TCL_ERROR;
	    }
	}
	else
	{
	    QBE_Context *nested_ctx;

	    /*
	     * Build nested select statement
	     */
	    nested_ctx = Nested_QBE_Context(qbe_ctx,
					    Tcl_DStringValue(&new_path_prefix),
					    nested_all, need_selector,
					    sub_class, sub_cname,
					    sub_spec_argc, sub_spec_argv);

	    if (nested_ctx == NULL)
	    {
		Tcl_DStringFree(&new_path_prefix);
		ckfree((char *)spec_argv);
		return TCL_ERROR;
	    }

	    /*
	     * Use "exists(<nested query>)" as "where" clause
	     * for this attribute
	     */
	    Add_Constraint(&qbe_ctx->wpart,
		"exists (", Tcl_DStringValue(&nested_ctx->spart), ")",
		(char *)NULL);
	    Free_QBE_Context(nested_ctx);
	}
	Tcl_DStringFree(&new_path_prefix);
    }
    else
    {
	sub_node = Create_Sub_Node(parseNode, aname, &new_node);

	if (new_node)
	{
	    /*
	     * Arrange to retrieve the field unless we only want
	     * the object ids from the QBE
	     */
	    if (qbe_ctx->oidOnly == FALSE)
	    {
		Vappend(&qbe_ctx->spart, ", ",
			path_prefix, ".\"", aname, "\"", (char *)NULL);
		/*
		 * Initialize ATTR node
		 */
		sub_node->node_type = ATTR_NODE;
		sub_node->column_count = 1;
	    }
	    else
	    {
		sub_node->node_type = ATTR_NODE;
		sub_node->column_count = 0;
	    }
	}
	else
	{
	    if (sub_node->node_type != ATTR_NODE)
	    {
		/*
		 * All nodes for this attributes must be non-QBE nodes
		 */
		ckfree((char *)spec_argv);
		return Udb_Error(qbe_ctx->interp, "EQBECONFLICT",
				 qbe_cname, aname, qbe_spec, (char *)NULL);
	    }
	}

	/*
	 * For the "any" operator, don't append anything to the "where"
	 * clause so just return.
	 */
	if (!operator || Equal(operator, "any"))
	{
	    if (spec_argc > 2)
	    {
		ckfree((char *)spec_argv);
		return Udb_Error(qbe_ctx->interp, "EQBEPARSE",
				 qbe_spec, (char *)NULL);
	    }
	}
	else if (Equal(operator, "contains"))
	{
	    DB_COLLECTION *col;
	    DB_VALUE value;

	    if (spec_argc < 3)
	    {
		goto syntax;
	    }
	    switch (attr_type)
	    {
	    case DB_TYPE_SET:
	    case DB_TYPE_SEQUENCE:
		break;
	    default:
		ckfree((char *)spec_argv);
		return Udb_Error(qbe_ctx->interp, "EOPINVAL", qbe_cname, aname,
				 operator, (char *)NULL);
	    }
	    col = Convert_List(qbe_ctx, domain, qbe_class, qbe_cname,
			       aname, qbe_spec, spec_argv[2]);

	    if (col == NULL)
	    {
		ckfree((char *)spec_argv);
		return TCL_ERROR;
	    }
	    DB_MAKE_COLLECTION(&value, col);
	    Push_Value(qbe_ctx, &value);

	    Add_Constraint(&qbe_ctx->wpart,
			   "CAST (", path_prefix, ".\"", aname, "\" AS SET)"
			   " SUPERSETEQ CAST(? AS SET)", (char *)NULL);
	}
	else
	{
	    if (Handle_Other_Operators(qbe_ctx, path_prefix, domain,
				       qbe_class, qbe_cname, qbe_spec,
				       spec_argc, spec_argv) != TCL_OK)
	    {
		ckfree((char *)spec_argv);
		return TCL_ERROR;
	    }
	}
    }

    if (new_node)
    {
	parseNode->column_count += sub_node->column_count;
    }
    ckfree((char *)spec_argv);
    return TCL_OK;
}


static void
Free_Tree(ParseNodePtr parseNode) 
{
    ParseNodePtr child;
    ParseNodePtr next;

    for (child = parseNode->children; child; child = next)
    {
	ckfree(child->aname);
	next = child->next;
	Free_Tree(child);
    }
    ckfree((char *)parseNode);
}


static ParseNodePtr
Create_Sub_Node(ParseNodePtr parentNode, char *aname, int *new)
{
    ParseNodePtr lastNode = NULL;
    ParseNodePtr newNode;
    ParseNodePtr child;

    for(child = parentNode->children; child; child = child->next)
    {
	if (Equal(child->aname, aname))
	{
	    *new = FALSE;
	    return child;
	}
	lastNode = child;
    }

    *new = TRUE;
    newNode = (ParseNodePtr)ckalloc(sizeof(ParseNode));
    newNode->next = NULL;
    strcpy(newNode->aname = ckalloc(strlen(aname)+1), aname);
    newNode->column = parentNode->column + parentNode->column_count;
    newNode->children = NULL;

    if (lastNode)
    {
	return lastNode->next = newNode;
    }
    return parentNode->children = newNode;
}

static int
Handle_Other_Operators(
    QBE_Context *qbe_ctx,
    char *path_prefix,
    DB_DOMAIN *domain,
    DB_OBJECT *qbe_class,
    char *qbe_cname,
    char *qbe_spec,
    int	 spec_argc,
    char **spec_argv
)
{
    DB_VALUE	value;
    DB_TYPE	type;
    char	*copy;
    DB_OBJECT   *item;
    char	*aname;
    char	*operator;
    char	*strval;

    assert(qbe_ctx && qbe_ctx->interp);
    assert(path_prefix);
    assert(domain);
    assert(qbe_class && qbe_cname);
    assert(qbe_spec && spec_argc >= 2 && spec_argv);

    aname = spec_argv[0];
    operator = spec_argv[1];
    strval = spec_argv[2] ? spec_argv[2] : "";
    type = db_domain_type(domain);

    assert(aname);
    assert(operator);

    if (Equal(operator, "=") || Equal(operator, "!="))
    {
	DB_COLLECTION *col;

	if (spec_argc != 2 && spec_argc != 3)
	{
	    return Udb_Error(qbe_ctx->interp, "EQBEPARSE",
			     qbe_spec, (char *)NULL);
	}
	
	if (strval[0] == '\0')
	{
	    switch (type)
	    {
	    case DB_TYPE_STRING:
		if (spec_argc != 2)
		    break;
		/* FALLTHROUGH */
	    case DB_TYPE_INTEGER:
	    case DB_TYPE_OBJECT:
		Add_Constraint(&qbe_ctx->wpart, 
		    path_prefix, ".\"", aname,
		    Equal(operator, "=") ? "\" IS NULL" : "\" IS NOT NULL",
		    (char *)NULL);
		return TCL_OK;
	    default:
		break;
	    }
	}
	/*
	 * Convert to SQL syntax for inequality operator
	 */
	if (Equal(operator, "!="))
	{
	    operator = "<>";
	}

	switch (type)
	{
	case DB_TYPE_INTEGER:
	    /*
	     * Use SQL/X string to integer function,  to make
	     * sure value is acceptable to the database.
	     */
	    if (Udb_String_To_Int32_Value(&value, strval) != NOERROR)
	    {
		return Udb_Error(qbe_ctx->interp, "EQBENOTINT",
				 qbe_cname, aname,
				 strval, qbe_spec, (char *)NULL);
	    }
	    Push_Value(qbe_ctx, &value);
	    break;

	case DB_TYPE_STRING:
	    if (strval[0] == '\0')
	    {
		if (Equal(operator, "="))
		{
		    Add_Constraint(&qbe_ctx->wpart, "(",
			path_prefix, ".\"", aname, "\" = '' OR ", 
			path_prefix, ".\"", aname, "\" IS NULL"
			")", (char *)NULL);
		}
		else
		{
		    Add_Constraint(&qbe_ctx->wpart, "(",
			path_prefix, ".\"", aname, "\" <> '' AND ", 
			path_prefix, ".\"", aname, "\" IS NOT NULL"
			")", (char *)NULL);
		}
		return TCL_OK;
	    }

	    /*
	     * Push string literal and add "?" to query
	     */
	    copy = ckalloc(strlen(strval)+1);
	    strcpy(copy, strval);
	    DB_MAKE_STRING(&value, copy);
	    Push_Value(qbe_ctx, &value);
	    break;

	case DB_TYPE_OBJECT:
	    /*
	     * Convert UUID to object and validate domain
	     */
	    if (!Uuid_Valid(strval))
	    {
		return Udb_Error(qbe_ctx->interp, "EQBENOTUUID",
				 qbe_cname, aname,
				 strval, qbe_spec, (char *)NULL);
	    }

	    item = _Udb_Find_Object(strval);

	    if (item == NULL)
	    {
		return Udb_Error(qbe_ctx->interp, "EQBENXITEM",
				 qbe_cname, aname,
				 strval, qbe_spec, (char *)NULL);
	    }
	    /*
	     * UniSQL/X 3.x will not do queries which look for objects
	     * with an incompatible domain
	     */
	    if (!Udb_ISA(db_get_class(item), db_domain_class(domain)))
	    {
		DB_OBJECT	*domain_class;
		const char	*domain_cname;

		check(domain_class = db_domain_class(domain));
		domain_cname = Udb_Get_Class_Name(domain_class);

		return Udb_Error(qbe_ctx->interp, "EQBEDOMAIN",
				 strval, domain_cname, qbe_spec, (char *)NULL);
	    }
	    /*
	     * Add item to push list and add "?" to query spec
	     * OIDs cannot directly be put into SQL queries
	     */
	    DB_MAKE_OBJECT(&value, item);
	    Push_Value(qbe_ctx, &value);
	    break;

	case DB_TYPE_SET:
	case DB_TYPE_SEQUENCE:
	    col = Convert_List(qbe_ctx, domain, qbe_class, qbe_cname,
			       aname, qbe_spec, strval);
	    if (col == NULL)
	    {
		return TCL_ERROR;
	    }
	    DB_MAKE_COLLECTION(&value, col);
	    Push_Value(qbe_ctx, &value);
	    break;

	default:
	    return Udb_Error(qbe_ctx->interp, "EOPINVAL",
			     qbe_cname, aname, operator, (char *)NULL);
	}
    }
    else if (Equal(operator, "<") ||
	     Equal(operator, ">") ||
	     Equal(operator, ">=") ||
	     Equal(operator, "<="))
    {
	if (spec_argc != 3)
	{
	    return Udb_Error(qbe_ctx->interp, "EQBEPARSE",
			     qbe_spec, (char *)NULL);
	}
	switch (type)
	{
        case DB_TYPE_INTEGER:
	    /*
	     * Use SQL/X string to integer function,  to make
	     * sure value is acceptable to the database.
	     */
	    if (Udb_String_To_Int32_Value(&value, strval) != NOERROR ||
		DB_IS_NULL(&value))
	    {
		return Udb_Error(qbe_ctx->interp, "EQBENOTINT",
				 qbe_cname, aname,
				 strval, qbe_spec, (char *)NULL);
	    }
	    Push_Value(qbe_ctx, &value);
	    break;

	case DB_TYPE_STRING:
	    /*
	     * Push string literal and add "?" to query
	     */
	    copy = ckalloc(strlen(strval)+1);
	    strcpy(copy, strval);
	    DB_MAKE_STRING(&value, copy);
	    Push_Value(qbe_ctx, &value);
	    break;

	default:
	    return Udb_Error(qbe_ctx->interp, "EOPINVAL", qbe_cname, aname,
			     operator, (char *)NULL);
	}
    }
    else if (Equal(operator, "~") || Equal(operator, "!~"))
    {
	/*
	 * Need a string argument and a string valued attribute
	 */
	if (spec_argc != 3)
	{
	    return Udb_Error(qbe_ctx->interp, "EQBEPARSE",
			     qbe_spec, (char *)NULL);
	}
	if (type != DB_TYPE_STRING)
	{
	    return Udb_Error(qbe_ctx->interp, "EOPINVAL",
			     qbe_cname, aname, operator, (char *)NULL);
	}

	Push_Glob(qbe_ctx, strval);

	Add_Constraint(&qbe_ctx->wpart, 
	    path_prefix, ".\"", aname, 
	    Equal(operator, "~") ?
		"\" LIKE ? ESCAPE '\\'" :
		"\" NOT LIKE ? ESCAPE '\\'", (char *)NULL);

	return TCL_OK;
    }
    else
    {	
	/*
 	 * Bad operator
	 */
	return Udb_Error(qbe_ctx->interp, "EQBEPARSE", qbe_spec, (char *)NULL);
    }
    /*
     * Generic binary operator constraint
     */
    Add_Constraint(&qbe_ctx->wpart, 
	path_prefix, ".\"", aname, "\" ", operator, " ?", (char *)NULL);
    return TCL_OK;
}


static int
Parse_Args(
    Tcl_Interp *interp,
    int *argc,
    char ***argv, 
    int *checkSyntax,
    int *timeOut,
    int *maxRows,
    int *all,
    int *nameFields,
    int *streamFlag,
    int *delFlag,
    int *oidOnly
)
{
    char *argv0 = **argv;

    *timeOut = 0;
    *maxRows = -1;
    *checkSyntax = *all = *nameFields =
	*streamFlag = *delFlag = *oidOnly = FALSE;

    /*
     * Skip over command name (arg_index starts at 1)
     */
    ++(*argv);
    --(*argc);

    for (; *argc > 0; ++(*argv), --(*argc))
    {
	if (Equal(**argv, "-syntax"))
	{
	    *checkSyntax = TRUE;
	}
	else if (Equal(**argv, "-timeOut"))
	{
	    ++(*argv);
	    --(*argc);
	    if (*argc == 0)
	    {
	    syntax_error:
		return Udb_Error(interp, "EUSAGE", argv0,
		    "?-syntax? ?-timeOut n? ?-maxRows n? ?-all? ?-nameFields?"
		    "?-stream? ?-deleted? ?-oidOnly? class ?constraint? ...",
		    (char *)NULL);
	    }
	    if (Tcl_GetInt(interp, **argv, timeOut) != TCL_OK)
	    {
		return TCL_ERROR;
	    }
	}
	else if (Equal(**argv, "-maxRows"))
	{
	    ++(*argv);
	    --(*argc);
	    if (*argc == 0)
	    {
		goto syntax_error;
	    }
	    if (Tcl_GetInt(interp, **argv, maxRows) != TCL_OK)
	    {
		return TCL_ERROR;
	    }
	}
	else if (Equal(**argv, "-all"))
	{
	    *all = TRUE;
	}
	else if (Equal(**argv, "-nameFields"))
	{
	    *nameFields = TRUE;
	}
	else if (Equal(**argv, "-stream"))
	{
	    *streamFlag = TRUE;
	}
	else if (Equal(**argv, "-deleted"))
	{
	    *delFlag = TRUE;
	}
	else if (Equal(**argv, "-oidOnly"))
	{
	    *oidOnly = TRUE;
	}
	else
	{
	    break;
	}
    }
    if (*argc <= 0)
    {
	goto syntax_error;
    }
    return TCL_OK;
}


static int
Traverse_Tree(
    Tcl_HashTable *streamTbl,
    Tcl_DString   *streamResult,
    DB_QUERY_RESULT *query_cursor,
    ParseNodePtr parseNode,
    DB_OBJECT *parentObject,
    int nameFields,
    int oidOnly
)
{
    char	new_uuid[UDB_UUID_SIZE];
    DB_OBJECT	*new_object, *class;
    DB_VALUE    colvalue;
    ParseNodePtr child;

    db_query_get_tuple_value(query_cursor, parseNode->column, &colvalue);

    /*
     * The subtree could be NULL (outer join semantics of path expressions)
     */
    if (DB_IS_NULL(&colvalue))
    {
	check(parentObject != NULL);
	check(parseNode->aname != NULL);
	Udb_Store_Value(streamTbl, parentObject, parseNode->aname, &colvalue);
	return TCL_OK;
    }

    /*
     * The object pointer is first in the query cursor
     */
    check(DB_VALUE_DOMAIN_TYPE(&colvalue) == DB_TYPE_OBJECT);
    new_object = DB_GET_OBJECT(&colvalue);

    if (oidOnly == TRUE)
    {
	Tcl_DStringAppendElement(streamResult, Udb_Get_Oid(new_object, NULL));
	return TCL_OK;
    }

    /*
     * Store the class if known
     */
    if (parseNode->all == FALSE)
    {
	DB_VALUE classValue;
	if (nameFields)
	{
	    /*
	     * We may not have all the name fields, do delayed fetch.
	     * This will check whether we in fact have them, just prior
	     * to actually fetching the object.
	     */
	    Udb_Delay_Fetch(streamTbl, new_object);
	}
	/*
	 * If query does not span subclasses,  use statically known class
	 * and possibly avoid the overhead of fetching the object
	 */
	class = parseNode->class;
	DB_MAKE_OBJECT(&classValue, class);
	Udb_Store_Value(streamTbl, new_object, NULL, &classValue);
    }
    else
    {
	DB_VALUE classValue;
	/*
	 * We do not know the class, do delayed fetch
	 */
	Udb_Delay_Fetch(streamTbl, new_object);
	DB_MAKE_NULL(&classValue);
	Udb_Store_Value(streamTbl, new_object, NULL, &classValue);
    }

    /*
     * Next is the uuid
     */
    db_query_get_tuple_value(query_cursor, parseNode->column+1, &colvalue);
    strncpy(new_uuid, DB_GET_STRING(&colvalue) , sizeof(new_uuid));
    check(new_uuid[sizeof(new_uuid)-1] == '\0');

    /*
     * !!!: Must store UUID after calling Udb_Delay_Fetch.
     * Udb_Delay_Fetch ignores objects with known UUIDs
     */
    Udb_Store_Value(streamTbl, new_object, "uuid", &colvalue);

    /*
     * Release uuid storage back to database workspace
     */
    db_value_clear(&colvalue);

    /*
     * Set parent attribute after storing our uuid,  so we do not
     * do unnecesarry Delay fetch processing
     */
    if (!parentObject)
    {
	/*
	 * These are the matching objects.
	 */
	Tcl_DStringAppendElement(streamResult, new_uuid);
    } else {
	/*
	 * Otherwise record uuid in appropriate attribute of parent node
	 */
	check(parseNode->aname != NULL);
	/*
	 * Construct a value container for storing object in the
	 * appropriate parent attribute
	 */
	DB_MAKE_OBJECT(&colvalue, new_object);
	Udb_Store_Value(streamTbl, parentObject, parseNode->aname, &colvalue);
    }

    /*
     * Process subnodes
     */
    for (child = parseNode->children; child; child = child->next)
    {
	if (child->node_type == QBE_NODE)
	{
	    (void) Traverse_Tree(streamTbl, streamResult, query_cursor,
				 child, new_object, nameFields, FALSE);
	}
	else
	{
	    DB_VALUE value;
	    db_query_get_tuple_value(query_cursor, child->column, &value);
	    Udb_Store_Value(streamTbl, new_object, child->aname, &value);
	    db_value_clear(&value);
	}
    }
    return TCL_OK;
}

static int queryTimedOut;

static void
TimeoutQuery(int sig)
{
    queryTimedOut = TRUE;
    db_set_interrupt(1);
}
	
/*
 * Implementation of user visible Tcl udb_qbe command.
 */
int  
Udb_Query_By_Example(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    DB_SESSION		*sess_id;
    STATEMENT_ID	stmt_id;
    DB_QUERY_RESULT	*query_cursor;
    DB_ERROR 		rowcount;
    DB_ERROR 		rowerr;
    DB_INT32		query_colcount;
    char		*query;
    char		*cname;
    Tcl_DString		streamResult;
    Tcl_HashTable	streamTbl;
    /*
     * Integer flags / options
     */
    void		(*oldsig)(int sig) = NULL;
    int			checkSyntax;
    int			timeOut;
    int			maxRows;
    int			all;
    int			nameFields;
    int			streamFlag;
    int			delFlag;
    int			oidOnly;
    int			ok;
    /*
     * Query compilation context: NULL if error.
     */
    QBE_Context		*qbe_ctx;
    int			retcode = TCL_OK;

    assert(interp && argc >= 1 && argv);

    ok = Parse_Args(interp, &argc, &argv, &checkSyntax, &timeOut, &maxRows,
		    &all, &nameFields, &streamFlag, &delFlag, &oidOnly);

    if (ok != TCL_OK)
    {
	return TCL_ERROR;
    }

    cname = argv[0];
    ++argv, --argc;

    qbe_ctx = New_QBE_Context(interp, maxRows == 0, all, delFlag, oidOnly,
			      cname, argc, argv);

    if (qbe_ctx == NULL)
    {
	return TCL_ERROR;
    }

    if (checkSyntax)
    {
	if (qbe_ctx->pushList)
	{
	    int i;
	    Tcl_DStringInit(&streamResult);
	    for (i = 0; i < qbe_ctx->pushNumElems; ++i)
	    {
		DB_VALUE	*value = &qbe_ctx->pushList[i];
		DB_COLLECTION	*col;
		DB_INT32	index;
		DB_INT32	col_size;
		DB_DOMAIN	*domain;

		if (DB_IS_NULL(value)) continue;
		switch (DB_VALUE_DOMAIN_TYPE(value))
		{
		case DB_TYPE_OBJECT:
		    Udb_Stringify_Value(&streamResult, value);
		    break;
		case DB_TYPE_SET:
		case DB_TYPE_SEQUENCE:
		    col = DB_GET_COLLECTION(value);
		    col_size = db_col_size(col);
		    check(domain = db_col_domain(col));
		    check(domain = db_domain_set(domain));
		    if (db_domain_type(domain) != DB_TYPE_OBJECT)
		    {
			break;
		    }
		    for (index = 0; index < col_size; ++index)
		    {
			DB_VALUE	elem_value;

			Udb_Get_Collection_Value(col, index, DB_TYPE_OBJECT,
						 &elem_value);
			Udb_Stringify_Value(&streamResult, &elem_value);
		    }
		    break;

		default:
		    break;
		}
	    }
	    Tcl_DStringResult(interp, &streamResult);
	}
	Free_QBE_Context(qbe_ctx);
	return TCL_OK;
    }

    query = Tcl_DStringValue(&qbe_ctx->spart);

    sess_id = db_open_buffer(query);

    if (qbe_ctx->pushList)
    {
	db_push_values(sess_id, qbe_ctx->pushNumElems, qbe_ctx->pushList);
    }

    if ((stmt_id = db_compile_statement(sess_id)) < 0)
    {
	panic("Could not compile SQL/X statement: %s", query);
    }

    if (timeOut > 0)
    {
	queryTimedOut = FALSE;
	oldsig = signal(SIGALRM, TimeoutQuery);
	alarm(timeOut);
    }

    rowcount = db_execute_statement(sess_id, stmt_id, &query_cursor);

    if (timeOut > 0)
    {
	alarm(0);
	signal(SIGALRM, oldsig);
	if (queryTimedOut == TRUE)
	{
	    db_set_interrupt(0);
	    Free_QBE_Context(qbe_ctx);
	    if (rowcount >= 0)
	    {
		db_query_end(query_cursor);
	    }
	    db_close_session(sess_id);
	    return Udb_Error(interp, "EQBETIMEOUT", (char *)NULL);
	}
    }

    if (rowcount < 0)
    {
	panic("Could not execute SQL/X statement: %s", query);
    }

    if (maxRows != -1)
    {
	if (rowcount > maxRows)
	{
	    Free_QBE_Context(qbe_ctx);
	    db_query_end(query_cursor);
	    db_close_session(sess_id);
	    return Udb_EROWCOUNT(interp, rowcount, maxRows);
	}
    }

    if (rowcount == 0)
    {
	Free_QBE_Context(qbe_ctx);
	db_query_end(query_cursor);
	db_close_session(sess_id);
	return TCL_OK;
    }

    Tcl_DStringInit(&streamResult);
    if (streamFlag)
    {
	Tcl_DStringAppendElement(&streamResult, "result");
	Tcl_DStringStartSublist(&streamResult);
	Tcl_DStringAppendElement(&streamResult, "qbe");
	Tcl_DStringStartSublist(&streamResult);
    }

    check((query_colcount = db_query_column_count(query_cursor)) > 0);

    if (oidOnly == FALSE)
    {
	Tcl_InitHashTable(&streamTbl, TCL_ONE_WORD_KEYS);
    }

    for (rowerr = db_query_first_tuple(query_cursor);
	 rowerr == DB_CURSOR_SUCCESS;
	 rowerr = db_query_next_tuple(query_cursor))
    {
	ok = Traverse_Tree(oidOnly == FALSE ? &streamTbl : NULL, &streamResult,
			   query_cursor, qbe_ctx->parseTree, NULL,
			   nameFields, oidOnly);
	if (ok != TCL_OK)
	{
	    Free_QBE_Context(qbe_ctx);
	    db_query_end(query_cursor);
	    db_close_session(sess_id);
	    Tcl_DStringFree(&streamResult);
	    if (oidOnly == FALSE)
	    {
		Udb_Delete_Stream_Table(&streamTbl);
	    }
	    return TCL_ERROR;
	}
	--rowcount;
    }
    db_query_end(query_cursor);
    db_close_session(sess_id);
    Free_QBE_Context(qbe_ctx);
    check (rowcount == 0);

    if (streamFlag)
    {
	Tcl_DStringEndSublist(&streamResult);
	Tcl_DStringEndSublist(&streamResult);
    }
    Tcl_DStringResult(interp, &streamResult);

    if (oidOnly == FALSE)
    {
	retcode = Udb_Stream_Encode(interp, &streamTbl, nameFields,
				    streamFlag, delFlag);
	Udb_Delete_Stream_Table(&streamTbl);
    }
    return retcode;
}
