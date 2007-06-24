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
/* $Id: transaction.h,v 1.13 1997/05/28 23:19:52 viktor Exp $ */
#ifndef _TRANSACTION_H
#define _TRANSACTION_H
#include <dbi.h>
#include <tcl.h>

typedef enum {NORESTORE, RESTOREDATA, RESTORESCHEMA} RestoreMode;

/*
 * item_class NON-NULL iff template is for a 'unameit_item'
 */
extern DB_OBJECT *Udb_Finish_Object(
    DB_OBJECT *item_class,
    DB_OTMPL *template,
    int item_deleted
);

extern RestoreMode Udb_Restore_Mode(RestoreMode *new);
extern Tcl_CmdProc Udb_Syscall;
extern Tcl_CmdProc Udb_Transaction;
extern Tcl_CmdProc Udb_Version;

extern Tcl_CmdProc Udb_Rollback;
extern Tcl_CmdProc Udb_Commit;

extern void Udb_OpenLog(const char *logPrefix);
extern void Udb_CloseLog(void);

extern void Udb_Force_Rollback(Tcl_Interp *interp);
extern int Udb_Do_Rollback(Tcl_Interp *interp);
extern int Udb_Do_Commit(Tcl_Interp *interp, const char *logEntry);

#endif
