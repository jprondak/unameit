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
#ifndef _auth_h_
#define _auth_h_

/*
 * $Id: auth.h,v 1.2.20.1 1997/08/28 18:26:38 viktor Exp $
 *
 * Authorization routines, used with routines in libconn/auth.c
 */
#include <uconfig.h>
#include <conn.h>

/* Current version of the Auth module. */
#define AUTH_NAME "Auth"
#define AUTH_VERSION "2.0"

/* Key used to store address of exported functions. */
#define AUTH_MASTER_FUNCTIONS_KEY "UName*It_AuthFunctions"

/* Error reporting uses the following code. */
#define AUTH_ERROR "AUTH"

/*
 * The following strings are used by authorization modules to indicate
 * that authenticating clients are the same principal as the server,
 * in which case they will be changed to the builtin UName*It 
 * principal.
 */
#define AUTH_NORMAL	"normal"
#define AUTH_PRIVILEGED "privileged"

typedef int (Auth_Read_Function) (ClientData, conn_t *, Tcl_Interp*, char *, unsigned32);
typedef int (Auth_Write_Function) (ClientData, conn_t *, Tcl_Interp*, int, char **);


typedef struct 
{
    const char *command;
    ClientData command_data;
    Tcl_CmdProc *proc;
    const char *params;
} cmd_entry;

typedef struct 
{
    const char *name;
    conn_auth_t type;
    
    Auth_Read_Function *read_auth_function;
    ClientData read_auth_data;
    
    Auth_Write_Function *write_auth_function;
    ClientData write_auth_data;

    cmd_entry *command_functions;
}
Auth_Functions;


int 
Auth_Register (Tcl_Interp *interp, Auth_Functions *calls, char **procedures);

int
Auth_Read (ClientData d, Tcl_Interp *interp, int argc, char *argv[]);

int
Auth_Write (ClientData d, Tcl_Interp *interp, int argc, char *argv[]);


typedef int (auth_func) ();

/*
 * This structure contains the function addresses that may be needed
 * by dynamically loaded authentication modules.
 */
typedef struct
{
    auth_func *Auth_Register;
    auth_func *Unameit_Conn_Write;
}
Auth_MasterFunctions;

#endif
