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
static char rcsid[] = "$Id: conn_tcl.c,v 1.7.20.4 1997/09/21 23:42:23 viktor Exp $";

#include <stdarg.h>
#include <conn.h>


void
Unameit_Conn_Interp_Reply(conn_t *conn, Tcl_Interp *interp, int result)
{
    int		result_len, err_code_len, err_info_len, data_len;
    char	*err_code, *err_info, *data_buf;
    Tcl_FreeProc *freeProc;

    if (result == TCL_OK)
    {
	/*
	 * The pull daemon puts file data directly on the connection
	 * If it has done so,  we do not overwrite it with the empty
	 * result from the interpreter
	 */
	if (conn->conn_state == CONN_WRITING)
	{
	    return;
	}

	data_len = strlen(interp->result);
	freeProc = interp->freeProc;

	/*
	 * When interp->result is "static" it is not necessarily
	 * stable!
	 */
	if (freeProc == TCL_STATIC)
	{
	    check(data_buf = ckalloc(data_len));
	    memcpy(data_buf, interp->result, data_len);

	    freeProc = TCL_DYNAMIC;
	}
	else
	{
	    data_buf = interp->result;
	}

	interp->result = "";
	interp->freeProc = TCL_STATIC;

	/*
	 * Return interpreter result to client
	 */
	Unameit_Conn_Write(conn, data_buf, data_len,
			   CONN_AUTH_ID_NONE, result, freeProc);
	return;
    }

    result_len = strlen(interp->result);
#ifdef DEBUG
    /*
     * Only set errorInfo when debugging
     */
    if (!(err_info = Tcl_GetVar(interp, "errorInfo", TCL_GLOBAL_ONLY)))
    {
	err_info = "";
    }
    err_info_len = strlen(err_info);
#else
    err_info = "";
    err_info_len = 0;
#endif

    if (!(err_code = Tcl_GetVar(interp, "errorCode", TCL_GLOBAL_ONLY))) {
	err_code = "";
    }
    err_code_len = strlen(err_code);

    data_len = result_len + err_info_len + err_code_len + 2;
    data_buf = ckalloc(data_len);
    (void)memcpy(data_buf, interp->result, result_len + 1);
    (void)memcpy(&data_buf[result_len+1], err_info, err_info_len + 1);
    (void)memcpy(&data_buf[result_len+err_info_len+2], err_code, err_code_len);

    Tcl_ResetResult(interp);

    Unameit_Conn_Write(conn, data_buf, data_len, CONN_AUTH_ID_NONE, result,
		      TCL_DYNAMIC);
}
