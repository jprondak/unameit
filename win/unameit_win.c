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
 * This wrapper uses the rest of the command to start another application.
 * The location of UNAMEIT is retrieved from the registry and used
 * to adjust the environment.
 * 
 */
#include <unameit_start.h>

void
ErrorExit (const char *msg)
{
    char buf[1000];
    strcpy (buf, msg);
    strcat (buf, "\n");

    FormatMessage( 
	FORMAT_MESSAGE_FROM_SYSTEM,
	NULL,
	GetLastError(),
	MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), 
	(LPTSTR) buf + strlen (buf),
	sizeof (buf) - strlen (buf),
	NULL);

    MessageBeep(MB_ICONEXCLAMATION);
    MessageBox(NULL, msg, "Fatal Error",
            MB_ICONSTOP | MB_OK | MB_TASKMODAL | MB_SETFOREGROUND);
    ExitProcess(1);
}


/*-----------------------------------------------------------------------------
 * WinMain --
 *
 * This is the main program for the application.
 *-----------------------------------------------------------------------------
 */
int APIENTRY
WinMain (HINSTANCE hInstance, 
	 HINSTANCE hPrevInstance, 
	 LPSTR lpszCmdLine, 
	 int nCmdShow)
{
    char mode[MAX_PATH];
    char *command = lpszCmdLine;
    const char *eres;
    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    BOOL result;

    while (*command && isspace(*command)) command++;
    
    if (strlen (command) < 1)
	ErrorExit ("usage: unameit_win command [args]");

    eres = unameit_setenv ();
    if (eres != NULL)
	ErrorExit (eres);
	
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
	ErrorExit(command);

    /*
     * Close process and thread handles. 
     */
    CloseHandle( pi.hProcess );
    CloseHandle( pi.hThread );

    return 0;                   /* Needed only to prevent compiler warning. */
}
