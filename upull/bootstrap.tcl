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

# You must be connected and authorized to a pull server before calling this
# function.
proc GetThisHostUuid {} {
    global HOST_UUID pullPriv

    set datadir $pullPriv(data)
    if {![cequal $HOST_UUID ""]} {
	return $HOST_UUID
    }
    set uuidfile [file join $datadir uuid]
    if {[catch {open $uuidfile r} fd] == 0} {
	if {[gets $fd line] == -1} {
	    error "$uuidfile exists and is empty!"
	}
	close $fd
	return [set HOST_UUID $line]
    } else {
	# Calling unameit_pull_version on the pull server causes it to reread
	# the canon_hosts file. We may have to reread this file before
	# we ask for this hosts uuid. Read the version and then throw it away.
	unameit_send unameit_pull_version

	foreach ip [get_ip_addrs] {
	    if {[catch {unameit_send [list unameit_pull_uuid $ip]} uuid]\
		    == 0} {
		set HOST_UUID $uuid
		set fd [atomic_open $uuidfile 0444]
		puts $fd $HOST_UUID
		atomic_close $fd
		return $HOST_UUID
	    }
	}
	error "Host not in the UName*It database"
    }
}

# Returns 1 if path list is OK, 0 if the uuid is found in the list.
proc CheckPathList {this_host_uuid} {
    global VERSION GEN_FILES pullPriv

    # Get the version each time. Different pull servers will have different
    # versions.
    if {[catch {unameit_send unameit_pull_version} VERSION]} {
	error "Cannot read pull server gen.version file"
    }

    # Read all the file names into GEN_FILES
    catch {unset GEN_FILES}
    array set GEN_FILES [unameit_send "unameit_pull_readdir gen.$VERSION"]

    if {![info exists GEN_FILES(path_list)]} {
	error "Pull server gen directory doesn't contain path_list file."
    }

    set datadir $pullPriv(data)
    set pl_file [file join $datadir tmp path_list]
    set vpl_file [file join gen.$VERSION path_list]
    unameit_cp $vpl_file $pl_file 1

    set found 0
    for_file line $pl_file {
	if {[cequal $line $this_host_uuid]} {
	    set found 1
	    break
	}
    }

    file delete -- $pl_file

    expr !$found
}

proc unameit_cp {remote_name local_name {use_remote 0}} {
    global pullPriv IS_PULL_SERVER errorCode

    set fh [atomic_open $local_name 0444]
    if {![info exists IS_PULL_SERVER] || $use_remote} {
	set is_pull_server 0
    } else {
	if {$IS_PULL_SERVER} {
	    set is_pull_server 1
	} else {
	    set is_pull_server 0
	}
    }
    if {$is_pull_server} {
	set rfh [open [file join $pullPriv(data) data $remote_name] r]
	copyfile $rfh $fh
	close $rfh
    } else {
	if {[catch {unameit_send $fh [list unameit_pull_read_file\
		$remote_name]} err] != 0} {
	    atomic_abort $fh
	    error $err {} $errorCode
	}
    }
    atomic_close $fh
}


proc unameit_connect_proc {} {
    global PULL_HOST pullPriv pullConfig DEMO_MODE
    #
    unameit_disconnect
    set connected 0
    # 
    # Setup the authentication modules
    #
    set auth $pullPriv(authentication)
    set service $pullPriv(service)
    
    # Currently, only try one host
    set hosts $pullPriv(server_host)

    foreach host $hosts {
	set code [catch {unameit_connect $host $service} err]
	if {$code == 0} {
	    if {[catch {unameit_authorize_login pullConfig} err]} {
		global errorCode errorInfo
		unameit_error_get_text err $errorCode
		unameit_disconnect
		puts stderr\
		    "Failed to authenticate to $service on $host: $err"
		continue
	    }
	    if {!$DEMO_MODE && ![CheckPathList [GetThisHostUuid]]} {
		unameit_disconnect
		puts stderr\
		    "$service on $host pulled from this host: loop detected"
		continue
	    }
	    puts "Connected to $service on $host."
	    set connected 1
	    set PULL_HOST $host
	    break
	} else {
	    puts stderr "failed: $err"
	}
    }

    if {!$connected} {
	error "Could not connect to any pull server host."
    }
}

proc unameit_start {} {
    global argc argv env pullConfig pullPriv HOST_UUID DOMAIN_NAME argv0\
	    SHORT_HOST DEMO_MODE
    package require Config
    package require Error
    unameit_getconfig pullConfig upull
    set DEMO_MODE 0
    if {[unameit_config_flag pullConfig demo_mode]} {
	set DEMO_MODE 1
	if {$argc != 1} {
	    puts stderr "Usage: $argv0 host"; exit 1
	}
	regexp {^([^.]*)} [lindex $argv 0] SHORT_HOST
    } else {
	if {$argc != 0} {
	    puts stderr "Usage: $argv0"; exit 1
	}
    }
    set DOMAIN_NAME [unameit_config pullConfig domain]
    unameit_configure_app pullConfig pullPriv
    set HOST_UUID ""

    catch {memory init on}
    file mkdir [file join $pullPriv(data) tmp]
    unameit_connect_proc
    uplevel #0 [unameit_send {unameit_pull_read_file pull_main.tcl}]
    main
}
source ../library/atomic.tcl
