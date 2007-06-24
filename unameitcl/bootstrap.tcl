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
# $Id: bootstrap.tcl,v 1.18.10.1 1997/08/28 18:29:28 viktor Exp $

proc unameit_try_to_connect {} {
    global errorCode unameitPriv

    unameit_disconnect_from_server
    set server [unameit_config unameitPriv server_host]
    set service [unameit_config unameitPriv service]
    set retries [unameit_config unameitPriv retries]
    set backoff [unameit_config unameitPriv backoff]

    while {1} {
	if {[catch {unameit_connect_to_server $server $service} msg] == 0} {
	    break
	}
	lassign $errorCode e1 e2 e3
	switch -- $e1.$e2.$e3 UNAMEIT.CONN.EAGAIN {} default {
	    error "Could not connect to $server:$service: $msg"
	}
	if {$retries == 0} {
	    error "Could not connect to $server:$service: timed out"
	}
	sleep $backoff
	set backoff [expr $backoff*2]
	incr retries -1
    }
}

#### 				Initialization routines

proc unameit_make_subsystem_interpreters {} {
    ## Create interpreters
    interp create cache_mgr
    interp create schema_mgr

    ## Load Tcl procedures
    load {} Cache_mgr cache_mgr
    load {} Schema_mgr schema_mgr
}

proc unameit_cross_subsystem_apis {} {
    ## Initialize cross commands between interpreters
    foreach command [cache_mgr eval unameit_get_schema_mgr_commands] {
	interp alias schema_mgr $command cache_mgr $command
    }
    foreach command [schema_mgr eval unameit_get_cache_mgr_commands] {
	interp alias cache_mgr $command schema_mgr $command
    }
}

proc unameit_export_subsystem_apis {args} {
    ## Export APIs to each interpreter.
    foreach mgr {cache_mgr schema_mgr} {
	foreach interp $args {
	    if {[cequal $mgr $interp]} continue

	    foreach routine [$mgr eval unameit_get_interface_commands] {
		interp alias $interp $routine $mgr $routine
	    }
	}
    }
}

proc unameit_start {} {
    global argc argv env argv0 unameitPriv 
    global TCLXENV

    catch {memory init on}
    package require Config
    package require Error
    if {[catch {
	set optind [unameit_getconfig unameitPriv unameitcl]
	
	set unameitPriv(subsystems_initialized) 0
	
	## Make the sub interpreters
	unameit_make_subsystem_interpreters
	
	## Set up internal cache/schema manager communication.
	unameit_cross_subsystem_apis
	
	## Export APIs
	unameit_export_subsystem_apis {} cache_mgr schema_mgr
	
	## Connect
	unameit_try_to_connect
	
	## Send authentication
	unameit_authorize_login unameitPriv
	
	## Initialize the cache and schema manager
	unameit_initialize_cache_mgr
	unameit_initialize_schema_mgr
	
	if {$optind == $argc} {
	    set argv {}
	    set argc 0
	    uplevel #0 commandloop
	} else {
	    set argv [lreplace $argv 0 [expr $optind - 1]]
	    set argc [expr $argc - $optind - 1]
	    uplevel #0 source [set argv0 [lvarpop argv]]
	}
    } msg]} {
	global errorCode errorInfo
	unameit_error_get_text msg $errorCode
	error $msg $errorInfo $errorCode
    }
}

#### 			Preloaded files from our Tcl library
source ../library/atomic.tcl
source ../library/getopt.tcl
