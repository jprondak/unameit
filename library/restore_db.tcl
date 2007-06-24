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
# $Id: restore_db.tcl,v 1.37.4.10 1997/10/04 00:35:35 viktor Exp $
#

#
# Restore the schema,  data or both
#
proc unameit_restore {what} {
    #
    # Definine these procedures only when actually doing a restore
    #

    #
    # Periodic commit hook
    #
    proc r_commit {count} {
	udb_commit "Data Restore Savepoint"
	#
	# Every 4000 objects,  tear down the workspace
	#
	if {$count % 4000 != 0} {
	    puts -nonewline .
	} else {
	    unameit_relogin
	    puts -nonewline !
	}
	flush stdout
    }

    #
    # Return a script for loading a list of field values into the database
    #
    proc c_loadcmd {level cname op} {
	upvar #0\
	    UNAMEIT_ATTRIBUTE_TYPE datatype\
	    UNAMEIT_REF_INTEGRITY ref_int
	upvar #$level\
	    fields fields\
	    deferred deferred\
	    loadcmd loadcmd
	#
	set decode "lassign \$DATA"
	set map ""
	set i 0
	set args {}
	foreach aname $fields($cname) {
	    lappend decode "A[incr i]"
	    #
	    # Skip attributes we cannot (yet?) set.
	    #
	    if {[info exists deferred($cname.$aname)]} continue
	    if {[info exists ref_int($cname.$aname)] &&
		[cequal $ref_int($cname.$aname) Network]} continue
	    #
	    lappend args $aname
	    append args " \$A$i"
	    if {[cequal $datatype($aname) Object]} {
		append map "\nset U {}; "
		append map "foreach O \$A$i {lappend U \$oid2uuid(\$O)}; "
		append map "set A$i \$U"
	    }
	}
	set maybe_commit\
	    {if {$uncommitted != -1 && [incr uncommitted] % 200 == 0}\
		    {r_commit $uncommitted}}
	#
	switch -- $op {
	    create {
		set loadcmd($cname)\
		    [format {%sset oid2uuid($oid) $uuid;\
				udb_create %s $uuid %s%s}\
			"$decode$map\n" $cname $args "\n$maybe_commit"]
	    }
	    update {
		set loadcmd($cname)\
		    [format {%sudb_update $uuid %s%s}\
			"$decode$map\n" $args "\n$maybe_commit"]
	    }
	}
    }

    #
    # Run loadcmd for each item in dump file
    #
    proc r_file {level cname path} {
	upvar #$level\
	    loadcmd loadcmd\
	    oid2uuid oid2uuid\
	    preloaded preloaded\
	    uncommitted uncommitted
	#
	set fh [open $path r]
	while {[lgets $fh list] != -1} {
	    lassign $list oid uuid DATA
	    if {![info exists preloaded($uuid)]} {
		eval $loadcmd($cname)
		continue
	    }
	    set oid2uuid($oid) $uuid
	}
	close $fh
    }

    #
    # Return class *name* of domain of attribute
    #
    proc c_domain {cname aname} {
	upvar #0\
	    UNAMEIT_CLASS_UUID cuuid\
	    UNAMEIT_ATTRIBUTE_UUID auuid\
	    UNAMEIT_POINTER_DOMAIN domain\
	    UNAMEIT_CLASS_NAME cnames
	set cnames($domain($cuuid($cname).$auuid($aname)))
    }

    #
    # Compute deferred fields,  based on what is left to restore and
    # the domains of relevant pointers
    #
    proc c_deferred {level cname deferred_array dontdefer} {
	upvar #0\
	    UNAMEIT_ATTRIBUTE_TYPE datatype

	upvar #$level\
	    unrestored unrestored\
	    fields fields

	upvar 1 $deferred_array deferred
	if {[info exists deferred($cname.List)]} return

	set deferred($cname.List) {}

	foreach aname $fields($cname) {
	    #
	    # We can restore all non-object fields
	    #
	    if {![cequal $datatype($aname) Object]} continue
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
	    restored restored\
	    fields fields\
	    deferred deferred

	foreach cname [array names restored] {
	    if {[lempty $deferred($cname.List)]} continue

	    puts -nonewline "\nPass 2: $cname"; flush stdout

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
	    unrestored unrestored\
	    deferred deferred

	if {![info exists unrestored($cname)]} return

	puts -nonewline "\nRestoring $cname"; flush stdout

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
	    uncommitted uncommitted

	foreach oid $memcache(subs.$node) {
	    lassign $memcache($oid) cname uuid DATA
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

    #
    # Create the root object of a hierarchy
    # Unsets the ($oid) memcache of the root node
    #
    proc r_root {level oid memcache_array} {
	upvar #$level\
	    loadcmd loadcmd\
	    uncommitted uncommitted\
	    oid2uuid oid2uuid

	upvar 1 $memcache_array memcache

	lassign $memcache($oid) cname uuid DATA
	eval $loadcmd($cname)
	# *MUST*
	unset memcache($oid)
    }

    #
    # Load data for a hierarchy of classes into callers memory,
    # sanity check the hierarchy, and return the list of classes.
    #
    proc c_tree {level dir tree_name root_oid memcache_array pointer args} {
	#
	upvar #$level\
	    unrestored unrestored\
	    fields fields\
	    deferred deferred\
	    oid2uuid oid2uuid

	puts -nonewline "\nRestoring $tree_name hierarchy"; flush stdout

	#
	# Load all relevant classes into memcache
	#
	upvar 1 $memcache_array memcache
	set root_found 0
	set clist [c_subs $tree_name unrestored]
	#
	foreach cname $clist {
	    #
	    # Compute index of pointer field in dump rows
	    #
	    if {[set i [lsearch -exact $fields($cname) $pointer]] < 0} {
		error "Field '$pointer' missing from dump of class '$cname'"
	    }

	    #
	    # '$args' is a list of additional fields not to defer
	    #
	    c_deferred $level $cname deferred [concat $pointer $args]
	    #
	    # Compute the load command,  used to restore each dumped row
	    #
	    c_loadcmd $level $cname create
	    #
	    set fh [open [file join $dir $unrestored($cname)] r]
	    #
	    while {[lgets $fh line] != -1} {
		lassign $line oid uuid DATA
		lappend memcache($oid) $cname $uuid $DATA
		set up [lindex $DATA $i]
		#
		if {![cequal $oid $root_oid]} {
		    if {[cequal $up ""]} {
			error\
			    "Non root $tree_name has NULL parent:\
				(Class=$cname OID=$oid UUID=$uuid)"
		    }
		    lappend memcache(subs.$up) $oid
		    continue
		}
		if {![cequal $up ""]} {
		    error "Root of $tree_name hierarchy has non NULL Parent"
		}
		set root_found 1
	    }
	    close $fh
	}
	#
	if {$root_found == 0} {
	    error "Root $tree_name (OID $root_oid) not found in dump"
	}
	set clist
    }

    proc loop_error {level memcache_array pointer} {
	upvar #$level\
	    fields fields
	upvar 1 $memcache_array memcache
	#
	# Find an oid
	#
	set search [array startsearch memcache]
	while {[array anymore memcache $search]} {
	    set oid [array nextelement memcache $search]
	    if {[string match subs.* $oid]} continue
	    break
	}
	array donesearch memcache $search
	#
	# Print at most ten elements from the loop
	#
	set count 0
	set print 0
	while 1 {
	    lassign $memcache($oid) cname uuid DATA
	    if {$print == 1} {
		puts "Class='$cname', OID='$oid', UUID='$uuid'"
		puts "Points at:"
		if {[info exists seen($oid)]} break
		if {[incr count] > 10} {puts "..."; break}
	    }
	    if {[info exists seen($oid)]} {
		set len [expr $count - $seen($oid) + 1]
		puts "\nLoop of length $len detected for field '$pointer'"
		set print 1
		set count 0
		unset seen
		continue
	    }
	    set seen($oid) [incr count]
	    set oid [lindex $DATA [lsearch -exact $fields($cname) $pointer]]
	}
	error ""
    }

    #
    # Restore regions, cells and organizations carefully
    #
    proc r_regions {level dir region_class org_class root_oid} {
	#
	upvar #$level\
	    unrestored unrestored\
	    deferred deferred

	set clist\
	    [c_tree $level $dir $region_class $root_oid memcache owner cellorg]

	r_root $level $root_oid memcache

	#
	# Restore all the organizations as promised
	#
	set olist [c_subs $org_class unrestored]
	foreach cname $olist {
	    c_deferred $level $cname deferred owner
	    r_class $level $dir $cname
	}

	r_subs $level $root_oid memcache

	if {[array size memcache] > 0} {
	    loop_error $level memcache owner
	}
	eval s_restored $level $clist
    }

    #
    # Restore roles
    #
    proc r_hier {level dir hname root_oid pointer} {
	#
	set clist [c_tree $level $dir $hname $root_oid memcache $pointer]
	#
	r_root $level $root_oid memcache
	r_subs $level $root_oid memcache
	#
	if {[array size memcache] > 0} {
	    loop_error $level memcache $pointer
	}
	eval s_restored $level $clist
    }

    #
    # Return *names* of classes, which indices in the array $type_array,
    # equal to or subclasses of the class *named* $super
    #
    proc c_subs {super type_array} {
	upvar #0\
	    UNAMEIT_CLASS_UUID cuuid\
	    UNAMEIT_CLASS_NAME cnames\
	    UNAMEIT_SUBS subs

	upvar 1 $type_array type

	set clist {}
	set super $cuuid($super)
	foreach class [concat $super $subs($super)] {
	    if {[info exists type($cnames($class))]} {
		lappend clist $cnames($class)
	    }
	}
	set clist
    }

    #
    # Try to restore each network hierarchy in turn, but only so long
    # as no subclasses are already restored and the owner field need
    # not be deferred.
    #
    proc r_networks {level dir} {
	upvar #0\
	    UNAMEIT_NETPOINTER netpointer\
	    UNAMEIT_ATTRIBUTE_UUID auuid\
	    UNAMEIT_ATTRIBUTE_CLASS aclass

	upvar #$level\
	    unrestored unrestored\
	    restored restored\
	    root_oid root_oid

	array set scan [array get netpointer]
	while {[array size scan] > 0} {
	    set progress 0
	    foreach aname [array names scan] {
		#
		# We have the parent network pointer of a network class,
		# what address family does this belong to?
		# Get the class name of the domain.
		#
		set cname [c_domain $aclass($aname) $aname]

		#
		# If no universe net,  the hierarchy is empty.
		#
		if {![info exists root_oid($cname)]} {
		    unset scan($aname)
		    continue
		}

		#
		# What has been restored?
		#
		set do [c_subs $cname unrestored]
		set done [c_subs $cname restored]
		if {[lempty $do] || ![lempty $done]} {
		    unset scan($aname)
		    continue
		}

		#
		# Check to see whether owner is deferred
		#
		c_deferred $level $cname tmp {}
		if {[info exists tmp($cname.owner)]} continue
		#
		# We have a suitable network hierarchy restore it!
		#
		incr progress
		r_hier $level $dir $cname $root_oid($cname) $aname
		unset root_oid($cname)
	    }
	    if {$progress == 0} break
	}
    }

    #
    # Populate forest as we go,  as soon as we reach an existing
    # node,  flush the tree below the node,  keeping memory requirements
    # as small as reasonable
    #
    proc r_forest {level cname path memcache_array pointer} {
	#
	upvar #$level\
	    unrestored unrestored\
	    deferred deferred\
	    fields fields\
	    loadcmd loadcmd\
	    uncommitted uncommitted\
	    oid2uuid oid2uuid
	#
	upvar 1 $memcache_array memcache

	if {[set i [lsearch -exact $fields($cname) $pointer]] < 0} {
	    error "Field '$pointer' missing from dump of class '$cname'"
	}

	puts -nonewline "\nRestoring $cname forest"; flush stdout

	c_deferred $level $cname deferred $pointer
	c_loadcmd $level $cname create

	set fh [open $path r]
	#
	while {[lgets $fh line] != -1} {
	    lassign $line oid uuid DATA
	    lappend memcache($oid) $cname $uuid $DATA
	    set up [lindex $DATA $i]
	    if {![cequal $up ""]} {
		lappend memcache(subs.$up) $oid
		if {[info exists oid2uuid($up)]} {
		    #
		    # Flush all the nodes below the existing item `$up'
		    #
		    r_subs $level $up memcache
		}
		continue
	    }
	    #
	    # Flush parentless item.  This may fail if pointer
	    # is enforced non NULL by libudb,  and would indicate
	    # some sort of data corruption
	    #
	    eval $loadcmd($cname)
	}
	close $fh
    }

    proc r_glob {level dir clist pointer} {
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
	    r_forest $level $cname $dumpfile memcache $pointer
	}
	if {[array size memcache] > 0} {
	    loop_error $level memcache $pointer
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
	    set progress 0
	    foreach cname [array names unrestored] {
		c_deferred $level $cname tmp {}
		if {[lempty $tmp($cname.List)]} {
		    #
		    # Hooray,  a class with no deferred fields, nail it!
		    #
		    r_class $level $dir $cname
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
	    foreach cname [set clist [array names unrestored]] {
		c_deferred $level $cname tmp {}
		if {![info exists tmp($cname.owner)]} {
		    lappend ok_list $cname
		    #
		    # Class with an undeferred owner field, lets estimate
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
		# Every class potentially has instances with unrestored owner
		# Restore them all as one massive owner hierarchy
		#
		r_glob $level $dir $clist owner
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
	}
    }

    proc r_protected {level dir file} {
	#
	set fh [open [file join $dir $file] r]
	#
	while {[lgets $fh line] != -1} {
	    lassign $line oid uuid
	    udb_protect_items $uuid
	}
	close $fh
    }

    #
    # Restore the data classes
    #
    proc r_data {dir file} {
	upvar #0\
	    UNAMEIT_CLASS_UUID cuuid\
	    UNAMEIT_ISA isa

	if {![info exists cuuid(cell)]} {
	    error "Cannot restore data: schema not restored"
	}
	if {![cequal [udb_get_root cell] ""] ||
		![cequal [udb_get_root role] ""]} {
	    error "Cannot restore data: database not empty"
	}

	#
	# Record variable frame level for storage of shared state
	#
	set level [info level]
	#
	# Turn on periodic commit
	#
	set uncommitted 0

	#
	# Load information about the classes to be restored
	#
	source [file join $dir $file]

	set ccount 0
	if {[info exists unrestored(role)]} {
	    if {![info exists root_oid(role)]} {
		error "No dba role in dump"
	    }
	    set ccount 1
	}

	#
	# If dump has other classes,  it should have some cells
	#
	if {![info exists unrestored(cell)]} {
	    #
	    # Can only restore roles if no cell data
	    #
	    if {[array size unrestored] > $ccount} {
		error "Cannot restore: No cell data in dump"
	    }
	} elseif {![info exists root_oid(cell)]} {
	    error "No root cell in dump"
	}

	#
	# We want to restore the region and role trees,  it would be nice
	# if each was connected,  and both were disjoint,  this will
	# be case unless the class of root of either tree, is a subclass
	# of the other.
	#
	# Pathology: Life is complicated if either roles are regions,
	# or cells are roles.  Fortunately the role class, is protected,
	# until the region and cell classes are also protected,  just
	# check here.
	#
	if {[info exists isa($cuuid(role).$cuuid(cell))]} {
	    error "Pathological schema,  cells should not also be roles"
	}

	if {[info exists root_oid(role)]} {
	    #
	    # Roles point to class oids,  but the schema is dumped and
	    # restored separately,  so these oids are not directly useful.
	    # The dump metadata for this reason includes the oid2classname
	    # array,  which we need to map to uuids before restoring the roles
	    #
	    foreach oid [array names oid2classname] {
		set oid2uuid($oid) $cuuid($oid2classname($oid))
	    }
	    #
	    # Restore the roles.
	    #
	    r_hier $level $dir role $root_oid(role) owner
	    #
	    # Automatically stored as root_object by libudb
	    #
	    unset root_oid(role)
	}

	#
	# If there is no root cell, no other classes to restore
	#
	if {[info exists root_oid(cell)]} {
	    #
	    # Restore all the regions
	    #
	    r_regions $level $dir region organization $root_oid(cell)
	    #
	    # Automatically stored as root_object by libudb
	    #
	    unset root_oid(cell)

	    r_networks $level $dir

	    r_all $level $dir
	}

	r_deferred $level $dir

	#
	# Restore as yet unset root objects
	#
	foreach cname [array names root_oid] {
	    switch -- $cname {
		cell -
		role {
		    continue
		}
	    }
	    udb_set_root $cname $oid2uuid($root_oid($cname))
	}

	#
	# Protect protected objects
	#
	r_protected $level $dir Protected.dat
    }

    #
    # Restore all schema classes
    #
    proc r_schema {dir file} {
	upvar #0\
	    UNAMEIT_CLASS_UUID cuuid\
	    UNAMEIT_ATTRIBUTE_UUID auuid

	if {[info exists cuuid(cell)]} {
	    error "Cannot restore schema: database not empty"
	}

	#
	# Record variable frame level for storage of shared state
	#
	set level [info level]

	#
	# Load information about the classes to be restored
	#
	source [file join $dir $file]

	#
	# Don't load these again, they are built into the meta schema.
	#
	foreach class [udb_qbe -all unameit_data_class unameit_class_name] {
	    set preloaded($class) 1
	    upvar 0 $class class_item
	    set cname $class_item(unameit_class_name)
	    foreach index [array names auuid $cname.*] {
		set preloaded($auuid($index)) 1
	    }
	}

	#
	# Turn off periodic commit
	#
	set uncommitted -1

	#
	# Until the cost function can figure that classes should be restored
	# first,  do so explicitly.
	#
	r_class $level $dir unameit_data_class

	#
	# Any old restore order will do for the schema,  and r_all
	# is supposed to figure out a decent heuristic
	#
	r_all $level $dir

	#
	# Restore deferred attributes.
	#
	r_deferred $level $dir

	#
	# Protect protected objects
	#
	r_protected $level $dir Protected.dat
    }

    proc read_version {path} {
	set fh [open $path r]
	if {[gets $fh version] == -1} {
	    error "Empty version file: $path"
	}
	if {[gets $fh junk] != -1 || ![eof $fh]} {
	    error "Data after first line in Version file: $path"
	}
	close $fh
	if {[scan $version "%d.%d.%d%s" major minor micro x] != 3 ||
		$major < 0 || $minor < 0 || $micro < 0} {
	    error "Malformed version: $version in $path"
	}
	return $version
    }

    set ok [catch {
	global unameitPriv
	global UNAMEIT_PROTECTED_ATTRIBUTE

	unset UNAMEIT_PROTECTED_ATTRIBUTE(modby)
	unset UNAMEIT_PROTECTED_ATTRIBUTE(mtime)
	unset UNAMEIT_PROTECTED_ATTRIBUTE(mtran)

	switch -- $what schema - all {

	    set vfile [file join $unameitPriv(data) data schema.version]
	    set version [read_version $vfile]
	    set dumpdir [file join $unameitPriv(data) data schema.$version]

	    puts -nonewline "Restoring schema: $version"

	    udb_transaction -restore_mode schema
	    r_schema $dumpdir Info.tcl

	    lassign [split $version .] major minor
	    puts -nonewline "\nCommitting schema (takes a while)..."
	    flush stdout
	    udb_commit -schemaMajor $major -schemaMinor [incr minor]\
		"Schema Restore Complete"
	    #
	    # Restoring the schema resets these,  so clear them once more
	    #
	    unset UNAMEIT_PROTECTED_ATTRIBUTE(modby)
	    unset UNAMEIT_PROTECTED_ATTRIBUTE(mtime)
	    unset UNAMEIT_PROTECTED_ATTRIBUTE(mtran)
	}

	switch -- $what data - all {

	    set vfile [file join $unameitPriv(data) data data.version]
	    set version [read_version $vfile]
	    set dumpdir [file join $unameitPriv(data) data data.$version]

	    puts -nonewline "\nRestoring data: $version"
	    udb_transaction -restore_mode data
	    r_data $dumpdir Info.tcl

	    lassign [split $version .] major
	    puts -nonewline "\nCommitting data..."
	    flush stdout
	    udb_commit -dataMajor [incr major] "Data Restore Complete"
	}

	puts -nonewline "\nBuilding indices..."
	flush stdout
	unameit_build_indices

	puts -nonewline "\nCommitting indices..."
	udb_commit "Restore Complete"

	puts "Done"
    } error]

    if {$ok != 0} {
	global errorCode errorInfo
	if {![cequal $errorCode NONE]} {
	    puts $errorCode
	}
	puts $error
	puts $errorInfo
	puts "Restore failed"
	exit 1
    }
}
