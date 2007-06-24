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
#include <stdio.h>

#include <errno.h>
#include <fcntl.h>
#include <sys/syscall.h>


int
main()
{
    printf("sub EINTR {%d;}\n", EINTR);
    printf("sub F_SETLK {%d;}\n", F_SETLK);
    printf("sub F_WRLCK {%d;}\n", F_WRLCK);
    printf("sub SYS_fchmod {%d;}\n", SYS_fchmod);
    printf("sub O_SYNC {%d;}\n", O_SYNC);
#if defined(SYS_fsync)
    printf("sub SYS_fsync {%d;}\n", SYS_fsync);
#elif defined(SYS_fdsync)
    printf("sub SYS_fdsync {%d;}\n", SYS_fdsync);
#else
   error do not have fsync syscall;
#endif
    puts("1;");
    exit(0);
}
