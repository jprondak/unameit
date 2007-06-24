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
# This routine formats an error message in the variable named by vtext.
# The return value indicates whether the error was:
#
#	normal		a user error that has been formatted
#	internal	a unameit error (bug) that has been formatted
#	unknown		a unameit error that could not be handled
#	other		not a unameit error - try another package
#
# The input in arglist is usually the global errorCode.
# The arglist will be:
#
#	UNAMEIT AUTH ukrbiv error_message symbol args
#
# where error_message is the kerberos 4 error text.
#
proc unameit_authorize_errtext_ukrbiv {vtext arglist} {
    upvar 1 $vtext text

    set arglist [lassign $arglist system subsystem module error_message symbol]

    switch -exact -- $symbol {
	EBADARGS {
	    set text "wrong number of arguments"
	    return internal
	}
	APINVAL {
	    set text "Kerberos 4 authentication packet is too long."
	    return internal
	}
	CCACHENOTDEST {
	    lassign $arglist ccache_type ccache_name
	    set text "WARNING: Your credential cache could not be destroyed.\n"
	    append text "ccache_type: $ccache_type\n"
	    append text "ccache_name: $ccache_name\n"
	    append text "Kerberos 4 error: $error_message"
	    return normal
	}
	CCACHETYPE {
	    lassign $arglist ccache_type
	    set text "Not a supported ccache_type.\n"
	    append text "ccache_type: $ccache_type\n"
	    append text "Kerberos 4 error: $error_message"
	    return internal
	}
	GETCRED {
	    set text "Could not read key from ticket file.\n"
	    append text "Kerberos 4 error: $error_message"
	    return internal
	}
	MKREQ {
	    lassign $arglist name inst realm
	    set text "Could not get service ticket.\n"
	    append text "Service: $name.$inst@$realm\n"
	    append text "Kerberos 4 error: $error_message"
	    return normal
	}
	KINIT {
	    lassign $arglist name inst realm
	    set text "Password kinit: $name.$inst@$realm.\n"
	    append text "Kerberos 4 error: $error_message"
	    return normal
	}
	KSINIT {
	    lassign $arglist srvtab name inst realm
	    set text "Srvtab kinit: $name.$inst@$realm.\n"
	    append text "Kerberos 4 error: $error_message"
	    return normal
	}
	RDREQ {
	    set text "Authentication error on server.\n"
	    append text "Kerberos 4 error: $error_message"
	    return normal
	}
	NOPASSWORD {
	    set text "You must enter a password."
	    return normal
	}
	NOSETSERVICE {
	    set text "Server's identity not initialized"
	    return internal
	}
	NOSETSERVER {
	    set text "Server principal not initialized"
	    return internal
	}
	default {
	    set text "Could not authenticate.\n"
	    append text "Kerberos 4 error: $error_message"
	    return normal
	}

    }
    return unknown
}
