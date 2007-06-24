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
/* $Id: error.h,v 1.4 1996/06/26 01:06:42 viktor Exp $ */
#ifndef _ERROR_H
#define _ERROR_H
#include <stdarg.h>

/*
   There are two kinds integrity checks: "assertions" and
   "checks". "Assertions" are integrity errors in the logic of the code and
   should never occur. They can be compiled out of the code using the
   -DNDEBUG flag. "Checks" are checks that must be true but may not be due
   to database errors such as schema configuration errors or errors with the
   database. In either case, about the only appropriate behavior is for the
   server to exit.
*/
/* The following macro is only used when it is clear from the macro what the
   problem is. If it isn't clear, then a statement of the form

       if (check) {
           panic(...);
       }

   is used instead.

   Tcl calls panic() when it encounters fatal errors,  this will
   call the procedure specified by Tcl_SetPanicProc(),
   it prints to stderr by default.  We substitute Unameit_Panic().
*/
#define check(ex) {\
    if (!(ex)) { \
        panic("Check failed: file \"%s\", line %d", rcsid, __LINE__); \
     } \
}

typedef void err_func_t(
    int exitcode,		/* 0 == don't exit */
    int priority,
    const char *fmt,
    va_list arg
);

extern void Unameit_Panic(const char *fmt, ...);
extern void Unameit_ePanic(const char *fmt, ...);
extern void Unameit_Complain(const char *fmt, ...);
extern void Unameit_eComplain(const char *fmt, ...);
extern void panic(const char *fmt, ...);
/*
 * Define procs that actually output the error message,
 * typically to stderr,  or via syslog.
 */
extern void Unameit_Set_Error_Funcs(err_func_t *f, err_func_t *ef);

#endif
