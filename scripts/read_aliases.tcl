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
# $Id: read_aliases.tcl,v 1.4.12.1 1997/08/28 18:29:18 viktor Exp $
#

# Parse a mail aliases file.
# May be replaced by a C or lex scanner.


#
# Return the next line. Discard comments and blank lines.
# return 0 on eof
#
proc mgets_line {filehandle line_name} {
    upvar 1 $line_name line
    while {0 <= [gets $filehandle line]} {
	if {[regexp -- {^[ \t]*$} $line]} {
	    continue
	}
	if {[regexp -- {^[ \t]*#} $line]} {
	    continue
	}
	return 1
    }
    return 0
}

#
# Returns 0 on eof.
# Sets line_name to the next unfolded line in the file.
# The global variable mgets_previous_line contains the line previously read,
# which is required by the CRLF-LWSP unfolding (line continuation).
# Since many unix systems seem to have discarded the CR, we treat
# newline-LWSP as a continuation.
#
# TBD - this may eventually be a C or lex-yacc function.
# 
proc mgets_entry {filehandle line_name} {
    
    upvar 1 $line_name line
    global mgets_previous_line 

    if {! [info exists mgets_previous_line]} {
	set mgets_status [mgets_line $filehandle mgets_previous_line]

	if {! $mgets_status} {
	    return 0
	}
    }

    set line $mgets_previous_line
    while {[set mgets_status [mgets_line $filehandle mgets_previous_line]]} {
	set first [string index $mgets_previous_line 0]
	if {[cequal " " $first] || [cequal "\t" $first]} {
	    append line $mgets_previous_line
	} else {
	    return 1
	}
    }

    set line [string trim $line]
    if [cequal "" $line] {
	unset mgets_previous_line 
	return 0
    }
    return 1
}

proc split_members {line m} {

    upvar 1 $m members

    set members {}
    foreach data [split $line ,] {
	set data [string trim $data]

	set comment ""
	set sep ""
	while {[regexp {^([^(]*)\(([^)]*)\)(.*)} $data x a1 c a2]} {
	    append comment "$sep$c"
	    set sep " "
	    set data [string trim "[string trim $a1] [string trim $a2]"]
	}
	
	log_debug "data: $data"
	log_debug "commment: $comment"
	if {[string length $data] > 0} {
	    lappend members [list $data $comment]
	}
    }
}

#
# Returns 0 on eof.
# Sets alias to the alias name and sets members to a list of members.
#
# TBD - this may eventually be a C or lex-yacc function.
#
proc mgets {filehandle alias_name members_name} {
    upvar 1 $alias_name alias \
	    $members_name member_list


    set member_list {}
    set alias ""

    if {! [mgets_entry $filehandle line]} {
	return 0
    }

    if {! [regexp -- {([^:]*):(.*)} $line junk a members]} {
	error "bad line in alias file : $line"
    }

    set alias [string trim $a]
    split_members $members member_list
    return 1
}

