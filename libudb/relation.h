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
#ifndef _RELATION_H
#define _RELATION_H

/*
 * Check/reset referential integrity tables
 */
extern int Udb_Do_Reference_Checks(Tcl_Interp *interp);
extern void Udb_Reset_Reference_Checks(void);

/*
 * Check/reset loop tables
 */
extern int Udb_Do_Loop_Checks(Tcl_Interp *interp);
extern void Udb_Reset_Loop_Checks(void);

/*
 * Update relations from hash table of DB_VALUE pointers keyed by
 * attribute name.
 */
extern void Udb_Update_Relations(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    DB_OBJECT *object,
    Tcl_HashTable *relations,
    int new_object,
    int dont_loopcheck
);

/*
 * Do the work of deleting an object
 */
extern int Udb_Delete_Object(
    Tcl_Interp *interp,
    DB_OBJECT *class,
    const char *uuid,
    DB_OBJECT *object
);

#endif /* _RELATION_H */
