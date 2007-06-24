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
# $Id: textview.tcl,v 1.2.12.1 1997/08/28 18:30:11 viktor Exp $
#

# Create a toplevel with a scrolling text area in it.
# Uses as a convenient way to display large areas of text.
#
# Inputs are:
#	
#	parent - master toplevel
#	textview - name of toplevel to create
#	title - title of created toplevel
#	stuff - string to display
#	
# Returns name of text area.

proc textview {parent textview title stuff} {

    catch {destroy $textview}
    toplevel $textview
    wm transient $textview $parent
    wm title $textview $title
    
    pack [button $textview.quit -command "destroy $textview" -text OK] -side bottom
    
    set text $textview.text
    set sb $textview.vsb
    text $text -yscrollcommand "$sb set" 
    scrollbar $sb -command "$text yview"
    pack $sb -side right -fill y
    pack $text -side left
    $text insert end $stuff
    $text configure -state disabled
    return $text
}    

package provide Textview 1.0
