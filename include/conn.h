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
/* $Id: conn.h,v 1.9.16.2 1997/08/28 18:26:39 viktor Exp $ */
#ifndef UNAMEIT_CONN_H
#define UNAMEIT_CONN_H

#include <uconfig.h>
#include <arith_types.h>
#include <conn_stream.h>
#include <tcl.h>

#include <md5.h>

#define	MIC_LEN	sizeof (((MD5_CTX *)0)->digest)

/*
 * Magic number in message headers
 */
#define CONN_MAGIC	0x95110814
/*
 * Tcl association key for pointer to connection handle
 */
#define CONN_ASSOC_KEY  "unameitConnPtr"

/*
 * States
 */
typedef enum 
{
    CONN_NEW     = 0,
    CONN_READING = 1,
    CONN_IODONE  = 2,
    CONN_WRITING = 3,
    CONN_EOF     = 4
}
conn_state_t;


/*
 * Authentication types. The string and the number are registered by
 * each module when loaded. The enum is just to keep the numbers unique.
 * Do not change any numbers - add new ones at the end.
 * If changing a string, be sure to change TCL code as well as C code.
 */
#define CONN_AUTH_NONE	   ""
#define CONN_AUTH_KRB4     "ukrbiv"
#define CONN_AUTH_UPASSWD  "upasswd"
#define CONN_AUTH_KRB5	   "ukrbv"
#define CONN_AUTH_TRIVIAL  "trivial"

typedef enum 
{
    CONN_AUTH_ID_NONE		= 0,
    CONN_AUTH_ID_KRB4		= 1,
    CONN_AUTH_ID_KRB5		= 2,
    CONN_AUTH_ID_UPASSWD	= 3,
    CONN_AUTH_ID_TRIVIAL	= 4
} 
conn_auth_t;

/*
 * Error codes
 */
typedef enum 
{
    ERR_CONN_OK 	= 0,
    ERR_CONN_INVAL	= 1,
    ERR_CONN_SHORT	= 2,
    ERR_CONN_SIZE	= 3,
    ERR_CONN_READ	= 4,
    ERR_CONN_WRITE	= 5,
    ERR_CONN_MAGIC 	= 6
}
conn_error_t;


/*
 * Packet size for sliding window code
 */
#define CONN_PKT_LEN 0x1000

typedef struct conn_header
{
    struct {
	unsigned char magic[sizeof(unsigned32)];
	unsigned char auth_type[sizeof(unsigned32)];
	unsigned char result[sizeof(unsigned32)];
	unsigned char datalen[sizeof(unsigned32)];
    } data;
    int offset;
    /* We know the length */
}
conn_header_t;

typedef struct conn_trailer
{
    int		offset;
    unsigned char mic[MIC_LEN];
}
conn_trailer_t;

typedef struct conn *conn_ptr_t;

typedef struct conn_crypto
{
    int		mic_ok;
    void	(*update_mic)(conn_ptr_t conn, int reset);
    void	*context;
}
conn_crypto_t;

typedef struct conn_message
{
    struct iovec   iov[3];
    int		   nvec;
    conn_header_t  header;
    conn_auth_t	   auth_type;
    unsigned32	   maxlen;
    unsigned32	   length;
    unsigned32	   offset;
    char *         data;
    Tcl_FreeProc   *free;
    conn_trailer_t trailer;
    conn_crypto_t  read_crypto;
    conn_crypto_t  write_crypto;
}
conn_message_t;

typedef struct conn
{
    /*
     * For insque() and remque() need these up front.
     */
    struct conn		*q_forw;
    struct conn		*q_back;
    SOCKET 		conn_stream;
    conn_message_t	conn_message;
    conn_error_t	conn_errno;
    conn_state_t	conn_state;
    time_t		conn_lastio;
    Tcl_Interp		*conn_interp;
    void		(*conn_callback)(struct conn *, conn_state_t);
}
conn_t;

typedef void (*conn_callback_t)(conn_t *conn, conn_state_t old_state);

extern void Unameit_Conn_Terminate(void);
extern void Unameit_Conn_Poll(conn_t *conn);
extern void Unameit_Conn_Progress(conn_t *conn);
extern void Unameit_Conn_Reap(conn_t *conn);

extern int
Unameit_Conn_Loop(
    Tcl_Interp *interp,
    const char *portname,	/* The name of the TCP port to listen on */
    conn_callback_t callback,	/* Upcall for completed I/O ops */
    int hours			/* The idle connection timeout in hours */
);

extern conn_t *
Unameit_Conn_Connect(
    Tcl_Interp *interp,
    const char *hostname,
    const char *portname
);


extern char *
Unameit_Conn_Read(conn_t *conn, unsigned32 *lenP, unsigned32 *ret_code);

extern void
Unameit_Conn_Write(
    conn_t *conn,
    char *data,
    unsigned32 len,
    conn_auth_t auth_type,
    unsigned32 result,
    Tcl_FreeProc *free_proc
);


extern void
Unameit_Conn_Interp_Reply(conn_t *conn, Tcl_Interp *interp, int result);

#endif 
