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
#
# $Id: error.tcl,v 1.3.16.1 1997/07/09 21:07:57 viktor Exp $
#

#
# This is the general error handling module. It calls the appropriate module
# for formatting error messages.
#

#
# This routine formats an error message in the variable named by vtext.
# The return value indicates whether the error was:
#
#	normal		a user error that has been formatted
#	internal	a unameit error (bug) that has been formatted
#	unknown		a unameit error that could not be handled
#	other		not a unameit error - try another package
#
# The input in arglist is usually the global errorCode.
#
proc unameit_error_get_text {vtext arglist} {

    upvar 1 $vtext text

    lassign $arglist system subsystem detail

    switch -- $system {
	UNAMEIT {
	}
	default {
	    return other
	}
    }

    #
    # You can't go get the error text for a CONN error! The
    # server connection is broken. Just return a normal error.
    # TBD - make error handler.
    # 
    # unameit_get_errtext does not exist unless the client has
    # connected, so check before calling
    #
    switch -exact -- $subsystem {
	CONN {
	    switch -- $detail {
		EBADMIC {
		    set text "Message integrity check failed"
		}
		EMALFORMED {
		    set text "Malformed server reply"
		}
		EIO -
		default {
		    set text "Lost connection with server"
		}
	    }
	    return unameit
	}
	AUTH {
	    return [unameit_authorize_errtext text $arglist]
	}
	default {
	    if {![lempty [info commands unameit_get_errtext]]} {
		lassign [unameit_get_errtext $arglist] type text
		return $type
	    }
	}
    }

    # we should not be here
    return unknown
}

package provide Error 1.0
