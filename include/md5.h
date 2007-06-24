/* $Id: md5.h,v 1.1.1.1 1995/10/23 19:20:15 simpson Exp $ */
/***********************************************************************
 ** md5.h -- header file for implementation of MD5                    **
 ** RSA Data Security, Inc. MD5 Message-Digest Algorithm              **
 ** Created: 2/17/90 RLR                                              **
 ** Revised: 12/27/90 SRD,AJ,BSK,JT Reference C version               **
 ** Revised (for MD5): RLR 4/27/91                                    **
 **********************************************************************/

#ifndef _MD5_H
#define _MD5_H

/* typedef a 32-bit type */

#include <arith_types.h>

/*
 * Data structure for MD5 (Message-Digest) computation
 */
typedef struct
{
  unsigned32 i[2];              /* number of _bits_ handled mod 2^64 */
  unsigned32 buf[4];            /* scratch buffer */
  unsigned char in[64];         /* input buffer */
  unsigned char digest[16];     /* actual digest after MD5Final call */
}
MD5_CTX;

void MD5Init(MD5_CTX *);
void MD5Update(MD5_CTX *, unsigned char *, unsigned32);
void MD5Final(MD5_CTX *);

#endif /* _MD5_H */
