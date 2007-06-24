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
# $Id: load_generate.tcl,v 1.14.10.5 1997/10/04 00:35:53 viktor Exp $
#

#
# Run 'cmd' to build temporary script file
#
proc build_script {cmd dir infoFile} {
    oid_heap_output_dat $dir $dir
    set tmpfile [file join $dir newdata.tcl]
    set fh [open $tmpfile w]
    #
    $cmd $dir $infoFile $fh
    close $fh
}

#
# Return a script for loading a list of field values into the database
#
proc c_loadcmd {level cname op} {
    upvar #$level\
	fields fields\
	deferred deferred\
	loadcmd loadcmd
    #
    set decode {lassign $DATA}
    set map ""
    set i 0
    set args {}
    foreach aname $fields($cname) {
	#
	lappend decode "A[incr i]"

	#
	# Skip unsettable attributes
	#
	if {[unameit_isa_protected_attribute $aname]} continue
	if {[unameit_isa_computed_attribute $cname $aname]} continue
	#
	# Skip deferred attributes
	#
	if {[info exists deferred($cname.$aname)]} continue
	#
	lappend args $aname
	append args " \$A$i"

	if {[unameit_is_pointer $aname]} {
	    switch -- [unameit_get_attribute_multiplicity $aname] {
		Scalar {
		    append map "\nset A$i \$oid2uuid(\$A$i)"
		}
		Set - Sequence {
		    append map "\nset U {}; "
		    append map "foreach O \$A$i {lappend U \$oid2uuid(\$O)}; "
		    append map "set A$i \$U"
		}
	    }
	}
    }
    #
    switch -- $op {
	create {
	    set format {%s%s; set oid2uuid($oid) [uuidgen]
		 puts $script_fh [list unameit_create %s $oid2uuid($oid) %s]}
	    set loadcmd($cname)\
		[format $format $decode $map $cname $args]
	}
	update {
	    set format {%s%s;\
		puts $script_fh [list unameit_update $oid2uuid($oid) %s]}
	    set loadcmd($cname)\
		[format $format $decode $map $args]
	}
    }

    log_debug ""
    log_debug "Load Command for $cname"
    log_debug $loadcmd($cname)
    log_debug ""
}

#
# Run loadcmd for each item in dump file
#
proc r_file {level cname path} {
    upvar #$level\
	loadcmd loadcmd\
	script_fh script_fh\
	oid2uuid oid2uuid

    #
    set fh [open $path r]
    while {[lgets $fh list] != -1} {
	lassign $list oid uuid DATA
	switch -- $uuid "" {
	    eval $loadcmd($cname)
	} default {
	    set oid2uuid($oid) $uuid
	}
    }
    close $fh
}

#
# Return class *name* of domain of attribute
#
proc c_domain {cname aname} {
    unameit_get_attribute_domain $cname $aname
}

#
# Compute deferred fields,  based on what is left to restore and
# the domains of relevant pointers
#
proc c_deferred {level cname deferred_array dontdefer} {
    upvar #$level\
	unrestored unrestored\
	fields fields

    upvar 1 $deferred_array deferred
    if {[info exists deferred($cname.List)]} return

    set deferred($cname.List) {}

    foreach aname $fields($cname) {
	#
	# We can preload all non-object fields
	#
	if {![unameit_is_pointer $aname]} continue
	#
	# And all computed fields
	#
	if {[unameit_isa_protected_attribute $aname]} continue
	if {[unameit_isa_computed_attribute $cname $aname]} continue
	#
	# Dont defer the fields the caller asks us not to
	#
	if {[lsearch -exact $dontdefer $aname] >= 0} continue
	#
	# Check for possible missing references,  and defer if any
	#
	set domain [c_domain $cname $aname]
	if {![lempty [c_subs $domain unrestored]]} {
	    set deferred($cname.$aname) 1
	    lappend deferred($cname.List) $aname
	}
    }
}

#
# Call restore_file for each dump file of classes with deferred fields,
# the deferred fields table reversed,  so we update the old deferred
# fields
#
proc r_deferred {level dir} {
    upvar #$level\
	script_fh script_fh\
	restored restored\
	fields fields\
	deferred deferred

    foreach cname [array names restored] {
	if {[lempty $deferred($cname.List)]} continue

	puts -nonewline "\nParsing pass 2: $cname"; flush stdout

	#
	# Flip the deferred list to now contain, all the already processed
	# fields,  and call restore_class with the 'udb_update' command.
	#
	foreach aname $fields($cname) {
	    if {[info exists deferred($cname.$aname)]} {
		unset deferred($cname.$aname)
	    } else {
		set deferred($cname.$aname) 1
	    }
	}
	c_loadcmd $level $cname update
	set dumpfile [file join $dir $restored($cname)]
	r_file $level $cname $dumpfile
    }
}

#
# Mark class as restored,  by moving dump file name from
# unrestored array to restored array
#
proc s_restored {level args} {
    upvar #$level\
	restored restored\
	unrestored unrestored
    #
    foreach cname $args {
	set restored($cname) $unrestored($cname)
	unset unrestored($cname)
    }
}

#
# Compute the deferred fields for a class and call restore_file
#
proc r_class {level dir cname} {
    upvar #$level\
	script_fh script_fh\
	unrestored unrestored\
	deferred deferred

    if {![info exists unrestored($cname)]} return

    puts -nonewline "\nParsing: $cname"; flush stdout

    set dumpfile [file join $dir $unrestored($cname)]

    c_deferred $level $cname deferred {}
    c_loadcmd $level $cname create

    #
    # Restore the class
    #
    r_file $level $cname $dumpfile
    s_restored $level $cname
}

#
# Walk a tree (rooted at 'oid') restoring all nodes but the root,
# which should have already been restored by the caller
# Unsets the memcache state of all traversed objects
# *including* the (subs.$oid) memcache of the root node
#
proc r_subs {level node memcache_array} {
    upvar 1 $memcache_array memcache

    if {![info exists memcache(subs.$node)]} return

    #
    upvar #$level\
	oid2uuid oid2uuid\
	loadcmd loadcmd\
	script_fh script_fh

    foreach oid $memcache(subs.$node) {
	lassign $memcache($oid) cname DATA u_arr
	array set unresolved $u_arr
	unset unresolved($node)
	#
	if {[array size unresolved] > 0} {
	    set memcache($oid) $cname $DATA [array get unresolved]
	    unset unresolved
	    continue
	}
	#
	# *MUST* clean up as we go, elements left in the memcache
	# after we are done are presumed to be part of
	# a loop disconnected from the root,  and will cause an error!
	#
	unset memcache($oid)
	#
	# Create the subnode
	#
	eval $loadcmd($cname)
	#
	# Recurse
	#
	r_subs $level $oid memcache
    }
    #
    # MUST also unset this
    #
    unset memcache(subs.$node)
}

proc loop_error {level memcache_array} {
    upvar #$level\
	fields fields
    upvar 1 $memcache_array memcache
    #
    # Find an oid
    #
    set search [array startsearch memcache]
    while {[array anymore memcache $search]} {
	set oid [array nextelement memcache $search]
	switch -glob -- $oid subs.* continue
	break
    }
    array donesearch memcache $search
    #
    # Print at most ten elements from the loop
    #
    set count 0
    set print 0
    while 1 {
	lassign $memcache($oid) cname DATA u_arr
	if {$print == 1} {
	    puts "Class='$cname', OID='$oid'"
	    if {[info exists seen($oid)]} break
	    if {[incr count] > 10} {puts "..."; break}
	}
	if {[info exists seen($oid)]} {
	    set len [expr $count - $seen($oid) + 1]
	    puts "\nLoop of length $len detected"
	    set print 1
	    set count 0
	    unset seen
	    continue
	}
	set seen($oid) [incr count]
	set oid [lindex $u_arr 0]
    }
    error ""
}

#
# Restore regions, cells and organizations carefully
#
proc r_regions {level dir oclass cclass rclass} {
    #
    upvar #$level\
	unrestored unrestored\
	deferred deferred

    #
    # Load the organizations
    #
    foreach cname [c_subs $oclass unrestored] {
	r_class $level $dir $cname
    }

    #
    # Load the cells
    #
    foreach cname [c_subs $cclass unrestored] {
	r_class $level $dir $cname
    }

    #
    # Load the regions
    #
    foreach cname [c_subs $rclass unrestored] {
	r_class $level $dir $cname
    }
}

#
# Return *names* of classes, which indices in the array $type_array,
# equal to or subclasses of the class *named* $super
#
proc c_subs {super type_array} {
    upvar 1 $type_array type

    set clist {}
    foreach cname [concat $super [unameit_get_subclasses $super]] {
	if {[info exists type($cname)]} {lappend clist $cname}
    }
    set clist
}

#
# Try to restore each network hierarchy in turn, but only so long
# as no subclasses are already restored and the owner field need
# not be deferred.
#
proc r_networks {level dir} {
    upvar #$level\
	unrestored unrestored\
	deferred deferred\
	restored restored\
	root_oid root_oid

    array set netpointer [unameit_get_netpointers]

    while {[array size netpointer] > 0} {
	set progress 0
	foreach aname [array names netpointer] {
	    #
	    # Get the class name of the domain.
	    #
	    set cname [c_domain [unameit_defining_class $aname] $aname]
	    #
	    # What has been restored?
	    #
	    set do [c_subs $cname unrestored]
	    set done [c_subs $cname restored]
	    if {[lempty $do] || ![lempty $done]} {
		unset netpointer($aname)
		continue
	    }
	    #
	    # Can we restore it now?
	    #
	    set ok 1
	    c_deferred $level $cname tmp $aname
	    foreach ptr $tmp($cname.List) {
		if {[catch {
			unameit_check_syntax $cname $ptr $cname "" db}]} {
		    set ok 0
		    break
		}
	    }
	    if {$ok == 0} {
		unset netpointer($aname)
		continue
	    }
	    #
	    # We have a suitable network hierarchy restore it!
	    #
	    incr progress
	    c_deferred $level $cname deferred $aname
	    r_class $level $dir $cname
	}
	if {$progress == 0} break
    }
}

#
# Populate forest as we go,  as soon as we reach a resolved
# node,  flush the tree below the node,  keeping memory requirements
# as small as reasonable
#
proc r_forest {level cname path memcache_array} {
    #
    upvar #$level\
	unrestored unrestored\
	deferred deferred\
	fields fields\
	loadcmd loadcmd\
	script_fh script_fh\
	oid2uuid oid2uuid
    #
    upvar 1 $memcache_array memcache

    puts -nonewline "\nParsing: $cname forest"; flush stdout

    c_deferred $level $cname deferred {}
    set ptrlist {}
    foreach aname $deferred($cname.List) {
	if {[catch {unameit_check_syntax $cname $aname $cname "" db}]} {
	    lappend ptrlist $aname
	    unset deferred($cname.$aname)
	    set i [lsearch -exact $deferred($cname.List) $aname]
	    set deferred($cname.List) [lreplace $deferred($cname.List) $i $i]
	}
    }
    c_loadcmd $level $cname create
    set parsecmd {lassign $DATA}
    foreach aname $fields($cname) {
	lappend parsecmd F($aname)
    }

    set fh [open $path r]
    #
    while {[lgets $fh line] != -1} {
	lassign $line oid uuid DATA
	#
	# Items with non-empty uuids are already loaded
	#
	switch -- $uuid "" {} default {
	    set oid2uuid($oid) $uuid
	    continue
	}
	#
	eval $parsecmd
	foreach ptr $ptrlist {
	    switch -- [set up $F($ptr)] "" continue
	    if {![info exists oid2uuid($up)]} {
		lappend memcache(subs.$up) $oid
		set unresolved($up) 1
	    }
	}
	switch -- [array size unresolved] 0 {
	    eval $loadcmd($cname)
	    r_subs $level $oid memcache
	    continue
	}
	lappend memcache($oid) $cname $DATA [array get unresolved]
	unset unresolved
    }
    close $fh
}

proc r_glob {level dir clist} {
    #
    upvar #$level\
	unrestored unrestored\
	deferred deferred
    #
    foreach cname $clist {
	#
	# Incrementally restore the presumably loop free forest.
	#
	set dumpfile [file join $dir $unrestored($cname)]
	r_forest $level $cname $dumpfile memcache
    }
    if {[array size memcache] > 0} {
	loop_error $level memcache
    }
    eval s_restored $level $clist
}

#
# Adjust cost of classes based on instance counts,
# XXX: This cost function is far from optimal.  Should be improved
# when time permits.
#
proc c_cost {level lhs aname cost_array} {
    upvar #$level\
	instances instances\
	unrestored unrestored

    upvar 1 $cost_array cost

    if {![info exists cost($lhs)]} {
	set cost($lhs) -$instances($lhs)
    }
    set domain [c_domain $lhs $aname]
    set clist [c_subs $domain unrestored]

    set sum 0
    foreach rhs $clist {
	if {![info exists cost($lhs.$rhs)]} {
	    set cost($lhs.$rhs) 1
	    incr cost($lhs) $instances($rhs)
	}
    }
}

#
# Restore data classes in a heuristically sensible order
#
proc r_all {level dir} {
    upvar 1\
	oid2uuid oid2uuid\
	unrestored unrestored\
	deferred deferred

    #
    while {[array size unrestored] > 0} {
	puts "while 0: [array names unrestored]"
	set try() ""; unset try
	foreach cname [array names unrestored] {
	    c_deferred $level $cname tmp {}
	    if {[lsearch $tmp($cname.List) owner] < 0} {
		set try($cname) ""
	    }
	    unset tmp
	}
	if {[array size try] == 0} {
	    r_glob $level $dir [array names unrestored]
	    return
	}
	while {[array size try] > 0} {
	    set progress 0
	    foreach cname [array names try] {
		c_deferred $level $cname tmp {}
		if {[lempty $tmp($cname.List)]} {
		    #
		    # Hooray,  a class with no deferred fields, nail it!
		    #
		    r_class $level $dir $cname
		    unset try($cname)
		    set progress 1
		}
		unset tmp
	    }
	    if {$progress} continue
	    #
	    # Every class above had some deferred fields,  try to pick a best
	    # one to do first.
	    #
	    set ok_list {}
	    foreach cname [array names try] {
		c_deferred $level $cname tmp {}
		set def($cname) {}
		set ok 1
		foreach aname $tmp($cname.List) {
		    if {[catch {
			    unameit_check_syntax $cname $aname $cname "" db
			    }]} {
			set ok 0
			lappend def($cname) $aname
		    }
		}
		if $ok {
		    lappend ok_list $cname
		    #
		    # Class has deferred fields, lets estimate
		    # cost of the deferred fields
		    #
		    foreach aname $tmp($cname.List) {
			c_cost $level $cname $aname cost
		    }
		}
		unset tmp
	    }
	    if {[lempty $ok_list]} {
		#
		# Every class potentially has instances with unrestored
		# non-deferrable pointer fields.
		# Load them all as one big glob.  Prune classes with
		# references outside this group.
		#
		while 1 {
		    set dont_break 0
		    set clist {}
		    foreach cname [array names try] {
			foreach aname $def($cname) {
			    set ok 1
			    foreach sub [c_domain $cname $aname] {
				if {[info exists unrestored($sub)] &&
				    ![info exists try($sub)]} {
				    set ok 0
				    break
				}
			    }
			}
			if {$ok} {
			    lappend clist $cname
			} else {
			    unset try($cname)
			    set dont_break 1
			    break
			}
		    }
		    if {!$dont_break} break
		}
		if {![lempty $clist]} {
		    #
		    # Can restore some of the classes at this level
		    #
		    r_glob $level $dir $clist
		    foreach cname $clist {
			unset try($cname)
		    }
		    break
		}
		#
		# Cannot restore any of the classes at this level,  try
		# the whole heap and pray!
		#
		r_glob $level $dir [array names unrestored]
		return
	    }
	    foreach cname $ok_list {
		if {![info exists min] || $cost($cname) < $min} {
		    set min $cost($cname)
		    set best $cname
		}
	    }
	    unset cost min
	    r_class $level $dir $best
	    unset try($best)
	}
    }
}

#
# Restore the data classes
#
proc r_data {dir file script_fh} {
    #
    # Record variable frame level for storage of shared state
    #
    set level [info level]

    #
    # Load information about the classes to be restored
    #
    source [file join $dir $file]

    #
    # Set the NULL uuid so that oid2uuid() does not blow up
    #
    set oid2uuid() {}

    #
    # Restore all the regions
    #
    r_regions $level $dir organization cell region

    r_networks $level $dir

    r_all $level $dir

    r_deferred $level $dir
}

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB dump_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB networks.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} 
    check_options LoadOptions \
	    d DataDir 
    check_files LoadOptions \
	    d DataDir 
} problem]} {
    puts $problem
    puts "Usage: unameit_load generate \n\
	    \[ -W -R -C -I \] logging options \n\
	    -d data 	name of directory made by unameit_load copy_checkpoint"
    exit 1
}

build_script r_data $LoadOptions(DataDir) Info.tcl
