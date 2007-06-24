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
#include <conn.h>
#include <auth.h>

/*
 * Encryption routines are taken from Kerberos 5 v4 compatability
 * include files.
 */
#define DEFINE_SOCKADDR

/*
 * Bypass v4 calls,  use v5 calls instead
 */

#include <kerberosIV/krb.h>
#ifndef WIN32
#include <kerberosIV/krb4-proto.h>
#endif
extern int mit_des_ecb_encrypt();
extern int mit_des_key_sched();


typedef struct
{
    unsigned32		seqno;
    unsigned32 		offset;
    des_cblock 		key;
    des_key_schedule	sched;
    MD5_CTX		md5_ctx;
    char		sessid[MIC_LEN];
    int			final;
} 
context_t;


static void 
Unameit_DesMd5_Mic_Enable(
    conn_t *conn,
    void *key,
    conn_state_t state,
    int seqno
);

static void
Unameit_DesMd5_Update_Mic(conn_t *conn, int reset)
{
    int		encrypt = ENCRYPT;
    int		start = 0;
    int		end = 0;
    unsigned32	net_seqno;
    context_t	*context = NULL;
    register    conn_message_t *message = &conn->conn_message;

    switch(conn->conn_state)
    {
    case CONN_READING:
	encrypt = DECRYPT;
	context = (context_t *) message->read_crypto.context;
	break;
    case CONN_WRITING:
	encrypt = ENCRYPT;
	context = (context_t *) message->write_crypto.context;
	break;
    default:
	panic("Calling Unameit_DesMd5_Update_Mic in invalid state: %d", conn->conn_state);
	break;
    }
    assert(context);

    if (reset)
    {
	context->offset = 0;
	return;
    }

    if (context->offset == 0)
    {
	if (encrypt == DECRYPT &&
	    message->header.offset < sizeof(message->header.data))
	{
	    /*
	     * Wait for complete header to arrive
	     */
	    return;
	}
	/*
	 * Compute the MD5 checksum.
	 */
	context->final = 0;
	MD5Init(&context->md5_ctx);
	/*
	 * Perturb the checksum by prefixing the key
	 */
	MD5Update(&context->md5_ctx, (char *)context->key, sizeof(des_cblock));
	/*
	 * Also include the sequence number
	 */
	net_seqno = unsigned32_hton(context->seqno);
	MD5Update(&context->md5_ctx, (char *)&net_seqno, sizeof(net_seqno));
	/*
	 * Checksum the header
	 */
	MD5Update(&context->md5_ctx,
		  (char *)&message->header.data, sizeof(message->header.data));
	/*
	 * Checksum the session token
	 */
	if (context->seqno > 0)
	{
	    MD5Update(&context->md5_ctx, context->sessid, MIC_LEN);
	}
	context->offset = sizeof(message->header.data);
    }

    start = context->offset - sizeof(message->header.data);
    switch (encrypt)
    {
    case ENCRYPT:
	if (message->header.offset < sizeof(message->header.data) &&
	    message->length > 0)
	{
	    end = message->offset + message->iov[1].iov_len;
	}
	else if (message->offset < message->length)
	{
	    end = message->offset + message->iov[0].iov_len;
	}
	else
	{
	    end = message->length;
	}
	break;
    case DECRYPT:
	end = message->offset;
	break;
    }

    if (start < end)
    {
	/*
	 * Checksum the data
	 */
	MD5Update(&context->md5_ctx, message->data+start, end - start);
	context->offset = end + sizeof(message->header.data);
    }

    if (end < message->length)
	return;

    /*
     * We might get here multiple times, while trying to finish I/O
     * on the trailer, call MD5Final just once.
     */
    if (context->final == 0)
    {
	/*
	 * Extract the digest
	 */
	MD5Final(&context->md5_ctx);
	context->final = 1;
    }
    else if (encrypt == ENCRYPT) 
    {
	/*
	 * We have already done everything that needs to be done.
	 * No need to waste cycles,  or get out of sync with the other
	 * end by incrementing the sequence number just because it takes
	 * a few I/Os to flush the trailer
	 */
	return;
    }

    switch (encrypt)
    {
    case DECRYPT:
	if (message->trailer.offset < MIC_LEN)
	{
	    /*
	     * Wait for trailer to arrive
	     */
	    return;
	}
	break;
    case ENCRYPT:
	/*
	 * Fill in the MIC
	 */
	memcpy(message->trailer.mic, context->md5_ctx.digest, MIC_LEN);
	break;
    }

    mit_des_ecb_encrypt(
	(des_cblock *)message->trailer.mic,
	(des_cblock *)message->trailer.mic,
	context->sched, encrypt
    );

    if (encrypt == DECRYPT)
    {
	message->read_crypto.mic_ok = 0;
	/*
	 * Verify first 8 bytes MIC
	 */
	if (memcmp(message->trailer.mic,
		   context->md5_ctx.digest, sizeof(des_cblock)) != 0)
	{
	    return;
	}
    }

    mit_des_ecb_encrypt(
	(des_cblock *)(message->trailer.mic + sizeof(des_cblock)),
	(des_cblock *)(message->trailer.mic + sizeof(des_cblock)),
	context->sched, encrypt
    );

    if (encrypt == DECRYPT)
    {
	/*
	 * Verify last 8 bytes of MIC
	 */
	if (memcmp(message->trailer.mic + sizeof(des_cblock),
		   context->md5_ctx.digest + sizeof(des_cblock),
		   sizeof(des_cblock)) != 0)
	{
	    return;
	}
	message->read_crypto.mic_ok = 1;
    }

    if (context->seqno == 0)
    {
	context_t *newcontext = NULL;
	/*
	 * Save first message digest for inclusion in md5 of rest of session
	 * this will make replay attacks harder.  It is up to first party
	 * (that sends a checksummed message) to make sure that it is
	 * never reused in future sessions with any client.
	 */
	memcpy(context->sessid, context->md5_ctx.digest, MIC_LEN);
	/*
	 * Initialize a new context for the reverse direction.
	 * Start new context with seqno == 1,  so it does not reinitialize
	 * the data for this context
	 */
	switch (encrypt)
	{
	case DECRYPT:
	    Unameit_DesMd5_Mic_Enable(conn, context->key, CONN_WRITING, 1);
	    newcontext = (context_t *) message->write_crypto.context;
	    break;
	case ENCRYPT:
	    Unameit_DesMd5_Mic_Enable(conn, context->key, CONN_READING, 1);
	    newcontext = (context_t *) message->read_crypto.context;
	    break;
	}
	memcpy(newcontext->sessid, context->md5_ctx.digest, MIC_LEN);
    }
    ++context->seqno;
}


static void
Unameit_DesMd5_Mic_Enable(
    conn_t *conn,
    void *key,
    conn_state_t state,
    int seqno
)
{
    context_t *context;
    
    if (conn->conn_errno)
	return;

    assert(conn->conn_state != state);

    context = (context_t *)ckalloc(sizeof(context_t));
    if (context == NULL)
    {
	panic("Out of memory");
    }
    context->offset = 0;
    context->seqno  = seqno;
    memcpy((char *)&context->key, key, sizeof(des_cblock));
    mit_des_key_sched(key, context->sched);

    switch (state)
    {
    case CONN_READING:
	conn->conn_message.read_crypto.update_mic = Unameit_DesMd5_Update_Mic;
	if (conn->conn_message.read_crypto.context)
	    ckfree((char *)conn->conn_message.read_crypto.context);
	conn->conn_message.read_crypto.context = (void *)context;
	break;
    case CONN_WRITING:
	conn->conn_message.write_crypto.update_mic = Unameit_DesMd5_Update_Mic;
	if (conn->conn_message.write_crypto.context)
	    ckfree((char *)conn->conn_message.write_crypto.context);
	conn->conn_message.write_crypto.context = (void *)context;
	break;
    default:
	panic("Invalid crypto state");
    }
}
