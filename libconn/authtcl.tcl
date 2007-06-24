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
# TCL procs useful by callers of the auth module.
# This file gets frinked.

#
# Use the currently set values to login to the server.
#
proc unameit_authorize_login_a {vn} {
    upvar 1 $vn login

    set auth $login(authentication)

    # get ticket granting ticket (or equivalent operation)
    foreach command $login(auth_operations) {
	set params [unameit_authorize_params $auth $command]
	set cmd [list unameit_authorize $auth $command]
	foreach p $params {
	    lappend cmd $login($p)
	}
	eval $cmd
    }

    # login to unameit server
    unameit_send_auth $auth

    # finished with credential cache
    switch -- $login(ccache_type) {
	temporary {
	    unameit_authorize $auth kdestroy
	}
    }
}


#
# Extract the configuration into an array and login to the server.
# This proc is used by non-gui applications, where the user has no
# way of overriding configuration settings.
#
proc unameit_authorize_login {vn} {
    upvar 1 $vn config
    set auth [unameit_config config authentication]
    unameit_auth_configure_client config login $auth
    unameit_authorize_login_a login
}

#
# Set up server side authentication parameters.
#
proc unameit_auth_configure_server {p_config p_auth auth_type} {
    upvar 1 $p_config config
    upvar 1 $p_auth auth

    if {[catch {package require $auth_type}]} {
	return -code error\
	    -errorcode [list UNAMEIT AUTH auth ENOMOD $auth_type]
    }

    set auth(authentication) $auth_type

    array set auth\
	[list \
	    use_keytab		1 \
	    use_ccache		0 \
	    use_password	0 \
	    ccache_type		temporary]

    set auth(auth_operations) set_service
    set lps(paramList) {}
    unameit_auth_add_params lps $auth_type set_service
    set auth(auth_parameters) $lps(paramList)

    # Lookup the parameters that have not been initialized by the caller
    foreach lp $auth(auth_parameters) {
	if {[info exists auth($lp)]} continue
	set auth($lp) [unameit_config config $lp $auth_type]
    }
}

#
# Translates login_type into the use_X keywords in the named variable.
# Also sets auth_parameters, which is a list of all parameters needed
# for authentication.
#
# The indexes in the authentication variable are just the parameter
# keywords, so if the type of authentication changes this proc should
# be called again.
#
#
proc unameit_auth_configure_client {p_config p_auth auth_type} {
    upvar 1 $p_config config
    upvar 1 $p_auth auth

    if {[catch {package require $auth_type}]} {
	return -code error\
	    -errorcode [list UNAMEIT AUTH auth ENOMOD $auth_type]
    }

    set login_type [unameit_config config login_type $auth_type]

    set auth(authentication) $auth_type

    set auth(login_type) $login_type

    switch -exact -- $login_type {
	write_temp_ccache_password {
	    array set auth [list \
		    use_keytab		0 \
		    use_ccache		0 \
		    use_password	1 \
		    ccache_type		temporary]
	}
	root -
	write_temp_ccache_keytab {
	    array set auth [list \
		    use_keytab		1 \
		    use_ccache		0 \
		    use_password	0 \
		    ccache_type		temporary]
	}
	read_permanent_ccache {
	    array set auth [list \
		    use_keytab		0 \
		    use_ccache		1 \
		    use_password	0 \
		    ccache_type		file]
	}
	default -
	read_default_ccache {
	    array set auth [list \
		    use_keytab		0 \
		    use_ccache		1 \
		    use_password	0 \
		    ccache_type		default]
	}
	write_default_ccache_password {
	    array set auth [list \
		    use_keytab		0 \
		    use_ccache		0 \
		    use_password	1 \
		    ccache_type		default]
	}
	write_default_ccache_keytab {
	    array set auth [list \
		    use_keytab		1 \
		    use_ccache		0 \
		    use_password	0 \
		    ccache_type		default]
	}
	write_permanent_ccache_password {
	    array set auth [list \
		    use_keytab		0 \
		    use_ccache		0 \
		    use_password	1 \
		    ccache_type		file]
	}
	write_permanent_ccache_keytab {
	    array set auth [list \
		    use_keytab		1 \
		    use_ccache		0 \
		    use_password	0 \
		    ccache_type		file]
	}
	default {
	    error "Invalid login type: $login_type" {}\
		[list UNAMEIT AUTH auth BADLTYPE $login_type]
	}
    }

    set lops [list set_server set_ccache]
    if {$auth(use_keytab)} {
	lappend lops ksinit
    } elseif {$auth(use_password)} {
	lappend lops kinit
    }

    set auth(auth_operations) $lops
    set lps(paramList) {}
    foreach lop $lops {
	unameit_auth_add_params lps $auth_type $lop
    }
    set auth(auth_parameters) $lps(paramList)

    # Lookup the parameters that have not been initialized by the caller.
    foreach lp $auth(auth_parameters) {
	if {[info exists auth($lp)]} continue
	set auth($lp) [unameit_config config $lp $auth_type]
    }
    #
    # For daemon clients client_principal == service.
    switch -- $login_type root {
	set auth(client_principal) $auth(service)
    }
}


#
# Build a command using data from an array. The parameter names are
# obtained from the command in the module. This is needed since the
# unameit_authorize command does not always have access to the array.
#
proc unameit_authorize_do {vn command} {
    upvar 1 $vn login

    set auth $login(authentication)
    set params [unameit_authorize_params $auth $command]
    set cmd [list unameit_authorize $auth $command]
    foreach p $params {
	lappend cmd $login($p)
    }
    eval $cmd
}

#
# Build mapping of parameter -> list of commands.
#
proc unameit_auth_add_params {p auth command} {
    upvar 1 $p pArray
    foreach p [unameit_authorize_params $auth $command] {
	if {![info exists pArray($p)]} {
	    lappend pArray(paramList) $p
	}
	lappend pArray($p) $command
    }
}


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
#
# The error handling procedure is either for itself (auth) or
# for a module within it (e.g. ukrbv). A proc is searched for
# by name (unameit_authorize_error_$module, e.g.
# unameit_authorize_errtext_$ukrbv); the proc should be defined in
# every package.
#
proc unameit_authorize_errtext {vtext arglist} {
    upvar 1 $vtext text
    lassign $arglist system subsystem module
    set eproc unameit_authorize_errtext_$module
    set fproc [info procs $eproc]

    if {[cequal $eproc $fproc]} {
	return [$eproc text $arglist]
    }
    return unknown
}

#
# The auth module handles errors for authentication in general, and
# also for the login procs in unameitd (see library/master.tcl) and
# other servers.
#
proc unameit_authorize_errtext_auth {vtext arglist} {
    upvar 1 $vtext text

    set arglist [lassign $arglist system subsystem module symbol]

    switch -- $symbol {
	EBADARGS {
	    set text "wrong number of arguments"
	    return internal
	}
	BADLTYPE {
	    lassign $arglist login_type
	    set text "Invalid login type: $login_type."
	    return normal
	}
	EBADMIC {
	    set text "Message integrity check failed."
	    return normal
	}
	EIO {
	    set text "The connection to the server is broken."
	    return normal
	}
	ENOMOD {
	    lassign $arglist module
	    set text "Authentication module is not available: $module."
	    return normal
	}
	ENOPRINCIPAL {
	    lassign $arglist principal
	    set text "Principal not in UName*It database: $principal"
	    return normal
	}
	ENOTSUPPCMD {
	    lassign $arglist authentication command
	    set text "Authentication command not supported: $command."
	    return internal
	}
	EPRINCIPALNOTUNIQUE {
	    lassign $arglist principal
	    set text "Principal not unique in UName*It database: $principal"
	    return internal
	}
	EWEAKMOD {
	    set text "Authentication module is not accepted by server."
	    return normal
	}
    }
    return unknown
}
