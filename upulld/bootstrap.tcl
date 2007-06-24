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
# Carefully clear a list of arrays.
#
proc unameit_clear_vars {vars} {
    foreach var $vars {
	upvar 1 $var val
	if {![info exists val]} continue
	unset val
    }
}

proc unameit_start {} {
    global unameitPriv
    package require Config
    package require Error

    if {[catch {
	unameit_getconfig unameitPriv upulld
	#
	# Set up the authentication modules
	#
	foreach auth [unameit_config unameitPriv authentications] {
	    package require $auth
	    # The same procedure applies to all authentications
	    proc unameit_login_$auth {client_type prealm args} unameit_login
	    unameit_auth_configure_server unameitPriv auth_config $auth
	    unameit_authorize_do auth_config set_service
	    catch {unset auth_config}
	}
	
	uplevel #0 {
	    catch {memory init on}
	    set datadir [file join [unameit_config unameitPriv data] data]
	    set port [unameit_config unameitPriv service]
	    set timeout [unameit_config unameitPriv timeout]

	    cd $datadir
	    if {[unameit_config unameitPriv foreground] == 0} {
		set tcl_interactive 0
		unameit_daemon_fork
		unameit_daemon_mode
	    }
	    catch {unameit_pull_version}
	    unameit_client_loop $port $timeout
	}
    } msg]} {
	global errorCode errorInfo
	unameit_error_get_text msg $errorCode
	puts stderr $msg
	exit 1
    }
}

proc unameit_this_pulld_is_root {} {
    global unameitPriv
    #
    # Use configuration information to compare our FQDN
    # with FQDN of UName*It server.
    #
    cequal\
	[host_info official_name [info hostname]]\
	[host_info official_name\
	    [unameit_config unameitPriv server_host "" unameit]]
}

proc unameit_pull_version {} {
    global VERSION UUID_TO_HOST UUID_TO_IP IP_TO_UUID UUID_TO_SECONDARY_IFS
    global HOST_TO_UUID unameitPriv

    ## Get latest version from file
    if {[catch {open gen.version r} f]} {
	unameit_clear_vars VERSION
	if {[unameit_this_pulld_is_root]} {
	    error "Please run 'ubackend' at least once before 'upull'"
	} else {
	    error "Please run 'upull' on\
		[unameit_config unameitPriv server_host "" unameit] first"
	}
    }
    set result [gets $f latest_version]
    close $f
    if {$result == -1} {
	error "UName*It Pull: gen.version file is empty."
    }

    ## If no change, return version
    if {[info exists VERSION] && [cequal $VERSION $latest_version]} {
	return $VERSION
    }

    ## Clear out global arrays
    unameit_clear_vars {
	UUID_TO_HOST UUID_TO_IP IP_TO_UUID UUID_TO_SECONDARY_IFS HOST_TO_UUID
    }

    ## Read new host info
    set f [open gen.$latest_version/canon_hosts r]
    while {[gets $f line] != -1} {
	lassign [split $line |] uuid address name scope owner \
		ifname macaddr receives_mail
	set UUID_TO_HOST($uuid) $name.$owner
	set UUID_TO_IP($uuid) $address
	set IP_TO_UUID($address) $uuid
	set HOST_TO_UUID($name) $uuid
    }
    close $f

    ## Read new secondary if info
    set f [open gen.$latest_version/secondary_ifs]
    while {[gets $f line] != -1} {
	lassign [split $line |] if ip mac hname scope owner huuid
	lappend UUID_TO_SECONDARY_IFS($huuid) $if@$ip
    }
    close $f

    set VERSION $latest_version
    return $VERSION
}


proc unameit_pull_whoami {uuid} {
    global UUID_TO_HOST UUID_TO_IP UUID_TO_SECONDARY_IFS

    unameit_pull_version
    if {![info exists UUID_TO_HOST($uuid)]} {
	error "$uuid doesn't exist in the pull data"
    }
    set secondary_ifs_value ""
    if {[info exists UUID_TO_SECONDARY_IFS($uuid)]} {
	set secondary_ifs_value $UUID_TO_SECONDARY_IFS($uuid)
    }
    return [list host $UUID_TO_HOST($uuid) \
	    ip $UUID_TO_IP($uuid) \
	    secondary_ifs $secondary_ifs_value]
}

proc unameit_get_uuid {} {
    unameit_pull_version
    if {[catch {open ../uuid r} fd]} {
	error "Cannot open uuid file on pull server. Run upull on pull server\
		first."
    }
    if {[gets $fd line] == -1} {
	close $fd
	error "uuid file on pull server is empty. Run upull on pull server\
		first."
    }
    close $fd
    set line
}

proc unameit_pull_uuid {ip} {
    global IP_TO_UUID

    unameit_pull_version
    if {![info exists IP_TO_UUID($ip)]} {
	error "Cannot find host with IP address $ip"
    }
    set IP_TO_UUID($ip)
}


proc unameit_pull_readdir {dir} {
    #
    # No absolute paths,  and no use of `..'
    #
    if {[regexp {^/} $dir] ||
    [regexp {(^|/)..(/|$)} $dir]} {
	error {Permission denied} {} {UNAMEIT EPERM $dir}
    }
    set flist {}
    foreach f [readdir $dir] {
	lappend flist $f [file type $dir/$f]
    }
    set flist
}

proc unameit_pull_get_host_uuid {host} {
    global HOST_TO_UUID

    unameit_pull_version
    if {![info exists HOST_TO_UUID($host)]} {
	error "Cannot find host $host in UName*It"
    }
    return $HOST_TO_UUID($host)
}

######################### Context switch code ######################
#
# generic login. Handles any form of authentication.
#
proc unameit_login {} {

    set session [interp create -safe]
    #
    # Exported System calls
    #
    lappend syscalls \
	    unameit_pull_readdir \
	    unameit_pull_uuid \
	    unameit_pull_version \
	    unameit_pull_whoami \
	    unameit_get_uuid \
	    unameit_pull_get_host_uuid
    #
    # Bind all system calls into safe interpreter
    #
    foreach syscall $syscalls {
	set target [lassign $syscall source]
	if {[cequal $target ""]} {
	    set target $source
	}
	interp alias $session $source {} $target
    }
    #
    # Load Upull_slave package (unameit_pull_read_file)
    #
    load {} Upull_slave $session
    return $session
}

#
# We don't need to keep track of the current principal
# We don't do transactions
#
proc unameit_begin {session} {}
proc unameit_commit {} {}
proc unameit_abort {} {}
