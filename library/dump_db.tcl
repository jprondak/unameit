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
# $Id: dump_db.tcl,v 1.31.4.1 1997/08/28 18:27:22 viktor Exp $
#

proc unameit_dump {} {
    global unameitPriv
    set dir $unameitPriv(data)

    #
    # Just in case some fool is dumping in the middle of a transaction,
    # roll it back,  do not want to dump uncommitted data!
    #
    udb_rollback
    #
    # Declare globals
    #
    global\
	UNAMEIT_CLASS_UUID UNAMEIT_CLASS_RO\
	UNAMEIT_ANAMES UNAMEIT_SUBS UNAMEIT_CLASS_NAME UNAMEIT_ATTRIBUTE_UUID
    #
    # Mode bits of backend output files
    #
    set MODE 0444
    #
    set VERSION [udb_version schema]
    lassign [split $VERSION .] major minor micro
    #
    # 'micro' == 0 iff no schema changes since last dump
    #
    if {$micro > 0} {
	set version_fh\
	    [atomic_open [file join $dir data schema.version] 0444]
	#
	set ok [catch {
	    set DUMPDIR [file join $dir data schema.$VERSION]
	    puts $version_fh $VERSION

	    #
	    # Create output directory (ok if present)
	    #
	    file mkdir $DUMPDIR

	    #
	    # Prepare new Info file
	    #
	    set info_fh [atomic_open [file join $DUMPDIR Info.tcl] $MODE]

	    #
	    # Save oid2uuid mapping of the `uuid' attribute.
	    # It is referenced by collision rules,  but its class is readonly
	    # and so is not dumped.
	    #
	    set uuid $UNAMEIT_ATTRIBUTE_UUID(uuid)
	    puts $info_fh "set oid2uuid([udb_oid $uuid]) $uuid"

	    set si_class $UNAMEIT_CLASS_UUID(unameit_schema_item)

	    foreach class $UNAMEIT_SUBS($si_class) {
		set cname $UNAMEIT_CLASS_NAME($class)
		#
		# Skip readonly schema classes
		#
		if {[info exists UNAMEIT_CLASS_RO($cname)]} continue

		set alist {}
		foreach aname $UNAMEIT_ANAMES($cname) {
		    switch -- $aname uuid - deleted {}\
			default {lappend alist $aname}
		}

		set instance_file [file join $DUMPDIR $cname.dat]
		set instance_fh [atomic_open $instance_file $MODE]

		set count [eval udb_dump_class $instance_fh $cname $alist]
		if {$count > 0} {
		    atomic_close $instance_fh
		    puts $info_fh [list set unrestored($cname) $cname.dat]
		    puts $info_fh [list set instances($cname) $count]
		    puts $info_fh [list set fields($cname) $alist]
		} else {
		    atomic_abort $instance_fh
		}
		unset instance_fh
	    }
	    #
	    # And the protected schema items
	    #
	    set protected_fh\
		[atomic_open [file join $DUMPDIR Protected.dat] $MODE]
	    udb_dump_protected $protected_fh unameit_schema_item
	    atomic_close $protected_fh
	    unset protected_fh
	    #
	    # Close schema class description file
	    #
	    atomic_close $info_fh
	    unset info_fh
	    #
	    # Even though system calls should not generally commit,
	    # this one must!  We cannot update the version file unless
	    # the database increments its version number.  Otherwise it
	    # could reuse the version number later.
	    #
	    lassign [split $VERSION .] major minor
	    udb_commit -schemaMinor [incr minor] "Schema Checkpoint"
	} error]

	if {$ok != 0} {
	    global errorInfo errorCode
	    set i $errorInfo
	    set c $errorCode
	    catch {atomic_abort $version_fh}
	    catch {atomic_abort $info_fh}
	    catch {atomic_abort $instance_fh}
	    catch {atomic_abort $protected_fh}
	    error $error $i $c
	}
	atomic_close $version_fh
    }

    #
    set VERSION [udb_version data]
    lassign [split $VERSION .] major minor micro
    #
    # 'micro' == 0 iff no data changes since last dump
    #
    if {$micro > 0} {
	set version_fh\
	    [atomic_open [file join $dir data data.version] 0444]
	#
	set ok [catch {
	    set DUMPDIR [file join $dir data data.$VERSION]
	    puts $version_fh $VERSION

	    #
	    # Create output directory
	    #
	    file mkdir $DUMPDIR

	    #
	    # Prepare new info file
	    #
	    set info_fh [atomic_open [file join $DUMPDIR Info.tcl] $MODE]

	    set di_class $UNAMEIT_CLASS_UUID(unameit_data_item)

	    foreach class $UNAMEIT_SUBS($di_class) {
		#
		# Map class uuid -> name
		#
		set cname $UNAMEIT_CLASS_NAME($class)

		#
		# Save oid to class name mapping for every data class, so
		# we can succesfully restore role objects!
		# Do it even for readonly classes,  since we do not yet
		# prevent users from assigning authorization for readonly
		# classes.
		#
		set coid [udb_oid $class]
		puts $info_fh "set oid2classname($coid) $cname"

		#
		# Save the `root' node if any of each class.
		# Readonly classes can legitimately point to a root object
		# of a hierarchy of their subclasses. 
		#
		if {![cequal [set root_uuid [udb_get_root $cname]] ""]} {
		    set root_oid [udb_oid $root_uuid]
		    puts $info_fh "set root_oid($cname) $root_oid"
		}

		#
		# Output the the subclass list of each class.
		# Needed for backend file generation.
		#
		set subnames {}
		foreach subclass $UNAMEIT_SUBS($class) {
		    lappend subnames $UNAMEIT_CLASS_NAME($subclass)
		}
		puts $info_fh [list set subclasses($cname) $subnames]

		#
		# Skip readonly data classes
		#
		if {[info exists UNAMEIT_CLASS_RO($cname)]} continue

		set alist {}
		foreach aname $UNAMEIT_ANAMES($cname) {
		    switch -- $aname uuid - deleted {}\
			default {lappend alist $aname}
		}

		set instance_file [file join $DUMPDIR $cname.dat]
		set instance_fh [atomic_open $instance_file $MODE]

		set count [eval udb_dump_class $instance_fh $cname $alist]
		if {$count > 0} {
		    atomic_close $instance_fh
		    puts $info_fh [list set unrestored($cname) $cname.dat]
		    puts $info_fh [list set instances($cname) $count]
		    puts $info_fh [list set fields($cname) $alist]
		} else {
		    atomic_abort $instance_fh
		}
		unset instance_fh
	    }
	    #
	    # And the protected data items
	    #
	    set protected_fh\
		[atomic_open [file join $DUMPDIR Protected.dat] $MODE]
	    udb_dump_protected $protected_fh unameit_data_item
	    atomic_close $protected_fh
	    unset protected_fh
	    #
	    # Close data class description file
	    #
	    atomic_close $info_fh
	    unset info_fh
	    #
	    # Even though system calls should not generally commit,
	    # this one must!  We cannot update the db.version file unless
	    # the database increments its version number.  Otherwise it
	    # could reuse the version number later.
	    #
	    lassign [split $VERSION .] major minor
	    udb_commit -dataMinor [incr minor] "Data Checkpoint"
	} error]

	if {$ok != 0} {
	    global errorInfo errorCode
	    set i $errorInfo
	    set c $errorCode
	    catch {atomic_abort $version_fh}
	    catch {atomic_abort $info_fh}
	    catch {atomic_abort $instance_fh}
	    catch {atomic_abort $protected_fh}
	    error $error $i $c
	}
	atomic_close $version_fh
    }
    unameit_relogin
}

proc unameit_relogin {} {
    global argv0 unameitPriv
    #
    # Poor man's GC.
    #
    if {![lempty [info commands udb_shutdown]]} udb_shutdown
    #
    if {[info exists unameitPriv(enable_logging)]} {
	#
	# Log transactions to the "data" directory.
	#
	udb_login $argv0 $unameitPriv(dbname)\
	    [file join $unameitPriv(data) data log]
    } else {
	udb_login $argv0 $unameitPriv(dbname)
    }
}
