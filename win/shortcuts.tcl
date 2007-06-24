#
# Copyright (c) 1997 Enterprise Systems Management Corp.
#
# This file is part of UName*It.
#
# UName*It is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2, or (at your option) any later
# version.
#
# UName*It is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with UName*It; see the file COPYING.  If not, write to the Free
# Software Foundation, 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA.
#
# $Id: shortcuts.tcl,v 1.7.10.1 1997/08/28 18:30:10 viktor Exp $
#

#
# Create a set of shortcuts. This will add items to the Start Menu or
# to a desktop.
#
# The definitions are read from UNAMEIT/install/start_menu.dat.
#
# This script is run by unameit_win, so it will inherit environment variables
# for UNAMEIT.

package require Config
package require Shortcut
load [unameit_filename UNAMEIT bin tclreg80.dll] registry
#
# Return the directory name for shortcuts.
# The type is:
#	CurrentUser
#	AllUsers
#
proc unameit_special_folder {which} {
    switch -- $which {
	AllUsers {
	    set key HKEY_LOCAL_MACHINE
	    set name "Common Programs"
	}

	CurrentUser {
	    set key HKEY_CURRENT_USER
	    set name "Programs"
	}
	default {
	    error "invalid folder type $which"
	}
    }

    append key "\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders"

    set entry [registry get $key $name]
    return [file nativename [file join $entry UNameIt]]
}

# Make shortcut to exe in bin directory
proc unameit_make_shortcut {top link path arguments} {
    file mkdir $top
    set link [file join $top $link]
    set path [unameit_nativename UNAMEIT_BIN $path]
    shortcut_create $link $path $arguments "" ""
}

proc unameit_delete_shortcut {top link} {
    file delete -- [file join $top $link]
}
    
proc unameit_make_shortcuts {top} {
    unameit_make_shortcut $top {Krb5 Tickets.lnk} unameit_win.exe krb5.exe
    unameit_make_shortcut $top {Edit Modes.lnk} unameit_win.exe \
	    "wishx.exe \"[unameit_filename unameit_mode_edit]\""
    unameit_make_shortcut $top Wishx.lnk unameit_win.exe wishx.exe 
}

package provide Shortcuts 1.0
