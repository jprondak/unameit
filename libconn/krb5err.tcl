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
#	UNAMEIT AUTH ukrbv error_message symbol args
#
# where error_message is the kerberos 5 error text.
#
proc unameit_authorize_errtext_ukrbv {vtext arglist} {
    upvar 1 $vtext text

    set arglist [lassign $arglist system subsystem module error_message symbol]
    switch -exact -- $symbol {
	BADARGS {
	    set text "wrong number of arguments"
	    return internal
	}
	BADPASSWORD {
	    set text "Password (or keytab key) is invalid."
	    return normal
	}
	BADPRINCIPAL {
	    lassign $arglist name inst realm
	    set text "Malformed kerberos principal: $name/$inst@$realm"
	    return normal
	}
	CCACHEINIT {
	    lassign $arglist ccache_type ccache_name
	    set text "Could not initialize credential cache.\n"
	    append text "ccache_type: $ccache_type\n"
	    append text "ccache_name: $ccache_name\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	CCACHENOTDEST {
	    lassign $arglist ccache_type ccache_name
	    set text "WARNING: Could not destroy credential cache.\n"
	    append text "ccache_type: $ccache_type\n"
	    append text "ccache_name: $ccache_name\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	CCACHERESOLVE {
	    lassign $arglist ccache_type ccache_name
	    set text "Invalid credential cache.\n"
	    append text "ccache_type: $ccache_type\n"
	    append text "ccache_name: $ccache_name\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	CCACHETYPE {
	    lassign $arglist ccache_type
	    set text "Not a supported credential cache type.\n"
	    append text "ccache_type: $ccache_type\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	FCC_NOFILE {
	    lassign $arglist ccache_type ccache_name
	    switch -exact -- $ccache_type {
		temporary {
		    set text "In-memory credential cache could not be used."
		    return internal
		}
		file {
		    set text "Your credential cache file could not be found.\n"
		    append text "(Did you kinit?)\n"
		    append text "ccache_name: $ccache_name"
		    return normal
		}
		default {
		    set text "Cannot access default credential cache.\n"
		    append text "(Did you kinit?)"
		    return normal
		}
	    }
	}
	INIT {
	    set text "Could not initialize Kerberos V context:\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	KEYTAB {
	    lassign $arglist keytab
	    set text "Invalid keytab file: $keytab\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	KINIT {
	    lassign $arglist principal
	    set text "Password kinit: $principal.\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	KSINIT {
	    lassign $arglist principal
	    set text "Keytab kinit: $principal.\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	MKREQ {
	    set text "Could not get service ticket.\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	NOPASSWORD {
	    set text "You must enter a password."
	    return normal
	}
	NOSETCCACHE {
	    set text "Missing or misconfigured login_type."
	    return normal
	}
	NOSETSERVER {
	    set text "Remote server principal not initialized"
	    return internal
	}
	NOSETSERVICE {
	    set text "Service principal and keytab not initialized"
	    return internal
	}
	PRINCIPAL_UNKNOWN {
	    lassign $arglist principal
	    set text "Principal not found in kerberos 5 database: $principal"
	    return normal
	}
	RDREQ {
	    set text "Authentication error on server.\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
	default {
	    set text "Could not authenticate.\n"
	    append text "Kerberos 5 error: $error_message"
	    return normal
	}
    }
    return unknown
}
