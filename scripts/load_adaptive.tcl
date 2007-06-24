#!/bin/sh
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
# $Id: load_adaptive.tcl,v 1.5.10.1 1997/08/28 18:29:03 viktor Exp $
#

# Adaptively commit the changes in the script specified by the first argument.
#
# Tcl ignores the next line. The shell doesn't.\
    exec unameitd $0 "$@"


#
# Compute smoothed error rate and adjust block size every 10 transactions
#
proc adjust {size_var count ecode} {
    global ecount erate
    incr ecount $ecode
    if {$count % 5} return
    set erate [expr 0.85 * $erate + 0.03 * $ecount]
    set ecount 0
    upvar 1 $size_var size
    if {$erate < 0.02} {
	set size [expr int($size * 1.4 + 4)]
	if {$size > 64} {
	    set size 64
	}
    } elseif {$erate > 0.03} {
	set size [expr ($size + 1) / 2]
	set erate [expr $erate / 1.4]
    }
}

#
# No point in retrying just one command
# Retry commit in middle and at end.
#
proc retry {cmds count err} {
    switch -- $count 0 - 1 {
	global errorCode
	puts "# $err"
	puts "# $errorCode"
	puts [lindex $cmds 0]
	return
    }
    set mid [expr $count / 2]
    set done 0
    set redo {}
    foreach cmd $cmds {
	switch -- [catch $cmd] 0 {lappend redo $cmd}
	switch -- [incr done] $mid - $count {
	    if {[catch unameit_commit err]} {retry $redo [llength $redo] $err}
	    set redo {}
	}
    }
}

proc adaptive_load {file} {
    global ecount erate errorCode
    set fh [open $file r]
    #
    # Initialize adaptive parameters
    #
    set bsize 4
    set erate 0.01
    set ecount 0
    set elem 0
    set trans 0
    set total 0
    set redo {}
    set interactive 0
    #
    while {[lgets $fh cmd] != -1} {
	if {[catch $cmd err]} {
	    puts "# $err"
	    puts "# $errorCode"
	    puts $cmd
	    continue
	}
	lappend redo $cmd
	switch -- [incr elem] $bsize {} default continue
	set e [catch unameit_commit err]
	if {([incr total $elem] % 2000) < $bsize} {
	    unameit_relogin
	}
	adjust bsize [incr trans] $e
	if {$e} {retry $redo $elem $err}
	set redo {}
	set elem 0
    }
    close $fh
    #
    # Commit partial batch
    #
    if {$elem} {
	set e [catch unameit_commit err]
	if {$e} {retry $redo $elem $err}
	set redo {}
	set elem 0
    }
}

if {[llength $argv] != 1} {
    error "usage: [file tail $argv0] <update_script>"
}

eval adaptive_load $argv
puts "Dump time: [time unameit_dump]"
