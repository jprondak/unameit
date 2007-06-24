/*
 * Copyright (c) 1995, 1996, 1997 Enterprise Systems Management Corp.
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
static char rcsid[] = "$Id: ";

#include <uconfig.h>
#include <sys/mman.h>

#include <conn.h>
#include <unameit_init.h>

static Tcl_PackageInitProc Init_Slave;

/*
 * All the packages that are statically linked against upulld should
 * go in the list below.
 */
static struct Inits
    {
	char			*pkg;
	Tcl_PackageInitProc	*pkg_init;
	Tcl_PackageInitProc	*pkg_safe_init;
	int			init_now;
    }
    inits[] =
    {
	{"Tclx", Tclx_Init, Tclx_SafeInit, 1},
	{"Userver", Userver_Init, NULL, 1},
	{"Auth", Auth_Init, Auth_Init, 1},
	{"Upull_slave", Init_Slave, Init_Slave, 0},
	{NULL, NULL, NULL, 0}
    };

/*
 * POSIX says that mmap() return MAP_FAILED on error,
 * but SunOS 4 has no such macro and returns -1.
 *
 * We use the POSIX (void *) return type,
 * instead of the traditional (caddr_t).
 */
#ifndef MAP_FAILED
#   define MAP_FAILED ((void *) -1)
#endif

typedef struct MappedFile
{
    void *		addr;
    unsigned32		len;
    unsigned32  	refcount;
    Tcl_HashEntry	*addrEntry;
    Tcl_HashEntry	*nameEntry;
} MappedFile, *MappedFilePtr;


static Tcl_HashTable	mfpByName;
static Tcl_HashTable	mfpByAddr;

static void
mfpDone(char *addr)
{
    Tcl_HashEntry *ePtr;
    MappedFilePtr mfp;

    assert(addr);
    ePtr = Tcl_FindHashEntry(&mfpByAddr, addr);
    assert(ePtr);
    mfp = (MappedFilePtr)Tcl_GetHashValue(ePtr);
    assert(mfp);
    assert(ePtr == mfp->addrEntry);
    assert(mfp == (MappedFilePtr)Tcl_GetHashValue(mfp->nameEntry));

    if (--mfp->refcount == 0)
    {
	if (mfp->len != 0)
	{
	    check(munmap(mfp->addr, mfp->len) == 0);
	}
	else
	{
	    assert(addr == (char *)mfp->nameEntry);
	}
	Tcl_DeleteHashEntry(ePtr);
	Tcl_DeleteHashEntry(mfp->nameEntry);
	ckfree((char *)mfp);
    }
}

static int
Read_File(ClientData nused, Tcl_Interp *interp, int argc, char *argv[])
{
    char		*file_name;
    Tcl_HashEntry	*ePtr;
    MappedFilePtr	mfp;
    int 		new;
    conn_t		*conn;

    if (argc != 2)
    {
	Tcl_AppendResult(interp, "wrong # args: should be \"",
	    argv[0], "\" filename", (char *)NULL);
	return TCL_ERROR;
    }

    conn = (conn_t *)Tcl_GetAssocData(interp, CONN_ASSOC_KEY, NULL);
    assert(conn);

    if (conn->conn_errno)
	return TCL_ERROR;

    file_name = argv[1];

    if (file_name[0] == '/' || strstr(file_name, "../") != NULL)
    {
	Tcl_SetResult(interp, "Permission denied", TCL_STATIC);
	Tcl_SetErrorCode(interp, "PULL", "EPERM", file_name, (char *)NULL);
	return TCL_ERROR;
    }

    ePtr = Tcl_CreateHashEntry(&mfpByName, file_name, &new);

    if (new)
    {
	struct stat	st;
	void		*ptr;
	int		fd;
	
	fd = open(file_name, O_RDONLY, 0);

	if (fd < 0)
	{
	cleanup:
	    Tcl_DeleteHashEntry(ePtr);
	    Tcl_AppendResult(interp, "Cannot read: ", file_name, ": ",
			     Tcl_PosixError(interp), (char *)NULL);
	    return TCL_ERROR;
	}

	if (fstat(fd, &st) == -1 || !S_ISREG(st.st_mode))
	{
	    (void) close(fd);
	    goto cleanup;
	}

	if (st.st_size != 0)
	{
	    ptr = mmap(0, st.st_size, PROT_READ, MAP_SHARED, fd, 0);

	    if(ptr == MAP_FAILED)
	    {
		goto cleanup;
	    }
	}
	else
	{
	    /*
	     * Need a unique address for each file.
	     * We don't care about contents so just use the hashEntry pointer
	     */
	    ptr = (void *)ePtr;
	}
	(void) close(fd);

	check(mfp = (MappedFilePtr)ckalloc(sizeof(MappedFile)));
	mfp->len = st.st_size;
	mfp->addr = ptr;
	mfp->refcount = 0;

	Tcl_SetHashValue(mfp->nameEntry = ePtr, (ClientData)mfp);

	mfp->addrEntry = Tcl_CreateHashEntry(&mfpByAddr, mfp->addr, &new);
	Tcl_SetHashValue(mfp->addrEntry, (ClientData)mfp);
	assert(new);
    }
    else
    {
	mfp = (MappedFilePtr) Tcl_GetHashValue(ePtr);
    }

    ++mfp->refcount;

    Unameit_Conn_Write(conn, mfp->addr, mfp->len, CONN_AUTH_ID_NONE,
		       TCL_OK, mfpDone);
    return TCL_OK;
}


static int 
Init_Slave(Tcl_Interp *slave)
{
    Tcl_CreateCommand(slave, "unameit_pull_read_file", Read_File, 0, 0);
    Tcl_PkgProvide(slave, "Upull_slave", "1.0");
    return TCL_OK;
}


#include <unameit_init.h>
#include "bootstrap.h"

int Tcl_AppInit(Tcl_Interp *interp)
{
    struct Inits	*initPtr;
    char		**procdef;

    assert(interp);

    openlog("UName*It", 0, LOG_LOCAL0);

    /*
     * The "Tcl" Package is special.  It should not be registered as
     * a loadable package.
     */
    if (Tcl_Init(interp) != TCL_OK)
    {
	return TCL_ERROR;
    }

    Tcl_InitMemory(interp);

    for (initPtr = inits; initPtr->pkg; initPtr++)
    {
	if (initPtr->init_now && initPtr->pkg_init(interp) != TCL_OK)
	{
	    return TCL_ERROR;
	}
	Tcl_StaticPackage(initPtr->init_now ? interp : NULL,
			  initPtr->pkg,
			  initPtr->pkg_init,
			  initPtr->pkg_safe_init);
    }

    for (procdef = bootstrap; *procdef; ++procdef)
    {
	if (Tcl_Eval(interp, *procdef) != TCL_OK)
	    return TCL_ERROR;
    }

    Tcl_InitHashTable(&mfpByName, TCL_STRING_KEYS);
    Tcl_InitHashTable(&mfpByAddr, TCL_ONE_WORD_KEYS);

    /*
     * Free before exit for memory debugging
     */
    Tcl_CreateExitHandler((Tcl_ExitProc *)Tcl_DeleteHashTable,
			  (ClientData)&mfpByName);

    Tcl_CreateExitHandler((Tcl_ExitProc *)Tcl_DeleteHashTable,
			  (ClientData)&mfpByAddr);

    return TCL_OK;
}
