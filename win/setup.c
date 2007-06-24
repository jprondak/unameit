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
 * The location of the unameit tree is extracted from the command line,
 * the environment is set so that the unameit modules will run,
 * then wishx is used to execute the installation script. The location
 * of the unameit tree is passed to the script, along with the Registry
 * key to use.
 * 
 */
#include <unameit_start.h>
#include <version.h>

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
    MessageBox(NULL, buf, "Fatal Error",
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
    STARTUPINFO si;
    PROCESS_INFORMATION pi;
    BOOL result;
    DWORD dresult;
    const char *sresult;
    char unameit[MAX_PATH];
    char wunameit[MAX_PATH];
    char command[BUFSIZE];
    LPTSTR filename;
    char *p;
    
    SetLastError(0);
    dresult = GetModuleFileName (NULL, unameit, sizeof(unameit));
    if (dresult <= 0 || dresult >= sizeof(unameit))
	ErrorExit ("could not get module name");
	
	/*
	 * the executable is in the bin subdirectory.
	 */
    dresult = GetFullPathName (unameit, sizeof(unameit), 
			       unameit, &filename);
    if (dresult <= 0 || dresult >= sizeof (unameit))
	ErrorExit ("could not get path of module");
    *(filename - 1) = '\0';
	
    dresult = GetFullPathName (unameit, sizeof(unameit), 
			       unameit, &filename);
    if (dresult <= 0 || dresult >= sizeof (unameit))
	ErrorExit ("could not get path of module's parent");
    *(filename - 1) = '\0';

    /*
     * Save the Windows name and make a unix (TCL) usable version.
     */
    strcpy (wunameit, unameit);
    for (p = unameit; *p; p++)
	if (*p == '\\')
	    *p = '/';
    
    sresult = unameit_setenviron (unameit, "c:/unameit");
    if (sresult != NULL)
	ErrorExit (sresult);

    sprintf (command, "\"%s\\bin\\wishx.exe\" \"%s/lib/unameit/unameit_setup.tcl\" Root \"%s\" top_key \"%s\" version \"%s\"", wunameit, unameit, wunameit, TOP_KEY, UNAMEIT_VERSION);

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
    {
	char message[1000];
	sprintf (message, "Could not execute setup command.\n%s\n", command);
	ErrorExit(message);
    }
    
    /*
     * Close process and thread handles. 
     */
    CloseHandle( pi.hProcess );
    CloseHandle( pi.hThread );
#if 0
    MessageBox(NULL, command, "Started Installation Script",
            MB_ICONSTOP | MB_OK | MB_TASKMODAL | MB_SETFOREGROUND);
#endif
    return 0;                   /* Needed only to prevent compiler warning. */
}
