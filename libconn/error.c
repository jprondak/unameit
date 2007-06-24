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
static char rcsid[] = "$Id: error.c,v 1.5.4.3 1997/09/21 23:42:23 viktor Exp $";

#include <uconfig.h>
#include <error.h>

/*
 * Basically, this is not functioning on Windows.
 * TBD - use the NT logging functions, probably in a separate module.
 */
#ifndef HAVE_SYSLOG
#define LOG_ALERT 2
#define LOG_INFO 1
#endif

static err_func_t *logit;
static err_func_t *elogit;

void Unameit_Panic(const char *fmt, ...)
{
    /*
     * Can't assert in Panic,  since assert calls panic!
     */
    if (logit)
    {
	va_list arg;
	va_start(arg, fmt);
	logit(1, LOG_ALERT, fmt, arg);
	va_end(arg);
    }
    exit(1);
}

void Unameit_ePanic(const char *fmt, ...)
{
    /*
     * Can't assert in Panic,  since assert calls panic!
     */
    if (elogit)
    {
	va_list arg;
	va_start(arg, fmt);
	elogit(1, LOG_ALERT, fmt, arg);
	va_end(arg);
    }
    exit(1);
}

void Unameit_Complain(const char *fmt, ...)
{
    assert(fmt);

    if (logit)
    {
	va_list arg;
	va_start(arg, fmt);
	logit(0, LOG_INFO, fmt, arg);
	va_end(arg);
    }
}

void Unameit_eComplain(const char *fmt, ...)
{
    assert(fmt);

    if (elogit)
    {
	va_list arg;
	va_start(arg, fmt);
	elogit(0, LOG_INFO, fmt, arg);
	va_end(arg);
    }
}

void Unameit_Set_Error_Funcs(err_func_t *f, err_func_t *ef)
{
    logit = f;
    elogit = ef;
}
