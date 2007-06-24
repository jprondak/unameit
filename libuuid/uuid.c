/*
 * 
 * (c) Copyright 1989 OPEN SOFTWARE FOUNDATION, INC.
 * (c) Copyright 1989 HEWLETT-PACKARD COMPANY
 * (c) Copyright 1989 DIGITAL EQUIPMENT CORPORATION
 * To anyone who acknowledges that this file is provided "AS IS"
 * without any express or implied warranty:
 *                 permission to use, copy, modify, and distribute this
 * file for any purpose is hereby granted without fee, provided that
 * the above copyright notices and this notice appears in all source
 * code copies, and that none of the names of Open Software
 * Foundation, Inc., Hewlett-Packard Company, or Digital Equipment
 * Corporation be used in advertising or publicity pertaining to
 * distribution of the software without specific, written prior
 * permission.  Neither Open Software Foundation, Inc., Hewlett-
 * Packard Company, nor Digital Equipment Corporation makes any
 * representations about the suitability of this software for any
 * purpose.
 * 
 */
static char rcsid[] = "$Id: uuid.c,v 1.7.20.3 1997/09/21 23:42:57 viktor Exp $";


#include <uconfig.h>
#include <arith_types.h>

#include "uuid.h"

#define UUID_VERSION "1.0"

#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif

/*
 * defines for time calculations
 */
#ifndef UUID_C_100NS_PER_SEC
#define UUID_C_100NS_PER_SEC            10000000
#endif

#ifndef UUID_C_100NS_PER_USEC
#define UUID_C_100NS_PER_USEC           10
#endif

/*
 * UADD_UVLW_2_UVLW - macro to add two unsigned 64-bit long integers
 *                      (ie. add two unsigned 'very' long words)
 *
 * Important note: It is important that this macro accommodate (and it does)
 *                 invocations where one of the addends is also the sum.
 *
 * This macro was snarfed from the DTSS group and was originally:
 *
 * UTCadd - macro to add two UTC times
 *
 * add lo and high order longword separately, using sign bits of the low-order
 * longwords to determine carry.  sign bits are tested before addition in two
 * cases - where sign bits match. when the addend sign bits differ the sign of
 * the result is also tested:
 *
 *        sign            sign
 *      addend 1        addend 2        carry?
 *
 *          1               1            TRUE
 *          1               0            TRUE if sign of sum clear
 *          0               1            TRUE if sign of sum clear
 *          0               0            FALSE
 */
#define UADD_UVLW_2_UVLW(add1, add2, sum)                               \
    if (!(((add1)->lo&0x80000000UL) ^ ((add2)->lo&0x80000000UL)))       \
    {                                                                   \
        if (((add1)->lo&0x80000000UL))                                  \
        {                                                               \
            (sum)->lo = (add1)->lo + (add2)->lo ;                       \
            (sum)->hi = (add1)->hi + (add2)->hi+1 ;                     \
        }                                                               \
        else                                                            \
        {                                                               \
            (sum)->lo  = (add1)->lo + (add2)->lo ;                      \
            (sum)->hi = (add1)->hi + (add2)->hi ;                       \
        }                                                               \
    }                                                                   \
    else                                                                \
    {                                                                   \
        (sum)->lo = (add1)->lo + (add2)->lo ;                           \
        (sum)->hi = (add1)->hi + (add2)->hi ;                           \
        if (!((sum)->lo&0x80000000UL))                                  \
            (sum)->hi++ ;                                               \
    }


/*
 * UADD_ULW_2_UVLW - macro to add a 32-bit unsigned integer to
 *                   a 64-bit unsigned integer
 *
 * Note: see the UADD_UVLW_2_UVLW() macro
 *
 */
#define UADD_ULW_2_UVLW(add1, add2, sum)                                \
{                                                                       \
    (sum)->hi = (add2)->hi;                                             \
    if ((*add1) & (add2)->lo & 0x80000000UL)                            \
    {                                                                   \
        (sum)->lo = (*add1) + (add2)->lo;                               \
        (sum)->hi++;                                                    \
    }                                                                   \
    else                                                                \
    {                                                                   \
        (sum)->lo = (*add1) + (add2)->lo;                               \
        if (!((sum)->lo & 0x80000000UL))                                \
        {                                                               \
            (sum)->hi++;                                                \
        }                                                               \
    }                                                                   \
}


/*
 * UADD_UW_2_UVLW - macro to add a 16-bit unsigned integer to
 *                   a 64-bit unsigned integer
 *
 * Note: see the UADD_UVLW_2_UVLW() macro
 *
 */
#define UADD_UW_2_UVLW(add1, add2, sum)                                 \
{                                                                       \
    (sum)->hi = (add2)->hi;                                             \
    if ((add2)->lo & 0x80000000UL)                                      \
    {                                                                   \
        (sum)->lo = (*add1) + (add2)->lo;                               \
        if (!((sum)->lo & 0x80000000UL))                                \
        {                                                               \
            (sum)->hi++;                                                \
        }                                                               \
    }                                                                   \
    else                                                                \
    {                                                                   \
        (sum)->lo = (*add1) + (add2)->lo;                               \
    }                                                                   \
}

#define USUB_UVLW_FROM_UVLW(sub1, sub2, diff) \
    if ((unsigned32)((sub2)->lo) > (unsigned32)((sub1)->lo)) { \
        (sub1)->hi  = (signed32)((sub1)->hi) - 1; \
    } \
    (diff)->lo = (unsigned32)((sub1)->lo) - (unsigned32)((sub2)->lo); \
    (diff)->hi = (signed32)((sub1)->hi) - (signed32)((sub2)->hi);

typedef struct
{
    char eaddr[6];      /* 6 bytes of ethernet hardware address */
} uuid_address_t, *uuid_address_p_t;


typedef struct
{
    unsigned32  lo;
    unsigned32  hi;
} uuid_time_t, *uuid_time_p_t;


typedef struct
{
    unsigned32  lo;
    unsigned32  hi;
} unsigned64_t, *unsigned64_p_t;


/*
 * U U I D _ _ U E M U L
 *
 * 32-bit unsigned * 32-bit unsigned multiply -> 64-bit result
 */
static void uuid__uemul (
        unsigned32           /*u*/,
        unsigned32           /*v*/,
        unsigned64_t *       /*prodPtr*/
    );

/*
 * Internal structure of universal unique IDs (UUIDs).
 *
 * The following information applies to variant #1 UUIDs:
 *
 * The lowest addressed octet contains the global/local bit and the
 * unicast/multicast bit, and is the first octet of the address transmitted
 * on an 802.3 LAN.
 *
 * The adjusted time stamp is split into three fields, and the clockSeq
 * is split into two fields.
 *
 * |<------------------------- 32 bits -------------------------->|
 *
 * +--------------------------------------------------------------+
 * |                     low 32 bits of time                      |  0-3  .time_low
 * +-------------------------------+-------------------------------
 * |     mid 16 bits of time       |  4-5               .time_mid
 * +-------+-----------------------+
 * | vers. |   hi 12 bits of time  |  6-7               .time_hi_and_version
 * +-------+-------+---------------+
 * |Res|  clkSeqHi |  8                                 .clock_seq_hi_and_reserved
 * +---------------+
 * |   clkSeqLow   |  9                                 .clock_seq_low
 * +---------------+----------...-----+
 * |            node ID               |  8-16           .node
 * +--------------------------...-----+
 *
 * --------------------------------------------------------------------------
 *
 * The structure layout of all three UUID variants is fixed for all time.
 * I.e., the layout consists of a 32 bit int, 2 16 bit ints, and 8 8
 * bit ints.  The current form version field does NOT determine/affect
 * the layout.  This enables us to do certain operations safely on the
 * variants of UUIDs without regard to variant; this increases the utility
 * of this code even as the version number changes (i.e., this code does
 * NOT need to check the version field).
 *
 * The "Res" field in the octet #8 is the so-called "reserved" bit-field
 * and determines whether or not the uuid is a old, current or other
 * UUID as follows:
 *
 *      MS-bit  2MS-bit  3MS-bit      Variant
 *      ---------------------------------------------
 *         0       x        x       0 (NCS 1.5)
 *         1       0        x       1 (DCE 1.0 RPC)
 *         1       1        0       2 (Microsoft)
 *         1       1        1       unspecified
 *
 * --------------------------------------------------------------------------
 *
 */

/***************************************************************************
 *
 * Local definitions
 *
 **************************************************************************/

#ifdef  UUID_DEBUG
#define DEBUG_PRINT(msg, st)    RPC_DBG_GPRINTF (( "%s: %08x\n", msg, st ))
#else
#define DEBUG_PRINT(msg, st)
#endif

/*
 * the number of elements returned by sscanf() when converting
 * string formatted uuid's to binary
 */
#define UUID_ELEMENTS_NUM       11

/*
 * local defines used in uuid bit-diddling
 */
#define HI_WORD(w)                  ((w) >> 16)
#define RAND_MASK                   0x3fff      /* same as CLOCK_SEQ_LAST */

#define TIME_MID_MASK               0x0000ffff
#define TIME_HIGH_MASK              0x0fff0000
#define TIME_HIGH_SHIFT_COUNT       16

#define MAX_TIME_ADJUST             0x7fff

#define CLOCK_SEQ_LOW_MASK          0xff
#define CLOCK_SEQ_HIGH_MASK         0x3f00
#define CLOCK_SEQ_HIGH_SHIFT_COUNT  8
#define CLOCK_SEQ_FIRST             1
#define CLOCK_SEQ_LAST              0x3fff      /* same as RAND_MASK */

/*
 * Note: If CLOCK_SEQ_BIT_BANG == TRUE, then we can avoid the modulo
 * operation.  This should save us a divide instruction and speed
 * things up.
 */

#ifndef CLOCK_SEQ_BIT_BANG
#define CLOCK_SEQ_BIT_BANG          1
#endif

#if CLOCK_SEQ_BIT_BANG
#define CLOCK_SEQ_BUMP(seq)         ((*seq) = ((*seq) + 1) & CLOCK_SEQ_LAST)
#else
#define CLOCK_SEQ_BUMP(seq)         ((*seq) = ((*seq) + 1) % (CLOCK_SEQ_LAST+1))
#endif

#define UUID_VERSION_BITS           (1 << 12)
#define UUID_RESERVED_BITS          0x80


/****************************************************************************
 *
 * local data declarations
 *
 ****************************************************************************/

/*
 * saved copy of our IEEE 802 address for quick reference
 */
static uuid_address_t  saved_addr;

/*
 * declarations used in UTC time calculations
 */
static uuid_time_t      time_now;     /* utc time as of last query        */
static uuid_time_t      time_last;    /* 'saved' value of time_now        */
static unsigned16       time_adjust;  /* 'adjustment' to ensure uniqness  */
static unsigned16       clock_seq;    /* 'adjustment' for backwards clocks*/

/*
 * true_random variables
 */
static unsigned32     rand_m;         /* multiplier                       */
static unsigned32     rand_ia;        /* adder #1                         */
static unsigned32     rand_ib;        /* adder #2                         */
static unsigned32     rand_irand;     /* random value                     */

typedef enum
{
    uuid_e_less_than, uuid_e_equal_to, uuid_e_greater_than
} uuid_compval_t;

/*
 * boolean indicating we've already determined our IEEE 802 address
 */
static int got_address = FALSE;

static int init (void);
static int Get_Uuid_Address (uuid_address_t *);
static unsigned16 true_random (void);
static void true_random_init (void);
static void new_clock_seq (unsigned16 *);

/*
 * T I M E _ C M P
 *
 * Compares two UUID times (64-bit DEC UID UTC values)
 */
static uuid_compval_t time_cmp (
        uuid_time_p_t        /*time1*/,
        uuid_time_p_t        /*time2*/
    );



/*****************************************************************************
 *
 *  Macro definitions
 *
 ****************************************************************************/

/*
 * ensure we've been initialized
 */
static int uuid_init_done = FALSE;

#define UUID_VERIFY_INIT(Arg)       \
    if (! uuid_init_done)           \
    {                               \
        if (init() != TCL_OK)       \
        {                           \
            return Arg;             \
        }                           \
    }

/*
 *  Define constant designation difference in Unix and DTSS base times:
 *  DTSS UTC base time is October 15, 1582.
 *  Unix base time is January 1, 1970.
 */
#define uuid_c_os_base_time_diff_lo     0x13814000
#define uuid_c_os_base_time_diff_hi     0x01B21DD2

/*
 * U U I D _ _ G E T _ O S _ T I M E
 *
 * Get OS time - contains platform-specific code.
 */
static int
uuid__get_os_time (uuid_time_t * uuid_time) 
{
    struct timeval      tp;
    unsigned64_t        utc,
                        usecs,
                        os_basetime_diff;
    /*
     * Get current time
     */
    if (gettimeofday (&tp, (struct timezone *) 0))
    {
        perror ("uuid__get_os_time");
        return TCL_ERROR;
    }

    /*
     * Multiply the number of seconds by the number clunks 
     */
    uuid__uemul ((long) tp.tv_sec, UUID_C_100NS_PER_SEC, &utc);

    /*
     * Multiply the number of microseconds by the number clunks 
     * and add to the seconds
     */
    uuid__uemul ((long) tp.tv_usec, UUID_C_100NS_PER_USEC, &usecs);
    UADD_UVLW_2_UVLW (&usecs, &utc, &utc);

    /*
     * Offset between DTSS formatted times and Unix formatted times.
     */
    os_basetime_diff.lo = uuid_c_os_base_time_diff_lo;
    os_basetime_diff.hi = uuid_c_os_base_time_diff_hi;
    UADD_UVLW_2_UVLW (&utc, &os_basetime_diff, uuid_time);

    return TCL_OK;
}


/* 
 * U U I D _ _ G E T _ O S _ P I D
 *
 * Get the process id
 */
static unsigned32
uuid__get_os_pid(void) 
{
    return ((unsigned32) getpid());
}


/*
 * get_macaddress (from first suitable interface)
 */
extern int Uuid_Get_Macaddress(uuid_address_p_t addr);

static int
init (void) 
{
    /*
     * init the random number generator
     */
    true_random_init();

    uuid__get_os_time (&time_last);

    clock_seq = true_random();

    uuid_init_done = TRUE;

    return TCL_OK;
}


static int
Create_Uuid(uuid_t *uuid) {
    uuid_address_t          eaddr;      /* our IEEE 802 hardware address */
    int			    status;
    int                     got_no_time = FALSE;

    UUID_VERIFY_INIT (TCL_ERROR);

    /*
     * get our hardware network address
     */
    status = Get_Uuid_Address (&eaddr);

    if (status != TCL_OK)
    {
        DEBUG_PRINT("Create_Uuid:Get_Uuid_Address", status);
        return status;
    }

    do
    {
        /*
         * get the current time
         */
        uuid__get_os_time (&time_now);

        /*
         * do stuff like:
         *
         *  o check that our clock hasn't gone backwards and handle it
         *    accordingly with clock_seq
         *  o check that we're not generating uuid's faster than we
         *    can accommodate with our time_adjust fudge factor
         */
        switch (time_cmp (&time_now, &time_last))
        {
            case uuid_e_less_than:
                new_clock_seq (&clock_seq);
                time_adjust = 0;
                break;
            case uuid_e_greater_than:
                time_adjust = 0;
                break;
            case uuid_e_equal_to:
                if (time_adjust == MAX_TIME_ADJUST)
                {
                    /*
                     * spin your wheels while we wait for the clock to tick
                     */
                    got_no_time = TRUE;
                }
                else
                {
                    time_adjust++;
                }
                break;
            default:
                status = TCL_ERROR;
                DEBUG_PRINT ("Create_Uuid", status);
                return status;
        }
    } while (got_no_time);

    time_last.lo = time_now.lo;
    time_last.hi = time_now.hi;

    if (time_adjust != 0)
    {
        UADD_UW_2_UVLW (&time_adjust, &time_now, &time_now);
    }

    /*
     * now construct a uuid with the information we've gathered
     * plus a few constants
     */
    uuid->time_low = time_now.lo;
    uuid->time_mid = time_now.hi & TIME_MID_MASK;

    uuid->time_hi_and_version =
        (time_now.hi & TIME_HIGH_MASK) >> TIME_HIGH_SHIFT_COUNT;
    uuid->time_hi_and_version |= UUID_VERSION_BITS;

    uuid->clock_seq_low = clock_seq & CLOCK_SEQ_LOW_MASK;
    uuid->clock_seq_hi_and_reserved =
        (clock_seq & CLOCK_SEQ_HIGH_MASK) >> CLOCK_SEQ_HIGH_SHIFT_COUNT;

    uuid->clock_seq_hi_and_reserved |= UUID_RESERVED_BITS;

    memcpy (uuid->node, &eaddr, sizeof (uuid_address_t));

    return TCL_OK;
}

/*****************************************************************************
 *
 *  LOCAL MATH PROCEDURES - math procedures used internally by the UUID module
 *
 ****************************************************************************/

/*
** T I M E _ C M P
**
** Compares two UUID times (64-bit UTC values)
**/

static
uuid_compval_t time_cmp (
    uuid_time_p_t           time1,
    uuid_time_p_t           time2
) {
    /*
     * first check the hi parts
     */
    if (time1->hi < time2->hi) return (uuid_e_less_than);
    if (time1->hi > time2->hi) return (uuid_e_greater_than);

    /*
     * hi parts are equal, check the lo parts
     */
    if (time1->lo < time2->lo) return (uuid_e_less_than);
    if (time1->lo > time2->lo) return (uuid_e_greater_than);

    return (uuid_e_equal_to);
}

/*
**  U U I D _ _ U E M U L
**
**  Functional Description:
**        32-bit unsigned quantity * 32-bit unsigned quantity
**        producing 64-bit unsigned result. This routine assumes
**        long's contain at least 32 bits. It makes no assumptions
**        about byte orderings.
**
**  Inputs:
**
**        u, v       Are the numbers to be multiplied passed by value
**
**  Outputs:
**
**        prodPtr    is a pointer to the 64-bit result
**
**  Note:
**        This algorithm is taken from: "The Art of Computer
**        Programming", by Donald E. Knuth. Vol 2. Section 4.3.1
**        Pages: 253-255.
**--
**/

static void
uuid__uemul (
    unsigned32          u,
    unsigned32          v,
    unsigned64_t        *prodPtr
) {
    /*
     * following the notation in Knuth, Vol. 2
     */
    unsigned32      uuid1, uuid2, v1, v2, temp;


    uuid1 = u >> 16;
    uuid2 = u & 0xffff;
    v1 = v >> 16;
    v2 = v & 0xffff;

    temp = uuid2 * v2;
    prodPtr->lo = temp & 0xffff;
    temp = uuid1 * v2 + (temp >> 16);
    prodPtr->hi = temp >> 16;
    temp = uuid2 * v1 + (temp & 0xffff);
    prodPtr->lo += (temp & 0xffff) << 16;
    prodPtr->hi += uuid1 * v1 + (temp >> 16);
}


/****************************************************************************
**
**    U U I D   T R U E   R A N D O M   N U M B E R   G E N E R A T O R
**
*****************************************************************************
**
** This random number generator (RNG) was found in the ALGORITHMS Notesfile.
**
** (Note 16.7, July 7, 1989 by Robert (RDVAX::)Gries, Cambridge Research Lab,
**  Computational Quality Group)
**
** It is really a "Multiple Prime Random Number Generator" (MPRNG) and is
** completely discussed in reference #1 (see below).
**
**   References:
**   1) "The Multiple Prime Random Number Generator" by Alexander Hass
**      pp. 368 to 381 in ACM Transactions on Mathematical Software,
**      December, 1987
**   2) "The Art of Computer Programming: Seminumerical Algorithms
**      (vol 2)" by Donald E. Knuth, pp. 39 to 113.
**
** A summary of the notesfile entry follows:
**
** Gries discusses the two RNG's available for ULTRIX-C.  The default RNG
** uses a Linear Congruential Method (very popular) and the second RNG uses
** a technique known as a linear feedback shift register.
**
** The first (default) RNG suffers from bit-cycles (patterns/repetition),
** ie. it's "not that random."
**
** While the second RNG passes all the emperical tests, there are "states"
** that become "stable", albeit contrived.
**
** Gries then presents the MPRNG and says that it passes all emperical
** tests listed in reference #2.  In addition, the number of calls to the
** MPRNG before a sequence of bit position repeats appears to have a normal
** distribution.
**
** Note (mbs): I have coded the Gries's MPRNG with the same constants that
** he used in his paper.  I have no way of knowing whether they are "ideal"
** for the range of numbers we are dealing with.
**
****************************************************************************/


/*
** T R U E _ R A N D O M _ I N I T
**
** Note: we "seed" the RNG with the bits from the clock and the PID
**
**/

static void
true_random_init(void) 
{
    uuid_time_t         t;
    unsigned16          *seedp, seed=0;


    /*
     * optimal/recommended starting values according to the reference
     */
    static unsigned32   rand_m_init     = 971;
    static unsigned32   rand_ia_init    = 11113;
    static unsigned32   rand_ib_init    = 104322;
    static unsigned32   rand_irand_init = 4181;

    rand_m = rand_m_init;
    rand_ia = rand_ia_init;
    rand_ib = rand_ib_init;
    rand_irand = rand_irand_init;

    /*
     * Generating our 'seed' value
     *
     * We start with the current time, but, since the resolution of clocks is
     * system hardware dependent (eg. Ultrix is 10 msec.) and most likely
     * coarser than our resolution (10 usec) we 'mixup' the bits by xor'ing
     * all the bits together.  This will have the effect of involving all of
     * the bits in the determination of the seed value while remaining system
     * independent.  Then for good measure to ensure a unique seed when there
     * are multiple processes creating UUID's on a system, we add in the PID.
     */
    uuid__get_os_time(&t);
    seedp = (unsigned16 *)(&t);
    seed ^= *seedp++;
    seed ^= *seedp++;
    seed ^= *seedp++;
    seed ^= *seedp++;
    rand_irand += seed + uuid__get_os_pid();
}


/*
** T R U E _ R A N D O M
**
** Note: we return a value which is 'tuned' to our purposes.  Anyone
** using this routine should modify the return value accordingly.
**/

static unsigned16
true_random(void) 
{
    rand_m += 7;
    rand_ia += 1907;
    rand_ib += 73939;

    if (rand_m >= 9973) rand_m -= 9871;
    if (rand_ia >= 99991) rand_ia -= 89989;
    if (rand_ib >= 224729) rand_ib -= 96233;

    rand_irand = (rand_irand * rand_m) + rand_ia + rand_ib;

    return (HI_WORD (rand_irand) ^ (rand_irand & RAND_MASK));
}


/*
** N E W _ C L O C K _ S E Q
**
** Ensure *clkseq is up-to-date
**
** Note: clock_seq is architected to be 14-bits (unsigned) but
**       I've put it in here as 16-bits since there isn't a
**       14-bit unsigned integer type (yet)
**/

static void
new_clock_seq (
    unsigned16              *clkseq
) 
{
    /*
     * A clkseq value of 0 indicates that it hasn't been initialized.
     */
    if (*clkseq == 0)
    {
        /*
         * with a volatile clock, we always init to a random number
         */
        *clkseq = true_random();
    }

    CLOCK_SEQ_BUMP (clkseq);
    if (*clkseq == 0)
    {
        *clkseq = *clkseq + 1;
    }
}


static int
Get_Uuid_Address (uuid_address_p_t addr) 
{
    int status;
    /*
     * just return address we determined previously if we've
     * already got one
     */
    if (got_address)
    {
        memcpy (addr, &saved_addr, sizeof (uuid_address_t));
        return TCL_OK;
    }

    /*
     * Otherwise, call the system specific routine.
     */
    status = Uuid_Get_Macaddress (addr);

    if (status == TCL_OK)
    {
        got_address = TRUE;
        memcpy (&saved_addr, addr, sizeof (uuid_address_t));

	return TCL_OK;
    }
    else
    {
        return TCL_ERROR;
    }
}


const char *
Uuid_StringCreate(void) 
{
    static char		uuid_string[UDB_UUID_SIZE];
    uuid_t		uuid;

    assert(sizeof(uuid_t) == 16);

    if (Create_Uuid(&uuid) != TCL_OK)
	return NULL;

    /*
     * Put uuid in network byte order
     */
    uuid.time_low = unsigned32_hton(uuid.time_low);
    uuid.time_mid = unsigned16_hton(uuid.time_mid);
    uuid.time_hi_and_version = unsigned16_hton(uuid.time_hi_and_version);

    Udb_Radix64_Encode((unsigned char *)&uuid, uuid_string);

    return uuid_string;
}


int
Uuid_Valid(const char *s) 
{
    uuid_t uuid;
    /*
     * XXX: Could also check the internal structure of the UUID.
     */
    return Udb_Radix64_Decode(s, (char *)&uuid) == 0;
}

/* ARGSUSED */
static int
Uuidgen(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    Tcl_SetResult(interp, (char *)Uuid_StringCreate(), TCL_VOLATILE);
    return TCL_OK;
}

static int
Uuidok(ClientData dummy, Tcl_Interp *interp, int argc, char *argv[])
{
    int ok = argc == 2 && Uuid_Valid(argv[1]);
    sprintf(interp->result, "%d", ok);
    return TCL_OK;
}

int
Uuid_Init(Tcl_Interp *interp)
{
    int result;

    Tcl_CreateCommand(interp, "uuidgen", Uuidgen, 0, 0);
    Tcl_CreateCommand(interp, "uuidok", Uuidok, 0, 0);
    if ((result = Tcl_PkgProvide(interp, "Uuid", UUID_VERSION)) != TCL_OK) {
	return result;
    }
    return TCL_OK;
}
