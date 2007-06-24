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
/*
 *
 * This wrapper sets the mode to the value of the first argument,
 * and then uses the rest of the command to start another application.
 * The location of UNAMEIT is retrieved from the registry and used
 * to adjust the environment.
 * 
 */
#include <unameit_start.h>

static void ErrorExit (const char *msg)
{
    DWORD err = GetLastError();
    
    fprintf (stderr, "%s\n", msg);
    if (err != 0)
    {
	LPVOID lpMsgBuf;
	FormatMessage( 
	    FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
	    NULL,
	    err,
	    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
	    (LPTSTR) &lpMsgBuf,
	    0,
	    NULL);
	fprintf (stderr, "%s\n", lpMsgBuf);
	LocalFree( lpMsgBuf );
    }
    
    exit (1);
}

/*
 * The location of the unameit tree is extracted from the registry, and
 * the environment is set so that the unameit modules will run,
 * then the executable is started. The environment PATH is set,
 * This program waits for the child to finish, then exits.
 */

main (int argc,
      char *argv[])
{
    int i;
    char *mode = NULL;
    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    BOOL result;
    char *command = NULL;
    const char *eres;
    
    SetLastError(0);
    command = GetCommandLine ();
    if (!command)
	ErrorExit ("could not get command line");

    /*
     * Skip command name, then whitespace.
     */
    while (*command && !isspace(*command)) command++;
    while (*command && isspace(*command)) command++;
    if (strlen (command) < 1)
	ErrorExit ("usage: unameit_con command [args]");
    
    /*
     * Set the environment.
     */
    eres = unameit_setenv ();
    if (eres != NULL)
    {
	ErrorExit (eres);
    }
	
    ZeroMemory( &si, sizeof(si) );
    si.cb = sizeof(si);

    /*
     * Start the child process. 
     */
    result = CreateProcess (NULL, 
			    command, 
			    NULL,    
			    NULL,    
			    FALSE,   
			    0,       
			    NULL,    
			    NULL,    
			    &si,     
			    &pi );
    if (!result)
	ErrorExit( "CreateProcess failed." );

    /*
     * Wait for the child to finish.
     * 
     */
    WaitForSingleObject (pi.hProcess, INFINITE);

    /*
     * Close process and thread handles. 
     */
    CloseHandle( pi.hProcess );
    CloseHandle( pi.hThread );

    return (0);
}
