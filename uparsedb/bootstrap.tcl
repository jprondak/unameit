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

source ../library/atomic.tcl

proc __diagnostic {args} { 
    global tcl_interactive
    if {! $tcl_interactive} return
    catch {
	eval puts $args
	flush stdout
    }
}

proc unameit_time {script {iterations 1}} {
    set microseconds [lindex [uplevel 1 [list time $script $iterations]] 0]
    set total_seconds [expr $microseconds/1000000]
    set minutes [expr $total_seconds/60]
    set seconds [expr $total_seconds%60]
    return "$minutes minutes $seconds seconds per iteration"
}

proc read_version {path} {
    if {[catch {open $path r} fh]} {
	return 0.0.0
    }
    if {[gets $fh version] == -1} {
	error "Empty version file: $path"
    }
    if {[gets $fh junk] != -1 || ![eof $fh]} {
	error "Data after first line in Version file: $path"
    }
    close $fh
    set vlist [split $version .]
    if {[llength $vlist] != 3} {
	error "Malformed version: $version in $path"
    }
    foreach v $vlist {
	if {[scan $v "%d%s" iv x] != 1 || $iv < 0} {
	    error "Malformed version: $version in $path"
	}
    }
    return $version
}

proc new_version {version_file script} {
    global VERSION 
    #
    # If it has already been done,  just pretend we did it
    #
    set version [read_version $version_file]
    if {[string compare $VERSION $version] == 0} return
    #
    # If someone is already doing it,  just exit
    #
    if {[catch {atomic_open $version_file 0444} lock_fh] != 0} {exit 0}
    #
    # Run the generation script
    #
    set ok [catch {puts $lock_fh $VERSION; eval $script} result]
    if {$ok != 0} {
	global errorInfo errorCode
	set err_i $errorInfo
	set err_c $errorCode
	catch {atomic_abort $lock_fh}
	return -code 1 -errorinfo $err_i -errorcode $err_c $result
    }
    atomic_close $lock_fh
}

proc dirsort {list} {
    if {[catch {lsort -decreasing -dictionary $list} result] == 0} {
	return $result
    }
    proc dict_comp {a b} {
	foreach apart [split $a .] bpart [split $b .] {
	    if {"$apart" > "$bpart"} {return 1}
	    if {"$apart" < "$bpart"} {return -1}
	}
	return 0
    }
    lsort -decreasing -command dict_comp $list
}

proc unameit_start {} {
    catch {memory init on}
    global unameitConfig VERSION

    package require Config
    unameit_getconfig unameitConfig uparsedb
    set datadir [file join [unameit_config unameitConfig data] data]
    set VERSION [read_version [file join $datadir data.version]]
    #
    # Exit if database never dumped
    #
    if {[cequal "" $VERSION]} {
	exit 0
    }
    lassign [split $VERSION .] major minor micro
    #
    new_version [file join $datadir gen.version] [format {
	new_version [file join %s dump.version] {
	    source [file join [unameit_filename UNAMEIT_BACKEND] tcldump.tcl]
	}
	source [file join [unameit_filename UNAMEIT_BACKEND] generator.tcl]
	#
	uplevel 1 {
	    if {![unameit_config_flag unameitConfig leave_dumpdir]} {
		#
		set re {^dump\.([0-9]+)\.([0-9]+)\.([0-9]+)$}
		#
		# Since we are going to delete the dump directory,
		# first remove dump.version,  so it does not cause
		# us to believe that the dump is still there.
		#
		cd $datadir
		file delete dump.version
		#
		foreach dumpdir [glob -nocomplain -- dump.*] {
		    if {[regexp $re $dumpdir junk d_major d_minor d_micro]} {
			if {$d_major > $major} continue
			if {$d_major == $major} {
			    if {$d_minor > $minor} continue
			    if {$d_minor == $minor && $d_micro > $micro} continue
			}
			catch {file delete -force -- $dumpdir}
		    }
		}
	    }
	}
    } [list $datadir]]

    #
    # Clean up old output directories.
    #
    # Keep the oldest snapshot after each 6 hour mark during the last 24 hours.
    #
    # Also keep the three numerically most recent snapshots.
    #

    set now [clock seconds]

    foreach time {12am 6am 12pm 6pm} {
	if {[set times($time) [clock scan $time -base $now]] > $now} {
	    set times($time) [clock scan "$time yesterday" -base $now]
	}
    }

    cd $datadir

    foreach prefix {data gen} {
	set re "^$prefix"
	append re {\.[0-9]+\.[0-9]+\.[0-9]+$}
	#
	set dirlist {}
	#
	foreach dir [dirsort [glob -nocomplain -- $prefix.*]] {
	    if {![regexp $re $dir]} continue
	    #
	    lappend dirlist $dir
	    set mtime($dir) [file mtime $dir]
	    #
	    foreach time {12am 6am 12pm 6pm} {
		#
		# Ignore dirs that are too old.
		#
		if {$mtime($dir) < $times($time)} continue
		#
		if {![info exists oldest($prefix.$time)]} {
		    #
		    # Initial candidate
		    #
		    set oldest($prefix.$time) $dir
		    continue
		}
		if {$mtime($dir) < $mtime($oldest($prefix.$time))} {
		    #
		    # Older candidate
		    #
		    set oldest($prefix.$time) $dir
		}
	    }
	}
	#
	# Always save the three most numerically recent versions
	#
	foreach dir [lrange $dirlist 0 2] {
	    set save($dir) 1
	}
    }

    foreach key [array names oldest] {
	#
	# Also save time based snapshots.
	#
	set save($oldest($key)) 1
    }

    #
    # Just in case: do not delete the current snapshot
    #
    set save(data.$VERSION) 1
    set save(gen.$VERSION) 1

    foreach dir [array names mtime] {
	lassign [split $dir .] junk d_major d_minor d_micro
	if {$d_major > $major} continue
	if {$d_major == $major && $d_minor >= $minor - 2} continue
	if {[info exists save($dir)]} continue
	#
	catch {file delete -force -- $dir}
    }
}
