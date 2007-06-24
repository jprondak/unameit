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
# $Id: cache_mgr.tcl,v 1.117.4.6 1997/10/11 00:52:52 viktor Exp $

#### The cache manager interpreter is a sibling of the schema manager
#### interpreter. Both of them are children of a parent interpreter
#### that uses their resources.

#### This cache manager expects
#### 1. to be linked with the libconn library. It needs to do this because
####    the Cache_mgr_Init routine calls Uclient_Init to get access to the
####    unameit_send (and other) commands in the libconn library.
#### 2. the parent interpreter to install the commands in the list 
####    schema_commands from the schema interpreter into this interpreter.

####			Initialization routines

### This routine returns a list of all the commands that should be exported to 
### the schema manager only.
proc unameit_get_schema_mgr_commands {} {
    return {
	unameit_get_attribute_classes
	unameit_get_menu_info
	unameit_get_class_metadata
	unameit_get_collision_rules
	unameit_get_protected_attributes
	unameit_get_net_pointers
	unameit_get_attr_order

	unameit_get_error_code_info
	unameit_get_error_proc_info
    }
}

### This routine contains all the commands exported by this
### interpreter; that is, this routine returns the API of this interpreter. 
### Aliases are made for every interpreter that uses the cache manager.
proc unameit_get_interface_commands {} {
    return {
	unameit_initialize_cache_mgr

	unameit_disconnect_from_server
	unameit_connect_to_server
	unameit_send_auth

	unameit_query
	unameit_get_cache_uuids
	unameit_sort_uuids

	uuidgen
	unameit_commit
	unameit_get_license_terms
	unameit_preview_cache
	unameit_get_toi_code
	unameit_get_server_version
	unameit_get_cache_mgr_version
	unameit_data_version
	unameit_schema_version
	unameit_can_modify_schema

	unameit_get_db_label
	unameit_get_new_label
	unameit_get_attribute_values
	unameit_multi_fetch
	unameit_revert_field
	unameit_revert_items
	unameit_create
	unameit_update
	unameit_get_item_state
	unameit_get_item_states
	unameit_delete_items
	unameit_load_uuids

	unameit_send
    }
    # unameit_send (above) is used in the SCI.  And in unameitcl
    # when one needs for some reason to bypass the cache manager.
}

proc unameit_can_modify_schema {} {
    unameit_send unameit_can_modify_schema
}

### Any initialization code for the cache manager should go here. This routine
### should be able to be called more than once!
proc unameit_initialize_cache_mgr {} {
    set global_vars {
	UNAMEIT_CACHE_ITEMS
	UNAMEIT_NEW_UUID_LIST
	UNAMEIT_CREATED
	UNAMEIT_UPDATED
	UNAMEIT_DELETED
	UNAMEIT_MODIFIED_ITEMS
    }
    global UNAMEIT_CACHE_ITEMS

    load {} Uqbe

    ## Delete all old items
    foreach uuid [array names UNAMEIT_CACHE_ITEMS] {
	global $uuid
	catch {unset $uuid}
    }

    ## Delete all updates to items
    foreach var [info globals new_*] {
	global $var
	unset $var
    }

    ## Delete all global variables
    foreach var $global_vars {
	global $var
	catch {unset $var}
    }

    # Masks for an item's state
    set UNAMEIT_CREATED 1
    set UNAMEIT_UPDATED 2
    set UNAMEIT_DELETED 4
}

####		Calls into this subsystem

proc unameit_get_cache_mgr_version {} {
    package require Cache_mgr
}

# We can't return the cache items on a class by class basis because when
# you run a query, the unameit_decode_items function populates the 
# UNAMEIT_CACHE_ITEMS array but it only returns the uuids of the items
# matching the query. Any "name attribute" items may have been created, but
# they are not returned so there is no way to see which items were actually
# added to UNAMEIT_CACHE_ITEMS. Fixing this would require modifying the
# unameit_decode_items function.
proc unameit_get_cache_uuids {{only_modified 0}} {
    global UNAMEIT_CACHE_ITEMS UNAMEIT_MODIFIED_ITEMS

    if {$only_modified} {
	return [array names UNAMEIT_MODIFIED_ITEMS]
    } else {
	return [array names UNAMEIT_CACHE_ITEMS]
    }
}

### This routine takes a list of qbe pathnames and generates and runs a query
### based on those pathnames and stores the results in the cache manager. Query
### paths look like 
###	foo(name)		{= Scott}
###	foo(owner.name)		{= west}
###	foo(owner.owner)	{= QuBsDdZm2QyrokU.65Leek}
###     foo(gid)		{< 50}
###	foo(ifname)		=
### In the last case, you are seeing if ifname is null.
proc unameit_query {query_list {options ""}} {
    #
    foreach {attr constraint} $query_list {
	lvarcat q_array($attr) $constraint
    }

    if {![info exists q_array(Class)]} {
	unameit_error ENOCLASSINDEX
    }

    lvarcat query unameit_qbe -nameFields $options

    if {[unameit_is_readonly $q_array(Class)]} {
	set q_array(All) ""
    }

    unameit_construct_query q_array query "" $q_array(Class)

    unameit_decode_items -result -global -noclobber\
	    -cache_list UNAMEIT_CACHE_ITEMS [unameit_send $query]
}

proc unameit_disconnect_from_server {} {
    unameit_disconnect
}

proc unameit_connect_to_server {server service} {
    unameit_connect $server $service
}

proc unameit_get_license_terms {} {
    unameit_send unameit_license_terms
}

proc unameit_get_toi_code {} {
    unameit_send unameit_get_toi_code
}

proc unameit_get_server_version {} {
    unameit_send unameit_get_server_version
}

proc unameit_data_version {} {
    unameit_send unameit_data_version
}

proc unameit_schema_version {} {
    unameit_send unameit_schema_version
}

### This routine always returns the old database label. It does not return
### the new label for the item if the item has been updated.
proc unameit_get_db_label {uuid} {
    unameit_get_label $uuid db
}

### This procedure returns the new label
proc unameit_get_new_label {uuid} {
    unameit_get_label $uuid new
}

proc unameit_get_label {uuid type} {
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item
    
    # Created items should hvae all name attribute fields filled in.
    if {![info exists uuid_item]} {
	unameit_load_uuids [list $uuid]
    }
    
    set cur_type $type

    if {![info exists new_uuid_item]} {
	set cur_type db
    }

    if {[cequal $cur_type db]} {
	if {[info exists uuid_item(.label)]} {
	    return $uuid_item(.label)
	}
    } else {
	if {[info exists new_uuid_item(.label)]} {
	    return $new_uuid_item(.label)
	}
    }

    ## Load information about this class if it isn't already loaded.
    unameit_class_uuid [set class $uuid_item(Class)]

    # Whenever we load an item, we always load the name attributes for
    # that item so we needn't check if they exist in the item. They do.

    set sep ""
    set label ""
    foreach name_attr [unameit_get_name_attributes $class] {
	if {[cequal $cur_type db] ||
	![info exists new_uuid_item($name_attr)]} {
	    set value $uuid_item($name_attr)
	} else {
	    set value $new_uuid_item($name_attr)
	}
	append label $sep
	if {[unameit_is_pointer $name_attr]} {
	    if {![cequal $value ""]} {
		append label [unameit_get_label $value $type]
	    }
	} else {
	    append label\
		[unameit_check_syntax $class $name_attr $uuid $value display]
	}
	set sep " "
    }

    if {[cequal $cur_type db]} {
	return [set uuid_item(.label) $label]
    } else {
	return [set new_uuid_item(.label) $label]
    }
}

### This routine fetches all the attributes from all the uuids in the list
### from the server. It returns the uuids in sorted order. It simply 
### populates the cache. It is needed by the TOI to prefetch objects that are 
### going to be displayed. The TOI doesn't use multiple calls to 
### unameit_get_attribute_values because that would cause many calls to the
### server which would be very expensive. All the uuids should be in the
### same class.
proc unameit_multi_fetch {uuids attrs} {
    ## If no uuids passed in, just return
    if {[lempty $uuids]} {
	return
    }

    ## Retrieve class info. This shouldn't be needed but can't hurt.
    ## It also sets up the "class" variable for later.
    upvar #0 [set uuid [lindex $uuids 0]] uuid_item
    if {![info exists uuid_item]} {
	unameit_load_uuids [list $uuid]
    }
    unameit_class_uuid [set class $uuid_item(Class)]

    ## Verify that all the attributes are in the class.
    foreach attr $attrs {
	if {![unameit_is_attr_of_class $class $attr]} {
	    unameit_error ENOATTR $class $attr
	}
    }

    ## Get the uuid list we are going to send down to the server. Throw
    ## away created uuids and uuids of objects that have all the attributes
    ## we are looking for already in memory.
    set fetch_list {}
    foreach uuid $uuids {
	upvar #0 $uuid uuid_item

	## Always fetch items that aren't in memory.
	if {![info exists uuid_item]} {
	    lappend fetch_list $uuid
	    continue
	}

	## Skip created items.
	if {[unameit_is_created $uuid]} {
	    continue
	}

	upvar #0 new_$uuid new_uuid_item

	foreach attr $attrs {
	    if {![info exists uuid_item($attr)] &&
	    ![info exists new_uuid_item($attr)]} {
		lappend fetch_list $uuid
		break
	    }
	}
    }

    ## Fetch 'em!
    if {![lempty $fetch_list]} {
	set send_result [unameit_send [eval list unameit_fetch -nameFields\
		{$fetch_list} $attrs]]
	unameit_decode_items -global -cache_list UNAMEIT_CACHE_ITEMS\
		$send_result
    }

    return [unameit_sort_uuids $uuids]
}

proc unameit_get_attribute_values {uuid type args} {
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    unameit_load_uuids [list $uuid]

    unameit_class_uuid [set class $uuid_item(Class)]

    ## If the user gave no attributes, retrieve them all.
    if {[lempty $args]} {
	set args [unameit_get_attributes $class]
	lappend args Class
    }
    
    foreach attr $args {
	if {[cequal $attr Class]} {
	    set result(Class) $class
	    continue
	}
	if {[cequal $attr uuid]} {
	    set result(uuid) $uuid
	    continue
	}

	if {![unameit_is_attr_of_class $class $attr]} {
	    unameit_error ENOATTR $uuid $attr
	}

	if {[cequal $type new] && [info exists new_uuid_item($attr)]} {
	    unameit_sort_attr_value $uuid $attr new
	    set result($attr) $new_uuid_item($attr)
	} else {
	    if {[info exists uuid_item($attr)]} {
		unameit_sort_attr_value $uuid $attr old
		set result($attr) $uuid_item($attr)
	    } else {
		lappend fetch_list $attr
	    }
	}

    }

    if {[info exists fetch_list]} {
	unameit_decode_items -global -cache_list UNAMEIT_CACHE_ITEMS\
		[unameit_send [eval list unameit_fetch -nameFields\
		{[list $uuid]} $fetch_list]]
	foreach attr $fetch_list {
	    catch {unset ${uuid}(.$attr.sorted)}
	    unameit_sort_attr_value $uuid $attr old
	    set result($attr) $uuid_item($attr)
	}
    }

    array get result
}

### Reverting a field has the following behavior:
### deleted(uuid)		=> simply return
### !exists(new_uuid)		=> simply return
### exists(new_uuid.attr)	=> Remove new_uuid.attr.
proc unameit_revert_field {uuid attr} {
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    unameit_load_uuids [list $uuid]

    set class $uuid_item(Class)
    if {![unameit_is_attr_of_class $class $attr]} {
	unameit_error ENOATTR $uuid $attr
    }

    ## Return on deleted objects.
    if {[unameit_is_deleted $uuid]} {
	return
    }

    ## Return if no new_uuid.
    if {![info exists new_uuid_item]} {
	return
    }

    if {[info exists new_uuid_item($attr)] &&
    [unameit_is_name_attribute $class $attr]} {
	catch {unset new_uuid_item(.label)}
    }

    ## Remove attribute.
    catch {unset new_uuid_item($attr)}
    # Most of the time the following will fail. Only for sets of objects
    # that have already been sorted will the index exist.
    catch {unset new_uuid_item(.$attr.sorted)}

    unameit_adjust_object_state $uuid
}

### Reverting an item has the following behavior:
### deleted(uuid)		=> Undelete.
### !deleted(uuid)		=> Delete new_uuid_item.
###				   
proc unameit_revert_items {uuid_list} {
    unameit_load_uuids $uuid_list

    foreach uuid $uuid_list {
	upvar #0 $uuid uuid_item
	upvar #0 new_$uuid new_uuid_item


	if {[unameit_is_deleted $uuid]} {
	    # The following causes deleted objects in the database to become
	    # undeleted on revert.
	    if {[info exists new_uuid_item(deleted)]} {
		unset new_uuid_item(deleted)
	    } else {
		if {![info exists new_uuid_item]} {
		    set new_uuid_item(uuid) $uuid
		    set new_uuid_item(Class) $uuid_item(Class)
		}
		set new_uuid_item(deleted) ""
	    }
	} else {
	    catch {unset new_uuid_item}
	}
	unameit_adjust_object_state $uuid
    }
}

### This routine creates a brand new item (i.e., an item that isn't in the 
### database).
proc unameit_create {class uuid args} {
    global UNAMEIT_CACHE_ITEMS errorInfo errorCode
    upvar #0 $uuid uuid_item

    unameit_class_uuid $class

    set uuid_item(Class) $class
    # NOTE! Newly created items have their uuid attribute set. Database items
    # don't.
    set uuid_item(uuid) $uuid

    if {[set code [catch {
	## Set passed to the arguments passed in
	array set passed $args

	## Get list of all attributes in this class
	foreach attr [unameit_get_attributes $class] {
	    set attrs($attr) 1
	}

	## Verify that the user didn't pass in any unknown or computed or
	## protected attributes (unless that attribute is also a name
	## attribute).
	foreach attr [array names passed] {
	    ## Check that attribute passed in exists.
	    if {![info exists attrs($attr)]} {
		unameit_error ENOATTR $class $attr
	    }

	    ## Check that attribute isn't protected or computed (unless
	    ## it's a name attribute).
	    if {[unameit_isa_protected_attribute $attr]} {
		unameit_error EPROTECTED $class $attr
	    }
	    if {[unameit_isa_computed_attribute $class $attr] &&
	    ![unameit_is_name_attribute $class $attr]} {
		unameit_error ECOMPUTED $class $attr
	    }
	}

	## Set any attributes not given
	foreach attr [array names attrs] {
	    if {![info exists passed($attr)]} {
		set uuid_item($attr) {}
	    } else {
		set uuid_item($attr) [unameit_check_syntax $class $attr\
			$uuid $passed($attr) db]
	    }

	    ## If setting a pointer attribute, load the item pointed to
	    ## so sort will work (only a problem for name attributes) and
	    ## so we can check the domain of the object we are setting
	    ## the attribute to.
	    switch -- [unameit_get_attribute_syntax $class $attr] pointer {
		set domain [unameit_get_attribute_domain $class $attr]
		unameit_load_uuids $uuid_item($attr)
		foreach u $uuid_item($attr) {
		    upvar #0 $u set_item
		    if {![unameit_is_subclass $domain $set_item(Class)]} {
			unameit_error EDOMAIN $uuid $attr $u
		    }
		}
	    }
	}

	# The following sets the UNAMEIT_MODIFIED_ITEMS array.
	unameit_adjust_object_state $uuid
    } msg]]} {
	unset uuid_item
	return -code $code -errorinfo $errorInfo -errorcode $errorCode $msg
    }

    set UNAMEIT_CACHE_ITEMS($uuid) 1

    return $uuid
}

proc uuidgen {} {
    global UNAMEIT_NEW_UUID_LIST

    if {![info exists UNAMEIT_NEW_UUID_LIST] ||
    [lempty $UNAMEIT_NEW_UUID_LIST]} {
	set UNAMEIT_NEW_UUID_LIST [unameit_send {
	    list\
		[uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen]\
		[uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen]\
		[uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen]\
		[uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen]\
		[uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen]\
		[uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen] [uuidgen]
	}]
    }
    lvarpop UNAMEIT_NEW_UUID_LIST
}

proc unameit_get_item_state {uuid} {
    global UNAMEIT_CREATED UNAMEIT_UPDATED UNAMEIT_DELETED
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    unameit_load_uuids [list $uuid]

    set result 0

    if {[unameit_is_deleted $uuid]} {
	set result [expr $result|$UNAMEIT_DELETED]
    }

    if {[unameit_is_created $uuid]} {
	set result [expr $result|$UNAMEIT_CREATED]
    }

    if {[info exists new_uuid_item]} {
	set result [expr $result|$UNAMEIT_UPDATED]
    }

    return $result
}

proc unameit_get_item_states {} {
    global UNAMEIT_CREATED UNAMEIT_UPDATED UNAMEIT_DELETED

    return [list $UNAMEIT_CREATED $UNAMEIT_UPDATED $UNAMEIT_DELETED]
}

proc unameit_delete_items {uuid_list} {
    global UNAMEIT_MODIFIED_ITEMS
    
    unameit_load_uuids $uuid_list

    ## Then do deletions
    foreach uuid $uuid_list {
	upvar #0 $uuid uuid_item
	upvar #0 new_$uuid new_uuid_item

	## If we have an old object that was a deleted object when we
	## ran the query, check to see if it has any modified attributes.
	## If not, remove it from the modified list and remove the new
	## state.
	if {[info exists uuid_item(deleted)] &&
	![cequal $uuid_item(deleted) ""]} {
	    catch {unset new_uuid_item(deleted)}
	} else {
	    ## Add the deleted flag to the new_uuid state always.
	    if {![info exists new_uuid_item]} {
		set new_uuid_item(uuid) $uuid
		set new_uuid_item(Class) $uuid_item(Class)
	    }
	    set new_uuid_item(deleted) yes
	}
	unameit_adjust_object_state $uuid
    }
}

proc unameit_commit {} {
    global UNAMEIT_MODIFIED_ITEMS

    ## Do all deletions first. These don't cause any harm.
    unameit_do_deletions script

    foreach uuid [array names UNAMEIT_MODIFIED_ITEMS] {
	## Next do creates and undeletes
	if {![unameit_is_created $uuid] && ![unameit_is_undeleted $uuid]} {
	    continue
	}

	## if A.f->B then B will get created first. If we are processing B,
	## check if B is already created and if so, continue.
	if {[info exists processed($uuid)]} {
	    continue
	}
	
	catch {unset seen_list}
	unameit_append_create_code_to_script $uuid script seen_list processed
    }

    foreach uuid [array names UNAMEIT_MODIFIED_ITEMS] {

	## Skip already processed items.
	if {[unameit_is_deleted $uuid] || [unameit_is_created $uuid] ||
	    [unameit_is_undeleted $uuid]} continue

	## Do updates.
	unameit_append_update_code_to_script $uuid script
    }
    
    ## Do all the object valued collection attributes of created items
    ## AFTER the scalar attributes. The collection attributes may point
    ## to objects that got created later.
    unameit_do_collection_attributes script

    if {[info exists script] && ![cequal $script ""]} {
	if {[info exists script] && ![cequal $script ""]} {
	    append script "unameit_commit [list "\n[unameit_preview_cache]"]\n"
	}
    }

    if {![lempty [interp alias {} unameit_get_objs_in_books]]} {
	## Append fetch commands to script be sent to server.
	if {![lempty [set objs_in_books [unameit_get_objs_in_books]]]} {
	    
	    ## Sort the uuids by class. Also, get the displayed attributes for
	    ## each class.
	    foreach uuid $objs_in_books {
		upvar #0 $uuid uuid_item
		lappend class2uuids([set class $uuid_item(Class)]) $uuid
		if {![info exists displayed_attrs($class)]} {
		    set displayed_attrs($class)\
			    [unameit_get_displayed_attributes $class]
		}
	    }

	    append script {set R {}}
	    foreach class [array names class2uuids] {
		append script [format {
		    append R "[unameit_fetch -nameFields %s %s] "
		} [list $class2uuids($class)] $displayed_attrs($class)]
	    }
	    append script {eval "unset R; list $R\n"}
	}
    }

    #
    # If nothing to do,  don't do it.
    #
    if {![info exists script] || [cequal $script ""]} {
	set reply {}
    } else {
	set reply [unameit_send $script]
    }

    unameit_initialize_cache_mgr

    #
    # Decode server reply
    #
    unameit_decode_items -global -cache_list UNAMEIT_CACHE_ITEMS\
	    $reply

    return		;# Return nothing
}

proc unameit_preview_cache {} {
    global UNAMEIT_MODIFIED_ITEMS

    set result ""

    set deleted_list {}
    set created_list {}
    set updated_list {}
    set undeleted_list {}

    foreach uuid [array names UNAMEIT_MODIFIED_ITEMS] {
	upvar #0 $uuid uuid_item
	upvar #0 new_$uuid new_uuid_item

	if {[unameit_is_deleted $uuid]} {
	    # Skip created and deleted items
	    if {[unameit_is_created $uuid]} {
		continue
	    }
	    lappend deleted_list $uuid
	    continue
	}

	if {[unameit_is_created $uuid]} {
	    lappend created_list $uuid
	    continue
	}
	if {[unameit_is_undeleted $uuid]} {
	    lappend undeleted_list $uuid
	}

	if {[info exists new_uuid_item] &&
	![lempty [unameit_get_modified_attrs $uuid]]} {
	    lappend updated_list $uuid
	}
    }

    set deleted_list [unameit_sort_uuids $deleted_list]
    set created_list [unameit_sort_uuids $created_list]
    set updated_list [unameit_sort_uuids $updated_list]
    set undeleted_list [unameit_sort_uuids $undeleted_list]

    foreach uuid $deleted_list {
	upvar #0 $uuid uuid_item
	append result "deleting [unameit_display_item $uuid]\n"
    }
    foreach uuid $undeleted_list {
	upvar #0 $uuid uuid_item
	append result "undeleting [unameit_display_item $uuid]\n"
    }
    foreach uuid $created_list {
	upvar #0 $uuid uuid_item
	append result "creating [unameit_display_item $uuid]\n"
    }
    foreach uuid $updated_list {
	upvar #0 $uuid uuid_item
	upvar #0 new_$uuid new_uuid_item

	set class $uuid_item(Class)
	append result "updating [unameit_display_item $class]:\
		[unameit_get_db_label $uuid]\n"
	foreach attr [unameit_get_modified_attrs $uuid] {
	    set display_attr [unameit_display_attr $class $attr]
	    set old_value [unameit_display_value $class $attr\
		    $uuid_item($attr)]
	    set new_value [unameit_display_value $class $attr\
		    $new_uuid_item($attr)]
	    append result "\t$display_attr\t$old_value --> $new_value\n"
	}
    }
    
    set result
}

proc unameit_get_sortdata {clist} {
    upvar #0\
	UNAMEIT_ATTRIBUTE_TYPE   atype\
	UNAMEIT_NAME_ATTRIBUTES  anames\
	UNAMEIT_SORTABLE_CLASSES sortable
    #
    # Loop elimination array aliased recursively into ultimate caller's
    # stack frame.  Must use same name for target and alias.
    #
    # Note:  Only needed if name attributes allow recursion,  which is
    # best avoided.
    #
    upvar 1 in_progress in_progress

    foreach c $clist {
	#
	# Abstract *data* classes do not have instances,  the
	# same is not generally true of meta-schema classes.
	#
	if {[info exists sortable($c)] ||
	    [unameit_is_readonly $c] &&
		[unameit_is_subclass unameit_data_item $c] ||
	    [info exists in_progress($c)]} continue
	#
	# Flag class as in_progress to avoid loop in case name attributes
	# can eventually point at same class.
	#
	set in_progress($c) 1
	#
	# Recursively compute name attributes for domains of all pointer
	# valued name attributes.
	#
	foreach a [set anames($c) [unameit_get_name_attributes $c]] {
	    set atype($a) [unameit_attribute_type $a]
	    switch -- $atype($a) Object {
		unameit_get_sortdata\
		    [lvarcat domains [unameit_get_subclasses\
			[set domains [unameit_get_attribute_domain $c $a]]]]
	    }
	}
	#
	# All necessary metadata is available for comparing pointer valued
	# name attributes recursively, we can now sort instances of the class.  
	#
	unset in_progress($c)
	set sortable($c) 1
    }
}

#
# Note!!! the variable names "anames" and "atype" are secretly known
# to the C implementation of unameit_sort_items.
# DO NOT CHANGE THESE NAMES HERE without changing libconn/qbe_tcl.c
#
proc unameit_sort_uuids {uuid_list} {
    upvar #0\
	UNAMEIT_NAME_ATTRIBUTES  anames\
	UNAMEIT_ATTRIBUTE_TYPE   atype

    unameit_load_uuids $uuid_list

    foreach uuid $uuid_list {
	upvar #0 $uuid item
	set getinfo($item(Class)) 1
    }
    unameit_get_sortdata [array names getinfo]

    unameit_sort_items $uuid_list
}

proc unameit_load_uuids {uuid_list} {
    set fetch {}
    foreach uuid $uuid_list {
	upvar #0 $uuid item
	if {[array exists item]} continue
	lappend fetch $uuid
    }
    if {[lempty $fetch]} return
    unameit_decode_items -global -cache_list UNAMEIT_CACHE_ITEMS\
	[unameit_send [list unameit_fetch -nameFields $fetch uuid]]
}

proc unameit_get_protected_attributes {} {
    unameit_send unameit_get_protected_attributes
}

proc unameit_get_net_pointers {} {
    unameit_send unameit_get_net_pointers
}

proc unameit_get_menu_info {} {
    unameit_send unameit_get_menu_info
}

proc unameit_get_attribute_classes {} {
    unameit_send unameit_get_attribute_classes
}

proc unameit_get_class_metadata {class} {
    unameit_send [list unameit_get_class_metadata $class]
}
proc unameit_get_collision_rules {class} {
    unameit_send [list unameit_get_collision_rules $class]
}

proc unameit_get_error_code_info {code} {
    unameit_send [list unameit_get_error_code_info $code]
}

proc unameit_get_error_proc_info {uuid} {
    unameit_send [list unameit_get_error_proc_info $uuid]
}

proc unameit_get_attr_order {} {
    unameit_send unameit_get_attr_order
}

####			Query construction routines

### This procedure takes the query array and a prefix and gives back an
### an array with the attributes taken out and the paths after the attributes.
### If there is no path after the attribute (i.e., it is not a nested QBE),
### then the empty list is returned.
###	foo.interface.macaddr
###	foo.owner.owner
###	foo.owner.host.enabled
###	foo.owner.Class
###	foo.owner.All
###	foo.name
###	foo.All
### and prefix is "foo.", then it will return
###
###  	interface macaddr\
###	owner {owner host.enabled Class All}\
###	name {}
###	All {}
### 
### suitable for an "array set".
proc unameit_group_nested_query_attrs {query_array_var prefix domain} {
    upvar 1 $query_array_var query_array

    foreach path [array names query_array $prefix*] {
	# Strip prefix from path.
	regsub ^$prefix $path "" path

	if {[regexp {^([^.]*)\.(.*)$} $path junk attr rest]} {
	    #
	    # Detect nested qbe vs direct constraint conflict!
	    #
	    if {[info exists direct($attr)]} {
		unameit_error EQBECONFLICT $domain $path $query_array($path)
	    }
	    lappend tuple_array($attr) $rest
	    set nested($attr) 1
	} else {
	    #
	    # Detect nested qbe vs direct constraint conflict!
	    #
	    if {[info exists nested($path)]} {
		unameit_error EQBECONFLICT $domain $path $query_array($path)
	    }
	    set tuple_array($path) ""
	    set direct($path) 1
	}
    }
    array get tuple_array
}

### This routine adds attribute comparisons to a query and may recursively
### call unameit_construct_query if there are any nested qbes.
proc unameit_add_attributes_to_query {query_array_var query_var prefix\
	domain attr attr_value} {
    upvar 1 $query_array_var query_array
    upvar 1 $query_var query

    set syntax [unameit_get_attribute_syntax $domain $attr]
    set mult [unameit_get_attribute_multiplicity $attr]
    set nullable [unameit_is_nullable $domain $attr]

    # If the attribute is not a nested qbe
    if {[lempty $attr_value]} {
	set constrained No
	foreach {op val} $query_array($prefix$attr) {
	    set val [unameit_check_syntax $domain $attr $domain $val query]
	    lappend query [list $attr $op $val]
	    set constrained Yes
	}
	switch -- $constrained No {
	    lappend query $attr
	}
    } else {
	# else generate nested qbe recursively.

	## Check that attribute is pointer or set or sequence of pointer
	if {![cequal $syntax pointer]} {
	    unameit_error EQBENOTOBJ $domain $attr
	}

	set nested_query [list $attr qbe]
	unameit_construct_query query_array nested_query $prefix$attr.\
	    [unameit_get_attribute_domain $domain $attr]
	lappend query $nested_query
    }
}

### Recursive routine for constructing the Tcl query from an array of paths.
proc unameit_construct_query {query_array_var query_var prefix domain} {
    upvar 1 $query_array_var query_array
    upvar 1 $query_var query

    ## Prefix -all if need be
    if {[info exists query_array(${prefix}All)]} {
	lappend query -all
    }

    ## Append the class or "" if all subclasses.
    if {[info exists query_array(${prefix}Class)]} {
	#
	# Adjust domain to match Class constraint
	# let server detect inheritance violations
	#
	lappend query [set domain $query_array(${prefix}Class)]
    } else {
	lappend query ""
    }

    ## Get all the attributes at this level. attr_array's indices will be
    ## all the attributes at this level. The values of attr_array are the
    ## remaining parts of the path for nested qbes.
    array set attr_array\
	[unameit_group_nested_query_attrs query_array $prefix $domain]

    # Foreach attribute at this level...
    foreach attr [array names attr_array] {
	#
	# Skip psuedo-attributes
	#
	switch -- $attr Class - All continue
	unameit_add_attributes_to_query query_array query $prefix\
	    $domain $attr $attr_array($attr)
    }
}

####			Miscellaneous internal routines

proc unameit_is_created {uuid} {
    upvar #0 $uuid uuid_item

    return [info exists uuid_item(uuid)]
}

proc unameit_is_deleted {uuid} {
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    if {[info exists new_uuid_item(deleted)]} {
	return [expr ![cequal $new_uuid_item(deleted) ""]]
    } else {
	if {[info exists uuid_item(deleted)]} {
	    return [expr ![cequal $uuid_item(deleted) ""]]
	} else {
	    return 0
	}
    }
}

proc unameit_is_undeleted {uuid} {
    if {[unameit_is_deleted $uuid]} {
	return 0
    }

    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item
    if {[info exists uuid_item(deleted)] &&
    ![cequal $uuid_item(deleted) ""] &&
    [info exists new_uuid_item(deleted)] &&
    [cequal $new_uuid_item(deleted) ""]} {
	return 1
    } else {
	return 0
    }
}

### Returns true if the deleted state in the old and new item match
proc unameit_deletions_match {uuid} {
    unameit_load_uuids [list $uuid]

    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    if {![info exists new_uuid_item(deleted)]} {
	return 1
    } else {
	if {![info exists uuid_item(deleted)] ||
	[lempty $uuid_item(deleted)]} {
	    set old_deleted 0
	} else {
	    set old_deleted 1
	}
	if {[lempty $new_uuid_item(deleted)]} {
	    set new_deleted 0
	} else {
	    set new_deleted 1
	}
	return [cequal $old_deleted $new_deleted]
    }
}

### Adjusts the UNAMEIT_MODIFIED_ITEMS variable and possibly delete
### the new_uuid state after a change. This routine contains the main
### state adjustment logic. Draw a 3d state table before you modify this code.
proc unameit_adjust_object_state {uuid} {
    global UNAMEIT_MODIFIED_ITEMS
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    if {[unameit_is_created $uuid]} {
	if {[unameit_is_deleted $uuid]} {
	    catch {unset UNAMEIT_MODIFIED_ITEMS($uuid)}
	} else {
	    set UNAMEIT_MODIFIED_ITEMS($uuid) 1
	    if {[lempty [unameit_get_modified_attrs $uuid]]} {
		catch {unset new_uuid_item}
	    }
	}
    } else {
	if {[lempty [unameit_get_modified_attrs $uuid]]} {
	    if {[unameit_deletions_match $uuid]} {
		catch {unset new_uuid_item}
		catch {unset UNAMEIT_MODIFIED_ITEMS($uuid)}
	    } else {
		set UNAMEIT_MODIFIED_ITEMS($uuid) 1
	    }
	} else {
	    if {[unameit_is_deleted $uuid]} {
		if {[info exists new_uuid_item(deleted)] &&
		[unameit_deletions_match $uuid]} {
		    catch {unset new_uuid_item(deleted)}
		}
		if {![unameit_deletions_match $uuid]} {
		    set UNAMEIT_MODIFIED_ITEMS($uuid) 1
		} else {
		    catch {unset UNAMEIT_MODIFIED_ITEMS($uuid)}
		}
	    } else {
		set UNAMEIT_MODIFIED_ITEMS($uuid) 1
	    }
	}
    }
}

proc unameit_sort_attr_value {uuid aname var} {
    #
    if {![cequal Set [unameit_get_attribute_multiplicity $aname]]} return
    #
    switch -- $var new {
	upvar #0 new_$uuid item
    } default {
	upvar #0 $uuid item
    }
    #
    if {[info exists item(.$aname.sorted)]} return
    #
    switch [unameit_attribute_type $aname] {
	String {
	    set item($aname) [lsort $item($aname)]
	}
	Integer {
	    set item($aname) [lsort -integer $item($aname)]
	}
	Object {
	    set item($aname) [unameit_sort_uuids $item($aname)]
	}
    }
    set item(.$aname.sorted) 1
}

proc unameit_get_modified_attrs {uuid} {
    upvar #0 new_$uuid new_uuid_item

    if {![info exists new_uuid_item]} return

    set result {}
    foreach attr [array names new_uuid_item] {
	switch -glob $attr {
	    .* -
	    uuid -
	    Class -
	    deleted {}
	    default {
		lappend result $attr
	    }
	}
    }
    return $result
}

proc unameit_update {uuid args} {
    unameit_load_uuids [list $uuid]

    global UNAMEIT_MODIFIED_ITEMS
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    if {[llength $args] == 0} return

    set class $uuid_item(Class)

    array set tmp $args
    
    foreach attr [array names tmp] {
	if {[unameit_isa_protected_attribute $attr]} {
	    unameit_error EPROTECTED $uuid $attr
	}

	if {[unameit_isa_computed_attribute $class $attr]} {
	    unameit_error ECOMPUTED $uuid $attr
	}

	if {![unameit_is_attr_of_class $class $attr]} {
	    unameit_error ENOATTR $uuid $attr
	}

	# Set the local temporary array first so we don't screw up the
	# global state if we are going to return an exception.
	set tmp($attr)\
	    [unameit_check_syntax $class $attr $uuid $tmp($attr) db]

	## If setting a pointer attribute, load the item pointed to
	## so sort will work (only a problem for name attributes) and
	## so we can check the domain of the object we are setting
	## the attribute to. Actually, updated objects are sorted by
	## their old names, so we don't really need to load the pointed
	## to item for sorting purposes. Doing it here though is consistent
	## with the creation code.
	switch -- [unameit_get_attribute_syntax $class $attr] pointer {
	    set domain [unameit_get_attribute_domain $class $attr]
	    unameit_load_uuids $tmp($attr)
	    foreach u $tmp($attr) {
		upvar #0 $u set_item
		if {![unameit_is_subclass $domain $set_item(Class)]} {
		    unameit_error EDOMAIN $uuid $attr $u
		}
	    }
	}
    }

    ## Fetch any attributes we are trying to set if they are not already
    ## in the cache manager. To do this, we can just call
    ## unameit_get_attribute_values and ignore the results.
    eval unameit_get_attribute_values {$uuid} old [array names tmp]

    set new_uuid_item(Class) $uuid_item(Class)
    set new_uuid_item(uuid) $uuid

    foreach attr [array names tmp] {
	## Sort sets for comparison
	switch -- [unameit_get_attribute_multiplicity $attr] Set {
	    set new_uuid_item($attr) $tmp($attr)
	    unameit_sort_attr_value $uuid $attr new
	    if {[cequal $new_uuid_item($attr) $uuid_item($attr)]} {
		unset new_uuid_item($attr)
		unset new_uuid_item(.$attr.sorted)
	    }
	} default {
	    set new_uuid_item($attr) $tmp($attr)
	    if {[cequal $new_uuid_item($attr) $uuid_item($attr)]} {
		unset new_uuid_item($attr)
	    }
	}
	if {[unameit_is_name_attribute $class $attr]} {
	    catch {unset new_uuid_item(.label)}
	}
    }

    unameit_adjust_object_state $uuid
}

####			Code generation routines

proc unameit_do_deletions {script_var} {
    global UNAMEIT_MODIFIED_ITEMS
    upvar 1 $script_var script

    foreach uuid [array names UNAMEIT_MODIFIED_ITEMS] {
	upvar #0 $uuid uuid_item
	upvar #0 new_$uuid new_uuid_item
	if {[unameit_is_deleted $uuid] &&
	[info exists new_uuid_item(deleted)]} {
	    if {![unameit_is_created $uuid]} {
		append script "unameit_delete $uuid\n"
	    }
	}
    }
}

proc unameit_do_collection_attributes {script_var} {
    global UNAMEIT_MODIFIED_ITEMS
    upvar 1 $script_var script

    foreach uuid [array names UNAMEIT_MODIFIED_ITEMS] {
	upvar #0 $uuid uuid_item
	upvar #0 new_$uuid new_uuid_item

	if {![unameit_is_created $uuid] && ![unameit_is_undeleted $uuid]} {
	    continue
	}

	set class $uuid_item(Class)

	if {[unameit_is_created $uuid]} {
	    set attrs [unameit_get_settable_collection_attrs $class\
		    [unameit_get_attributes $class]]
	} else {
	    set attrs [unameit_get_settable_collection_attrs $class\
		    [unameit_get_modified_attrs $uuid]]
	}
	    
	foreach attr $attrs {
	    if {[info exists new_uuid_item($attr)]} {
		set value $new_uuid_item($attr)
	    } else {
		set value $uuid_item($attr)
	    }
	    append script [list unameit_update $uuid $attr $value]\n
	}
    }
}

proc unameit_get_settable_scalar_attrs {class alist} {
    set result {}
    foreach attr $alist {
	if {![unameit_is_attr_of_class $class $attr]} {
	    unameit_error ENOATTR $uuid $attr
	}
	if {[unameit_isa_protected_attribute $attr]} {
	    continue
	}
	if {[unameit_isa_computed_attribute $class $attr]} {
	    continue
	}
	#
	# Skip non scalar attributes (pointers)
	#
	switch -- [unameit_get_attribute_multiplicity $attr] Scalar {
	    lappend result $attr
	}
    }
    return $result
}

proc unameit_get_settable_collection_attrs {class alist} {
    set result {}
    foreach attr $alist {
	if {![unameit_is_attr_of_class $class $attr]} {
	    unameit_error ENOATTR $uuid $attr
	}
	if {[unameit_isa_protected_attribute $attr]} {
	    continue
	}
	if {[unameit_isa_computed_attribute $class $attr]} {
	    continue
	}
	#
	# We want only the non scalar attributes
	#
	switch -- [unameit_get_attribute_multiplicity $attr] Scalar continue
	lappend result $attr
    }
    return $result
}

proc unameit_append_create_code_to_script {uuid script_var seen_list_var\
	processed_var} {
    unameit_load_uuids [list $uuid]

    upvar 1 $script_var script
    upvar 1 $seen_list_var seen_list
    upvar 1 $processed_var processed
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    if {[info exists seen_list($uuid)]} {
	eval unameit_error ECODEGENLOOP [array names seen_list]
    }

    set seen_list($uuid) 1

    set class $uuid_item(Class)
    if {[set created [unameit_is_created $uuid]]} {
	set cmd [list unameit_create $class $uuid]
    } else {
	set cmd [list unameit_undelete $uuid]
    }

    #
    # Examine all the scalar attributes,  but for undeleted objects
    # handle ordering for unmodified pointers to also undeleted objects
    #
    set attrs\
	[unameit_get_settable_scalar_attrs $class\
	    [unameit_get_attributes $class]]
    
    foreach attr $attrs {
	if {[info exists new_uuid_item($attr)]} {
	    set value $new_uuid_item($attr)
	    set new 1
	} else {
	    ## Undeleted objects may not have all the attributes loaded.
	    if {![info exists uuid_item($attr)]} {
		continue
	    }
	    set value $uuid_item($attr)
	    set new 0
	}
	if {[unameit_is_pointer $attr]} {
	    if {![lempty $value]} {
		if {[unameit_is_deleted $value]} {
		    unameit_error EREFINTEGRITY [list $uuid $attr $value]
		}
		if {([unameit_is_created $value] ||
			[unameit_is_undeleted $value]) &&
			![info exists processed($value)]} {
		    unameit_append_create_code_to_script $value script\
			    seen_list processed
		}
	    }
	    if {$created || $new} {
		lappend cmd $attr $value
	    }
	} else {
	    if {$created || $new} {
		lappend cmd $attr $value
	    }
	}
    }

    append script $cmd\n

    # Do this last. We can't set it until the object is fully created. Since
    # this routine is recursive, this object may be seen again.
    set processed($uuid) 1
}

proc unameit_append_update_code_to_script {uuid script_var} {
    unameit_load_uuids [list $uuid]

    upvar 1 $script_var script
    upvar #0 $uuid uuid_item
    upvar #0 new_$uuid new_uuid_item

    set class $uuid_item(Class)

    set cmd [list unameit_update $uuid]

    ## All the creates have already run,  so we can do all the attributes
    set modified [unameit_get_modified_attrs $uuid]
    set attrs [unameit_get_settable_scalar_attrs $class $modified]
    lvarcat attrs [unameit_get_settable_collection_attrs $class $modified]
    
    foreach attr $attrs {
	set value $new_uuid_item($attr)

	if {[unameit_is_pointer $attr]} {
	    foreach refuuid $value {
		if {[unameit_is_deleted $refuuid]} {
		    unameit_error EREFINTEGRITY [list $uuid $attr $refuuid]
		}
	    }
	    lappend cmd $attr $value
	} else {
	    lappend cmd $attr $value
	}
    }
    append script $cmd\n
}
