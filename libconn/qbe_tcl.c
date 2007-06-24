/*
 * Copyright (c) 1995, 1996, 1997 Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: qbe_tcl.c,v 1.16.10.4 1997/09/21 23:42:27 viktor Exp $";

#include <uconfig.h>

#include <setjmp.h>
#include <radix.h>

#define UQBE_VERSION "2.0"

/*
 * Need to be static,  since qsort does not let us pass additional state
 */
static Tcl_Interp	*sortInterp;
static Tcl_HashTable 	comparison_cache;
static jmp_buf		regs;

/*
 * Comparison function for qsort()
 */
static int
compare_uuids(const void *u1, const void *u2)
{
    char	*uuid1 = *(char **)u1;
    char	*uuid2 = *(char **)u2;
    char	*c1;
    char	*c2;
    Tcl_DString sbuf;
    char	*nattrs;
    int		na_argc;
    char	**na_argv;
    int		i;
    int		new;

#define UUID_FLAGS (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
#define META_FLAGS TCL_LEAVE_ERR_MSG

    c1 = Tcl_GetVar2(sortInterp, uuid1, "Class", UUID_FLAGS);
    c2 = Tcl_GetVar2(sortInterp, uuid2, "Class", UUID_FLAGS);

    if (c1 == NULL || c2 == NULL)
    {
      do_longjmp:
	longjmp(regs, 1);
    }

    nattrs = Tcl_GetVar2(sortInterp, "anames", c1, META_FLAGS);

    if (nattrs == NULL)
    {
	goto do_longjmp;
    }

    /*
     * If classes don't have the same name attributes,
     * we compare the class names only
     */
    if (strcmp(c1, c2) != 0)
    {
    	int	class_cmp;
	char	*nattrs2;
	
	nattrs2 = Tcl_GetVar2(sortInterp, "anames", c2, META_FLAGS);
	if (nattrs2 == NULL)
	{
	    goto do_longjmp;
	}
	if ((class_cmp = strcmp(nattrs, nattrs2)) != 0)
	{
	    return class_cmp;
	}
    }

    if (Tcl_SplitList(sortInterp, nattrs, &na_argc, &na_argv) != TCL_OK)
    {
	goto do_longjmp;
    }

    for (i=0; i < na_argc; ++i)
    {
	char	*type;
	char	*a1;
	char	*a2;
	int	a_cmp = 0;

	type = Tcl_GetVar2(sortInterp, "atype", na_argv[i], META_FLAGS);
	if (type == NULL)
	{
	    ckfree((char *)na_argv);
	    goto do_longjmp;
	}

	a1 = Tcl_GetVar2(sortInterp, uuid1, na_argv[i], UUID_FLAGS);
	a2 = Tcl_GetVar2(sortInterp, uuid2, na_argv[i], UUID_FLAGS);

	if (a1 == NULL || a2 == NULL)
	{
	    ckfree((char *)na_argv);
	    goto do_longjmp;
	}

	if (Equal(type, "String"))
	{
	    a_cmp = strcmp(a1, a2);
	}
	else if (Equal(type, "Integer"))
	{
	    int i1;
	    int i2;

	    if (Tcl_GetInt(sortInterp, a1, &i1) != TCL_OK ||
		Tcl_GetInt(sortInterp, a2, &i2) != TCL_OK)
	    {
		ckfree((char *)na_argv);
		goto do_longjmp;
	    }
	    a_cmp = (i1 - i2);
	}
	else if (Equal(type, "Object"))
	{
	    /*
	     * If uuids are equal or either is empty, strcmp yields the
	     * right result.  If not equal, sign used in building key in
	     * comparison cache below.
	     *
	     * Though NULL UUIDS should not normally arise in name attributes,
	     * this is not the place to object!
	     */
	    a_cmp = strcmp(a1, a2);

	    if (a_cmp != 0 && *a1 && *a2)
	    {
		Tcl_HashEntry	*ePtr;
		int		reverse_result = FALSE;

		Tcl_DStringInit(&sbuf);

		/* Sort uuids and see if it is in the hash table. */
		if (a_cmp > 0)
		{
		    Tcl_DStringAppend(&sbuf, a2, -1);
		    Tcl_DStringAppend(&sbuf, a1, -1);
		    reverse_result = TRUE;
		}
		else
		{
		    Tcl_DStringAppend(&sbuf, a1, -1);
		    Tcl_DStringAppend(&sbuf, a2, -1);
		}

		ePtr = Tcl_CreateHashEntry(&comparison_cache,
					   Tcl_DStringValue(&sbuf), &new);
		Tcl_DStringFree(&sbuf);
		
		if (new == 0)
		{
		    a_cmp = (int)Tcl_GetHashValue(ePtr);
		    if (reverse_result)
		    {
			a_cmp = -a_cmp;
		    }
		}
		else
		{
		    char a1_copy[UDB_UUID_SIZE], a2_copy[UDB_UUID_SIZE];
		    (void)strcpy(a1_copy, a1);
		    (void)strcpy(a2_copy, a2);
		    a1 = a1_copy;
		    a2 = a2_copy;
		    a_cmp = compare_uuids(&a1, &a2);
		    /*
		     * XXX: assume ClientData can hold a small int
		     * and not lose its sign
		     */
		    Tcl_SetHashValue(ePtr, (ClientData)(reverse_result ?
							-a_cmp : a_cmp));
		}
	    }
	}
	if (a_cmp != 0)
	{
	    ckfree((char *)na_argv);
	    return a_cmp;
	}
    }
    ckfree((char *)na_argv);
    return 0;
}


int
/* ARGSUSED */
Sort_Items(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    char *list;
    char **split_argv;
    int  split_argc;

    if (argc != 2)
    {
	Tcl_AppendResult(interp, "usage: ", argv[0], " item_list", (char *)0);
	return TCL_ERROR;
    }

    if (Tcl_SplitList(interp, argv[1], &split_argc, &split_argv) != TCL_OK)
    {
	return TCL_ERROR;
    }
    
    sortInterp = interp;

    Tcl_InitHashTable(&comparison_cache, TCL_STRING_KEYS);

    if (setjmp(regs) != 0)
    {
	ckfree((char *)split_argv);
	Tcl_DeleteHashTable(&comparison_cache);
	return TCL_ERROR;
    }

    qsort(split_argv, split_argc, sizeof(char *), compare_uuids);

    Tcl_DeleteHashTable(&comparison_cache);

    list = Tcl_Merge(split_argc, split_argv);

    Tcl_SetResult(interp, list, TCL_DYNAMIC);
    ckfree((char *)split_argv);

    return TCL_OK;
}


int
Decode_Items(ClientData d, Tcl_Interp *interp, int argc, char *argv[])
{
    char 	*argv0 = argv[0];
    int  	qbe_argc;
    char 	**qbe_argv;
    int  	elem_argc;
    char 	**elem_argv;
    int  	i;
    int  	global = 0;
    char	*cache_list = NULL;
    int  	noclobber = FALSE;
    char 	*result_uuid = NULL;
    Tcl_DString	sbuf;

    ++argv; --argc;

    while (argc > 0 && argv[0][0] == '-')
    {
	if (Equal(&argv[0][1], "global"))
	{
	    ++argv; --argc;
	    global |= TCL_GLOBAL_ONLY;
	}
	else if (Equal(&argv[0][1], "noclobber"))
	{
	    ++argv; --argc;
	    noclobber = TRUE;
	}
	else if (Equal(&argv[0][1], "result"))
	{
	    ++argv; --argc;
	    result_uuid = "result";
	}
	else if (Equal(&argv[0][1], "cache_list"))
	{
	    ++argv; --argc;
	    if (argc == 0)
	    {
		goto usage;
	    }
	    cache_list = *argv;
	    argv++, argc--;
	}
	else
	{
	    goto usage;
	}
    }

    if (argc != 1)
    {
      usage:
	Tcl_AppendResult(interp, "usage: ", argv0,
	    " ?-global? ?-noclobber? ?-result? ?-cache_list variable? data",
			 (char *)NULL);
	return TCL_ERROR;
    }

    Tcl_DStringInit(&sbuf);

    if (Tcl_SplitList(interp, argv[0], &qbe_argc, &qbe_argv) != TCL_OK)
    {
	goto err_free0;
    }
    if (qbe_argc & 1)
    {
	goto err_free1;
    }

    for (i=0; i < qbe_argc; ++i)
    {
	char *uuid = qbe_argv[i];
	char *data = qbe_argv[++i];
	int field;

	if (Tcl_SplitList(interp, data, &elem_argc, &elem_argv) != TCL_OK)
	{
	    goto err_free1;
	}

	if (elem_argc & 1)
	{
	    goto err_free2;
	}

	if (result_uuid && Equal(uuid, result_uuid))
	{
	    if (elem_argc != 2)
	    {
		goto err_free2;
	    }
	    Tcl_DStringAppend(&sbuf, elem_argv[1], -1);
	    ckfree((char *)elem_argv);
	    continue;
	}

	if (cache_list)
	{
	    if (!Tcl_SetVar2(interp, cache_list, uuid, "1", global))
	    {
		ckfree((char *)elem_argv);
		ckfree((char *)qbe_argv);
		Tcl_DStringFree(&sbuf);
		return TCL_ERROR;
	    }
	}

	for (field = 0; field < elem_argc; ++field)
	{
	    register char *name = elem_argv[field];
	    register char *val = elem_argv[++field];

	    if (noclobber && Tcl_GetVar2(interp, uuid, name, global))
	    {
		continue;
	    }

	    if (Tcl_SetVar2(interp, uuid, name, val,
			    global|TCL_LEAVE_ERR_MSG) == NULL)
	    {
		ckfree((char *)elem_argv);
		ckfree((char *)qbe_argv);
		Tcl_DStringFree(&sbuf);
		return TCL_ERROR;
	    }
	}
	ckfree((char *)elem_argv);
    }
    ckfree((char *)qbe_argv);

    Tcl_DStringResult(interp, &sbuf);

    return TCL_OK;

err_free2:
    ckfree((char *)elem_argv);
err_free1:
    ckfree((char *)qbe_argv);
err_free0:
    Tcl_DStringFree(&sbuf);
    Tcl_SetResult(interp, "Malformed reply from server", TCL_STATIC);
    Tcl_SetErrorCode(interp, "UNAMEIT", "EQBEDECODE", (char *)NULL);
    return TCL_ERROR;
}

int
Uqbe_Init(Tcl_Interp *interp)
{
    int	result;

    assert(interp);

    Tcl_CreateCommand(interp, "unameit_decode_items", Decode_Items,
		      NULL, NULL);
    Tcl_CreateCommand(interp, "unameit_sort_items", Sort_Items, 
		      NULL, NULL);
    if ((result = Tcl_PkgProvide(interp, "Uqbe", UQBE_VERSION)) != TCL_OK)
    {
	return result;
    }

    return TCL_OK;
}
