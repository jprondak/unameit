/*
 * Copyright (c) 1996 Enterprise Systems Management Corp.
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
/* $Id: convert.h,v 1.2 1996/07/26 12:54:37 viktor Exp $ */
#ifndef _CONVERT_H
#define _CONVERT_H
#include <dbi.h>
#include <tcl.h>

/*
 * Convert string to DB_INT32 DB_VALUE,  empty string -> NULL value.
 * Error codes from db_value_put()
 */
extern DB_ERROR Udb_String_To_Int32_Value(DB_VALUE *valPtr, char *input);

/*
 * Convert string to DB_INT32, returns TCL_OK on success
 * empty string or non integer returns TCL_ERROR,  if interp is not NULL,
 * leaves an error message in interp->result.
 */
extern int Udb_String_To_Int32(
    Tcl_Interp *interp,
    char *input,
    DB_INT32 *intPtr
);

/*
 * Convert *NON NULL* DB_VALUE to string form, and append as a DString element
 */
extern void Udb_Stringify_Value(Tcl_DString *string, DB_VALUE *value);

/*
 * Sets an attribute in an object. An edit object template containing the 
 * changes to be applied to the object will be filled in on return. The
 * class of the original object is needed to check the attribute type.
 * 	The topology modification list is appended to on return. It is
 * allocated with malloc and should be freed when done.
 * Returns TCL_OK on success, TCL_ERROR if an error.
 */

extern int Udb_Set_Attribute(
    Tcl_Interp *interp,
    char *uuid,
    DB_OBJECT *object,
    DB_OTMPL *template,
    char *aname,
    char *input,
    Tcl_HashTable *relations
);
#endif
