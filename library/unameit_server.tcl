# $Id: $
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

############################# Utility routines ##########################

proc unameit_isa {super sub} {
    upvar #0\
	UNAMEIT_ISA isa\
	UNAMEIT_CLASS_UUID cuuid
    #
    info exists isa($cuuid($super).$cuuid($sub))
}

proc unameit_merge {uuid oldVar newarr newVar mergeVar} {
    uplevel 1 [list upvar 1 $uuid $uuid $uuid $oldVar $newarr $newVar]
    upvar 1 $mergeVar merge $oldVar old $newVar new
    array set merge [array get old]
    array set merge [array get new]
}

############################# Authorization routines ##########################

#
# Compute the role hierarchy
#
proc unameit_reload_roles {} {
    upvar #0\
	UNAMEIT_CLASS_NAME cnames
    foreach gvar {
	    UNAMEIT_ROLE_UUID UNAMEIT_SUBROLES UNAMEIT_CREATE_CLASSES
	    UNAMEIT_UPDATE_CLASSES UNAMEIT_DELETE_CLASSES
	} {
	global $gvar
	catch {unset $gvar}
    }

    #
    # "rlist" is a list of all the uuids of roles
    #
    # "al" is the ancestor list indexed by role uuid.
    # all the values are role uuids higher up the tree.
    #
    # "dl" is the descendent list array.
    #
    # "isdesc(<uuid1>.<uuid2>)" is true if uuid1 is a descendent of uuid2.
    #

    set rlist\
	[udb_qbe -all role\
	    role_name owner\
	    unameit_role_create_classes\
	    unameit_role_delete_classes\
	    unameit_role_update_classes]
    #
    # Initialize the al, dl and isdesc arrays
    #
    foreach r1 $rlist {
	set al($r1) {}
	set dl($r1) {}
	set isdesc($r1.$r1) 1
	set UNAMEIT_CREATE_CLASSES($r1) {}
	set UNAMEIT_UPDATE_CLASSES($r1) {}
	set UNAMEIT_DELETE_CLASSES($r1) {}
    }
    #
    # Compute the role hierarchy.
    #
    set al() {}; # So that $al($owner) works for empty owner
    foreach r1 $rlist {
	upvar 0 $r1 r1_item
	set owner $r1_item(owner)
	foreach r2 [concat $owner $al($owner)] {
	    if {[info exists isdesc($r1.$r2)]} continue
	    set isdesc($r1.$r2) 1
	    lappend al($r1) $r2
	    lappend dl($r2) $r1
	    foreach r3 $dl($r1) {
		if {[info exists isdesc($r3.$r2)]} continue
		set isdesc($r3.$r2) 1
		lappend al($r3) $r2
		lappend dl($r2) $r3
	    }
	}
    }
    foreach r1 $rlist {
	upvar 0 $r1 r1_item
	set name $r1_item(role_name)
	set UNAMEIT_SUBROLES($r1) $r1
	set UNAMEIT_ROLE_UUID($name) $r1
	lvarcat UNAMEIT_SUBROLES($r1) $dl($r1)
    }
    #
    foreach op {create update delete} {
	catch {unset authorize}
	set field unameit_role_${op}_classes
	upvar 0 UNAMEIT_[string toupper $op]_CLASSES array
	# 
	# Fill in super roles of each class
	#
	foreach role $rlist {
	    upvar 0 $role role_item
	    foreach class $role_item($field) {
		#
		# The role may allow access to as yet uncommitted classes!
		#
		if {[catch {set cnames($class)} cname]} continue
		#
		# Propagate control to ancestors unless they already have it
		#
		foreach super [concat $role $al($role)] {
		    if {[info exists authorize($super.$class)]} break
		    lappend array($super) $cname
		    set authorize($super.$class) 1
		}
	    }
	}
    }
}

#
# Add data for given principal to cache (up to 100 principals),
# of each authorized region and the associated authorization roles.
#
proc unameit_principal {uuid} {
    #
    # This will complain if uuid is deleted
    #
    udb_principal $uuid
    #
    # Superuser is not subject to authorization
    #
    switch -- $uuid "" return
    #
    upvar #0 UNAMEIT_PRINCIPALS pcache UNAMEIT_STALE_AUTH stale
    if {[array size stale] > 0} {
	unameit_flush_auth_cache
    }
    set i [lsearch -exact $pcache $uuid]
    if {$i >= 0} {
	#
	# Move this principal to front of cache
	#
	if {$i > 0} {
	    set pcache [concat $uuid [lreplace $pcache $i $i]]
	}
	#
	# Use cached authorization data
	#
	return
    }
    #
    upvar #0\
	UNAMEIT_SUBROLES roles\
	UNAMEIT_ROLE_UUID ruuid\
	UNAMEIT_CREATE_CLASSES create_classes\
	UNAMEIT_UPDATE_CLASSES update_classes\
	UNAMEIT_DELETE_CLASSES delete_classes
    #
    upvar #0\
	UNAMEIT_PAUTH_$uuid pauth\
	UNAMEIT_PGRANT_$uuid pgrant
    catch {unset pauth}
    catch {unset pgrant}
    #
    # Load all authorization records for this user
    #	
    set radmin $ruuid(regionadmin)
    set isradmin 0
    foreach record [udb_qbe authorization [list principal = $uuid] role\
	    owner] {
	upvar 0 $record item
	set role $item(role)
	set owner $item(owner)
	#
	# Cache delegation authorization
	#
	foreach subrole $roles($role) {
	    set pgrant($owner.$subrole) 1
	    if {[cequal $subrole $radmin]} {set isradmin 1}
	}
	#
	# Cache operation authorization
	#
	foreach op {create update delete} {
	    foreach class [set ${op}_classes($role)] {
		set pauth($owner.$class.$op) 1
	    }
	}
    }
    #
    # Allow regionadmins for *any* region to create/update/delete,
    # in the root cell, "global" objects such as server_type, os, machine, ...
    #
    if {$isradmin} {
	set owner [udb_get_root cell]
	set role $ruuid(rootadmin)
	foreach op {create update delete} {
	    foreach class [set ${op}_classes($role)] {
		set pauth($owner.$class.$op) 1
	    }
	}
    }
    #
    # Cleanup any cached creds of LRU principal.
    #
    switch -- [set lru [lvarpop pcache 99]] "" {} default {
	catch {uplevel #0 unset UNAMEIT_PAUTH_$lru}
	catch {uplevel #0 unset UNAMEIT_PGRANT_$lru}
    }
    #
    # We go at front of pcache
    #
    lvarpush pcache $uuid
}

#
# Use above cache to resolve authorization decisions,  also
# fill in cache of
#
proc unameit_test_cando {principal class event owner} {
    #
    upvar #0 UNAMEIT_PAUTH_$principal pauth
    #
    # Check fast cache
    #
    if {[info exists pauth($owner.$class.$event)]} {
	return $pauth($owner.$class.$event)
    }
    #
    upvar #0 UNAMEIT_ISA isa UNAMEIT_CLASS_UUID cuuid
    #
    # Walk up tree
    #
    set olist {}
    set allow 0
    while {![cequal "" $owner]} {
	#
	if {[info exists pauth($owner.$class.$event)]} {
	    set allow $pauth($owner.$class.$event)
	    break
	}
	udb_fetch $owner owner
	upvar 0 $owner owner_item
	set ocuuid $cuuid([set oclass $owner_item(Class)])
	#
	lappend olist $owner
	#
	# Do not go up beyond containing cell!
	#
	if {[info exists isa($cuuid(cell).$ocuuid)]} {
	    set allow 0
	    break
	}
	set owner $owner_item(owner)
    }
    foreach o $olist {
	set pauth($o.$class.$event) $allow
    }
    return $allow
}

#
# Compute authorization class and authorization domain of an
# object in given class owned by given owner.
#
proc unameit_auth_info {class uuid event newarr} {
    #
    upvar #0 UNAMEIT_ISA isa UNAMEIT_CLASS_UUID cuuid
    upvar #0 UNAMEIT_ATTRIBUTE_UUID auuid
    #
    if {![info exists auuid($class.owner)]} {
	#
	# Must be schema item
	#
	return [list $class ""]
    }
    #
    switch -- $event {
	create {
	    upvar 1 $newarr new
	    if {[cequal "" [set owner $new(owner)]]} {
		unameit_error ENULL $uuid owner
	    }
	}
	delete {
	    udb_fetch $uuid owner
	    set owner [set ${uuid}(owner)]
	}
	update {
	    udb_fetch $uuid owner
	    set owner [set ${uuid}(owner)]
	}
    }
    #
    # Walk up tree
    #
    while {![cequal "" $owner]} {
	#
	# Owner may be deleted earlier in current transaction,  since
	# the deletion is not yet commited,  for authorization purposes
	# the owner exists!
	#
	if {[catch {udb_fetch $owner owner}]} {
	    unameit_error ENXREFITEM $uuid owner $owner
	}
	upvar 0 $owner owner_item
	set ocuuid $cuuid([set oclass $owner_item(Class)])
	#
	if {[info exists isa($cuuid(region).$ocuuid)]} break
	#
	# XXX:
	# If owner is *not* a region,  use owner's class for
	# authorization check.  Works better for host-interfaces,
	# and other `part-of' relations.
	#
	set class $oclass
	set owner $owner_item(owner)
    }
    list $class $owner
}

proc unameit_check_auth {class uuid event newarr} {
    set p [udb_principal]
    if {[cequal "" $p]} {return 1}
    #
    #
    upvar 1 $newarr new
    #
    # Authorization records are managed by delegation.
    #
    if {[cequal $class authorization]} {
	return [unameit_check_grant_auth $p $uuid $event new]
    }
    #
    switch -- $event update {
	if {[info exists new(owner)]} {
	    if {[cequal "" [set owner $new(owner)]]} {
		unameit_error ENULL $uuid owner
	    }
	    #
	    # Getting auth_info for "create" will use new owner.
	    #
	    lassign [unameit_auth_info $class $uuid create new] ac ao
	    if {[unameit_test_cando $p $ac update $ao] == 0} {
		return 0
	    }
	}
    }
    lassign [unameit_auth_info $class $uuid $event new] ac ao
    switch -- [unameit_test_cando $p $ac $event $ao] 0 {return 0}
    #
    #
    # Do reference authorization checks if any
    #
    upvar 1 $uuid old
    if {![info exists old(.check_auth)]} return
    #
    foreach attr $old(.check_auth) {
	set check($attr) 1
    }
    foreach attr [array names check] {
	#
	# Attribute may be set valued
	#
	if {[info exists old($attr)]} {
	    foreach u $old($attr) {
		set refarr($u) 1
	    }
	}
	if {[info exists new($attr)]} {
	    foreach u $new($attr) {
		set refarr($u) 1
	    }
	}
	foreach u [array names refarr] {
	    #
	    # !!! Clean up array for next attribute
	    #
	    unset refarr($u)
	    #
	    # Check authorization for this reference
	    #
	    set code [catch {
		    lassign [unameit_auth_info $class $u update nodata] x ao
		    unameit_test_cando $p $ac $event $ao
		} ok]
	    switch -- $code 0 {
		switch -- $ok 0 {unameit_error EREFPERM $uuid $attr $u}
		continue
	    }
	    #
	    # ENXITEM in auth code above is actually ENXREFITEM for the
	    # reference via $attr.
	    #
	    lassign $errorCode e1 e2
	    switch -- $e1.$e2 UNAMEIT.ENXITEM {
		unameit_error ENXREFITEM $uuid $attr $u
	    }
	    error $ok $errorInfo $errorCode
	}
    }
    return 1
}

proc unameit_test_grant {principal uuid role owner} {
    upvar #0\
	UNAMEIT_CLASS_UUID cuuid\
	UNAMEIT_PGRANT_$principal pgrant
    #
    # Test for cached value!
    #
    if {[info exists pgrant($owner.$role)]} {
	return $pgrant($owner.$role)
    }
    #
    # Walk up tree,  but do not leave containing cell.
    #
    set olist {}
    while 1 {
	if {[cequal "" $owner]} {
	    set allow 0
	    break
	}
	if {[info exists pgrant($owner.$role)]} {
	    set allow $pgrant($owner.$role)
	    break
	}
	udb_fetch $owner owner
	upvar 0 $owner owner_item
	set oclass $cuuid($owner_item(Class))
	#
	# Save list of traversed regions
	#
	if {[info exists isa($cuuid(region).$oclass)]} {
	    lappend olist $owner
	}
	#
	# Do not go up beyond containing cell!
	#
	if {[info exists isa($cuuid(cell).$oclass)]} {
	    set allow 0
	    break
	}
	set owner $owner_item(owner)
    }
    foreach o $olist {
	set pgrant($o.$role) $allow
    }
    return $allow
}

#
# One may modify an authorization object if one holds the same
# or stronger role.
#
proc unameit_check_grant_auth {principal uuid event newarr} {
    #
    upvar #0 UNAMEIT_ISA isa UNAMEIT_CLASS_UUID cuuid
    #
    upvar 1 $newarr new
    switch -- $event {
	create {
	    set role $new(role)
	    set owner $new(owner)
	}
	delete {
	    udb_fetch $uuid role owner
	    set role [set ${uuid}(role)]
	    set owner [set ${uuid}(owner)]
	}
	update {
	    udb_fetch $uuid role owner
	    set role [set ${uuid}(role)]
	    set owner [set ${uuid}(owner)]
	    if {[info exists new(role)]} {
		set newrole $new(role)
	    }
	    if {[info exists new(owner)]} {
		set newowner $new(owner)
	    }
	}
    }
    if {[unameit_test_grant $principal $uuid $role $owner] == 0} {
	return 0
    }
    #
    set samerole [catch {set role $newrole}]
    set sameowner [catch {set owner $newowner}]
    if {$samerole && $sameowner} {return 1}
    #
    unameit_test_grant $principal $uuid $role $owner
}

proc unameit_flush_auth_cache {} {
    upvar #0 UNAMEIT_PRINCIPALS pcache UNAMEIT_STALE_AUTH stale
    if {[info exists stale(regions)] || [info exists stale(roles)]} {
	if {[info exists stale(roles)]} {
	    #
	    # Role hierarchy or class lists are stale
	    #
	    unameit_reload_roles
	}
	#
	# All authorization data is stale.
	#
	if {[info exists pcache]} {
	    foreach p $pcache {
		catch "uplevel #0 {unset UNAMEIT_PAUTH_$p}"
		catch "uplevel #0 {unset UNAMEIT_PGRANT_$p}"
	    }
	}
	set pcache {}
    } else {
	foreach p [array names stale] {
	    set i [lsearch -exact $pcache $p]
	    set pcache [lreplace $pcache $i $i]
	    catch "uplevel #0 {unset UNAMEIT_PAUTH_$p}"
	    catch "uplevel #0 {unset UNAMEIT_PGRANT_$p}"
	}
    }
    unset stale
}

proc unameit_uncache_auth_region {args} {
    uplevel #0 set UNAMEIT_STALE_AUTH(regions) 1
}

proc unameit_uncache_authorization {class uuid event newarr args} {
    lassign $args principalAttr roleAttr ownerAttr
    upvar 1 $uuid old $newarr new $uuid $uuid
    #
    # Post delete trigger may not have prefetched old attributes 
    #
    if {[cequal $event postdelete] && ![info exists old($principalAttr)]} {
	udb_fetch $uuid $principalAttr
    }
    foreach array {old new} {
	upvar 0 $array item
	if {![info exists item($principalAttr)]} continue
	set p $item($principalAttr)
	upvar #0\
	    UNAMEIT_PAUTH_$p pauth\
	    UNAMEIT_PGRANT_$p pgrant
	if {[array exists pauth] || [array exists pgrant]} {
	    uplevel #0 set UNAMEIT_STALE_AUTH($p) 1
	}
    }
}

proc unameit_uncache_auth_role {args} {
    uplevel #0 set UNAMEIT_STALE_AUTH(roles) 1
}

############### Syntax checks and trigger management routines ##############

proc unameit_decode_attributes {event cname uuid values_var vlist} {
    global errorCode errorInfo
    upvar #0\
	UNAMEIT_PROTECTED_ATTRIBUTE protected\
	UNAMEIT_ATTRIBUTE_UUID auuid\
	UNAMEIT_COMPUTED computed\
	UNAMEIT_ANAMES alist\
	UNAMEIT_CHECK_UPDATE_ACCESS check_auth
    #
    upvar 1 $values_var values $uuid old
    #
    # Are all attributes valid?
    #
    foreach {aname val} $vlist {
	if {[info exists protected($aname)]} {
	    unameit_error EPROTECTED $uuid $aname
	}
	if {[info exists computed($cname.$aname)]} {
	    unameit_error ECOMPUTED $uuid $aname
	}
	if {![info exists auuid($cname.$aname)]} {
	    unameit_error ENOATTR $uuid $aname
	}
	set values($aname) $val
    }
    #
    # Supply empty values for "missing attributes"
    #
    if {[cequal $event create]} {
	foreach aname $alist($cname) {
	    if {[info exists values($aname)] ||
		    [info exists computed($cname.$aname)] ||
		    [info exists protected($aname)]} continue
	    set values($aname) {}
	}
    }
    #
    # Now check each attribute value
    #
    foreach aname [array names values] {
	set values($aname)\
	    [unameit_check_syntax $cname $aname $uuid $values($aname)]
	if {[info exists check_auth($cname.$aname)]} {
	    lappend old(.check_auth) $aname
	}
    }
}

proc unameit_encode_attributes {cname values_var} {
    upvar #0 UNAMEIT_REF_INTEGRITY ref_int
    upvar 1 $values_var values
    #
    set result ""
    foreach aname [array names values] {
	#
	# Skip network pointer attributes
	# They implement internal database state, and
	# may only be set by `libudb'
	#
	if {[info exists ref_int($cname.$aname)] &&
	    [cequal $ref_int($cname.$aname) Network]} continue
	#
	lappend result $aname $values($aname)
    }
    set result
}

#
# This function determines whether a trigger function should be run by
# checking if any of the attributes in `deplist' are going to change.
# On create, all the arguments are always given so this function will
# always return 1. As a side effect, it fills in the fetchArr with the
# names of attributes that need to be fetched from the database.
#
proc unameit_should_run_trigger {event fetchArrVar values_var deplist} {
    #
    # If creating trigger is unconditional,  and no attributes to fetch.
    #
    switch -- $event create - postcreate {return 1}
    #
    # If dependency list is empty,  trigger is unconditional, and again
    # no attributes to fetch.
    #
    if {[cequal "" $deplist]} {return 1}
    #
    upvar 1 $values_var values
    upvar 1 $fetchArrVar fetchArr
    #
    #  If updating,  trigger is only run when attributes change,  otherwise
    # (delete) trigger is unconditional
    #
    switch -- $event {
	update - postupdate {
	    set run 0
	    foreach attr $deplist {
		if {[info exists values($attr)]} {
		    set run 1
		    break
		}
	    }
	}
	default {set run 1}
    }
    if {$run} {
	foreach attr $deplist {
	    set fetchArr($attr) 1
	}
    }
    return $run
}

proc unameit_run_triggers {event class uuid values_var} {
    upvar #0\
	UNAMEIT_COMPUTE_TRIGGERS ctriggers\
	UNAMEIT_GENERIC_TRIGGERS gtriggers
    upvar #0\
	UNAMEIT_UPDATABLE updatable\
	UNAMEIT_ANAMES alist
    #
    upvar 1 $values_var values $uuid $uuid $uuid item
    #
    # signatures holds the signatures of the triggers we are going to run.
    #
    set signatures {}
    #
    # Run `compute' triggers first.
    #
    if {[info exists ctriggers($event.$class)]} {
	foreach trigger $ctriggers($event.$class) {
	    #
	    # Each trigger is a 3 element list,  consisting of
	    # 1. Procedure and hardwired arguments
	    # 2. Dependency attributes,  that fire the trigger
	    # 3. Computed attributes that should be set by the trigger
	    #
	    lassign $trigger proc args deplist clist
	    #
	    if {[unameit_should_run_trigger $event fetchArr values $deplist]} {
		lappend signatures [concat [list $proc] $args $deplist $clist]
		#
		# The following array is used to determine if an attribute in
		# values was set by a computation function or not and it is
		# used in the ECWORM error call.
		#
		foreach attr $clist {
		    set attr_deplist($attr) $deplist
		}
	    }
	}
    }

    #
    # Fill in function_tuples with generic triggers.
    #
    if {[info exists gtriggers($event.$class)]} {
	foreach trigger $gtriggers($event.$class) {
	    lassign $trigger proc args deplist
	    if {[unameit_should_run_trigger $event fetchArr values $deplist]} {
		lappend signatures [concat [list $proc] $args $deplist]
	    }
	}
    }

    #
    # Get the old values of any write once attributes if we are doing
    # an update of a commited object.
    #
    if {[cequal $event update] && ![udb_is_new $uuid]} {
	foreach attr $alist($class) {
	    if {!$updatable($class.$attr) &&
		    ([info exists values($attr)] ||
		     [info exists attr_deplist($attr)])} {
		set fetchArr($attr) 1
		lappend wolist $attr
	    }
	}
    }

    #
    # Fetch old values of attributes needed by the triggers.
    #
    switch -- $event {
	delete -
	update {
	    #
	    # Fetch the missing attribute values.
	    #
	    set fetchList {}
	    foreach attr [array names fetchArr] {
		if {![info exists item($attr)]} {
		    lappend fetchList $attr
		}
	    }
	    eval [list udb_fetch $uuid] $fetchList
	}
	postupdate {
	    #
	    # For update triggers that run only after the update,
	    # fetch unchanged old attributes.  It is too late to fetch
	    # old attributes that have changed.
	    #
	    set fetchList {}
	    foreach attr [array names fetchArr] {
		if {![info exists item($attr)] &&
			![info exists values($attr)]} {
		    lappend fetchList $attr
		}
	    }
	    if {![lempty $fetchList]} {
		eval [list udb_fetch $uuid] $fetchList
	    }
	}
    }

    #
    # Run the triggers.
    #
    foreach signature $signatures {
	set args [lassign $signature proc]
	eval [list $proc $class $uuid $event values] $args
    }

    #
    # If necessary, check that WORM attributes didn't change.
    #
    if {![info exists wolist]} return
    #
    foreach attr $wolist {
	if {[cequal [set ${uuid}($attr)] $values($attr)]} {
	    unset values($attr)
	    continue
	}
	if {![info exists attr_deplist($attr)]} {
	    unameit_error EWORM $uuid $attr
	}
	unameit_error ECWORM $uuid $attr $attr_deplist($attr)
    }
}

######################### Triggers ####################
#
#

#
# Set attribute to NULL (or empty string) value.
#
proc unameit_null_trigger {class uuid event newarr attr} {
    upvar 1 $newarr new
    set new($attr) ""
}

#
# Set attribute to value hardcoded into trigger.
#
proc unameit_literal_trigger {class uuid event newarr value attr} {
    upvar 1 $newarr new
    set new($attr) $value
}

#
# Set pointer attribute to `root cell' object.
#
proc unameit_root_cell_trigger {class uuid event newarr ptrAttr} {
    upvar 1 $newarr new
    set new($ptrAttr) [udb_get_root cell]
}

#
# Default pointer attribute to `root' object of class.
#
proc unameit_root_default_trigger {class uuid event newarr ptrAttr} {
    upvar 1 $newarr new
    if {[cequal "" $new($ptrAttr)]} {
	set new($ptrAttr) [udb_get_root $class]
    }
}

#
# Set pointer attribute to `root cell' object.
#
proc unameit_cell_of_trigger {class uuid event newarr ptrAttr compAttr} {
    upvar 1 $newarr new
    set new($compAttr) [udb_cell_of $new($ptrAttr)]
}

#
# Copy attribute from pointed to item to pointing item.
#
proc unameit_copy_trigger {class uuid event newarr args} {
    set attr2 [lvarpop args end]
    set ptrAttr [lvarpop args end]
    if {[lempty $args]} {
	set attr1 $attr2
    } else {
	set attr1 $args
    }
    upvar 1 $newarr new
    set item $new($ptrAttr)
    if {[catch {udb_fetch $item $attr1} err]} {
	global errorCode errorInfo
	lassign $errorCode e1 e2
	switch -- $e1.$e2 {
	    UNAMEIT.ENXITEM {unameit_error ENXREFITEM $uuid $ptrAttr $item}
	    default {error $err $errorInfo $errorCode}
	}
    }
    set new($attr2) [set ${item}($attr1)]
}

### This routine checks to see if the ng_host and ng_user fields of a 
### netgroup_member are compatible. It raises an error if they are not.
proc unameit_check_ng_member_compatibility {class uuid event newarr args} {
    lassign $args host_attr user_attr ng_attr

    unameit_merge $uuid old $newarr new merge

    set host_uuid $merge($host_attr)
    set user_uuid $merge($user_attr)
    set ng_uuid $merge($ng_attr)

    switch [llength $ng_uuid].[llength $host_uuid].[llength $user_uuid] {
	0.0.0 {
	    ## Can't have all fields null.
	    unameit_error EOR $uuid $ng_attr $host_attr $user_attr
	}
	1.1.1 {
	    unameit_error EEXCLUSIVE $uuid $ng_attr $host_attr $user_attr
	}
	1.1.0 {
	    unameit_error EEXCLUSIVE $uuid $ng_attr $host_attr
	}
	1.0.1 {
	    unameit_error EEXCLUSIVE $uuid $ng_attr $user_attr
	}
	0.1.1 {
	    udb_fetch $host_uuid uuid
	    udb_fetch $user_uuid uuid
	    upvar 0 ${host_uuid}(Class) hClass
	    upvar 0 ${user_uuid}(Class) uClass

	    switch [unameit_isa region $hClass].[unameit_isa region $uClass] {
		1.0 -
		1.1 {
		    ## Host region, non null user
		    unameit_error ENGREGIONONLY $uuid $host_attr $user_attr
		}
		0.1 {
		    ## User region, non null host
		    unameit_error ENGREGIONONLY $uuid $user_attr $host_attr
		}
	    }
	}
    }
}

#
# Make sure primary server is not also a secondary server!
#
proc unameit_primary_not_secondary {class uuid event newarr args} {
    #
    lassign $args primAttr secAttr
    #
    unameit_merge $uuid old $newarr new merge
    #
    set primary $merge($primAttr)
    #
    foreach el $merge($secAttr) {
	if {[cequal $el $primary]} {
	    unameit_error EPRIMARYSERVER $uuid $secAttr $el
	}
    }
}

#
# Validates that the org of a pointer is equal to the org of the object
#
proc unameit_check_ref_org {class uuid event newarr args} {
    #
    lassign $args refAttr ownerAttr
    #
    unameit_merge $uuid old $newarr new merge
    #
    set ref $merge($refAttr)
    #
    # If pointer is NULL,  no org compatibility to check!
    #
    if {[cequal "" $ref]} return
    #
    # Either pointer may be invalid,  map ENXITEM to ENXREFITEM
    #
    if {[catch {udb_org_of $ref} refOrg]} {
	unameit_error ENXREFITEM $uuid $refAttr $ref
    }
    #
    set owner $merge($ownerAttr)
    if {[catch {udb_org_of $owner} org]} {
	unameit_error ENXREFITEM $uuid $ownerAttr $owner
    }
    #
    if {![cequal $org $refOrg]} {
	unameit_error EXORG $uuid $refAttr $ref
    }
}

#
# Validates that the cell of a pointer is equal to the cell of the object
#
proc unameit_check_ref_cell {class uuid event newarr args} {
    #
    lassign $args refAttr ownerAttr
    #
    unameit_merge $uuid old $newarr new merge
    #
    set ref $merge($refAttr)
    #
    # If pointer is NULL,  no cell compatibility to check!
    #
    if {[cequal "" $ref]} return
    #
    # Either pointer may be invalid,  ENXITEM to ENXREFITEM
    #
    if {[catch {udb_cell_of $ref} refCell]} {
	unameit_error ENXREFITEM $uuid $refAttr $ref
    }
    #
    set owner $merge($ownerAttr)
    if {[catch {udb_cell_of $owner} cell]} {
	unameit_error ENXREFITEM $uuid $ownerAttr $owner
    }
    #
    if {![cequal $cell $refCell]} {
	unameit_error EXCELL $uuid $refAttr $ref
    }
}

proc unameit_remote_printer_trigger {class uuid event newarr args} {
    upvar #0\
	UNAMEIT_ATTRIBUTE_UUID auuid
    #
    lassign $args ownerAttr rmAttr rpAttr
    unameit_merge $uuid old $newarr new merge
    #
    unameit_check_ref_cell $class $uuid $event new $rmAttr $rpAttr
    udb_fetch [set rp $merge($rpAttr)] uuid
    set rpClass [set ${rp}(Class)]
    #
    # If rp is also indirect,  nothing further to check.
    #
    if {[info exists auuid($rpClass.$rpAttr)]} return
    #
    # rp is a type,  make sure rm is in our cell and updatable by user.
    #
    unameit_check_ref_cell $class $uuid $event new $ownerAttr $rmAttr
    #
    lappend old(.check_auth) $rmAttr
}

proc unameit_check_login_auto_data {class uuid event newarr args} {
    #
    lassign $args mapAttr hostAttr dirAttr
    #
    unameit_merge $uuid old $newarr new merge
    #
    set map $merge($mapAttr)
    set host $merge($hostAttr)
    #
    # If both map and host provided,  nothing to check.
    #
    if {![cequal "" $map] && ![cequal "" $host]} return
    #
    if {[cequal "" $host]} {
	if {![cequal "" $map]} {
	    unameit_error ENOAUTOHOST $uuid $mapAttr
	}
	#
	# Home directory is not automounted,  disallow :&
	#
	set dir $merge($dirAttr)
	if {[regexp {[:&]} $dir]} {
	    unameit_error EPATHNAMEILLEGAL $uuid $dirAttr $dir
	}
	return
    }
    unameit_error ENOAUTOMAP $uuid $mapAttr
}

proc unameit_autoint_trigger {class uuid event newarr args} {
    lassign $args intAttr ownerAttr
    #
    unameit_merge $uuid old $newarr new merge
    #
    # If value provided by user,  no need to auto-generate!
    #
    set int $merge($intAttr)
    if {![cequal "" $int]} return
    #
    set owner $merge($ownerAttr)
    #
    global UNAMEIT_AUTO_RANGE
    lassign $UNAMEIT_AUTO_RANGE($class.$intAttr) min max
    #
    set auto_int [udb_auto_integer $uuid $owner $intAttr $min]
    if {![cequal "" $auto_int] && $auto_int <= $max} {
	set new($intAttr) $auto_int
	return
    }
    unameit_error ERANGEFULL $uuid $intAttr
}

proc unameit_check_qbe_syntax {class uuid event newarr args} {
    #
    lassign $args qbeAttr depAttr
    #
    global UNAMEIT_ISA UNAMEIT_CLASS_UUID UNAMEIT_QBE_CLASS
    upvar 1 $newarr new
    #
    # Carefully construct query command,  to avoid running eval on
    # user supplied strings.
    #
    set cmd [list udb_qbe -syntax]
    foreach arg $new($qbeAttr) {lappend cmd $arg}
    #
    # Check query syntax and save objects that the query depends on.
    #
    if {[catch {eval $cmd} new($depAttr)]} {
	global errorCode
	unameit_error EBADQUERY $uuid $qbeAttr $errorCode
    }
    #
    # Parse query to get class name.
    #
    set spec $new($qbeAttr)
    while 1 {
	switch -- [set qbeClassName [lvarpop spec]] -all {} default break
    }
    #
    set qbeClass $UNAMEIT_CLASS_UUID($qbeClassName)
    #
    # Check that class given is subclass of the class in the meta
    # data attribute.
    #
    set qbeDomainClass $UNAMEIT_QBE_CLASS($class.$qbeAttr)
    #
    if {![info exists UNAMEIT_ISA($qbeDomainClass.$qbeClass)]} {
	unameit_error EQBENOTSUBCLASS $uuid $qbeAttr $qbeClassName
    }
}

proc unameit_copyback_trigger {class uuid event newarr args} {
    #
    upvar 1 $newarr new $uuid old
    #
    set len [llength [set alist [lassign $args relClass relAttr]]]
    set cmd [list lassign [lrange $alist 0 [expr $len / 2 - 1]]]
    #
    foreach attr [lrange $alist [expr $len / 2] end] {
	lappend cmd copyto($attr)
    }
    eval $cmd
    set vlist {}
    foreach attr [array names copyto] {
	if {[info exists new($attr)]} {
	    lappend vlist $copyto($attr) $new($attr)
	}
    }
    #
    # Loop over relatives propagating attribute changes.
    #
    foreach rel [udb_qbe -all $relClass [list $relAttr = $uuid]] {
	eval udb_update $rel $vlist
    }
}

#
# Console line number may not exceed termninal server nLines.
#
proc unameit_check_line {class uuid event newarr args} {
    lassign $args nLinesAttr lineAttr ownerAttr
    #
    unameit_merge $uuid old $newarr new merge
    #
    set owner $merge($ownerAttr)
    set line $merge($lineAttr)
    #
    udb_fetch $owner $nLinesAttr
    #
    set nLines [set ${owner}($nLinesAttr)]
    if {$line > $nLines} {
	unameit_error ETOOBIG $uuid $lineAttr $line $nLines
    }
}

#
# Terminal server nLines must equal or exceed largest line number.
#
proc unameit_check_lines {class uuid event newarr args} {
    #
    lassign $args consClass ownerAttr lineAttr nLinesAttr
    #
    upvar 1 $newarr new
    set nLines $new($nLinesAttr)
    #
    foreach console\
	    [udb_qbe -all $consClass [list $ownerAttr = $uuid] $lineAttr] {
	set line [set ${console}($lineAttr)]
	if {$line > $nLines} {
	    unameit_error ETOOSMALL $uuid $nLinesAttr $nLines $line
	}
    }
}

proc unameit_region_name_change {class uuid event newarr args} {
    upvar #0 UNAMEIT_ISA isa UNAMEIT_CLASS_UUID cuuid
    set is_cell [info exists isa($cuuid(cell).$cuuid($class))]
    #
    lassign $args nameAttr relnameAttr ownerAttr
    upvar 1 $newarr new $uuid old $uuid $uuid
    #
    switch -- $event {
	create -
	update {
	    #
	    #
	    set name $new($nameAttr)
	    set dupregion [udb_qbe -all region [list $nameAttr = $name]]
	    #
	    # Make sure no *other* region,  has the new FQDN.
	    # Allowing even temporary duplicate region names will
	    # break the tree maintenance (this) code.
	    #
	    if {![cequal "" $dupregion] && ![cequal $dupregion $uuid]} {
		unameit_error EDUPREGION $uuid $nameAttr $name
	    }
	    #
	    # Find ancestor region.
	    #
	    set found 0
	    set upname [split $name .]
	    while {[llength $upname] > 2} {
		lappend prefix [lvarpop upname]
		set upregion\
		    [udb_qbe -all region [list $nameAttr = [join $upname .]]]
		switch -- [llength $upregion] {
		    0 continue
		    1 {
			set found 1
			break
		    }
		    default {
			#
			# Should `never' happen.
			#
			lassign $upregion r1 r2
			unameit_error EDUPREGION $r1 $nameAttr [join $upname .]
		    }
		}
	    }
	    if {$found == 1} {
		#
		# Set new owner and relname.
		#	
		set new($ownerAttr) $upregion
		set new($relnameAttr) [join $prefix .]
		#
		if {[cequal $event update] &&\
			!$is_cell &&\
			![cequal\
			    [udb_cell_of $uuid]\
			    [udb_cell_of $upregion]]} {
		    #
		    # Region FQDN change may not move it to a new cell!
		    #
		    unameit_error ENEWFQDNCELL $uuid $nameAttr $name
		}
	    } else {
		if {!$is_cell} {
		    #
		    # Region FQDN change may not move it into root cell!
		    #
		    unameit_error EROOTREGION $uuid $nameAttr $name
		}
		#
		# Cell is a top level cell!
		#
		set new($ownerAttr) [udb_get_root cell]
		set new($relnameAttr) $name
	    }
	}
    }
    switch -- $event {
	delete -
	update {
	    #
	    # Cells with inferior *regions* may not be deleted
	    #
	    if {$is_cell && [cequal $event delete] &&\
		    ![lempty [set subs\
			[udb_qbe region [list $ownerAttr = $uuid]]]]} {
		#
		# Return up to 10 integrity violations
		#
		set cmd [list unameit_error EREFINTEGRITY]
		foreach sub [lrange $subs 0 9] {
		    lappend cmd [list $sub $ownerAttr $uuid]
		}
		eval $cmd
	    }
	    #
	    # Save old values of name relname and owner
	    #
	    udb_fetch $uuid $nameAttr $relnameAttr $ownerAttr
	}
	postdelete -
	postupdate {
	    #
	    # Take care of old regions
	    #
	    set name $old($nameAttr)
	    set owner $old($ownerAttr)
	    set relname $old($relnameAttr)
	    #
	    # Update old subregions,  
	    #
	    if {$is_cell} {
		#
		# We are going to rename subregions recursively,  so
		# get all regions that extend the FQDN.
		#
		set subs\
		    [udb_qbe -all region\
			[list $nameAttr ~ "*.$name"] $relnameAttr $ownerAttr]
		if {[cequal $event postupdate]} {
		    #
		    # Record this cell's name change,  simplifies inheritance
		    # of new subcells below
		    #
		    set moved_region($new($nameAttr)) $uuid
		}
	    } else {
		#
		# We are going to reparent the immediate subregions,
		# so get the regions owned by $uuid.
		#
		set subs\
		    [udb_qbe -all region [list $ownerAttr = $uuid] $relnameAttr]
	    }
	    foreach sub $subs {
		upvar 0 $sub subitem
		if {!$is_cell} {
		    #
		    # Reparent the subregion
		    #
		    udb_update $sub\
			$ownerAttr $owner\
			$relnameAttr "$subitem($relnameAttr).$relname"
		} else {
		    set oldowner $subitem($ownerAttr)
		    #
		    # Do not descend below subcells
		    #
		    if {![cequal [udb_cell_of $oldowner] $uuid]} continue
		    #
		    # Reparent subcells, and rename subregions.
		    # Compute old relname relative to *this* cell
		    #
		    set subname $subitem($nameAttr)
		    set sublen [clength $subname]
		    set len [clength $name]
		    set subrelname\
			[crange $subname 0 [expr $sublen - $len - 2]]
		    #
		    if {[cequal [udb_cell_of $sub] $sub]} {
			#
			# A subcell of this cell,  grow relname
			# to be relative to cell's old owner.
			#
			append subrelname ".$relname"
			udb_update $sub $ownerAttr $owner\
			    $relnameAttr $subrelname
			#
		    } elseif {[cequal $event postupdate]} {
			#
			# A subregion of this cell: change name to
			# track cell's new name
			#
			set movedname $subrelname.$new($nameAttr)
			udb_update $sub $nameAttr $movedname
			#
			# Store away FQDN->uuid mapping for renamed
			# subregions,  we need them below when dealing
			# with newly inherited subregions
			#
			set moved_region($movedname) $sub
		    }
		}
	    }
	    unameit_uncache_auth_region
	}
	postcreate {
	    #
	    if {$is_cell} {
		if {![cequal "" [set who [udb_principal]]]} {
		    #
		    # Authorize creator to administer new cell
		    # XXX: Eventually would like to put action
		    # in the client!
		    #
		    global UNAMEIT_ROLE_UUID
		    set role $UNAMEIT_ROLE_UUID(celladmin)
		    udb_create authorization [uuidgen]\
			role $role owner $uuid principal $who
		}
	    }
	    unameit_uncache_auth_region
	}
    }
    #
    # After create and update,  fix any `inherited' subregions.
    #
    switch -- $event {
	postcreate -
	postupdate {
	    set relname $new($relnameAttr)
	    set relnamelen [clength $relname]
	    set owner $new($ownerAttr)
	    #
	    # Update the ownership and relnames of new subregions
	    #
	    set subs\
		[udb_qbe -all region $nameAttr\
		    "$ownerAttr = $owner"\
		    [list $relnameAttr ~ "*.$relname"]]
	    #
	    foreach sub $subs {
		upvar 0 $sub subitem
		if {[cequal $event postupdate]} {
		    set subname $subitem($nameAttr)
		    #
		    # Find lowest moved region in this cell,  above $sub
		    #
		    set comps [split $subname .]
		    set relcomps {}
		    while {![info exists moved_region([join $comps .])]} {
			lappend relcomps [lvarpop comps]
		    }
		    if {[lempty $relcomps]} {
			#
			# This inherited region collides with a moved region
			# lose!
			#
			unameit_error EDUPREGION $sub $nameAttr $subname
		    }
		    set newrelname [join $relcomps .]
		    set newowner $moved_region([join $comps .])
		} else {
		    set sublen [clength [set subrelname $subitem($relnameAttr)]]
		    #
		    # Trim trailing ".$relname" from subrelname
		    #
		    set newrelname\
			[crange $subrelname 0 [expr $sublen - $relnamelen - 2]]
		    set newowner $uuid
		}
		#
		# This will fail if sub is a region,  and we are a new
		# cell above it,  but that's just what we want,  so let
		# "libudb" do the work.
		#
		udb_update $sub $ownerAttr $newowner $relnameAttr $newrelname
	    }
	}
    }
}

############################### System Call Code ##########################

proc unameit_license_terms {} {
    global unameitPriv
    #
    lassign [udb_license_info] h p

    set expd $unameitPriv(license_end)
    set maxh $unameitPriv(license_host_units)
    set maxp $unameitPriv(license_person_units)
    set type $unameitPriv(license_type)
    set fmt "%22s license units consumed: %3d%% (%d/%d)\n"
    #
    if {$maxh > 0} {
	set hpercentile [expr 100*$h/$maxh]
	append terms [format $fmt Host $hpercentile $h $maxh]
    }
    if {$maxp > 0} {
	set ppercentile [expr 100*$p/$maxp]
	append terms [format $fmt Person $ppercentile $p $maxp]
    }
    #
    if {![cequal $expd -1]} {
	set fmt "\n[replicate " " 19]License expiration date: %b %e, %Y\n"
	append terms [clock format $expd -format $fmt]
    }
    switch -- $type {
      eval {
	append terms "

    By using this product, you agree to the following: This product
      is distributed \"as-is\".  Use of this product is entirely at
      your own risk.  You assume all liability.  Enterprise Systems
       Management Corporation and its licensors make no warranty.\n

    This product and related documentation are protected by copyright
      and distributed under a temporary license restricting its use,
     copying, and distribution.  Decompilation, reverse engineering,
       or extraction of source code are strictly prohibited.  This
        product is not licensed for production use, but rather for
      internal evaluation purposes only.  No part of this product or
     related documentation may be reproduced in any form by any means
        without prior written authorization of Enterprise Systems
           Management Corporation and its licensors, if any.\n

      Upon expiration of the license, you agree to remove this product
     completely from all systems and media and return any distribution
        media, along with all copies of the related documentation, to
                Enterprise Systems Management Corporation.
	  "
      }
    }
    return $terms
}

#########################################
# System calls that do updates!		#
#########################################

proc unameit_create {class uuid args} {
    upvar #0 UNAMEIT_CLASS_UUID cuuid
    #
    # User initiated system calls have level == 1,  trigger or
    # cascade calls have level > 1
    #
    set level [info level]
    #
    if {![info exists cuuid($class)]} {
	unameit_error ENXREFCLASS $uuid $class
    }
    unameit_decode_attributes create $class $uuid values $args
    set cmd [list udb_create $class $uuid]
    #
    # Do all updates atomically
    #
    udb_syscall {
	unameit_run_triggers create $class $uuid values
	if {$level == 1 &&
		[unameit_check_auth $class $uuid create values] == 0} {
	    unameit_error EPERM $uuid
	}
	eval $cmd [unameit_encode_attributes $class values]
	unameit_run_triggers postcreate $class $uuid values
    }
}

proc unameit_update {uuid args} {
    #
    # User initiated system calls have level == 1,  trigger or
    # cascade calls have level > 1
    #
    set level [info level]
    #
    # If protected (or invalid uuid) error
    #
    if {$level == 1 && [udb_protected $uuid]} {
	unameit_error EPERM $uuid
    }
    #
    # If deleted,  error.
    #
    udb_fetch $uuid deleted
    upvar 0 $uuid item
    if {![cequal "" $item(deleted)]} {
	unameit_error ENXITEM $uuid
    }
    #
    # Get class for authorization and triggers.
    #
    set class $item(Class)
    unameit_decode_attributes update $class $uuid values $args
    set cmd [list udb_update $uuid]
    #
    # Do all updates atomically
    #
    udb_syscall {
	unameit_run_triggers update $class $uuid values
	if {$level == 1 &&
		[unameit_check_auth $class $uuid update values] == 0} {
	    unameit_error EPERM $uuid
	}
	eval $cmd [unameit_encode_attributes $class values]
	unameit_run_triggers postupdate $class $uuid values
    }
}

proc unameit_delete {uuid} {
    #
    # User initiated system calls have level == 1,  trigger or
    # cascade calls have level > 1
    #
    set level [info level]
    #
    # If protected (or invalid uuid) error
    #
    upvar 0 $uuid item
    if {$level == 1} {
	if {[udb_protected $uuid]} {
	    unameit_error EPERM $uuid
	}
	#
	# Nothing to do if already deleted
	#
	udb_fetch $uuid deleted
	if {![cequal "" $item(deleted)]} return
	set class $item(Class)
	#
	# Check authorization
	#
	if {[unameit_check_auth $class $uuid delete empty0] == 0} {
	    unameit_error EPERM $uuid
	}
    } else {
	#
	# Cascaded objects are never already deleted,  and we do not
	# care whether they are protected
	#
	udb_fetch $uuid uuid
	set class $item(Class)
    }
    #
    # Do all updates atomically
    #
    udb_syscall {
	unameit_run_triggers delete $class $uuid empty1
	udb_delete $uuid
	unameit_run_triggers postdelete $class $uuid empty2
    }
}

proc unameit_undelete {uuid args} {
    upvar #0\
	UNAMEIT_PROTECTED_ATTRIBUTE protected\
	UNAMEIT_COMPUTED computed
    #
    # User initiated system calls have level == 1,  trigger or
    # cascade calls have level > 1
    #
    set level [info level]
    #
    # Users may not undelete protected objects, (also syntax checks the uuid)
    #
    if {$level == 1 && [udb_protected $uuid]} {
	unameit_error EPERM $uuid
    }
    udb_fetch $uuid
    upvar 0 $uuid item
    set class $item(Class)
    if {[cequal "" $item(deleted)]} {
	unameit_error ENOTDELETED $uuid
    }
    #
    # Fill in default (old) values for all fields.
    #
    foreach attr [array names item] {
	if {[info exists computed($class.$attr)]} continue
	if {[info exists protected($attr)]} continue
	if {[cequal $attr Class]} continue
	set values($attr) $item($attr)
    }
    unameit_decode_attributes create $class $uuid values $args
    set cmd [list udb_undelete $uuid]
    #
    # Do all updates atomically
    #
    udb_syscall {
	unameit_run_triggers create $class $uuid values
	if {$level == 1 &&
		[unameit_check_auth $class $uuid update values] == 0} {
	    unameit_error EPERM $uuid
	}
	eval $cmd [unameit_encode_attributes $class values]
	unameit_run_triggers postcreate $class $uuid values
    }
}

proc unameit_change_password {uuidlist newpass} {
    #
    # Iterate over all logins with matching name and password,
    # at least one exists.
    #
    foreach uuid $uuidlist {
	## Get object class
	udb_fetch [list $uuid] uuid
	upvar 0 $uuid item
	
	set class $item(Class)
	set cmd [list udb_update $uuid password]

	## Change password
	set pass [unameit_check_syntax $item(Class) password $uuid $newpass]

	lappend cmd $pass

	eval $cmd
    }

    ## Return last uuid's values
    return $pass
}

proc unameit_change_shell {uuidlist newshell} {
    #
    # Iterate over all logins with matching name and password,
    # at least one exists.
    #
    foreach uuid $uuidlist {
	## Get object Class and domain (for shell_location)
	udb_fetch [list $uuid] owner shell
	upvar 0 $uuid item
	
	set class $item(Class)
	set cmd [list udb_update $uuid shell]

	## One may not change the shell if it was not one of the
	## standard shells.
	if {[regexp / $item(shell)]} {
	    unameit_error EPERM $uuid
	}

	## Get the tail of the shell,  "file tail" is platform dependent
	## We always want '/'
	set tail [lindex [split $newshell /] end]
	set tail [unameit_check_syntax $class shell $uuid $tail]

	## Compute the new shell location

	## Look up shell location for region
	set location [udb_qbe shell_location shell_path\
		[list shell_name = $tail] [list owner = $item(owner)]]

	## Else look for shell location for cell
	if {[lempty $location]} {
	    set cell [udb_cell_of $item(owner)]
	    if {![cequal $cell $item(owner)]} {
		set location [udb_qbe shell_location shell_path\
			[list shell_name = $tail] [list owner = $cell]]
	    }
	}
	if {[lempty $location]} {
	    ## Use default
	    set shell_path /bin/$tail
	} else {
	    ## Use override path
	    upvar 0 $location location_item
	    set shell_path $location_item(shell_path)
	}
	## Make sure shell is compatible with what the user requested
	switch -- $newshell /bin/$tail - /usr/bin/$tail - $shell_path {}\
	    default {unameit_error EPERM $uuid}

	lappend cmd $tail
	eval $cmd
    }

    ## Return last uuid's values
    return $shell_path
}
