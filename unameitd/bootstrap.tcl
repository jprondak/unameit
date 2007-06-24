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
# Wrapper code for executing client requests and returning results.
#

#
# Read a file, discarding comments and trimming components.
# Lappends to var a balanced list of {param value}. Both are trimmed,
# value may be empty.

proc unameit_read_license_file {var filename} {
    upvar 1 $var data
    for_file line $filename {
	set line [string trim $line]
	if {! [regexp -- "^(license_\[^ \t]*)(.*)" $line x key val]} continue
	set data($key) [string trim $val]
    }
}

proc unameit_canon_license {} {
    #
    # Make sure all the licese parameters that we need were set.
    # Canonicalize key and dates.
    #
    foreach param {start end type host_units person_units key} {
	upvar #0 unameitPriv(license_$param) $param
	if {![info exists $param]} {
	    error "License '$param' not set in license file"
	}
    }

    # Get rid of the dashes in the key
    regsub -all -- - $key "" key

    # Change start and end to clock values
    foreach var {start end} {
	upvar 0 $var time_var
	if {[cequal $time_var ""]} {
	    set time_var -1
	} else {
	    set time_var [clock scan $time_var -gmt 1]
	}
    }
}

proc unameit_db_restart {} {
    #
    global unameitPriv argv0
    upvar #0 unameitPriv(restore) restore

    #
    # Create slave interpreter for database commands
    #
    interp create udb_interp
    load {} Tclx udb_interp
    load {} Udb udb_interp
    load {} Uaddress udb_interp
    load {} Uuid udb_interp
    #
    # Create slave interpreter for schema management commands
    #
    interp create umeta_interp
    load {} Tclx umeta_interp
    load {} Umeta umeta_interp
    load {} Uqbe umeta_interp
    load {} Ucanon umeta_interp
    #
    # Load qbe decoding into master interpreter
    #
    load {} Uqbe
    #
    # Set unameitPriv variable in udb interpreter. It is needed by the license
    # logging, dump and other routines.
    #
    udb_interp eval [list array set unameitPriv [array get unameitPriv]]
    udb_interp eval [list set argv0 $argv0]
    #
    # Login to the database
    #
    udb_interp eval unameit_relogin
    #
    # Export udb_qbe command to meta interpreter
    #
    interp alias\
	umeta_interp unameit_qbe\
	udb_interp udb_qbe -stream
    #
    # Export QBE command to master interpreter, (for looking up principals)
    #
    interp alias\
	{} unameit_qbe\
	udb_interp udb_qbe -stream
    #
    # Export udb_transaction and udb_principal and udb_commit and udb_rollback
    # to master interpreter
    #
    interp alias {} unameit_transaction udb_interp udb_transaction
    interp alias {} unameit_principal udb_interp unameit_principal
    interp alias {} unameit_commit udb_interp udb_commit
    interp alias {} unameit_abort udb_interp udb_rollback
    #
    # Allow meta interpreter to set variables in database interpreter
    #
    interp alias umeta_interp udb_array_set udb_interp array set
    interp alias umeta_interp udb_set udb_interp set
    interp alias umeta_interp udb_unset udb_interp unset
    #
    # Set up calls from udb_interp into global master interpreter
    #
    udb_interp alias unameit_get_server_version unameit_get_server_version
    #
    # Load schema into meta interpreter
    #
    umeta_interp eval unameit_load_schema
    #
    # Export unameit_error and unameit_crypt from meta interpreter
    #
    interp alias udb_interp unameit_error umeta_interp unameit_error
    interp alias {} unameit_error umeta_interp unameit_error
    interp alias {} unameit_crypt umeta_interp unameit_crypt
    #
    # Export syntax check proc from meta interpreter
    #
    interp alias\
	udb_interp unameit_check_syntax\
	umeta_interp unameit_check_syntax
    #
    # Restore if requested
    #
    switch -- $restore all - schema - data {
	interp alias\
	    udb_interp unameit_build_indices\
	    umeta_interp unameit_build_indices
	udb_interp eval [list unameit_restore $restore]
    }
    #
    # Delete restore proc
    #
    udb_interp eval [list rename unameit_restore {}]
}

proc unameit_start {} {

    catch {memory init on}
    global unameitPriv argv0 argc argv unameitConfig
    upvar #0 unameitPriv(foreground) foreground
    upvar #0 unameitPriv(restore) restore
    upvar #0 unameitPriv(service) service
    upvar #0 unameitPriv(timeout) timeout
    #
    package require Config
    package require Error

    #
    # set defaults
    #
    set foreground 0
    set restore nothing

    unameit_getconfig unameitConfig unameitd
    unameit_configure_unisqlx unameitConfig
    unameit_configure_app unameitConfig unameitPriv

    #cmdtrace on

    set unameitPriv(dbname) [unameit_config unameitConfig dbname unisqlx]

    # read license file
    set lfile [unameit_filename UNAMEIT_ETC license]
    unameit_read_license_file unameitPriv $lfile

    #
    # Convert license info to canonical form
    #
    unameit_canon_license

    #
    # Override from command line
    #
    if {[catch { \
            set optind [getopt $argc $argv \
	    {F foreground 1} \
	    {R restore $optarg} \
	    ]}] != 0} {

        return -code error\
	    "Usage: [file tail $argv0] \[-F] \[-R what] \[bootfile args...]"
    }
    if {$optind < $argc} {
	set bootfile [lindex $argv $optind]
	incr optind
	set argv [lrange $argv $optind end]
    }
    #
    # Become daemon unless requested otherwise
    #
    if {$foreground == 0 && ![info exists bootfile] &&
	    [cequal $restore nothing]} {
	unameit_daemon_fork
    }

    #
    # Import passwd authentication procs
    # into main interpreter.  Also uuid generation for one time
    # session handles.
    #
    load {} Auth
    load {} Upasswd
    load {} Uuid

    # 
    # Get authentication parameters for each authentication type,
    # then set the service and keytab.
    #
    foreach auth [unameit_config unameitConfig authentications] {
	if [catch {
	    package require $auth
	    catch {unset auth_config}
	    unameit_auth_configure_server unameitConfig auth_config $auth
	    unameit_authorize_do auth_config set_service
	} msg] {
	    global errorCode errorInfo
	    unameit_error_get_text msg $errorCode
	    puts stderr $msg
	    exit 1
	}
    }

    #
    # Restart database
    #
    unameit_db_restart

    #
    # Run single user script if requested
    #
    if {[info exists bootfile]} {
	#
	# Initialize slave interpreter for script
	#
	interp create unameit_suser
	load {} Tclx unameit_suser
	load {} Uqbe unameit_suser
	unameit_user_init unameit_suser {} UName*It
	#
	# Export relogin, build_indices and crypt
	#
	interp alias\
	    unameit_suser unameit_relogin\
	    udb_interp unameit_relogin
	interp alias\
	    unameit_suser unameit_build_indices\
	    umeta_interp unameit_build_indices
	interp alias\
	    unameit_suser unameit_crypt\
	    umeta_interp unameit_crypt
	#
	# If Tcl_AppInit() defines master eval,  export it to the slave
	#
	if {![lempty [info commands master_eval]]} {
	    unameit_suser alias master_eval master_eval
	}
	#
	# Set up client info in libudb.
	#
	unameit_begin unameit_suser
	#
	# Give control to script.
	#
	set code\
	    [catch {unameit_suser eval "
		    [list set argc [llength $argv]]
		    [list set argv0 $bootfile]
		    [list set argv $argv]
		    [list source $bootfile]"} msg]
	if {$code == 1} {
	    global errorCode errorInfo TCLXENV
	    puts stderr "Error: $msg"
	    puts stderr "Error Code: $errorCode"
	    if {![info exists TCLXENV(noDump)]} {
		puts stderr "Stack Trace:\n$errorInfo"
	    }
	}
	#
	# Rollback uncommited changes
	#
	catch {udb_interp eval udb_shutdown}
	#
	# Exit.  Do not want to come up multi-user after boot script.
	# There may be more prep work left to do.
	#
	exit $code
    }
    #
    # If database was restored,  clean up and exit
    #
    if {![cequal $restore nothing]} {
	catch {udb_interp eval udb_shutdown}
	return
    }
    #
    # Detach controlling terminal
    #
    if {$foreground == 0} {
	unameit_daemon_mode
    }
    #
    # Process client requests
    #
    uplevel #0 [list unameit_client_loop $service $timeout]
    catch {udb_interp eval udb_shutdown}
}

source ../library/master.tcl
source ../library/getopt.tcl
source version.tcl
