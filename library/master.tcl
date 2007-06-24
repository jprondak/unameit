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
########################### Session Management Code ##########################
# $Id: master.tcl,v 1.40.4.4 1997/10/09 01:06:34 viktor Exp $
#

#
# Standard system calls for strongly authenticated users
#
proc unameit_user_init {slave principal pname} {
    #
    # Save interpreter principal uuid and user friendly string.
    #
    unameit_slave_record $slave unameitSlaveRec $principal $pname

    #
    # System calls available to kerberized users
    #
    lappend udb_interp_syscalls\
	unameit_create\
	unameit_update\
	unameit_delete\
	unameit_undelete\
	unameit_license_terms\
	{unameit_qbe udb_qbe -stream}\
	{unameit_fetch udb_fetch -stream}\
	{unameit_abort udb_rollback}\
	{unameit_root udb_get_root}\
	{unameit_schema_version udb_version schema}\
	{unameit_data_version udb_version data}\
	unameit_get_server_version

    lappend umeta_interp_syscalls\
	unameit_get_menu_info\
	unameit_get_class_metadata\
	unameit_get_collision_rules\
	unameit_get_attribute_classes\
	unameit_get_protected_attributes\
	unameit_get_net_pointers\
	unameit_get_error_code_info\
	unameit_get_error_proc_info

    if {[cequal $principal ""]} {
	#
	# Super user system calls
	#
	interp alias $slave unameit_shutdown {} unameit_shutdown
	interp alias $slave unameit_can_modify_schema $slave return 1
	lappend udb_interp_syscalls unameit_dump
	#
	# Super user can pass flags to commit
	#
	lappend udb_interp_syscalls\
	    {unameit_commit udb_commit}\
	    {unameit_protect udb_protect_items}
    } else {
	#
	# Mortals cannot pass flags to commit, or modify the schema
	#
	lappend udb_interp_syscalls {unameit_commit udb_commit --}
	interp alias $slave unameit_can_modify_schema $slave return 0
    }
    interp alias $slave unameit_get_toi_code {} unameit_get_toi_code

    #
    # Bind all system calls into safe interpreter
    #
    foreach interp {udb_interp umeta_interp} {
	foreach syscall [set ${interp}_syscalls] {
	    set target [lassign $syscall source]
	    if {[cequal $target ""]} {
		interp alias $slave $source $interp $source
	    } else {
		eval interp alias $slave $source $interp $target
	    }
	}
    }

    #
    # Allow slave to generate new UUID strings
    #
    load {} uuid $slave
}


#
# This version of unameit_login_trivial is specific to the unameitd
# server, and is used with the trivial package (for demos).
#
# Other components of the principal (e.g. instance) follow in
# args. If the client_type is privileged, the principal is set to
# the builtin UName*It.
#
# kerberos 5 format of principal name is used here for error
# messages.
#
# NOTE: the login routines may be moved to separate modules.
#
proc unameit_login_trivial {client_type domain args} {
    if {[cequal privileged $client_type]} {
	set principal ""
	set login UName*It
    } else {
	#
	set region\
	    [unameit_decode_items -result\
		[unameit_qbe -all region [list name = $domain]]]
	#
	if {[lempty $region]} {
	    return -code error -errorcode\
		[list UNAMEIT AUTH trivial ENODOMAIN $domain]
	}
	set cell [udb_interp eval udb_cell_of $region]
	unameit_decode_items\
	    [udb_interp eval [list udb_fetch -stream $cell name]]
	upvar 0 $cell cell_item
	#
	set login "[join $args /]@$cell_item(name)"
	lassign $args pname pinst
	#
	# Check for a unameit principal
 	#
	set match\
	    [unameit_decode_items -result\
		[unameit_qbe -all principal\
		    [list pname = $pname]\
		    [list pinst = $pinst]\
		    [list prealm = $cell]]]
	#
	# If the principal is not found,
	# look for a host principal with the hostname as an instance.
	#
	switch -- [llength $match] 0 {
	    set domain [join [lassign [split $pinst .] name] .]
	    set match\
		[unameit_decode_items -result\
		    [unameit_qbe -all host_principal \
			[list pname = $pname] \
			[list phost qbe "" [list name = $name] \
			[list owner qbe "" [list name = $domain]]] \
			[list prealm = $cell]]]
	}

	#
	# Error if single match is not found.
	#
	switch -- [llength $match] {
	    0 {
		return -code error -errorcode\
		    [list UNAMEIT AUTH auth ENOPRINCIPAL $login]
	    }
	    1 {
		set principal [lindex $match 0]
	    }
	    default {
		return -code error -errorcode\
		    [list UNAMEIT AUTH auth EPRINCIPALNOTUNIQUE $login]
	    }
	}
    }

    set session [interp create -safe [uuidgen]]
    #
    # Bind standard system calls
    #
    unameit_user_init $session $principal $login
    #
    # Return session handle
    #
    return $session
}


#
# This version of unameit_login_ukrbv is specific to the unameitd
# server, and is used with the ukrbv package (kerberos 5).
#
# Other components of the principal (e.g. instance) follow in
# args. If the client_type is privileged, the principal is set to
# the builtin UName*It.
#
# kerberos 5 format of principal name is used here for error
# messages.
#
# NOTE: the login routines may be moved to separate modules.
#
proc unameit_login_ukrbv {client_type prealm args} {
    #
    # Check for super user principal (same instance as server)
    #
    if {[cequal privileged $client_type]} {
	set login UName*It
	set principal ""
    } else {
	#
	# Reconstruct string representation for errors and auditing
	#
	set login "[join $args /]@$prealm"
	if {![lempty [lassign $args pname pinst]]} {
	    #
	    # We only support two part principals
	    #
	    return -code error -errorcode\
		[list UNAMEIT AUTH auth ENOPRINCIPAL $login]
	}
	#
	# Check for a unameit principal
 	#
	set query [list -all principal \
		[list pname = $pname] \
		[list pinst = $pinst] \
		[list prealm qbe "" [list name = [string tolower $prealm]]]]
	set match [unameit_decode_items -result [eval unameit_qbe $query]]
	#
	# If the principal is not found,
	# look for a host principal with the short hostname as an instance.
	#
	switch -- [llength $match] {
	    0 {
		set pieces [split $pinst .]
		set dp [lassign $pieces hostname]
		set domain [join $dp .]
		set query [list -all host_principal \
			[list pname = $pname] \
			[list phost qbe "" [list name = $hostname] \
			[list owner qbe "" [list name = $domain]]] \
			[list prealm qbe ""\
			[list name = [string tolower $prealm]]]]
		set match [unameit_decode_items -result [eval unameit_qbe $query]]
	    }
	}

	#
	# Error if single match is not found.
	#
	switch -- [llength $match] {
	    0 {
		return -code error -errorcode\
		    [list UNAMEIT AUTH auth ENOPRINCIPAL $login]
	    }
	    1 {
		set principal [lindex $match 0]
	    }
	    default {
		return -code error -errorcode\
		    [list UNAMEIT AUTH auth EPRINCIPALNOTUNIQUE $login]
	    }
	}
    }

    set session [interp create -safe [uuidgen]]
    #
    # Bind standard system calls
    #
    unameit_user_init $session $principal $login
    #
    # Return session handle
    #
    return $session
}

#
# Kerberos 4 version of the above routine.
#
proc unameit_login_ukrbiv {client_type prealm args} {
    #
    # Check for super user principal (same instance as server)
    #
    if {[cequal privileged $client_type]} {
	set login UName*It
	set principal ""
    } else {
	#
	# Build a string to use for reporting purposes
	#
	set login "[join $args .]@$prealm"
	lassign $args pname pinst
	#
	# Check for a unameit principal
 	#
	set query [list -all principal \
		[list pname = $pname] \
		[list pinst = $pinst] \
		[list prealm qbe "" [list name = [string tolower $prealm]]]]
	set match [unameit_decode_items -result [eval unameit_qbe $query]]
	#
	# Error if single match is not found.
	#
	switch -- [llength $match] {
	    0 {
		return -code error -errorcode\
		    [list UNAMEIT AUTH auth ENOPRINCIPAL $login]
	    }
	    1 {
		set principal [lindex $match 0]
	    }
	    default {
		return -code error -errorcode\
		    [list UNAMEIT AUTH auth EPRINCIPALNOTUNIQUE $login]
	    }
	}
    }
    set session [interp create -safe [uuidgen]]
    #
    # Bind standard system calls
    #
    unameit_user_init $session $principal $login
    #
    # Return session handle
    #
    return $session
}

#
# Authenticate a user
#
proc unameit_login_upasswd {login passwd} {
    #
    # Build query to find the user.
    #
    set query [list user_login [list name = $login] shell password]
    #
    # Execute the query
    #
    set match [unameit_decode_items -result [eval unameit_qbe $query]]
    #
    # Want all users with the given password.
    #
    set uuidlist {}
    foreach uuid $match {
	upvar 0 $uuid item
	set upass $item(password)
	set cpass [unameit_crypt $passwd $upass]
	if {[cequal $cpass $upass]} {
	    lappend uuidlist $uuid
	}
    }

    if {[lempty $uuidlist]} {
	return -code error -errorcode\
	    [list UNAMEIT AUTH upasswd ENOLOGIN $login]
    }

    set session [interp create -safe [uuidgen]]
    unameit_slave_record $session unameitSlaveRec "" $login
    #
    # Can only change password/shell for this uuid
    #
    interp alias $session unameit_change_password\
	udb_interp unameit_change_password $uuidlist
    interp alias $session unameit_change_shell\
	udb_interp unameit_change_shell $uuidlist
    #
    # Return session handle
    #
    return $session
}

proc unameit_begin {session} {
    foreach {puuid pname} [unameit_slave_record $session unameitSlaveRec] {
	unameit_transaction $pname
	unameit_principal $puuid
	break
    }
}

proc unameit_shutdown {} {
    #
    # It MUST be possible to restart the server as soon as
    # "unameit_shutdown" completes on the client.
    #
    # Shutdown the database and terminate the client loop
    # This must close down the server socket before (or without)
    # replying to the client.
    #
    udb_interp eval udb_shutdown
    unameit_end_loop
}

proc unameit_get_toi_code {} {
    upvar #0 UNAMEIT_TOI_CACHE cache
    #
    # Initialize to empty if not set.  Otherwise NOOP.
    #
    append cache(path) ""
    append cache(mtime) ""
    #
    # Compute toi pathname.
    #
    switch -- $cache(path) "" {
	set cache(path) [unameit_filename UNAMEIT_TOILIB toi.tcl]
    }
    #
    # If mtime has changed,  reread.
    #
    file stat $cache(path) fileInfo
    switch -- $cache(mtime) $fileInfo(mtime) {} default {
	set fd [open $cache(path) r]
	fconfigure $fd -buffersize $fileInfo(size)
	set cache(data) [read $fd]
	close $fd
	set cache(mtime) $fileInfo(mtime)
    }
    #
    # Return data.
    #
    set cache(data)
}
