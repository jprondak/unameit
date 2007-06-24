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
# $Id: dump_common.tcl,v 1.50.10.1 1997/08/28 18:29:00 viktor Exp $
#

#
# Info variables are global.
# 	InfoFiles(class)
#	InfoDir
#	InfoMode 		a = append, r = read
#
# Procedures available are:
#	
#	dump_open_dir		open the directory of data files
#	dump_close_dir		close same
#	dump_edit_class		open data file for the class and read it
#	dump_process_class	process each record of a closed class
#	dump_close_class	close data file for a class
#	dump_class_list		return list of open classes
#	dump_get_fields		return list of field names for a class
#	dump_put_instance	write out an instance; class must be open
#	dump_put_instance_a	write out an instance; class must be open
#	dump_put_instance_l	write out an instance; class must be open
#	

###########################################################################
# Source and lock the Info.tcl file in the given directory.

proc dump_open_dir {dir {mode a}} {
    global InfoFiles InfoDir InfoMode

    # Return if directory opened already
    if {[info exists InfoFiles(Info.tcl)]} {
	error "Info already loaded"
    }
    set InfoDir $dir
    set InfoMode $mode
    set path [file join $dir Info.tcl]
    if {[file exists $path]} {
	uplevel #0 source $path
    } else {
	error "'$path' not found"
    }
    if {[cequal r $InfoMode]} {
	return
    }
    set InfoFiles(Info.tcl) [atomic_open $path 0644]

    return
}

###########################################################################
# This writes out the Info file and closes all open data files.
# Then the global variables are deleted.

proc dump_close_dir {} {
    global fields instances unrestored InfoFiles InfoDir oid2classname InfoMode

    if {[cequal r $InfoMode]} {
	return
    }

    set fh $InfoFiles(Info.tcl)

    if {[catch {
	foreach {oid name} [array get oid2classname] {
	    puts $fh [list set oid2classname($oid) $name]
	}
	foreach cname [array names fields] {
	    puts $fh [list set fields($cname) $fields($cname)]
	    puts $fh [list set instances($cname) $instances($cname)]
	    puts $fh [list set unrestored($cname) $unrestored($cname)]
	}
    } error] == 0} {
	for_array_keys cname InfoFiles {
	    atomic_close $InfoFiles($cname)
	}
	unset fields instances unrestored InfoFiles InfoDir 
    } else {
	global errorCode errorInfo
	set ec $errorCode
	set ei $errorInfo
	atomic_abort $fh
	return -code error -errorinfo $ei errorcode $ec $error
    }
    return
}

###########################################################################
# Read the datafile for the given class and execute code fragment
# (i.e. a callback) for each of the class members.
#
# The format of the datafiles is:
#	OID UUID {list of data}
#
# Evaluation is done by constructing an 'lassign' command with the
# field names and eval'ing it. This places the data list and the uuid
# into the variable F. The OID is be placed into the variable
# oid. The variables F and oid may be used or copied by the code
# fragment. 
#
# dump_edit_class saves a filehandle to the atomic_open'ed data file in 
# InfoFiles($class)
#
# dump_process_class reads the input file and invokes the user's callback
# but does not leave the file open.

proc dump_edit_class {cname {code ""}} {
    global fields instances unrestored InfoDir InfoFiles InfoMode
    upvar 1 oid oid \
	    F F

    log_debug "dump_edit_class $cname"

    if {[info exists InfoFiles($cname)]} {
	error "$cname already loaded"
    } 

    if {[cequal r $InfoMode]} {
	error "$InfoDir open in readonly mode"
    }

    if {![cequal $code ""] && [info exists unrestored($cname)]} {
	set file $unrestored($cname)
	set in [open [file join $InfoDir $file ] r]
    } else {
	set file $cname.dat
	set unrestored($cname) $file
	set fields($cname) [dump_get_fields $cname]
    }
    set instances($cname) 0
    set InfoFiles($cname) [atomic_open [file join $InfoDir $file] 0644]
    if {![info exists in]} {return}

    # Make a command that will assign each data value read to a field
    # in F.
    set cmd {lassign $DATA }
    foreach f $fields($cname) {
	lappend cmd F($f)
    }

    # Eval the assignment command for each list in the data file.
    # Then eval the callback.
    while {[lgets $in line] >= 0} {
	catch {unset F}
	set F(Class) $cname
	lassign $line oid F(uuid) DATA	
	eval $cmd
	uplevel 1 $code
    }
    close $in
    return 
}
###########################################################################
# Close the open class data file. If not opened, just return.

proc dump_close_class {cname} {
    global InfoFiles InfoMode

    if {[cequal r $InfoMode]} {
	return
    }
    if {[info exists InfoFiles($cname)]} {
	atomic_close $InfoFiles($cname)
	unset InfoFiles($cname)
    }
}
###########################################################################
# Return a list of the open classes.

proc dump_class_list {} {
    global InfoFiles

    if {[info exists InfoFiles]} {
	return [array names InfoFiles]
    } else {
	return ""
    }
}

###########################################################################
# dump_process_class reads the input file and invokes the user's callback
# but does not leave the file open. The class must not be currently open,
# since the data in the file would not necessarily be uptodate.
# If there are no instances of the class nothing will happen.

proc dump_process_class {cname code} {
    global fields instances unrestored InfoDir InfoFiles 
    upvar 1 oid oid \
	    F F

    if {[info exists InfoFiles($cname)]} {
	error "$cname already loaded"
    } 

    if {[info exists unrestored($cname)]} {
	set file $unrestored($cname)
	set in [open [file join $InfoDir $file ] r]
    } else {
	return
    }

    # Make a command that will assign each data value read to a field
    # in F.
    set cmd {lassign $DATA }
    foreach f $fields($cname) {
	lappend cmd F($f)
    }

    # Eval the assignment command for each list in the data file.
    # Then eval the callback.
    while {[lgets $in line] >= 0} {
	catch {unset F}
	set F(Class) $cname
	lassign $line oid F(uuid) DATA	
	eval $cmd
	uplevel 1 $code
    }
    close $in
    return 
}

###########################################################################
# Query the schema to get a list of the fields. This should be the
# same as the 'fields' list for the class. However, if there are
# no instances of the class the 'fields' list may not exist.

proc dump_get_fields {cname} {
    set fields [unameit_get_settable_attributes $cname]
    return $fields
}

###########################################################################
# 
# Write out an instance of a class to an atomic_open'ed filehandle,
# such as would be returned from edit_class.
# The instance may contain any fields, but MUST contain uuid and Class.
#
proc dump_put_instance {oid instance} {
    global fields instances unrestored InfoDir InfoFiles 
    upvar 1 $instance F

    set cname $F(Class)
    incr instances($cname)

    # Construct the list that is within the output record.
    set DATA {}

    foreach f $fields($cname) {
        if {[info exists F($f)]} {
            lappend DATA $F($f)
        } else {
            lappend DATA {}
        }
    }

    # write oid uuid and data values
    puts $InfoFiles($cname) [list $oid $F(uuid) $DATA]

    return
}

###########################################################################
#
# This version has the oid in the variable with the name Oid
#
proc dump_put_instance_a {instance} {
    global fields instances unrestored InfoDir InfoFiles 
    upvar 1 $instance F

    set cname $F(Class)
    incr instances($cname)

    # Construct the list that is within the output record.
    set DATA {}

    foreach f $fields($cname) {
        if {[info exists F($f)]} {
            lappend DATA $F($f)
        } else {
            lappend DATA {}
        }
    }

    # write oid uuid and data values
    puts $InfoFiles($cname) [list $F(Oid) $F(uuid) $DATA]

    return
}

###########################################################################
#
# This version uses a list, similar to the one obtained by
# array get on the above variable.
#
proc dump_put_instance_l {listname} {
    upvar 1 $listname data
    array set F $data
    dump_put_instance_a F
    return
}


###########################################################################
#
# Run the canonicalization function for the class, attribute

proc dump_canon_attr {class attr value} {
    unameit_check_syntax $class $attr "" $value db
}

