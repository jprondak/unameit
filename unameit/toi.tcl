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

#### 			Main TOI code (downloaded from server)

# State in the UI is stored in global variables with the same name as the
# widget pathnames. There are basically three places state is stored: 1)
# global state per toplevel is stored in the widget path of the toplevel.
# We always know the name of this variable by "winfo toplevel $widget" on
# any widget below that toplevel. 2) Widget state for each class form is stored
# in the widget path name for that form. If a class frame is named
# .top0^.object_box^.canvas.computer then a global variable with that same
# name stores all the state for that class. 3) Widget state for each attribute
# is stored in the outermost frame for that attribute. Every widget below
# this outermost frame has a global variable with the same name as the
# widget. The index attr_state^ in this global variable points at the real
# global variable containing all the state for the attribute. E.g., if
# we have a widget .top0^.object_box^.canvas.computer.name.entry^, then
# a global variable with that same name will have an index attr_state^
# that points to the global variable .top0^.object_box^.canvas.computer.name.
# This allows us to change the widget tree under 
# .top0^.object_box^.canvas.computer.name without having to change code all
# over the place. The indirection localizes the changes to only the place
# that the widget is created. The attribute state variable also has an index
# class_state^ that points to the class state variable for that attribute.
# The class state does not have an index pointing to the global state for
# the form because that can be computed with "winfo toplevel". A destroy 
# binding is set up for "all" that destroys the global state for every
# widget when the widget is destroyed.
#	The working sets for each class must be variables unto themselves
# because they use the ordered list routines. However, they really belong
# at the toplevel level because they are per toplevel, not per class form.
# They are inconvenient to store there though because there are not widgets
# per class at that level. So we store them in the same variable as the
# class form, intermingling the ordered list data with the data the TOI
# code stuffs into the class global. By using indices carefully, the two
# don't collide. Also, by using the same variable name, the working sets
# for a class will be cleaned up automatically when the widget hierarchy
# for that class disappears.
#	Popup dialogs are always subwidgets of the toplevel that popped them
# up. Because of this, destroying a toplevel will automatically destroy
# any dialogs associated with that toplevel.
#	By convention, state variables have an "_s" appended to them. Paths
# to these state variable have "_p" appended to them.
# 	Here is a widget tree with some variables at each level
#
#	.top0^			class^, mode^, <class> (for each class)
#	  |
#    .object_box^.canvas
#	  |
#      user_login		class^, attr^, uuids^, <attr> (for each attr)
#         |
#      shell--------		attr^, attr_state^, class_state^, other_vars.
#        / \        \
#   entry^  other   csh		attr_state^, name^ (if enum)
#
# .top0^
# ______
# class^		Name of current class in form when in item or query
#			mode. Unset in login or about mode.
# mode^			Current mode: item, query, about, login.
# <class>		Pointer to widget path (i.e., state variable) for
#			each class.
#
# user_login
# ----------
# class^		Name of class this state variable is for. 
#			Self-referential, but since we don't inspect the widget
#			tree, necessary.
# attr^			Attribute with the focus. Changes with focus. Also,
#			the attribute to change the focus to when we come
#			back to this class.
# uuids^		List of uuids of all the items selected in the
#			working set. The first selected item is the one
#			displayed.
# <attr>		Pointer to widget path (i.e., state variable) for
# 			each attribute.
#
# shell
# -----
# attr^			Name of attribute for this widget path.
# attr_state^		Pointer to state variable for this attribute. Not
#			very useful here, but useful in all the subwidgets of
#			this attribute. Each subwidget has (and must) have
#			this attribute filled in so we can find the state
#			variable associated with the attribute.
# other vars.		Miscellaneous attribute state. E.g., value^ is
#			the widget value for entry and pointer widgets,
#			pointers^ contains the uuid of the object for
#			pointer widgets, attr_state^ contains Hex/Normal
#			for addresses, etc.
#
# csh (Any widget level below the attribute level)
# ---
# attr_state^		Pointer to state for this attribute.
# name^			Only used for radio buttons. The name of the 
#			enumeration value this radio button represents.

####			Window routines

proc unameit_set_listbox_item_state {widget index uuid} {
    global unameitPriv

    if {[unameit_item_is $uuid deleted]} {
	$widget item configure $index -overstrike 1
    } else {
	$widget item configure $index -overstrike 0
    }

    ## Make created objects take priority over updated objects otherwise if
    ## you create an object and then update it you won't be able to tell
    ## that this object was created.
    if {[unameit_item_is $uuid created]} {
	$widget item configure $index -foreground $unameitPriv(create_color)
	return
    }
    if {[unameit_item_is $uuid updated]} {
	$widget item configure $index -foreground $unameitPriv(update_color)
	return
    }
    $widget item configure $index -foreground [option get . foreground\
	    Foreground]
}

proc unameit_refresh_preview_window {} {
    global unameitPriv

    if {![winfo exists .preview^]} return

    .preview^.text_frame^.text configure -state normal
    .preview^.text_frame^.text delete 0.0 end
    .preview^.text_frame^.text insert end [unameit_preview_cache]
    .preview^.text_frame^.text configure -state disabled
}

### This routine is called when the user hits Button 1 in the working set box.
proc unameit_set_ws_item {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s
    set attr $class_s(attr^)

    ## Save the selection BEFORE doing an automatic apply. Automatic apply
    ## can change the selection (when it calls unameit_update_ws_labels).
    set selections [$toplevel_p.working_set^.listframe^.fancylistbox\
	    curselection]

    ## Try to apply the focus field and if it fails, reset the ws highlight.
    if {[set code [catch {unameit_apply_focus_field $toplevel_p} msg]]} {
	global errorCode errorInfo
	if {[info exists class_s(uuids^)]} {
	    unameit_select_ws_entries $toplevel_p [lindex $class_s(uuids^) 0]
	} else {
	    unameit_select_ws_entries $toplevel_p ""
	}
	return -code $code -errorcode $errorCode -errorinfo $errorInfo $msg
    }

    if {[ordered_list_size class_s] == 0} {
	return
    }

    set uuid_list {}
    foreach selection $selections {
	lappend uuid_list [get_nth_from_ordered_list class_s $selection]
    }
    if {[lempty $uuid_list]} {
	unameit_empty_form $toplevel_p
    } else {
	set class_s(uuids^) $uuid_list
	unameit_fill_in_class_data $class_p

	$toplevel_p.working_set^.listframe^.fancylistbox see\
		[lindex $selections 0]
    }
}

proc unameit_select_all_items {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s
    set attr $class_s(attr^)

    unameit_apply_focus_field $toplevel_p

    if {[ordered_list_size class_s] == 0} {
	return
    }

    set class_s(uuids^) [get_values_from_ordered_list class_s]
    unameit_fill_in_class_data $class_p

    $toplevel_p.working_set^.listframe^.fancylistbox see 0
}

proc unameit_button1_on_field {widget} {
    upvar #0 $widget widget_s
    upvar #0 [set attr_p $widget_s(attr_state^)] attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    upvar #0 [set toplevel_p [winfo toplevel $widget]] toplevel_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    unameit_apply_focus_field_if_different_attr $attr_p

    set widget_type [unameit_get_widget_type $class $attr]

    if {![info exists widget_s(name^)]} {
	unameit_switch_focus $widget
    } else {
	## Radioboxes, choices and checkboxes.

	# Invoke the button to toggle its state and variable.
	# We will skip the class binding below
	$widget invoke
	
	switch -- $widget_type {
	    check_box -
	    radio_box {
		unameit_automatic_apply $attr_p
	    }
	    choice {
		if {[cequal $widget_s(name^) Other]} {
		    unameit_switch_focus $attr_p.entry^
		} else {
		    if {[cequal [focus -lastfor $toplevel_p] $attr_p.entry^]} {
			focus $attr_p
		    }
		    $attr_p.entry^ delete 0 end
		    unameit_automatic_apply $attr_p
		}
	    }
	}

	# Skip the class binding
	# It will otherwise toggle the button again.
	return -code break
    }
}

### This routine is called when the user clicks on a field in the listbox
### for a set or sequence of pointers.
proc unameit_set_list_box_menubutton {attr_p} {
    set toplevel_p [winfo toplevel $attr_p]

    unameit_apply_focus_field $toplevel_p
    unameit_switch_focus $attr_p

    ## We know the pointer is disabled because we did an apply_focus above.
    ## If it was enabled, it was currently the focus and is now disabled.
    unameit_show_item_at_anchor $attr_p
} 

proc unameit_redisplay_address {attr_p display_type} {
    upvar #0 $attr_p attr_s
    set class_p $attr_s(class_state^)
    set toplevel_p [winfo toplevel $attr_p]

    ## We have to do this because the popup menu may not apply the focus
    ## if on the same field.
    unameit_apply_focus_field $toplevel_p

    set attr_s(address_state^) $display_type

    set value [unameit_get_widget_value $attr_p]

    ## The unameit_set_widget function takes care of displaying in hex
    ## or normal mode.
    unameit_set_widget_value $attr_p $value

    unameit_set_item_menus $class_p
}

### This procedure disables the buttons on the button bar and in the popup
### menus. See the unameit_add_${widget_type}_field routines to see which
### states the buttons/menus are enabled/disabled and which entries are 
### created. It is only called in item mode. In query mode, there is
### no enabling/disabling to do.
proc unameit_set_item_menus {class_p} {
    upvar #0 $class_p class_s
    set class $class_s(class^)
    upvar #0 [set toplevel_p [winfo toplevel $class_p]] toplevel_s

    set on_item [info exists class_s(uuids^)]

    ## Set Create, Delete and Revert button states
    if {!$on_item} {
	set state disabled
    } else {
	set state normal
    }
    if {[unameit_is_readonly $class]} {
	set create_state disabled
	set state disabled
    } else {
	set create_state normal
    }
    foreach button {Delete Revert} {
	$toplevel_p.button_bar^.[s2w $button] configure -state $state
    }
    $toplevel_p.button_bar^.[s2w Create] configure -state $create_state

    ## Set Back and Forward button state
    if {[empty $toplevel_s(visit_list^)] ||
    $toplevel_s(visit_list_index^) <= 0} {
	set state disabled
    } else {
	set state normal
    }
    $toplevel_p.button_bar^.[s2w Back] configure -state $state
    if {[set len [llength $toplevel_s(visit_list^)]] == 0 ||
    $len-1 <= $toplevel_s(visit_list_index^)} {
	set state disabled
    } else {
	set state normal
    }
    $toplevel_p.button_bar^.[s2w Forward] configure -state $state

    ## Set Revert menu item state
    unameit_iterate_over_class $class_p {
	upvar 1 on_item on_item

	## Skip widgets that aren't entries, texts, text lists or
	## pointer fields
	if {![cequal $widget_type entry] && ![cequal $widget_type text] &&
	![cequal $widget_type text_list] && ![cequal $syntax pointer]} {
	    continue
	}

	if {[unameit_is_readonly $class] ||
	[unameit_is_prot_or_comp $class $attr] || !$on_item} {
	    set state disabled
	} else {
	    set state normal
	}
	if {[cequal $syntax pointer]} {
	    $attr_p.menubutton^.menu^ entryconfigure\
		    $attr_s(revert_loc^) -state $state
	} else {
	    switch $widget_type {
		text -
		text_list {
		    $attr_p.revert^ configure -state $state
		}
		default {
		    $attr_p.menu^ entryconfigure $attr_s(revert_loc^)\
			    -state $state
		}
	    }
	}
    }

    ## Set Hex/Normal menu item state
    unameit_iterate_over_class $class_p {
	upvar 1 on_item on_item

	## Skip every field that isn't an address.
	if {![cequal $syntax address]} {
	    continue
	}

	if {$on_item} {
	    if {[cequal $attr_s(address_state^) Normal]} {
		set normal_state disabled
		set hex_state normal
	    } else {
		set normal_state normal
		set hex_state disabled
	    }
	} else {
	    set normal_state disabled
	    set hex_state disabled
	}
	$attr_p.menu^ entryconfigure $attr_s(normal_loc^) -state $normal_state
	$attr_p.menu^ entryconfigure $attr_s(hex_loc^) -state $hex_state
    }
}

proc unameit_advance_ws_selection {toplevel_p count} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s
    set attr $class_s(attr^)

    unameit_apply_focus_field $toplevel_p

    if {[lempty [set selections\
	    [$toplevel_p.working_set^.listframe^.fancylistbox\
	    curselection]]]} {
	return
    }
    set index [lindex $selections 0]

    set listbox_size [$toplevel_p.working_set^.listframe^.fancylistbox size]
    set index [expr ($index+$count)%$listbox_size]

    set class_s(uuids^) [get_nth_from_ordered_list class_s $index]
    $toplevel_p.working_set^.listframe^.fancylistbox selection clear 0 end
    $toplevel_p.working_set^.listframe^.fancylistbox selection set $index
    $toplevel_p.working_set^.listframe^.fancylistbox see $index

    unameit_fill_in_class_data $class_p
}

proc unameit_create_class_fields {widget class} {
    ## Create frame containing object fields as child of canvas
    set class_p [frame $widget.[s2w $class]]
    unameit_add_wrapper_binding $class_p

    upvar #0 $class_p class_s

    set class_s(class^) $class

    set label_width 10
    set labels {}

    ## Preset the class_s(<attr>) and attr_s(attr^) variables so
    ## unameit_iterate_over_class doesn't choke.
    foreach attr [unameit_get_displayed_attributes $class] {
	set class_s($attr) $class_p.[s2w $attr]
	upvar #0 $class_s($attr) attr_s
	set attr_s(attr^) $attr
    }

    ## Add all the different fields.
    unameit_iterate_over_class $class_p {
	## Access variables from previous frame
	upvar 1 label_width label_width labels labels

	## Create frame to hold label and widget
	set label_text [unameit_display_attr $class $attr]
	if {[clength $label_text] > $label_width} {
	    set label_width [clength $label_text]
	}
	frame $attr_p
	unameit_add_wrapper_binding $attr_p
	pack $attr_p -side top -anchor w -fill both

	set attr_s(attr_state^) $attr_p		;# Self referential
	set attr_s(class_state^) $class_p	;# Pointer to parent

	## Create label
	set label [label $attr_p.label^ -text $label_text -anchor ne]
	unameit_add_wrapper_binding $label
	pack $label -side left -padx 1m -pady 1m -fill both
	lappend labels $label
	upvar #0 $label label_s
	set label_s(attr_state^) $attr_p

	## Trash pointer values for pointer attributes.
	if {[cequal $syntax pointer]} {
	    set attr_s(pointers^) ""
	}

	# Object-oriented programming? Smiley...
	set widget [unameit_add_${widget_type}_field $attr_p]
	pack $widget -side right -padx 1m -pady 1m -expand 1 -fill both
    }
    foreach label $labels {
	$label conf -width $label_width
    }

    return $class_p
}

####		Routines to create each syntax on the screen

# Buttons at the top of the main screen and menus items are created and
# enabled/disabled as follows:
#
# Buttons on top screen
# ---------------------
# Clear
# Create	Disabled: read only classes
# Delete	Disabled: read only classes, not on item
# Query
# Revert	Disabled: read only classes, not on item
#
# Entry field: Revert  Disabled: query mode, readonly classes,
#				 protected/computed fields, not on item
#
# Address: Revert      Same as Entry
#
#          Hex/Normal  Disabled: query mode, not on item
#
# Pointer: Match Name Disabled: item mode and (readonly class or
#		       computed/protected)
#
#          Full Query Disabled: item mode and (readonly class or
#		       computed/protected)
#
#	   Clear  /    Disabled: item mode and (readonly class or
#	   Delete      computed/protected)
#
#	   Mod Obj1... Doesn't exist: item mode and (readonly class or
#	   Mod Objn    computed/protected)
#
#	   Revert      Same as Entry
#
#	   Traverse    Disabled: query mode
#
#	   Embed       Disabled: item mode

proc unameit_add_menu_item {parent attr_p count_var label state code} {
    upvar 1 $count_var count

    if {![winfo exists $parent.menu^]} {
	upvar menu menu

	set menu [menu $parent.menu^]

	unameit_add_wrapper_binding $menu

	upvar #0 $menu menu_s
	set menu_s(attr_state^) $attr_p

	upvar #0 $attr_p attr_s
	set attr_s(menu^) $menu
    }

    $parent.menu^ add command -label $label -state $state\
	    -command [list unameit_wrapper $code]
    incr count
}

proc unameit_add_entry_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    ## Create the entry field
    set entry [entry $attr_p.entry^ -width 32 -textvariable ${attr_p}(value^)]
    unameit_add_wrapper_binding $entry
    upvar #0 $entry entry_s
    set entry_s(attr_state^) $attr_p

    set mode $toplevel_s(mode^)
    set syntax [unameit_get_attribute_syntax $class $attr]

    set count 0

    ## Add Revert
    set attr_s(revert_loc^) $count
    unameit_add_menu_item $attr_p $attr_p count Revert disabled\
	    [list unameit_revert_field_callback $attr_p]

    ## Add Hex/Normal
    if {[cequal $syntax address]} {
	## We want address fields to stay in Hex or Normal mode
	## even if we come back to them.
	set attr_s(address_state^) Normal

	set attr_s(normal_loc^) $count
	unameit_add_menu_item $attr_p $attr_p count Normal disabled\
		[list unameit_redisplay_address $attr_p Normal]

	set attr_s(hex_loc^) $count
	unameit_add_menu_item $attr_p $attr_p count Hex disabled\
		[list unameit_redisplay_address $attr_p Hex]
    }
	

    ## Set it up so that if you try to post this menu, you do an automatic
    ## apply on the previous field and then switch focus to this field.
    $menu configure -postcommand [format {
	unameit_apply_focus_field_if_different_attr %s
	unameit_switch_focus %s
    } [list $attr_p] [list $entry]]

    bind $entry <Button-3> [list unameit_wrapper [list tk_popup $menu %X %Y]]

    return $entry
}

proc unameit_add_menu_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 $attr_s(class_state^) class_s
    
    set class $class_s(class^)
    set attr $attr_s(attr^)
    set mode $toplevel_s(mode^)
    set mult [unameit_get_attribute_multiplicity $attr]

    ## Initially create menubutton with empty text. There is no item to
    ## point to yet.
    # We must turn off indicatoron to get rid of Tk's scanning behavior.
    # If you don't turn off the scanning behavior, when you are doing
    # a pointer completion and you select a class menu and move to a
    # pointer field menu you get an error.
    set menubutton [menubutton $attr_p.menubutton^ -width 32 -takefocus 1\
	    -highlightthickness 2 -pady 1 -padx 1\
	    -menu $attr_p.menubutton^.menu^\
	    -anchor w -relief groove -indicatoron 1]
    unameit_add_wrapper_binding $menubutton
    upvar #0 $menubutton menubutton_s
    set menubutton_s(attr_state^) $attr_p

    ## Create entry widget. Just don't pack it yet.
    set entry [entry $attr_p.entry^ -width 32 -textvariable ${attr_p}(value^)]
    unameit_add_wrapper_binding $entry
    upvar #0 $entry entry_s
    set entry_s(attr_state^) $attr_p

    set attr_s(fence^) 0

    ## set_state is enabled if we can set this pointer value
    if {[cequal $mode item] && ([unameit_is_readonly $class] ||
    [unameit_is_prot_or_comp $class $attr])} {
	set set_state disabled
    } else {
	set set_state normal
    }

    ## Add Simple Query
    # In Tk 3.0 and later, menu MUST be children of the menubutton.
    unameit_add_menu_item $menubutton $attr_p attr_s(fence^) {Match Name}\
	    $set_state [list unameit_enable_pointer_entry $attr_p]

    ## Add Full Query (Submenu?)
    unameit_add_query_menu $attr_p attr_s(fence^) $set_state

    ## Add Clear/Delete
    if {[cequal $mult Scalar]} {
	set label Clear
    } else {
	set label Delete
    }
    unameit_add_menu_item $menubutton $attr_p attr_s(fence^) $label\
	    $set_state [list unameit_delete_pointers $attr_p]

    ## Add Revert
    set attr_s(revert_loc^) $attr_s(fence^)
    unameit_add_menu_item $menubutton $attr_p attr_s(fence^) Revert\
	    disabled [list unameit_revert_field_callback $attr_p]

    ## Add Traverse
    if {[cequal $mode item]} {
	set state normal
    } else {
	set state disabled
    }
    set attr_s(traverse_loc^) $attr_s(fence^)
    unameit_add_menu_item $menubutton $attr_p attr_s(fence^) Traverse\
	    $state ""

    ## Add Embed. XXX: Not yet implemented.
    #if {[cequal $mode query]} {
    #	unameit_add_menu_item $menubutton $attr_p attr_s(fence^) Embed\
    #	    normal ""
    #}

    ## Set it up so that if you try to post this menu, you do an automatic
    ## apply on the previous field and then switch focus to this field.
    $menu configure -postcommand [format {
	unameit_apply_focus_field %s
	unameit_switch_focus %s
	unameit_modify_popup_menu %s
    } [list $toplevel_p] [list $menubutton] [list $attr_p]]

    return $menubutton
}

proc unameit_add_text_list_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s

    set mode $toplevel_s(mode^)

    ## Create outer frame
    set frame [frame $attr_p.frame^ -bd .02i -relief groove]
    unameit_add_wrapper_binding $frame
    upvar #0 $frame frame_s
    set frame_s(attr_state^) $attr_p

    ## Create scrollable text box
    set top_frame [unameit_create_scrollable $attr_p top^ text y 1 $attr_p\
	    -width 20 -height 5 -state disabled -takefocus 1]
    pack $top_frame -in $frame -side top -fill both -expand 1

    ## Create button box
    set bottom_frame [frame $attr_p.bottom_frame^]
    unameit_add_wrapper_binding $bottom_frame
    upvar #0 $bottom_frame bottom_frame_s
    set bottom_frame_s(attr_state^) $attr_p
    pack $bottom_frame -in $frame -side bottom

    ## Add buttons
    set edit_button [button $attr_p.edit^ -text Edit -command [list\
	    unameit_wrapper [list unameit_edit_text_callback $attr_p]]]
    unameit_add_wrapper_binding $edit_button
    upvar #0 $edit_button edit_button_s
    set edit_button_s(attr_state^) $attr_p
    pack $edit_button -in $bottom_frame -side left

    if {[cequal $mode item]} {
	set state normal
    } else {
	set state disabled
    }
    set revert_button [button $attr_p.revert^ -text Revert -state $state\
	    -command [list unameit_wrapper [list\
	    unameit_revert_field_callback $attr_p]]]
    unameit_add_wrapper_binding $revert_button
    upvar #0 $revert_button revert_button_s
    set revert_button_s(attr_state^) $attr_p
    pack $revert_button -in $bottom_frame -side right

    ## Set a ButtonPress-1 binding to change focus to this text box if Edit
    ## or Revert are hit.
    foreach widget [list $edit_button $revert_button] {
	bind $widget <ButtonPress-1> [list unameit_wrapper [format {
	    unameit_apply_focus_field_if_different_attr %s
	    unameit_switch_focus %s
	} [list $attr_p] [list $top_frame.text]]]
    }

    return $frame
}

proc unameit_add_text_field {attr_p} {
    unameit_add_text_list_field $attr_p
}

proc unameit_add_radio_box_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set attr_s(value^) ""

    set frame [frame $attr_p.frame^ -relief groove -bd .02i]
    unameit_add_wrapper_binding $frame
    upvar #0 $frame frame_s
    set frame_s(attr_state^) $attr_p

    set enums [unameit_get_enumeration_values $class $attr]

    set x 0; set y 0
    foreach enum $enums {
	set wname [s2w $enum]
	set radiobutton\
	    [radiobutton $attr_p.$wname\
		-text $enum -variable ${attr_p}(value^) -value $enum]
	unameit_add_wrapper_binding $radiobutton
	upvar #0 $radiobutton radiobutton_s
	set radiobutton_s(attr_state^) $attr_p
	set radiobutton_s(name^) $enum

	grid $radiobutton -column $x -row $y -sticky we -padx 2m -in $frame
	if {$y == 0} {
	    grid columnconfigure $frame $x -weight 1
	}
	if {[incr x] >= 3} {set x 0; incr y}
    }

    return $frame
}

proc unameit_add_check_box_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set frame [frame $attr_p.frame^ -relief groove -bd .02i]
    unameit_add_wrapper_binding $frame
    upvar #0 $frame frame_s
    set frame_s(attr_state^) $attr_p

    set enums [unameit_get_enumeration_values $class $attr]

    set x 0; set y 0
    foreach enum $enums {
	set wname [s2w $enum]
	set checkbutton\
	    [checkbutton $attr_p.$wname\
		-text $enum -variable ${attr_p}(include^$enum)]
	unameit_add_wrapper_binding $checkbutton
	upvar #0 $checkbutton checkbutton_s
	set checkbutton_s(attr_state^) $attr_p
	set checkbutton_s(name^) $enum

	grid $checkbutton -column $x -row $y -sticky we -padx 2m -in $frame
	if {$y == 0} {
	    grid columnconfigure $frame $x -weight 1
	}
	if {[incr x] >= 3} {set x 0; incr y}
    }

    return $frame
}

proc unameit_add_choice_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set attr_s(value^) ""

    set frame [frame $attr_p.frame^ -relief groove -bd .02i]
    unameit_add_wrapper_binding $frame
    upvar #0 $frame frame_s
    set frame_s(attr_state^) $attr_p

    set enums [unameit_get_enumeration_values $class $attr]

    ## Create radio box
    set x 0; set y 0
    foreach enum [concat $enums Other] {
	set wname [s2w $enum]
	set radiobutton\
	    [radiobutton $attr_p.$wname\
		-text $enum -variable ${attr_p}(value^) -value $enum]
	unameit_add_wrapper_binding $radiobutton
	upvar #0 $radiobutton radiobutton_s
	set radiobutton_s(attr_state^) $attr_p
	set radiobutton_s(name^) $enum

	grid $radiobutton -column $x -row $y -sticky we -padx 2m -in $frame
	if {$y == 0} {
	    grid columnconfigure $frame $x -weight 1
	}
	if {[incr x] >= 3} {set x 0; incr y}
    }

    ## Create entry field
    if {0 < $y} {
	set columns 3
    } else {
	set columns $x
    }
    if {$x == 0} {
	set row $y
    } else {
	set row [expr $y+1]
    }
    # The entry widget cannot take the focus. It is OK to leave it enabled
    # though. If the user clicks on it, Other is automatically selected.
    set entry [entry $attr_p.entry^ -width 32 -textvariable\
	    ${attr_p}(entry^) -takefocus 0]
    unameit_add_wrapper_binding $entry
    upvar #0 $entry entry_s
    set entry_s(attr_state^) $attr_p
    set entry_s(name^) Other

    grid configure $entry -sticky we -column 0 -row $row -columnspan $columns\
	    -in $frame

    return $frame
}

proc unameit_add_list_box_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    
    set mode $toplevel_s(mode^)

    set attr_s(fence^) 0

    set frame [frame $attr_p.frame^ -bd .02i -relief groove]
    unameit_add_wrapper_binding $frame
    upvar #0 $frame frame_s
    set frame_s(attr_state^) $attr_p

    set top_frame [unameit_create_scrollable $attr_p top^ listbox y 1 $attr_p\
	    -width 20 -height 3 -selectmode extended]
    pack $top_frame -in $frame -side top -fill both -expand 1

    set menubutton [unameit_add_menu_field $attr_p]
    pack $menubutton -in $frame -side bottom -fill x -padx 1m -pady 1m
    
    ## Add binding to show the item in the entry field at the selection.
    bind $top_frame.listbox <1>\
	    [list unameit_wrapper [list unameit_set_list_box_menubutton\
	    $attr_p]]

    ## Update selection first because we inspect it.
    bindtags $top_frame.listbox [list Wrapper $toplevel_p Listbox\
	    $top_frame.listbox all]

    return $frame
}

####		Routines to clear the widgets on the screen

proc unameit_clear_entry_field {attr_p} {
    upvar #0 $attr_p attr_s

    set attr_s(value^) ""
}

proc unameit_clear_menu_field {attr_p} {
    upvar #0 $attr_p attr_s

    set attr_s(pointers^) ""
    $attr_p.menubutton^ configure -text ""
}
    
proc unameit_clear_text_list_field {attr_p} {
    $attr_p.top^.text configure -state normal
    $attr_p.top^.text delete 0.0 end
    $attr_p.top^.text configure -state disabled
}

proc unameit_clear_text_field {attr_p} {
    unameit_clear_text_list_field $attr_p
}

proc unameit_clear_radio_box_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set attr_s(value^)\
	    [lindex [unameit_get_enumeration_values $class $attr] 0]
}

proc unameit_clear_check_box_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    foreach enum [unameit_get_enumeration_values $class $attr] {
	set attr_s(include^$enum) 0
    }
}

proc unameit_clear_choice_field {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set attr_s(value^)\
	    [lindex [unameit_get_enumeration_values $class $attr] 0]
    set attr_s(entry^) ""
}

proc unameit_clear_list_box_field {attr_p} {
    upvar #0 $attr_p attr_s

    set attr_s(pointers^) {}
    $attr_p.top^.listbox delete 0 end
    $attr_p.menubutton^ configure -text ""
}

####		Routines to retrieve the value of each widget
####		(the empty string is returned if no value)

proc unameit_get_widget_value {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set widget_type [unameit_get_widget_type $class $attr]

    return [unameit_get_${widget_type}_value $attr_p]
}

proc unameit_set_widget_value {attr_p value {run_canonicalization 1}} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set widget_type [unameit_get_widget_type $class $attr]

    if {$run_canonicalization} {
	if {[cequal [set mode $toplevel_s(mode^)] item] &&
	[info exists class_s(uuids^)]} {
	    set uuid [lindex $class_s(uuids^) 0]
	} else {
	    set uuid $class
	}

	set syntax [unameit_get_attribute_syntax $class $attr]
	if {[cequal $mode item] && [cequal $syntax address]} {
	    if {[cequal $attr_s(address_state^) Normal]} {
		set canon_style display
	    } else {
		set canon_style db
	    }
	} else {
	    set canon_style [unameit_get_canon_style $attr_p]
	}
	set display_value $value
	## Canonicalization may fail if we are trying to display an existing
	## value in the database that doesn't even pass the display
	## validation function! This is legal, but rare.
	if {![catch {
	    unameit_check_syntax $class $attr $uuid $value $canon_style
	} temp]} {
	    set display_value $temp
	}
	unameit_set_${widget_type}_value $attr_p $display_value
    } else {
	unameit_set_${widget_type}_value $attr_p $value
    }
}

proc unameit_get_entry_value {attr_p} {
    upvar #0 $attr_p attr_s

    return $attr_s(value^)
}

proc unameit_set_entry_value {attr_p value} {
    upvar #0 $attr_p attr_s

    set attr_s(value^) $value
}

proc unameit_get_menu_value {attr_p} {
    upvar #0 $attr_p attr_s

    return $attr_s(pointers^)
}

proc unameit_set_menu_value {attr_p value} {
    upvar #0 $attr_p attr_s

    set attr_s(pointers^) $value
    if {![empty $value]} {
	set value [unameit_get_label $value]
    }
    $attr_p.menubutton^ configure -text $value
}

proc unameit_get_text_list_value {attr_p} {
    unameit_text_widget_to_list $attr_p
}

proc unameit_set_text_list_value {attr_p value} {
    unameit_list_to_text_widget $attr_p $value
}

proc unameit_get_text_value {attr_p} {
    $attr_p.top^.text get 1.0 {end -1 chars}
}

proc unameit_set_text_value {attr_p value} {
    $attr_p.top^.text configure -state normal
    $attr_p.top^.text delete 1.0 end
    $attr_p.top^.text insert 1.0 $value
    $attr_p.top^.text configure -state disabled
}

proc unameit_get_radio_box_value {attr_p} {
    upvar #0 $attr_p attr_s

    return $attr_s(value^)
}

proc unameit_set_radio_box_value {attr_p value} {
    upvar #0 $attr_p attr_s

    set attr_s(value^) $value
}

proc unameit_get_check_box_value {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set list {}
    foreach enum [unameit_get_enumeration_values $class $attr] {
	if {$attr_s(include^$enum)} {
	    lappend list $enum
	}
    }
    lsort $list
}

proc unameit_set_check_box_value {attr_p value} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    foreach enum [unameit_get_enumeration_values $class $attr] {
	set attr_s(include^$enum) 0
    }
    foreach enum $value {
	set attr_s(include^$enum) 1
    }
}

proc unameit_get_choice_value {attr_p} {
    upvar #0 $attr_p attr_s

    if {[cequal $attr_s(value^) Other]} {
	return $attr_s(entry^)
    } else {
	return $attr_s(value^)
    }
}

proc unameit_set_choice_value {attr_p value} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set enums [unameit_get_enumeration_values $class $attr]

    if {[lsearch -exact $enums $value] == -1} {
	set attr_s(value^) Other
	set attr_s(entry^) $value
    } else {
	set attr_s(value^) $value
	set attr_s(entry^) ""
    }
}

proc unameit_get_list_box_value {attr_p} {
    upvar #0 $attr_p attr_s

    return $attr_s(pointers^)
}

proc unameit_set_list_box_value {attr_p value} {
    upvar #0 $attr_p attr_s
    set attr $attr_s(attr^)

    set multiplicity [unameit_get_attribute_multiplicity $attr]

    if {[cequal $multiplicity Scalar] || [cequal $multiplicity Sequence]} {
	# Scalar and sequence values must use the exact order
	set attr_s(pointers^) $value
    } else {
	# but sets can be sorted.
	set value [unameit_sort_uuids $value]
	set attr_s(pointers^) $value
    }
    $attr_p.menubutton^ configure -text ""
    $attr_p.top^.listbox delete 0 end
    foreach uuid $value {
	$attr_p.top^.listbox insert end [unameit_get_label $uuid]
    }
}

####		Routines to enable and disable widget class bindings

proc unameit_disable_class_bindings {widget} {
    bindtags $widget [list Wrapper [winfo toplevel $widget] $widget all]
}

proc unameit_enable_class_bindings {widget class_type} {
    bindtags $widget [list Wrapper [winfo toplevel $widget]\
	    $widget $class_type all]
}

proc unameit_disable_entry_class_bindings {attr_p} {
    unameit_disable_class_bindings $attr_p.entry^
    $attr_p.entry^ configure -insertontime 0
}

proc unameit_enable_entry_class_bindings {attr_p} {
    unameit_enable_class_bindings $attr_p.entry^ Entry
    $attr_p.entry^ configure -insertontime 600
}

proc unameit_disable_menu_class_bindings {attr_p} {
    unameit_disable_class_bindings $attr_p.menubutton^
}

proc unameit_enable_menu_class_bindings {attr_p} {
    unameit_enable_class_bindings $attr_p.menubutton^ Menubutton
}

proc unameit_disable_list_box_class_bindings {attr_p} {
    unameit_disable_menu_class_bindings $attr_p
}

proc unameit_enable_list_box_class_bindings {attr_p} {
    unameit_enable_menu_class_bindings $attr_p
}

proc unameit_disable_text_list_class_bindings {attr_p} {
    unameit_disable_class_bindings $attr_p.edit^ Button
    unameit_disable_class_bindings $attr_p.revert^ Button
}

proc unameit_enable_text_list_class_bindings {attr_p} {
    unameit_enable_class_bindings $attr_p.edit^ Button
    unameit_enable_class_bindings $attr_p.revert^ Button
}

proc unameit_disable_text_class_bindings {attr_p} {
    unameit_disable_text_list_class_bindings $attr_p
}

proc unameit_enable_text_class_bindings {attr_p} {
    unameit_enable_text_list_class_bindings $attr_p
}

proc unameit_disable_radio_box_class_bindings {attr_p} {
    unameit_iterate_over_enums $attr_p {
	bindtags $widget [list Wrapper [winfo toplevel $widget] all]
    }
}

proc unameit_enable_radio_box_class_bindings {attr_p} {
    unameit_iterate_over_enums $attr_p {
	unameit_enable_class_bindings $widget Radiobutton
    }
}

proc unameit_disable_check_box_class_bindings {attr_p} {
    unameit_iterate_over_enums $attr_p {
	bindtags $widget [list Wrapper [winfo toplevel $widget] all]
    }
}

proc unameit_enable_check_box_class_bindings {attr_p} {
    unameit_iterate_over_enums $attr_p {
	unameit_enable_class_bindings $widget Checkbutton
    }
}

proc unameit_disable_choice_class_bindings {attr_p} {
    unameit_disable_radio_box_class_bindings $attr_p

    set widget $attr_p.[s2w Other]
    unameit_disable_class_bindings $widget
    bindtags $widget [list Wrapper [winfo toplevel $widget] all]

    bindtags $attr_p.entry^ [list Wrapper [winfo toplevel $attr_p.entry^] all]
}

proc unameit_enable_choice_class_bindings {attr_p} {
    unameit_enable_radio_box_class_bindings $attr_p

    set widget $attr_p.[s2w Other]
    unameit_enable_class_bindings $widget Radiobutton

    unameit_enable_class_bindings $attr_p.entry^ Entry
}

####		Routines to enable and disable each type of widget

proc unameit_enable_entry_widget {attr_p} {
    $attr_p.entry^ configure -state normal
}

proc unameit_disable_entry_widget {attr_p} {
    $attr_p.entry^ configure -state disabled
}

proc unameit_enable_menu_widget {attr_p} {
    $attr_p.menubutton^ configure -state normal
}

proc unameit_disable_menu_widget {attr_p} {
    $attr_p.menubutton^ configure -state disabled
}

proc unameit_enable_text_list_widget {attr_p} {
    $attr_p.edit^ configure -state normal
}

proc unameit_disable_text_list_widget {attr_p} {
    $attr_p.edit^ configure -state disabled
}

proc unameit_enable_text_widget {attr_p} {
    unameit_enable_text_list_widget $attr_p
}

proc unameit_disable_text_widget {attr_p} {
    unameit_disable_text_list_widget $attr_p
}

proc unameit_enable_list_box_widget {attr_p} {
    unameit_enable_menu_widget $attr_p
}

proc unameit_disable_list_box_widget {attr_p} {
    unameit_disable_menu_widget $attr_p
}

proc unameit_enable_radio_box_widget {attr_p} {
    unameit_iterate_over_enums $attr_p {
	$widget configure -state normal
    }
}

proc unameit_disable_radio_box_widget {attr_p} {
    unameit_iterate_over_enums $attr_p {
	$widget configure -state disabled
    }
}

proc unameit_enable_check_box_widget {attr_p} {
    unameit_iterate_over_enums $attr_p {
	$widget configure -state normal
    }
}

proc unameit_disable_check_box_widget {attr_p} {
    unameit_iterate_over_enums $attr_p {
	$widget configure -state disabled
    }
}

proc unameit_enable_choice_widget {attr_p} {
    unameit_iterate_over_enums attr_p {
	$widget configure -state normal
    }
    set widget $attr_p.[s2w Other]
    $widget configure -state normal
    $attr_p.entry^ configure -state normal
}

proc unameit_disable_choice_widget {attr_p} {
    unameit_iterate_over_enums $attr_p {
	$widget configure -state disabled
    }
    set widget $attr_p.[s2w Other]
    $widget configure -state disabled
    $attr_p.entry^ configure -state disabled
}

####		Routines to set the bindings for each type of widget
####		so the canonicalization and apply functions are run

proc unameit_set_bindings {attr_p widget_type} {
    upvar #0 $attr_p attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    ## Set up Tab and Shift-Tab bindings
    foreach key {Tab Shift-Tab} {
	unameit_set_bindings_$widget_type $attr_p $key
    }

    set mode $toplevel_s(mode^)

    ## Don't set up Button-1 bindings or revert bindings for protected
    ## or computed attributes in item mode.
    if {[cequal $mode item] && ([unameit_isa_protected_attribute $attr] ||
    [unameit_isa_computed_attribute $class $attr])} {
	return
    }

    switch $widget_type {
	choice -
	check_box -
	radio_box {
	    unameit_iterate_over_enums $attr_p {
		bind $widget <Button-1>\
			[list unameit_wrapper [list unameit_button1_on_field\
			$widget]]
	    }
	    if {[cequal $widget_type choice]} {
		## Set up binding for Other radiobutton and entry widget
		set other_label [s2w Other]
		bind $attr_p.$other_label <Button-1>\
			[list unameit_wrapper [list unameit_button1_on_field\
			$attr_p.$other_label]]
		bind $attr_p.entry^ <Button-1>\
			[list unameit_wrapper [list unameit_button1_on_field\
			$attr_p.$other_label]]
	    }
	}
	default {
	    set main_widget [unameit_get_main_${widget_type}_widget\
		    $attr_p]
	    bind $main_widget <Button-1> [list unameit_wrapper\
		    [list unameit_button1_on_field $main_widget]]
        }
    }
}

proc unameit_set_bindings_entry {attr_p key} {
    bind $attr_p.entry^ <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.entry^]]
}

proc unameit_set_bindings_menu {attr_p key} {
    bind $attr_p.menubutton^ <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.menubutton^]]

    bind $attr_p.entry^ <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.entry^]]
}

proc unameit_set_bindings_text_list {attr_p key} {
    ## Make Control-Tab the same as Tab in text widgets. Don't use Alt-Tab.
    ## CDE doesn't like when you rebind the Alt keys.
    if {[cequal $key Tab]} {
	bind $attr_p.top^.text <Control-Tab> [bind Text <Tab>]
    }

    bind $attr_p.top^.text <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.top^.text]]

    ## Don't process Tab class binding if we are setting tab key. We do
    ## need to process the "all" binding though since this takes us to the
    ## next widget.
    if {[cequal $key Tab]} {
	bind $attr_p.top^.text <$key> +[format {
	    %s
	    break
	} [bind all <Tab>]]
    }
}

proc unameit_set_bindings_text {attr_p key} {
    unameit_set_bindings_text_list $attr_p $key
}

proc unameit_set_bindings_radio_box {attr_p key} {
    unameit_iterate_over_enums $attr_p [list\
	    bind {$widget} <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply {$widget}]]]
}

proc unameit_set_bindings_check_box {attr_p key} {
    unameit_iterate_over_enums $attr_p [list\
	    bind {$widget} <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply {$widget}]]]
}

proc unameit_set_bindings_choice {attr_p key} {
    unameit_iterate_over_enums $attr_p [list\
	    bind {$widget} <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply {$widget}]]]

    set wname [s2w Other]
    bind $attr_p.$wname <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.$wname]]

    bind $attr_p.entry^ <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.entry^]]
}

# Automatic apply for listboxes is much like menus but we don't want tab
# to go to the next field if enabled.
proc unameit_set_bindings_list_box {attr_p key} {
    bind $attr_p.menubutton^ <$key> [list unameit_wrapper\
	    [list unameit_automatic_apply $attr_p.menubutton^]]

    bind $attr_p.entry^ <$key> [list unameit_wrapper [format {
	unameit_automatic_apply %s
	break
    } [list $attr_p.entry^]]]
}

### This function is the automatic apply function that is always called.
### It simply determines whether the widget is a pointer or not and calls
### lower level apply functions. Do not call the lower level apply functions
### directly.
proc unameit_automatic_apply {widget {display_dialog_box 0}} {
    upvar #0 $widget widget_s
    upvar #0 [set attr_p $widget_s(attr_state^)] attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    ## Run pointer or non-pointer automatic apply.
    if {[cequal [unameit_get_attribute_syntax $class $attr] pointer]} {
	unameit_automatic_apply_pointer $attr_p
    } else {
	unameit_automatic_apply_nonpointer $attr_p $display_dialog_box
    }
}

### This function does an automatic apply on a pointer field. It returns a
### boolean value on whether you should go to the next field or not.
proc unameit_automatic_apply_pointer {attr_p} {
    upvar #0 $attr_p attr_s
    set attr $attr_s(attr^)
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)

    set mode $toplevel_s(mode^)

    ## If pointer is disabled, return. Disabled fields have nothing to apply.
    if {[unameit_pointer_is_disabled $attr_p]} {
	return
    }

    ## The user hit spacebar and then decided not to query after all.
    if {[empty [set query_text [$attr_p.entry^ get]]]} {
	unameit_redisplay_pointer $attr_p
	error {} {} {UNAMEIT EIGNORE}
    }

    ## Run query
    set uuids_found [unameit_query_for_uuids $class $attr $query_text]

    switch [llength $uuids_found] {
	0 {
	    error "No matches" "" {UNAMEIT ELITERALERROR}
	}
	1 {
	    unameit_iterate_over_uuids $attr_p [lindex $uuids_found 0]\
		    append
	    unameit_set_completion_value $uuids_found
	}
	default {
	    if {[unameit_select_uuids_from_list $attr_p $uuids_found\
		    uuids_selected] == 0} {
		unameit_set_pointer_from_uuids $attr_p $uuids_selected
		unameit_set_completion_value $uuids_selected
	    } else {
		unameit_redisplay_pointer $attr_p
	    }
	}
    }
}

proc unameit_automatic_apply_nonpointer {attr_p {display_dialog_box 0}} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set mode $toplevel_s(mode^)

    set widget_value [unameit_get_widget_value $attr_p]

    if {[cequal $mode item] && [info exists class_s(uuids^)]} {
	set first_uuid [lindex $class_s(uuids^) 0]

	## Get old value with db canonicalization.
	array set temp [unameit_get_attribute_values $first_uuid new $attr]
	set old_value $temp($attr)

	## Get new value with db canonicalization (if possible).
	set new_value $widget_value
	if {![catch {
		    unameit_check_syntax $class $attr $first_uuid\
			    $widget_value db
		} t]} {
	    set new_value $t
	}

	## Compare values for equality. If equal, do nothing. We have to
	## compare if the old and new values are equal because values
	## that don't pass canonicalization are legal in the database.
	## You just can't enter them through the TOI.
	if {![cequal $old_value $new_value]} {
	    set display_attr [unameit_display_attr $class $attr]

	    if {!$display_dialog_box || ($display_dialog_box &&
	    [tk_dialog .apply_attr "Apply $display_attr" "$display_attr\
		    has been modified. Keep changes to $display_attr?"\
		    warning 0 Yes No] == 0)} {
		foreach uuid $class_s(uuids^) {
		    # unameit_update may raise an exception.
		    unameit_update $uuid $attr $new_value
		}
		unameit_refresh_preview_window
		unameit_set_object_description $toplevel_p $first_uuid
		unameit_update_ws_labels $toplevel_p $class_s(uuids^)
	    }
	}
    } else {
	if {[cequal $mode item]} {
	    set canon_style db
	    if {[empty $widget_value]} return
	} else {
	    set canon_style query
	}
	set new_value [unameit_check_syntax $class $attr $class\
		$widget_value $canon_style]
    }

    ## Always redisplay the value. The reason is that the user
    ## may have changed the value to the "db" canonicalization
    ## format which is different than the "display" format.
    ## If the user did this and the value didn't change, we want
    ## to redraw with the display format.
    ##     If there isn't an item, then unameit_set_widget_value
    ## runs the canonicalization function.
    unameit_set_widget_value $attr_p $new_value

    return
}

#### Returns the "main" widget associated with a field. The "main" widget is
#### the widget we need to disable if the field is read-only or for bindings.

proc unameit_get_main_entry_widget {attr_p} {
    return [list $attr_p.entry^]
}

proc unameit_get_main_menu_widget {attr_p} {
    return [list $attr_p.menubutton^]
}

proc unameit_get_main_text_list_widget {attr_p} {
    return [list $attr_p.top^.text]
}

proc unameit_get_main_text_widget {attr_p} {
    unameit_get_main_text_list_widget $attr_p
}

proc unameit_get_main_list_box_widget {attr_p} {
    unameit_get_main_menu_widget $attr_p
}

proc unameit_get_main_radio_box_widget {attr_p} {
    global unameitPriv

    set list {}
    unameit_iterate_over_enums $attr_p {
	upvar list list
	lappend list $widget
    }
    return $list
}

proc unameit_get_main_check_box_widget {attr_p} {
    global unameitPriv

    set list {}
    unameit_iterate_over_enums $attr_p {
	upvar list list
	lappend list $widget
    }
    return $list
}

proc unameit_get_main_choice_widget {attr_p} {
    global unameitPriv

    set list {}
    unameit_iterate_over_enums $attr_p {
	upvar list list
	lappend list $widget
    }
    lappend temp $attr_p.[s2w Other] $attr_p.entry^
    return $temp
}

####		Special routines needed by pointers

proc unameit_set_pointer_value_from_listbox {attr_p uuids} {
    upvar #0 $attr_p attr_s
    
    set button [unameit_popup_object_selection_dialog $attr_p "Pick an item"\
	    $uuids single select_list]
    if {$button == 1 || [llength $select_list] == 0} return

    unameit_iterate_over_uuids $attr_p $select_list append
}

### Code to set up Traverse in attribute menus.
proc unameit_change_traverse {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)
   
    ## Get domain of attribute we are sitting on.
    set domain [unameit_get_attribute_domain $class $attr]

    ## Change Traverse to cascading menu if the  field for the item we are 
    ## on is null and there are more than concrete subclasses of the domain.
    set menu $attr_s(menu^)
    set index $attr_s(traverse_loc^)
    set state [$menu entrycget $index -state]

    if {[empty [$attr_p.menubutton^ cget -text]]} {
	set class_list {}
	foreach subclass [lsort [concat $domain\
		[unameit_get_subclasses $domain]]] {
	    if {[unameit_is_readonly $subclass]} continue
	    lappend class_list $subclass
	}
	set class_list [lsort $class_list]
    } else {
	set class_list $domain
    }

    switch -- [llength $class_list] {
	0 {
	    $menu entryconf $index -state disabled
	}
	1 {
	    if {![cequal [$menu type $index] command]} {
		$menu delete $index
		$menu insert $index command
	    }
	    $menu entryconf $index\
		-label Traverse\
		-state $state\
		-command [list unameit_wrapper\
			    "[list unameit_traverse $attr_p] $class_list"]
	}
	default {
	    if {![cequal [$menu type $index] cascade]} {
		$menu delete $index
		$menu insert $index cascade\
		    -label Traverse\
		    -state $state\
		    -menu $menu.traverse_classes^
	    }
	    if {![winfo exists $menu.traverse_classes^]} {
		menu $menu.traverse_classes^
	    } else {
		$menu.traverse_classes^ delete 0 end
	    }
	    foreach c $class_list {
		$menu.traverse_classes^ add command\
		    -label [unameit_display_item $c]\
		    -command [list unameit_wrapper\
				[list unameit_traverse $attr_p $c]]
	    }
	}
    }
}

proc unameit_add_query_menu {attr_p indexVar state} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    upvar 1 $indexVar index

    set class $class_s(class^)
    set attr $attr_s(attr^)
    set menu $attr_s(menu^)
   
    set domain [unameit_get_attribute_domain $class $attr]

    set class_list {}
    foreach c [lsort [concat $domain [unameit_get_subclasses $domain]]] {
	if {![unameit_is_readonly $c]} {
	    lappend class_list $c
	}
    }

    switch -- [llength $class_list] {
	0 {
	    $menu insert $index command -label {Full Query}\
	        -state disabled\
		-command ""
	}
	1 {
	    $menu insert $index command -label {Full Query}\
		-state $state\
		-command [list unameit_wrapper\
		    "[list unameit_full_query $attr_p] $class_list"]
	}
	default {
	    $menu insert $index cascade -label {Full Query}\
		-state $state\
		-menu $menu.query_classes^
	    #
	    menu $menu.query_classes^
	    #
	    $menu.query_classes^ add command -label All\
		-command [list unameit_wrapper\
		    [list unameit_full_query $attr_p ""]]
	    #
	    foreach menu_class $class_list {
		$menu.query_classes^ add command\
		    -label [unameit_display_item $menu_class]\
		    -command [list unameit_wrapper\
			[list unameit_full_query $attr_p $menu_class]]
	    }
	}
    }
    incr index
}

proc unameit_add_other_objs {attr_p} {
    global UNAMEIT_TOPLEVELS unameitPriv

    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set menu $attr_s(menu^)
    set mode $toplevel_s(mode^)

    ## Get domain of attribute we are sitting on.
    set domain [unameit_get_attribute_domain $class $attr]

    # The following "if" is because of a bug in Tk.
    if {[$menu index end]  >= $attr_s(fence^)} {
	## Trash old entries past the fence.
	$menu delete $attr_s(fence^) end
    }

    ## Get list of all modified objects.
    foreach uuid [unameit_build_uuid_list_from_domain $domain 1 1] {
	if {[cequal $mode item]} {
	    if {![unameit_item_is $uuid deleted]} {
		set uuid_list($uuid) 1
	    }
	} else {
	    if {![unameit_item_is $uuid created]} {
		set uuid_list($uuid) 1
	    }
	}
    }

    ## Compute subclass list for domain. Do this before we access the
    ## array UNAMEIT_TOPLEVELS because computing this list may have to
    ## go to the server. In the time taken going to the server, the user
    ## can possibly create or delete new toplevels.
    set subclass_list [eval list {$domain} [unameit_get_subclasses\
		$domain]]

    ## Add objects selected in each class in each toplevel.
    foreach tlevel_p [array names UNAMEIT_TOPLEVELS] {
	upvar #0 $tlevel_p tlevel_s

	if {![cequal $tlevel_s(mode^) item]} continue

	## Get list of all items currently selected in the subclasses.
	foreach subclass $subclass_list {

	    if {![info exists tlevel_s($subclass)]} {
		continue
	    }

	    upvar #0 $tlevel_s($subclass) tclass_s

	    if {[info exists tclass_s(uuids^)]} {
		foreach uuid $tclass_s(uuids^) {
		    if {[cequal $mode item]} {
			if {![unameit_item_is $uuid deleted]} {
			    set uuid_list($uuid) 1
			}
		    } else {
			if {![unameit_item_is $uuid created]} {
			    set uuid_list($uuid) 1
			}
		    }
		}
	    }
	}
    }

    ## Add Name Query and Full Query matches
    foreach subclass [eval list {$domain} [unameit_get_subclasses $domain]] {
	if {[info exists unameitPriv(complete^$subclass)]} {
	    set uuid $unameitPriv(complete^$subclass)
	    if {[cequal $mode item]} {
		if {![unameit_item_is $uuid deleted]} {
		    set uuid_list($uuid) 1
		}
	    } else {
		set uuid_list($uuid) 1
	    }
	}
    }

    set uuids [array names uuid_list]

    if {[llength $uuids] > 10} {
	$menu add command -label More... -command\
		[list unameit_wrapper\
		[list unameit_set_pointer_value_from_listbox $attr_p $uuids]]
    } else {
	if {[llength $uuids] > 0} {
	    $menu add separator
	}

	set bgcolor [$menu cget -background]

	## Sort list and add all the entries.
	foreach menu_uuid [unameit_sort_uuids $uuids] {
	    set label [unameit_get_label $menu_uuid]

	    if {[unameit_item_is $menu_uuid created]} {
		set color $unameitPriv(create_color)
	    } elseif {[unameit_item_is $menu_uuid updated]} {
		set color $unameitPriv(update_color)
	    } else {
		set color black
	    }
	    $menu add command -label $label -command\
		    [list unameit_wrapper\
		    [list unameit_iterate_over_uuids $attr_p\
		    $menu_uuid append]] -foreground $color \
		    -activeforeground $color -activebackground $bgcolor
	}
    }
}

### This routine appends any modified objects and the object currently
### selected for any subclass to the popup menu. It also changes the Traverse
### menu item into a cascading menu if we are in an abstract class and
### we are not on an item.
proc unameit_modify_popup_menu {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    unameit_change_traverse $attr_p

    set mode $toplevel_s(mode^)
    set menu $attr_s(menu^)

    ## Don't do the following if we are on a readonly class or if the attribute
    ## is protected or computed, unless we are in query mode.
    if {[cequal $mode item] && ([unameit_is_readonly $class] ||
    [unameit_is_prot_or_comp $class $attr])} {
	return
    }

    unameit_add_other_objs $attr_p
}

proc unameit_iterate_over_uuids {attr_p values insert_type} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set attr $attr_s(attr^)
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)

    set multiplicity [unameit_get_attribute_multiplicity $attr]
    set mode $toplevel_s(mode^)

    if {[cequal $mode query]} {
	unameit_set_displayed_pointer_value $attr_p\
		[unameit_set_pointer_value $class $attr_p $values $insert_type]
    } else {
	if {![info exists class_s(uuids^)]} {
	    set new_values [unameit_set_pointer_value $class $attr_p $values\
		    $insert_type]
	} else {
	    set i 0
	    foreach uuid $class_s(uuids^) {
		if {$i == 0} {
		    set new_values [unameit_set_pointer_value $uuid $attr_p\
			    $values $insert_type]
		} else {
		    unameit_set_pointer_value $uuid $attr_p $values\
			    $insert_type
		}
		incr i
	    }
	}
	unameit_set_displayed_pointer_value $attr_p $new_values
	if {[info exists class_s(uuids^)]} {
	    unameit_update_ws_labels $toplevel_p $class_s(uuids^)
	    unameit_refresh_preview_window
	}
    }
}

## uuid can be a class in the case of query mode.
proc unameit_set_pointer_value {uuid attr_p values insert_type} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set attr $attr_s(attr^)
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)

    set multiplicity [unameit_get_attribute_multiplicity $attr]
    set mode $toplevel_s(mode^)

    set new_value $values

    if {![cequal $multiplicity Scalar]} {
	switch $insert_type {
	    append {
		if {![cequal $mode query] && [info exists class_s(uuids^)]} {
		    array set tmp [unameit_get_attribute_values $uuid new\
			    $attr]
		    set old_value $tmp($attr)
		} else {
		    set old_value $attr_s(pointers^)
		}
		if {[cequal $multiplicity Set]} {
		    set new_value\
			[unameit_sort_uuids [union $old_value $values]]
		} else {
		    set selection [lindex [$attr_p.top^.listbox curselection]\
			    0]
		    set new_value $old_value
		    if {[empty $selection]} {
			set insert_loc [llength $new_value]
		    } else {
			if {$selection > [llength $new_value]} {
			    set insert_loc [llength $new_value]
			} else {
			    set insert_loc $selection
			}
		    }
		    lvarpush new_value $values $insert_loc
		    set new_value [eval concat $new_value]
		}
	    }
	    noappend {
		if {[cequal $multiplicity Set]} {
		    set new_value [unameit_sort_uuids $new_value]
		}
	    }
	    delete {
		if {![cequal $mode query] && [info exists class_s(uuids^)]} {
		    array set tmp [unameit_get_attribute_values $uuid new\
			    $attr]
		    set old_value $tmp($attr)
		} else {
		    set old_value $attr_s(pointers^)
		}
		if {[cequal $multiplicity Set]} {
		    foreach value $old_value {
			set var($value) 1
		    }
		    foreach value $values {
			catch {unset var($value)}
		    }
		    set new_value\
			[unameit_sort_uuids [array names var]]
		} else {
		    foreach value $values {
			set delete($value) 1
		    }
		    set new_value {}
		    foreach value $old_value {
			if {![info exists delete($value)]} {
			    lappend new_value $value
			}
		    }
		}
	    }
	}
    }

    if {[cequal $mode query]} {
	set canon_style query
    } else {
	set canon_style db
    }
    # This may raise an error if canonicalizing a scalar value to null
    # and nulls aren't allowed.
    unameit_check_syntax $class $attr $uuid $new_value $canon_style

    if {![cequal $mode query] && [info exists class_s(uuids^)]} {
	unameit_update $uuid $attr $new_value
    }

    return $new_value
}

proc unameit_set_displayed_pointer_value {attr_p values} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set attr $attr_s(attr^)
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)

    set multiplicity [unameit_get_attribute_multiplicity $attr]
    set mode $toplevel_s(mode^)

    ## Update value in lookaside array
    set attr_s(pointers^) $values

    ## if !scalar {
    ##    Clear selection in listbox
    ##    Update listbox contents
    ## }
    if {![cequal $multiplicity Scalar]} {
	unameit_set_list_box_value $attr_p $values
    }

    ## if not in query mode and we are on an object {
    ##     Update cache value
    ##     Refresh preview window
    ##	   Set object description
    ##	   Update ws label
    ## }
    if {![cequal $mode query] && [info exists class_s(uuids^)]} {
	unameit_set_object_description $toplevel_p [lindex $class_s(uuids^) 0]
    }

    # Redisplay pointer entry
    unameit_redisplay_pointer $attr_p
}

proc unameit_redisplay_pointer {attr_p} {
    upvar #0 $attr_p attr_s
    set attr $attr_s(attr^)

    set multiplicity [unameit_get_attribute_multiplicity $attr]

    ## Disable pointer entry.
    unameit_disable_pointer_entry $attr_p

    ## if scalar {
    ##     Redisplay entry
    ## } else {
    ##     show_item_at_anchor
    ## }
    if {[cequal $multiplicity Scalar]} {
	unameit_set_menu_value $attr_p $attr_s(pointers^)
    } else {
	unameit_show_item_at_anchor $attr_p
    }
}

proc unameit_set_pointer_from_uuids {attr_p uuid_list} {
    upvar #0 $attr_p attr_s
    set attr $attr_s(attr^)
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s

    set multiplicity [unameit_get_attribute_multiplicity $attr]
    set mode $toplevel_s(mode^)

    if {[llength $uuid_list] == 1} {
	unameit_iterate_over_uuids $attr_p $uuid_list append
    } else {
	if {[cequal $multiplicity Scalar]} {
	    if {![cequal $mode query] && [info exists class_s(uuids^)]} {
		foreach u $uuid_list {
		    unameit_clone $toplevel_p [list $attr_p $u]
		}
		unameit_redisplay_pointer $attr_p
		unameit_fill_in_ws_window $toplevel_p
		unameit_refresh_preview_window
	    } else {
		unameit_disable_pointer_entry $attr_p
	    }
	} else {
	    unameit_iterate_over_uuids $attr_p $uuid_list append
	}
    }
}

proc unameit_show_item_at_anchor {attr_p} {
    upvar #0 $attr_p attr_s

    ## if selection {
    ##     Display item at selection
    ## } else {
    ##     Clear entry
    ## }
    set selection [lindex [$attr_p.top^.listbox curselection] 0]

    if {![empty $selection]} {
	set text [unameit_get_label [lindex $attr_s(pointers^) $selection]]
    } else {
	set text ""
    }

    $attr_p.menubutton^ configure -text $text
}

proc unameit_disable_pointer_entry {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    pack forget $attr_p.entry^

    set widget_type [unameit_get_widget_type $class $attr]
    if {[cequal $widget_type menu]} {
	pack $attr_p.menubutton^ -side right -padx 1m -pady 1m -expand 1\
		-fill both
    } else {
	pack $attr_p.menubutton^ -side bottom -padx 1m -pady 1m -expand 1\
		-fill both -in $attr_p.frame^
    }

    focus $attr_p.menubutton^

    ## Fill in menu text.
    if {[cequal [unameit_get_attribute_multiplicity $attr] Scalar]} {
	unameit_set_menu_value $attr_p $attr_s(pointers^)
    } else {
	unameit_show_item_at_anchor $attr_p
    }
}

proc unameit_enable_pointer_entry {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    pack forget $attr_p.menubutton^

    set widget_type [unameit_get_widget_type $class $attr]
    if {[cequal $widget_type menu]} {
	pack $attr_p.entry^ -side right -padx 1m -pady 1m -expand 1 -fill both
    } else {
	pack $attr_p.entry^ -side bottom -padx 1m -pady 1m -expand 1\
		-fill both -in $attr_p.frame^
    }
    focus $attr_p.entry^
    $attr_p.entry^ delete 0 end
}

proc unameit_pointer_is_disabled {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set widget_type [unameit_get_widget_type $class $attr]

    if {[cequal $widget_type menu]} {
	set menubutton_parent $attr_p
    } else {
	set menubutton_parent $attr_p.frame^
    }
    if {[lsearch -exact [pack slaves $menubutton_parent]\
	    $attr_p.menubutton^] == -1} {
	return 0
    } else {
	return 1
    }
}

proc unameit_delete_pointers {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set attr $attr_s(attr^)

    set multiplicity [unameit_get_attribute_multiplicity $attr]

    if {[cequal $multiplicity Scalar]} {
	unameit_iterate_over_uuids $attr_p "" noappend
    } else {
	foreach index [$attr_p.top^.listbox curselection] {
	    set del_uuids([lindex $attr_s(pointers^) $index]) 1
	}
	unameit_iterate_over_uuids $attr_p [array names del_uuids] delete
    }
}

proc unameit_build_uuid_list_from_domain {class get_subclasses only_modified} {
    set cache_uuids [unameit_get_cache_uuids $only_modified]

    set list {}
    foreach uuid $cache_uuids {
	array set tmp [unameit_get_attribute_values $uuid new Class]
	if {$get_subclasses} {
	    if {[unameit_is_subclass $class $tmp(Class)]} {
		lappend list $uuid
	    }
	} else {
	    if {[cequal $class $tmp(Class)]} {
		lappend list $uuid
	    }
	}
    }

    return $list
}

proc unameit_select_uuids_from_list {attr_p uuid_list uuids_selected_var} {
    upvar #0 $attr_p attr_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set attr $attr_s(attr^)
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    upvar 1 $uuids_selected_var uuids_selected

    set mode $toplevel_s(mode^)
    set multiplicity [unameit_get_attribute_multiplicity $attr]

    ## Put up listbox
    if {[cequal $multiplicity Scalar]} {
	set selectmode single
	if {[cequal $mode item] && [info exists class_s(uuids^)]} {
	    set selectmode extended
	}
    } else {
	set selectmode extended
    }
    return [unameit_popup_object_selection_dialog\
	    $attr_p "Multiple matches. Please select which object(s) you\
	    want." $uuid_list $selectmode uuids_selected]
}

proc unameit_query_for_uuids {class attr value} {
    global unameitPriv
    ## Grab domain
    set domain [unameit_get_attribute_domain $class $attr]

    ## Set the automatic query array variable using the leftmost nonpointer
    ## name attribute.
    unameit_set_automatic_query_array q $domain $value ""

    ## Run query
    unameit_query [array get q] [list\
	    -timeOut $unameitPriv(queryTimeOut)\
	    -maxRows $unameitPriv(queryMaxRows)]
}

### This routine looks for the leftmost attribute in the name attribute tree
### that is not a pointer field. It then sets up the query array so
### that a query using this query array will try to match this field.
proc unameit_set_automatic_query_array {q_var class value prefix\
	{classes_seen ""}} {
    upvar 1 $q_var q

    set q(${prefix}All) 1
    set q(${prefix}Class) $class

    if {[lsearch -exact $classes_seen $class] != -1} {
	error "Leftmost non-pointer name attribute loop"
    }

    set attr [lindex [unameit_get_name_attributes $class] 0]
    if {[empty $attr]} {
	unameit_error ENONAMEATTRS $class
    }
    set syntax [unameit_get_attribute_syntax $class $attr]

    if {[cequal $syntax pointer]} {
	set domain [unameit_get_attribute_domain $class $attr]
	lappend classes_seen $class
	unameit_set_automatic_query_array q $domain $value $prefix$attr.\
		$classes_seen
    } else {
	switch $syntax {
	    string {
		if {![regexp {\*$} $value] && ![regexp {\?$} $value]} {
		    append value *
		}
	    }
	    default {}
	}
	set operator [unameit_get_operator $class $attr\
	  [set value [unameit_check_syntax $class $attr $class $value query]]]
	set q($prefix$attr) [list $operator $value]
    }
}

proc unameit_popup_object_selection_dialog {attr_p text uuids selectmode
uuids_selected_var} {
    upvar #0 $attr_p attr_s
    upvar 1 $uuids_selected_var uuids_selected

    set new_toplevel $attr_p.object_selection^

    set creation_code [format {
	## Add message
	set label [label %s.message^ -justify left -text %s]
	pack $label -side top
    
	## Add listbox
	set def_width 20
	set listbox [unameit_create_scrollable %s listbox^\
		fancylistbox y 0 "" -width $def_width -height 30 \
		-selectmode %s -takefocus 0]
	pack $listbox -side top -fill both -expand 1

	set sorted_uuids [unameit_sort_uuids %s]

	set i 0
	set width $def_width
	foreach uuid $sorted_uuids {
	    set label [unameit_get_label $uuid]
	    if {[clength $label] > $width} {
		set width [clength $label]
	    }
	    $listbox.fancylistbox insert end $label
	    unameit_set_listbox_item_state $listbox.fancylistbox $i $uuid
	    incr i
	}
	if {$width != $def_width} {
	    $listbox.fancylistbox configure -width $width
	}
	upvar #0 %s attr_s
	set attr_s(sorted_uuids^) $sorted_uuids
    } [list $new_toplevel] [list $text] [list $new_toplevel]\
	    [list $selectmode] [list $uuids] [list $attr_p]]

    set popdown_code [format {
	upvar #0 %s attr_s

	set attr_s(uuids_selected^) {}
	foreach index [%s.listbox^.fancylistbox curselection] {
	    lappend attr_s(uuids_selected^)\
		    [lindex $attr_s(sorted_uuids^) $index]
	}
    } [list $attr_p] [list $new_toplevel]]

    set button_hit [unameit_popup_modal_dialog $new_toplevel\
	    "Object Selection" Selection 0 {OK Cancel} $creation_code\
	    $popdown_code]

    if {$button_hit == 0} {
	set uuids_selected $attr_s(uuids_selected^)
    }

    unset attr_s(uuids_selected^)
    unset attr_s(sorted_uuids^)

    return $button_hit
}

####			Megawidget routines

proc unameit_create_button_bar {parent bar_name buttons side args} {
    set button_bar [frame $parent.$bar_name]
    unameit_add_wrapper_binding $button_bar

    foreach button_name $buttons {
	set button [eval {button\
		$button_bar.[s2w $button_name]\
		-text $button_name} $args]
	unameit_add_wrapper_binding $button
	pack $button -side $side
    }

    return $button_bar
}

### This routine creates a scrollable object and returns it with optional
### x and y scrollbars. "type" gives the type of object to create. "scrollbars"
### is a list of zero to 2 elements. If the list contains "x", an x scrollbar
### is created. If the list contains "y", a y scrollbar is created. "args"
### are passed to object created.
proc unameit_create_scrollable {widget frame_name type scrollbars\
	add_wrappers attr_p args} {
    ## Create frame we are going to return
    set frame [frame $widget.$frame_name]
    if {$add_wrappers} {
	unameit_add_wrapper_binding $frame
    }
    if {![empty $attr_p]} {
	upvar #0 $frame frame_s
	set frame_s(attr_state^) $attr_p
    }

    ## Create a forward reference to the object since the scrollbar and object
    ## creation commands are mutually referential.
    set obj_name $frame.$type

    ## See which scrollbars we need to create
    if {[lsearch -exact $scrollbars x] != -1} {
	set x_scroll 1
    } else {
	set x_scroll 0
    }
    if {[lsearch -exact $scrollbars y] != -1} {
	set y_scroll 1
    } else {
	set y_scroll 0
    }

    ## Create subframe if need be. We need to create this before the x
    ## scrollbar or it will be above the x scrollbar and obscure it!
    if {$x_scroll && $y_scroll} {
	set bottom_frame [frame $frame.bottom]
	if {$add_wrappers} {
	    unameit_add_wrapper_binding $bottom_frame
	}
	if {![empty $attr_p]} {
	    upvar #0 $bottom_frame bottom_frame_s
	    set bottom_frame_s(attr_state^) $attr_p
	}
    }

    ## Create x scrollbar if need be
    if {$x_scroll} {
	set x_scrollbar [scrollbar $frame.x_scrollbar -orient horizontal\
		-command [list $obj_name xview]]
	if {$add_wrappers} {
	    unameit_add_wrapper_binding $x_scrollbar
	}
	if {![empty $attr_p]} {
	    upvar #0 $x_scrollbar x_scrollbar_s
	    set x_scrollbar_s(attr_state^) $attr_p
	}
    }

    ## Create y scrollbar if need be
    if {$y_scroll} {
	set y_scrollbar [scrollbar $frame.y_scrollbar -orient vertical\
		-command [list $obj_name yview]]
	if {$add_wrappers} {
	    unameit_add_wrapper_binding $y_scrollbar
	}
	if {![empty $attr_p]} {
	    upvar #0 $y_scrollbar y_scrollbar_s
	    set y_scrollbar_s(attr_state^) $attr_p
	}
    }

    ## Create padding if need be. We have to know the size of the y scrollbar
    ## so we can't create it until here.
    set pad [unameit_widget_size $y_scrollbar -width]
    set padding_frame [frame $frame.padding -width $pad -height $pad]
    if {$add_wrappers} {
	unameit_add_wrapper_binding $padding_frame
    }
    if {![empty $attr_p]} {
	upvar #0 $padding_frame padding_frame_s
	set padding_frame_s(attr_state^) $attr_p
    }

    ## Create object
    set obj_cmd [list $type $obj_name]
    if {$x_scroll} {
	lappend obj_cmd -xscrollcommand [list $x_scrollbar set]
    }
    if {$y_scroll} {
	lappend obj_cmd -yscrollcommand [list $y_scrollbar set]
    }
    set obj [eval $obj_cmd $args]
    if {$add_wrappers} {
	unameit_add_wrapper_binding $obj
    }
    if {![empty $attr_p]} {
	upvar #0 $obj obj_s
	set obj_s(attr_state^) $attr_p
    }

    ## Pack everything
    if {$x_scroll && $y_scroll} {
	pack $bottom_frame -side bottom -fill x
	pack $padding_frame -in $bottom_frame -side left
	set x_scroll_frame $bottom_frame
    } else {
	set x_scroll_frame $frame
    }
    if {$x_scroll} {
	pack $x_scrollbar -in $x_scroll_frame -side bottom -fill x
    }
    if {$y_scroll} {
	pack $y_scrollbar -side left -fill y
    }
    pack $obj_name -side left -fill both -expand 1

    return $frame
}

### Dialog box routine that pops up a window and allows nothing to continue
### until that window is dismissed. Used by the error message routine. When
### we get an error, we don't know which toplevel caused the error so we
### don't allow any other windows to continue until the dialog is dismissed.
### Any widgets created during this dialog should not look at the mutex.
### If they did, you wouldn't be able to interact with the widgets!
proc unameit_popup_modal_dialog {w title iconname default button_list code
{before_return_code ""}} {
    global unameitPriv

    ## Create toplevel
    toplevel $w -class Dialog
    wm withdraw $w

    ## Set up w manager stuff
    wm title $w $title
    wm iconname $w $iconname
    wm protocol $w WM_DELETE_WINDOW { }

    ## Bring dialog to front on button press
    bind $w <ButtonPress> [list raise $w]

    ## Add buttons. These must be added before the code is executed because
    ## the code will likely be packed with "expand", and "expand" widgets
    ## should be packed after non-"expand" widgets or resizing doesn't work
    ## well (the buttons disappear).
    set buttons [frame $w.buttons^ -relief raised -bd .02i]

    set i 0
    foreach but $button_list {
	set button [button $buttons.button$i -text $but -command [format {
	    unameit_run_modal_popdown_code %s %s
	    set unameitPriv(button_%s) %s
	} [list $i] [list $before_return_code] [list $w] [list $i]]]
	if {$i == $default} {
	    set default_frame [frame $buttons.default_frame -relief sunken\
		    -bd .02i]
	    raise $button $default_frame
	    pack $default_frame -side left -expand 1 -padx 3m -pady 2m
	    pack $button -padx 2m -pady 2m -in $default_frame
	} else {
	    pack $button -side left -expand 1 -padx 3m -pady 2m
	}

	incr i
    }

    pack $buttons -side bottom -fill x

    ## Create <Return> binding if default.
    if {$default >= 0} {
	bind $w <Return> [format {
	    %s configure -state active -relief sunken
	    update idletasks
	    after 100
	    %s configure -state normal -relief raised
	    unameit_run_modal_popdown_code %s %s
	    set unameitPriv(button_%s) %s
	    break
	} [list $buttons.button$default] [list $buttons.button$default]\
		[list $default] [list $before_return_code] [list $w]\
		[list $default]]
    }
	    
    set oldFocus [focus -lastfor $w]
    ## If there is a default button, set the keyboard focus to it.
    if {[winfo exists $buttons.default_frame]} {
	focus $buttons.button$default
    } else {
	focus $buttons
    }

    eval $code

    ## Update all the geometry information so we know how big it wants to
    ## be, then center the window in the display and de-iconify it.

    update idletasks
    set x [expr [winfo screenwidth $w]/2 - [winfo reqwidth $w]/2 \
	    - [winfo vrootx [winfo parent $w]]]
    set y [expr [winfo screenheight $w]/2 - [winfo reqheight $w]/2 \
	    - [winfo vrooty [winfo parent $w]]]
    wm geom $w +$x+$y
    wm deiconify $w

    ## In case parent window is destroyed, destroy window.
    bind $w <Destroy> [format {set unameitPriv(button_%s) 1} [list $w]]

    set oldGrab [grab current $w]
    if {![empty $oldGrab]} {
	set grabStatus [grab status $oldGrab]
    }
    grab $w

    ## Wait for the user to respond, then restore the focus and
    ## return the index of the selected button.  Restore the focus
    ## before deleting the window, since otherwise the window manager
    ## may take the focus away so we can't redirect it.  Finally,
    ## restore any grab that was in effect.

    tkwait variable unameitPriv(button_[list $w])

    catch {focus $oldFocus}
    catch {
	bind $w <Destroy> {}
	destroy $w
    }
    if {![empty $oldGrab]} {
	if {[cequal $grabStatus global]} {
	    grab -global $oldGrab
	} else {
	    grab $oldGrab
	}
    }

    return $unameitPriv(button_[list $w])
}

proc unameit_run_modal_popdown_code {button_hit code} {
    eval $code
}

### Generic dialog box routine that disables the parent window but allows
### other toplevels to continue. Uses mutex and wrapper logic.
proc unameit_popup_nonmodal_dialog {popup dead_widget title iconname\
	default button_list code {before_return_code ""}\
	{after_focus_reset_code ""}} {
    global unameitPriv
    ## Create toplevel
    toplevel $popup -class Dialog
    unameit_add_wrapper_binding $popup
    wm withdraw $popup

    upvar #0 [set toplevel_p [winfo toplevel [winfo parent $popup]]] toplevel_s

    ## Set up window manager stuff
    wm title $popup "$unameitPriv(mode): $title"
    wm iconname $popup $iconname
    wm protocol $popup WM_DELETE_WINDOW { }
    wm transient $popup [winfo toplevel [winfo parent $popup]]

    ## Add buttons. These must be added before the code is executed because
    ## the code will likely be packed with "expand", and "expand" widgets
    ## should be packed after non-"expand" widgets or resizing doesn't work
    ## well (the buttons disappear).
    set buttons [frame $popup.buttons^ -relief raised -bd .02i]
    unameit_add_wrapper_binding $buttons

    set i 0
    foreach but $button_list {
	set button [button $buttons.button$i -text $but -command\
		[list unameit_wrapper [list\
		unameit_popup_finished $popup $before_return_code\
		$after_focus_reset_code $i]]]
	unameit_add_wrapper_binding $button
	if {$i == $default} {
	    set default_frame [frame $buttons.default_frame -relief sunken\
		    -bd .02i]
	    unameit_add_wrapper_binding $default_frame
	    raise $button $default_frame
	    pack $default_frame -side left -expand 1 -padx 3m -pady 2m
	    pack $button -padx 2m -pady 2m -in $default_frame
	} else {
	    pack $button -side left -expand 1 -padx 3m -pady 2m
	}

	incr i
    }

    pack $buttons -side bottom -fill x

    ## Create <Return> binding if default.
    if {$default >= 0} {
	bind $popup <Return> [list unameit_wrapper [format {
	    %s configure -state active -relief sunken
	    update idletasks
	    after 100
	    %s configure -state normal -relief raised
	    unameit_popup_finished %s %s %s %d
	    break
	} [list $buttons.button$default] [list $buttons.button$default]\
		[list $popup] [list $before_return_code]\
		[list $after_focus_reset_code] [list $default]]]
    }
	    
    set oldFocus [focus -lastfor $toplevel_p]

    unameit_run_user_popup_code $popup $code

    ## Disable parent after running the users code. If the users code gets
    ## an error creating the screen, we would have to undo this code so we
    ## try to create the screen first.
    set toplevel_s(old_focus^) $oldFocus
    set toplevel_s(dead_widget^) $dead_widget
    set toplevel_s(dead_tags^) [bindtags $dead_widget]
    bindtags $dead_widget Wrapper
    focus $dead_widget
    unameit_busy busy $toplevel_p

    ## Update all the geometry information so we know how big it wants to
    ## be, then center the window in the display and de-iconify it.

    update idletasks
    set x [expr [winfo screenwidth $popup]/2 - [winfo reqwidth $popup]/2 \
	    - [winfo vrootx [winfo parent $popup]]]
    set y [expr [winfo screenheight $popup]/2 - [winfo reqheight $popup]/2 \
	    - [winfo vrooty [winfo parent $popup]]]
    wm geom $popup +$x+$y
    wm deiconify $popup
}

## When a popup dialog is created, the user can pass in his own code to create
## widgets in the dialog. This user code is run in its own procedure so it gets
## its own local variables and doesn't clobber the local variables in the
## popup dialog box routine.
proc unameit_run_user_popup_code {popup code} {
    eval $code
}

## This routine runs when a popup button is hit. If it raises an error,
## the popup will not be popped down. If it doesn't, the popup will be
## popped down.
proc unameit_popup_finished {popup before_return_code after_focus_reset_code\
	button_hit} {
    eval $before_return_code

    ## Set up toplevel_p to the correct value. Who knows what the user's code
    ## above did.
    upvar #0 [set toplevel_p [winfo toplevel [winfo parent $popup]]] toplevel_s

    unameit_busy normal $toplevel_p

    # If old_focus^ is the empty string, focus does nothing.
    focus $toplevel_s(old_focus^); unset toplevel_s(old_focus^)

    bindtags $toplevel_s(dead_widget^) $toplevel_s(dead_tags^)

    ## Don't move this after the destroy because the destroy trashes variables
    ## named after the widgets.
    eval $after_focus_reset_code

    destroy $popup
}

####		Routines related to committing the cache and redisplaying

### This routine runs a command for each book. The result returned is a
### union of all the uuids returned by the call to each book.
proc unameit_for_each_book {cmd args} {
    global UNAMEIT_TOPLEVELS

    set result() 1; unset result()
    foreach toplevel_p [array names UNAMEIT_TOPLEVELS] {
	foreach val [eval {$cmd} {$toplevel_p} $args] {
	    if {![empty $val]} {
		set result($val) 1
	    }
	}
    }
    array names result
}

proc unameit_get_objs_in_book {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s

    foreach class [unameit_get_class_list] {
	if {[info exists toplevel_s($class)]} {
	    upvar #0 $toplevel_s($class) class_s

	    foreach uuid [get_values_from_ordered_list class_s] {
		set result($uuid) 1
	    }
	}
    }

    array names result
}

proc unameit_redisplay_book {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s

    set mode $toplevel_s(mode^)
    if {![cequal $mode item]} return

    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s

    if {![info exists class_s(uuids^)]} {
	## The object we were staring at was deleted.
	unameit_empty_form $toplevel_p
    } else {
	unameit_fill_in_class_data $class_p
    }
    unameit_fill_in_ws_window $toplevel_p
}

### Routines for switching states from on type of form (e.g., a greeting
### window) to another type of toplevel form (e.g., a class form).

proc unameit_about_box_to_login {toplevel_p} {
    pack forget $toplevel_p.about^
    unameit_set_menubar_type $toplevel_p none
    unameit_create_login_screen $toplevel_p
    foreach char {b c d e n q r v m l p a s} {
	bind $toplevel_p <Control-x>$char ""
    }
}

proc unameit_new_window {} {
    global unameitPriv

    set greeting_text [unameit_get_greeting_window_info]

    set toplevel_p [unameit_get_new_toplevel]

    set message_area [unameit_create_message_area $toplevel_p]
    pack $message_area -side bottom -fill x

    if {[unameit_can_modify_schema]} {
	set type schema
    } else {
	set type normal
    }
    array set main_menubar $unameitPriv(${type}_main_menubar)

    set menubar [unameit_build_menubar $toplevel_p ${type}_menubar^\
	    menu_data class2window main_menubar $type]

    ## Set up menubar callbacks
    unameit_set_standard_callbacks $toplevel_p class2window Dismiss^\
	    Exit^ New^ Connect^ Preview^

    ## Set up class menubar callbacks
    unameit_set_class_menubar_callbacks $toplevel_p class2window

    upvar #0 $toplevel_p toplevel_s

    ## Record locations of miscellaneous box menu items. The bindings
    ## for these change in the menu as we switch states. Record this
    ## on a toplevel basis because the menu paths will differ for
    ## each toplevel.
    set toplevel_s(${type}_login_menu_loc) $class2window(Login^)
    set toplevel_s(${type}_about_menu_loc) $class2window(About^)
    set toplevel_s(${type}_save_menu_loc) $class2window(Save^)
    set toplevel_s(${type}_preview_menu_loc) $class2window(Preview^)

    unameit_set_menubar_type $toplevel_p $type

    unameit_create_greeting_window $toplevel_p $greeting_text
}

proc unameit_switch_to_new_class {toplevel_p new_class {modify_visit_list 1}} {
    global unameitPriv
    upvar #0 $toplevel_p toplevel_s

    if {[cequal $toplevel_s(mode^) item]} {
	unameit_apply_focus_field $toplevel_p
    }

    ## Get all items in new class's working set if a working set exists.
    if {[info exists toplevel_s($new_class)]} {
	upvar #0 $toplevel_s($new_class) class_s
	unameit_multi_fetch [get_values_from_ordered_list\
	    class_s] [unameit_get_displayed_attributes $new_class]
    }

    set textual_class_name [unameit_display_item $new_class]

    ## Get the multiplicity for each attribute and cache it. This makes
    ## calls to get the defining class for an attribute.
    foreach attr [unameit_get_displayed_attributes $new_class] {
	unameit_get_attribute_multiplicity $attr
    }
        
    ## *** After this point, we cannot make any calls to the server. We
    ## *** are breaking down windows and rebuilding them.

    ## Hidden shortcut for demos.
    if {![cequal $toplevel_s(mode^) item]} {
	bind $toplevel_p <Control-x>Q [list unameit_wrapper [format {
	    unameit_run_all_query %s
	    break
	} [list $toplevel_p]]]
    }

    if {[unameit_is_readonly $new_class]} {
	wm title $toplevel_p "$unameitPriv(mode): <$textual_class_name>"
	wm iconname $toplevel_p <$textual_class_name>
    } else {
	wm title $toplevel_p "$unameitPriv(mode): $textual_class_name"
	wm iconname $toplevel_p $textual_class_name
    }

    ## Initialize visit list if it doesn't exist. It won't exist when we
    ## first create the class window.
    if {![info exists toplevel_s(visit_list^)]} {
	set toplevel_s(visit_list^) {}
	set toplevel_s(visit_list_index^) -1
    }

    ## Modify visit list
    if {$modify_visit_list} {
	set len [llength $toplevel_s(visit_list^)]
	if {[incr toplevel_s(visit_list_index^)] < $len} {
	    set toplevel_s(visit_list^) [lreplace $toplevel_s(visit_list^)\
		    $toplevel_s(visit_list_index^) end]
	}
	lappend toplevel_s(visit_list^) $new_class
    }

    ## Create top class window.
    unameit_create_top_class_window $toplevel_p $new_class

    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s

    ## Fill in data on form.
    if {![info exists class_s(uuids^)]} {
	unameit_set_item_menus $class_p
	unameit_nullify_object_description $toplevel_p
    } else {
	unameit_fill_in_class_data $class_p
    }

    unameit_fill_in_ws_window $toplevel_p
}

proc unameit_class_window_to_about_box {toplevel_p} {
    set greeting_text [unameit_get_greeting_window_info]

    # *** After this point, we can't make calls to the server

    unameit_unset_ws_bindings $toplevel_p
    foreach char {b c d e n q Q r v m s f} {
	bind $toplevel_p <Control-x>$char ""
    }

    pack forget $toplevel_p.object_box^
    pack forget $toplevel_p.working_set^
    pack forget $toplevel_p.object_description^
    pack forget $toplevel_p.button_bar^
    pack forget $toplevel_p.spacer^

    unameit_create_greeting_window $toplevel_p $greeting_text
}

proc unameit_class_window_to_login {toplevel_p} {
    unameit_unset_ws_bindings $toplevel_p
    foreach char {b c d e n q Q r v m l p a s f} {
	bind $toplevel_p <Control-x>$char ""
    }

    pack forget $toplevel_p.object_box^
    pack forget $toplevel_p.working_set^
    pack forget $toplevel_p.object_description^
    pack forget $toplevel_p.button_bar^
    pack forget $toplevel_p.spacer^
    unameit_set_menubar_type $toplevel_p none

    unameit_create_login_screen $toplevel_p
}

####			Main toplevel window routines

proc unameit_create_greeting_window {toplevel_p greeting_text} {
    global unameitPriv
    upvar #0 $toplevel_p toplevel_s

    ## When looking at a greeting window, we aren't looking at a class.
    catch {unset toplevel_s(class^)}

    set toplevel_s(mode^) greeting

    ## Set title to UName*It
    wm title $toplevel_p "$unameitPriv(mode): UName*It"
    wm iconname $toplevel_p $unameitPriv(mode)

    if {![winfo exists $toplevel_p.about^]} {
	set text [unameit_create_scrollable $toplevel_p about^ text y 1 ""]
	$text.text insert end $greeting_text
	$text.text configure -state disabled
    }

    pack $toplevel_p.about^ -side left -fill both -expand 1

    ## Disable About and Save menu items
    set type $toplevel_s(menubar_type^)
    switch -- $type normal - schema {} default return 

    lassign $toplevel_s(${type}_about_menu_loc) menu item
    $menu entryconfigure $item -state disabled
    bind $toplevel_p <Control-x>a [format {
	%s invoke %s
	break
    } [list $menu] [list $item]]

    lassign $toplevel_s(${type}_save_menu_loc) menu item
    $menu entryconfigure $item -state disabled
    bind $toplevel_p <Control-x>s [format {
	%s invoke %s
	break
    } [list $menu] [list $item]]

    ## Set up Login binding.
    lassign $toplevel_s(${type}_login_menu_loc) menu item
    $menu entryconfigure $item -command\
    	[list unameit_wrapper [list unameit_about_box_to_login $toplevel_p]]
    bind $toplevel_p <Control-x>l [format {
	%s invoke %s
	break
    } [list $menu] [list $item]]

    lassign $toplevel_s(${type}_preview_menu_loc) menu item
    bind $toplevel_p <Control-x>p [format {
	%s invoke %s
	break
    } [list $menu] [list $item]]
}

proc unameit_create_top_class_window {toplevel_p new_class} {
    global unameitPriv
    upvar #0 $toplevel_p toplevel_s

    set toplevel_slaves [pack slaves $toplevel_p]
    foreach slave $toplevel_slaves {
	set slaves($slave) 1
    }

    set toplevel_s(mode^) item
    set type $toplevel_s(menubar_type^)

    ## Unmap the About box if need be. Also, if we are coming from the
    ## greeting window, change the callback for the About, Login,
    ## and Save menu items.
    if {[info exists slaves($toplevel_p.about^)]} {
	pack forget $toplevel_p.about^

	lassign $toplevel_s(${type}_about_menu_loc) menu item
	$menu entryconfigure $item -command [list unameit_wrapper\
		[list unameit_class_window_to_about_box $toplevel_p]]\
		-state normal

	lassign $toplevel_s(${type}_login_menu_loc) menu item
	$menu entryconfigure $item -command [list unameit_wrapper\
		[list unameit_class_window_to_login $toplevel_p]]

	lassign $toplevel_s(${type}_save_menu_loc) menu item
	$menu entryconfigure $item -command [list unameit_wrapper\
		[list unameit_save_ws_list $toplevel_p]] -state normal

	set from_about_box 1
    } else {
	set from_about_box 0
    }

    ## Create the button bar
    if {![winfo exists $toplevel_p.button_bar^]} {
	set button_bar [unameit_create_button_bar $toplevel_p button_bar^\
	{Back Forward Create Delete Empty Narrow Query Revert Review} left]
	set button [button $button_bar.commit -text Commit]
	unameit_add_wrapper_binding $button
	pack $button -side right

	## Add bindings for the buttons.
	foreach tuple {{Empty unameit_empty_form 0} {Create unameit_clone 0}\
		{Delete unameit_delete_uuids 0} {Back unameit_back 0}\
		{Query unameit_query_callback 0} {Revert unameit_revert 0}\
		{Commit unameit_commit_callback 2} {Review unameit_review 2}\
	        {Narrow unameit_narrow_to_selection 0}\
		{Forward unameit_forward 0}} {
	    lassign $tuple label command underline
	    set widget [s2w $label]
	    $button_bar.$widget configure -command [list unameit_wrapper\
		    [list $command $toplevel_p]] -underline $underline
	}
    }
    set button_bar $toplevel_p.button_bar^

    ## Start out with Create, Delete and Revert disabled.
    ## We may be on a readonly class or not on an item.
    unameit_set_buttons $toplevel_p disabled Create Delete Revert

    if {![info exists slaves($button_bar)]} {
	pack $button_bar -side top -fill x
    }

    ## Create the object description label at the top
    if {![winfo exists $toplevel_p.object_description^]} {
	set label [label $toplevel_p.object_description^ -relief groove\
		-borderwidth .02i -anchor w]
	unameit_add_wrapper_binding $label
    }
    if {![info exists slaves($toplevel_p.object_description^)]} {
	pack $toplevel_p.object_description^ -side top -fill x
    }

    ## Create the working set box
    if {![winfo exists $toplevel_p.working_set^]} {
	set ws [frame $toplevel_p.working_set^]
	unameit_add_wrapper_binding $ws

	set ws_message [label $toplevel_p.working_set^.message^]
	unameit_add_wrapper_binding $ws_message
	pack $ws_message -side bottom -fill x

	set ws_box [unameit_create_scrollable $toplevel_p.working_set^\
	    listframe^ fancylistbox y 1 "" -width 20 -height 1 -takefocus 0]
	$ws_box.fancylistbox configure -selectmode extended
	pack $ws_box -side top -fill both -expand 1

	bind $ws_box.fancylistbox <ButtonRelease-1> [list unameit_wrapper\
		[list unameit_set_ws_item $toplevel_p]]
	bind $ws_box.fancylistbox <Triple-ButtonPress-1> [list unameit_wrapper\
		[list unameit_select_all_items $toplevel_p]]

	## Change the binding tags on the working set box so that the selection
	## is moved before the callback is called. We need to inspect the
	## selection.
	bindtags $ws_box.fancylistbox [list Wrapper $toplevel_p Flb_Bind\
		Listbox $ws_box.fancylistbox all]
    }
    if {![info exists slaves($toplevel_p.working_set^)]} {
	pack $toplevel_p.working_set^ -side right -expand 1 -fill both
    }

    ## Put a spacer between the working set box and the canvas
    if {![winfo exists $toplevel_p.spacer^]} {
	set spacer [frame $toplevel_p.spacer^ -width .125i]
	unameit_add_wrapper_binding $spacer
    }
    if {![info exists slaves($toplevel_p.spacer^)]} {
	pack $toplevel_p.spacer^ -side right -fill y
    }

    if {![winfo exists $toplevel_p.object_box^.canvas]} {
	unameit_create_scrollable $toplevel_p object_box^ canvas {x y} 1 ""
    }
    if {![info exists toplevel_s($new_class)]} {
	set class_fields [unameit_create_class_fields\
		$toplevel_p.object_box^.canvas $new_class]
	pack $class_fields
	set toplevel_s($new_class) $class_fields
	upvar #0 $class_fields class_fields_s
	init_ordered_list class_fields_s
    } else {
	set class_fields $toplevel_s($new_class)
    }

    if {![info exists slaves($toplevel_p.object_box^)]} {
	pack $toplevel_p.object_box^ -side left -fill y
    }

    ## If we are not on the correct class, do the canvas scroll stuff.
    if {![info exists toplevel_s(class^)] ||
    ![cequal $toplevel_s(class^) $new_class]} {
	## Move scrollregion to upper left quadrant
	set cwidth [$toplevel_p.object_box^.canvas cget -width]
	set cheight [$toplevel_p.object_box^.canvas cget -height]
	$toplevel_p.object_box^.canvas configure -scrollregion\
		[list 0 0 -$cwidth -$cheight]

	## Put new class box in canvas with nw corner at (0,0).
	set win_num [$toplevel_p.object_box^.canvas create window 0 0\
		-anchor nw -window $class_fields]

	## Make canvas scrollregion the size of the new class box.
	update idletasks
	set width [winfo reqwidth $class_fields]
	set height [winfo reqheight $class_fields]
	## Remove old window from canvas
	if {[info exists toplevel_s(class_win_id^)]} {
	    $toplevel_p.object_box^.canvas delete $toplevel_s(class_win_id^)
	}
	## Add new window and adjust canvas size
	$toplevel_p.object_box^.canvas configure -width $width -height $height\
		-scrollregion [list 0 0 $width $height]

	$toplevel_p.object_box^.canvas yview moveto 0

	set toplevel_s(class_win_id^) $win_num
    }

    set toplevel_s(class^) $new_class

    unameit_item_mode $toplevel_p

    unameit_set_focus $toplevel_s($new_class)

    if {$from_about_box} {
	## Add accelerators
	foreach tuple {{Back b} {Create c} {Delete d} {Empty e} {Forward f}\
		{Narrow n} {Query q} {Revert r} {Review v} {Commit m}} {
	    lassign $tuple button key
	    set widget [s2w $button]
	    bind $toplevel_p <Control-x>$key [format {
		%s.%s invoke
		break
	    } [list $button_bar] [list $widget]]
	}
	foreach tuple {{about a} {login l} {preview p}} {
	    lassign $tuple entry key
	    lassign $toplevel_s(${type}_${entry}_menu_loc) menu index
	    bind $toplevel_p <Control-x>$key [format {
		%s invoke %s
		break
	    } [list $menu] [list $index]]
	}
    }
}

proc unameit_preview_window {} {
    global unameitPriv

    if {[winfo exists .preview^]} {
	raise .preview^
	wm deiconify .preview^
	return
    }
    toplevel .preview^ -class Dialog
    wm title .preview^ "$unameitPriv(mode): Preview"
    wm iconname .preview^ Preview
    catch {wm iconbitmap .preview^ @$unameitPriv(library)/unameit.icon}

    # Important. Make sure you pack the non-expand boxes before the expand
    # boxes or you will get incorrect behavior when shrinking. The expand
    # box will take all the non-expand space. Order matters.
    set dismiss [button .preview^.dismiss^ -text Dismiss -command\
	    {destroy .preview^}]
    pack $dismiss -side bottom -padx 2m -pady 2m

    set text_frame [unameit_create_scrollable .preview^ text_frame^\
	    text {x y} 1 ""]
    $text_frame configure -relief groove -bd .02i
    
    $text_frame.text insert end [unameit_preview_cache]
    $text_frame.text configure -state disabled

    pack $text_frame -side top -fill both -expand 1
}

proc unameit_save_ws_list {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s

    set toplevel_name $toplevel_p.save^

    set creation_code [format {
	## Create file name save entry
	set fn_frame [frame %s.fn_frame^]
	pack $fn_frame -side top

	set fn_label [label $fn_frame.fn_label^ -text {File name: }]
	pack $fn_label -side left

	set fn_entry [entry $fn_frame.fn_entry^ -width 20]
	pack $fn_entry -side right -fill x -expand 1

	focus $fn_entry
    } [list $toplevel_name]]

    set popdown_code [format {
	upvar #0 %s class_s

	set file_name [%s.fn_frame^.fn_entry^ get]
	if {$button_hit == 0 &&
	[catch {open $file_name w} class_s(file_name_fd^)]} {
	    tk_dialog %s.save_error^ {Save Error} $class_s(file_name_fd^)\
		    error 0 OK
	    error {} {} {UNAMEIT EIGNORE}
	}
    } [list $class_p] [list $toplevel_name] [list $toplevel_name]]

    set button_hit [unameit_popup_modal_dialog $toplevel_name\
	    "Save Item List" Save 0 {OK Cancel} $creation_code $popdown_code]

    if {$button_hit == 0} {
	foreach item [get_values_from_ordered_list class_s] {
	    puts $class_s(file_name_fd^) [unameit_get_label $item]
	}
	close $class_s(file_name_fd^)
    }

    catch {unset class_s(file_name_fd^)}

    return $button_hit
}

####		Routines related to filling in data on the form

proc unameit_set_object_description {toplevel_p uuid} {
    array set tmp [unameit_get_attribute_values $uuid new Class]
    set old_label [unameit_get_db_label $uuid]
    set new_label [unameit_get_new_label $uuid]

    set text "[unameit_display_item $tmp(Class)]: "
    if {[cequal $old_label $new_label]} {
	append text $old_label
    } else {
	append text "$old_label --> $new_label"
    }
    $toplevel_p.object_description^ configure -text $text
}

proc unameit_nullify_object_description {toplevel_p} {
    $toplevel_p.object_description^ configure -text ""
}

proc unameit_query_mode {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s

    set toplevel_s(mode^) query

    set class_s(focus_list^) {}

    ## Setup automatic apply bindings and set focus list.
    unameit_iterate_over_class $class_p {
	unameit_set_bindings $attr_p $widget_type
	switch -- $widget_type {
	    choice -
	    check_box -
	    radio_box {}
	    default {
		lappend class_s(focus_list^) $attr
	    }
	}
    }
	
    unameit_set_focus $class_p
}

proc unameit_item_mode {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s

    set toplevel_s(mode^) item

    set class_s(focus_list^) {}

    ## Enable or disable fields as appropriate
    unameit_iterate_over_class $class_p {
	if {[unameit_is_readonly $class] && ![cequal $syntax pointer]} {
		unameit_disable_${widget_type}_class_bindings $attr_p
	}
    }
	
    ## Change automatic apply bindings
    unameit_iterate_over_class $class_p {
	unameit_set_bindings $attr_p $widget_type
    }

    ## Disable protected attribute fields
    unameit_iterate_over_class $class_p {
	## Disable protected and computed attributes.
	if {[unameit_is_prot_or_comp $class $attr]} {
	    if {[cequal $syntax pointer]} {
		$attr_p.menubutton^ configure -takefocus 0
	    } else {
		unameit_disable_${widget_type}_widget $attr_p
	    }
	} else {
	    switch $widget_type {
		choice -
		check_box -
		radio_box {}
		default {
		    lappend class_s(focus_list^) $attr
		}
	    }
	}
    }
		    
    ## Set up ^N and ^P bindings
    unameit_set_ws_bindings $toplevel_p
}

proc unameit_fill_in_class_data {class_p} {
    upvar #0 $class_p class_s
    upvar #0 [set toplevel_p [winfo toplevel $class_p]] toplevel_s
    
    set uuid [lindex $class_s(uuids^) 0]

    ## Set up the menu item states
    unameit_set_item_menus $class_p

    ## Trash pointer mapping variable
    unameit_iterate_over_class $class_p {
	if {[cequal $syntax pointer]} {
	    catch {unset attr_s(pointers^)}
	}
    }

    ## Set object description
    unameit_set_object_description $toplevel_p $uuid

    ## Display the item contents
    unameit_display_item_in_form $class_p

    ## Select the working set entry in the listbox
    unameit_select_ws_entries $toplevel_p $class_s(uuids^)

    unameit_set_focus $class_p
}

proc unameit_delete_trailing_newlines_from_text {widget} {
    while {[cequal [$widget get {end -2 chars} {end -1 chars}] \n]} {
	$widget delete {end -2 chars}
    }
}

proc unameit_last_text_line {widget line_number} {
    if {[$widget compare $line_number.0 == end]} {
	return 1
    }

    if {$line_number == 1 && [$widget compare 1.0 == {1.0 lineend}] &&
    [$widget compare {1.0 lineend} == {end -1 chars}]} {
	return 1
    }

    return 0
}

proc unameit_get_list_from_text_widget {twidget uuid attr} {
    unameit_delete_trailing_newlines_from_text $twidget

    set result {}
    for {set i 1; set build_str ""}\
	    {![unameit_last_text_line $twidget $i]}\
	    {incr i} {
	append build_str [$twidget get $i.0 "$i.0 lineend"]

	if {[info complete $build_str]} {
	    lappend result $build_str
	    set build_str ""
	} else {
	    append build_str \n
	}
    }
    if {![empty $build_str]} {
	error {} {} [list UNAMEIT ENOTLIST $uuid $attr $build_str]
    }
    return $result
}    

proc unameit_text_widget_to_list {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    $attr_p.top^.text configure -state normal
    if {[info exists class_s(uuids^)]} {
	set uuid [lindex $class_s(uuids^) 0]
    } else {
	set uuid $class
    }
    set result [unameit_get_list_from_text_widget $attr_p.top^.text $uuid\
	    $attr]
    $attr_p.top^.text configure -state disabled
    return $result
}

proc unameit_list_to_text_widget {attr_p list} {
    unameit_clear_text_field $attr_p
    $attr_p.top^.text configure -state normal
    foreach value $list {
	$attr_p.top^.text insert end $value\n
    }
    $attr_p.top^.text configure -state disabled
}

proc unameit_display_item_in_form {class_p} {
    upvar #0 $class_p class_s
    set class $class_s(class^)

    set uuid [lindex $class_s(uuids^) 0]

    ## Fetch the fields of the item we are going to display. We use the
    ## values in the iteration loop below.
    array set item\
	[eval unameit_get_attribute_values $uuid new\
	    [unameit_get_displayed_attributes $class]]

    ## If the class is readonly then the widgets are disabled and we can't
    ## draw in them. We need to enable them temporarily so we can draw in
    ## them. See the enable/disable code below.
    unameit_iterate_over_class $class_p {
	upvar 1 item item

	if {[unameit_is_readonly $class] && ![cequal $syntax pointer]} {
	    unameit_enable_${widget_type}_class_bindings $attr_p
	}

	## Display the value in the widget.
        unameit_set_widget_value $attr_p $item($attr)

	if {[unameit_is_readonly $class] && ![cequal $syntax pointer]} {
	    unameit_disable_${widget_type}_class_bindings $attr_p
	}
    }
}

####			Miscellaneous callbacks

proc unameit_revert_field_callback {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set toplevel [winfo toplevel $attr_p]
    set attr $attr_s(attr^)

    foreach uuid $class_s(uuids^) {
	unameit_revert_field $uuid $attr
    }

    array set temp [unameit_get_attribute_values [lindex $class_s(uuids^) 0]\
	    new $attr]
    unameit_set_widget_value $attr_p $temp($attr)

    unameit_set_object_description $toplevel [lindex $class_s(uuids^) 0]
    unameit_update_ws_labels $toplevel $class_s(uuids^)
    unameit_refresh_preview_window
}

proc unameit_set_class_menubar_callbacks {toplevel_p class2window_var} {
    upvar 1 $class2window_var class2window

    foreach class [array names class2window] {
	if {[unameit_is_standard_menu_field $class]} {
	    continue
	}
	lassign $class2window($class) menu index
	$menu entryconfigure $index -command [list unameit_wrapper\
		[list unameit_switch_to_new_class $toplevel_p $class]]
    }
}

proc unameit_traverse {attr_p {use_class ""}} {
    upvar #0 $attr_p attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    ## Try to apply current field. If it fails, we can't Traverse.
    unameit_apply_focus_field $toplevel_p

    ## Set new_uuid to empty or the uuid we are looking at.
    if {[cequal [unameit_get_attribute_multiplicity $attr] Scalar]} {
	set new_uuid $attr_s(pointers^)
    } else {
	set selection [lindex [$attr_p.top^.listbox curselection] 0]
	if {[empty $selection]} {
	    set new_uuid ""
	} else {
	    set new_uuid [lindex $attr_s(pointers^) $selection]
	}
    }
    
    ## Set the class based on the uuid. If the uuid isn't in the new
    ## classes' working set, add it. Also, make it the last seen item.
    if {[empty $new_uuid]} {
	if {[empty $use_class]} {
	    set new_class [unameit_get_attribute_domain $class $attr]
	} else {
	    set new_class $use_class
	}
    } else {
	array set temp [unameit_get_attribute_values $new_uuid new Class]
	set new_class $temp(Class)
    }

    ## Create the class window.
    unameit_switch_to_new_class $toplevel_p $new_class

    ## We have to create the class window before we can populate its
    ## uuid list. The class window may not have been created yet.
    if {![empty $new_uuid]} {
	unameit_set_ws_uuids $toplevel_p $new_uuid 1 $new_class
	upvar #0 [set new_class_p $toplevel_s($new_class)] new_class_s
	set new_class_s(uuids^) [list $new_uuid]
	unameit_fill_in_class_data $new_class_p
	unameit_fill_in_ws_window $toplevel_p
    }
}

proc unameit_full_query {attr_p query_class} {
    upvar #0 $attr_p attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    upvar #0 [set toplevel_p [winfo toplevel $attr_p]] toplevel_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    ## Try to apply current field. If it fails, we can't Traverse.
    unameit_apply_focus_field $toplevel_p

    switch -- $query_class "" {
	set use_class [unameit_get_attribute_domain $class $attr]
    } default {
	set use_class $query_class
    }

    set creation_code [format {
	upvar #0 [set toplevel_p [winfo toplevel $popup]] toplevel_s

	set toplevel_s(mode^) query
	set class %s
	set query_class %s

	unameit_create_scrollable $toplevel_p object_box^ canvas {x y} 1 ""
	set class_fields [unameit_create_class_fields\
		$toplevel_p.object_box^.canvas $class]
	pack $class_fields

	set toplevel_s(class^) $class
	set toplevel_s(query_class^) $query_class
	set toplevel_s($class) $class_fields
	upvar #0 $class_fields class_s

	unameit_query_mode $toplevel_p

	set message [label $toplevel_p.message^]
	unameit_add_wrapper_binding $message
	pack $message -side bottom -fill x
	## We have to do this so the binding for the toplevel window doesn't
	## fire.
	bind $message <Any-KeyPress> break
	bind $message <Any-KeyRelease> break

	pack $toplevel_p.object_box^ -side top -fill both -expand 1
    } [list $use_class] [list $query_class]]

    set popdown_code {
	global unameitPriv
	upvar #0 [set toplevel_p $popup] toplevel_s
	set class $toplevel_s(class^)
	set query_class $toplevel_s(query_class^)
	upvar #0 [set class_p $toplevel_s($class)] class_s

	if {$button_hit == 0} {
	    unameit_apply_focus_field $toplevel_p

	    set query(Class) $class
	    switch -- $query_class "" {set query(All) 1}

	    unameit_iterate_over_class $class_p {
		upvar query query

		if {![empty [set value [unameit_get_widget_value $attr_p]]]} {
		    set value\
			[unameit_check_syntax $class $attr $class $value query]
		    switch -- [unameit_get_attribute_syntax $class $attr] {
			time {
			    lassign [unameit_fuzzy_time $value] start end
			    set query($attr) [list >= $start <= $end]
			}
			default {
			    set operator\
				[unameit_get_operator $class $attr $value]
			    set query($attr) [list $operator $value]
			}
		    }
		}
	    }

	    ## Run the query
	    $popup.message^ configure -text {Running query...}
	    if {[set code [catch {
		unameit_query\
			[array get query]\
			[list\
			-timeOut $unameitPriv(queryTimeOut)\
			-maxRows $unameitPriv(queryMaxRows)]
	    } query_result]]} {
		global errorCode errorInfo
		$popup.message^ configure -text ""
		return -code $code -errorcode $errorCode -errorinfo\
			$errorInfo $query_result
	    }

	    if {[lempty $query_result]} {
		$popup.message^ configure -text {No matches}
		error {} {} {UNAMEIT EIGNORE}
	    }

	    $popup.message^ configure -text ""

	    set parent_toplevel_p [winfo toplevel [winfo parent $popup]]
	    upvar #0 $parent_toplevel_p parent_toplevel_s
	    set parent_class $parent_toplevel_s(class^)
	    upvar #0 [set parent_class_p $parent_toplevel_s($parent_class)]\
		    parent_class_s
	    set parent_attr $parent_class_s(attr^)
	    upvar #0 [set parent_attr_p $parent_class_s($parent_attr)]\
		    parent_attr_s

	    if {[llength $query_result] > 1} {
		if {[unameit_select_uuids_from_list $parent_attr_p\
			$query_result query_result] == 1} {
		    ## User hit Cancel. Go back to Query window.
		    error {} {} {UNAMEIT EIGNORE}
		}
	    }
	}
    }

    ## This code must be executed after the focus is restored because it
    ## inspects the focus.
    set after_focus_reset_code {
	if {$button_hit == 0} {
	    unameit_set_pointer_from_uuids $parent_attr_p $query_result
	    unameit_set_completion_value $query_result
	}
    }

    # Both item and query windows have a toplevel_p.message^ window.
    set title [unameit_display_item $use_class]
    if {[unameit_is_readonly $use_class]} {
	set title <$title>
    }
    set title "$title Query"
    unameit_popup_nonmodal_dialog $toplevel_p.query^ $toplevel_p.message^\
	    $title Query 0 {{Run Query} Cancel} $creation_code $popdown_code\
	    $after_focus_reset_code
}

proc unameit_back {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s

    if {[llength $toplevel_s(visit_list^)] == 0 ||
    $toplevel_s(visit_list_index^) <= 0} {
	return
    }

    ## If the switch to the new class fails because an automatic apply failed,
    ## reset the visit list index.
    set new_class [lindex $toplevel_s(visit_list^)\
	    [incr toplevel_s(visit_list_index^) -1]]
    if {[set code [catch {unameit_switch_to_new_class $toplevel_p\
	    $new_class 0} msg]]} {
	global errorInfo errorCode
	incr toplevel_s(visit_list_index^) 1
	return -code $code -errorinfo $errorInfo -errorcode $errorCode $msg
    }
}

proc unameit_forward {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s

    if {[set len [llength $toplevel_s(visit_list^)]] == 0 ||
    $len-1 <= $toplevel_s(visit_list_index^)} {
	return
    }

    ## If the switch to the new class fails because an automatic apply failed,
    ## reset the visit list index.
    set new_class [lindex $toplevel_s(visit_list^)\
	    [incr toplevel_s(visit_list_index^) 1]]
    if {[set code [catch {unameit_switch_to_new_class $toplevel_p\
	    $new_class 0} msg]]} {
	global errorInfo errorCode
	incr toplevel_s(visit_list_index^) -1
	return -code $code -errorinfo $errorInfo -errorcode $errorCode $msg
    }
}

proc unameit_clone {toplevel_p {tuple ""}} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s
    set attr $class_s(attr^)
    upvar #0 [set attr_p $class_s($attr)] attr_s

    if {[cequal $tuple ""]} {
	unameit_apply_focus_field $toplevel_p
    }

    if {![lempty $tuple]} {
	lassign $tuple clone_attr_p clone_attr_uuid
	upvar #0 $clone_attr_p clone_attr_s
	set clone_attr $clone_attr_s(attr^)
	set uuid_list [lindex $class_s(uuids^) 0]
    } else {
	if {[info exists class_s(uuids^)]} {
	    set uuid_list $class_s(uuids^)
	} else {
	    set uuid_list none
	}
    }

    set settable_attrs {}
    foreach display_attr [unameit_get_displayed_attributes $class] {
	if {[unameit_is_name_attribute $class $display_attr] ||
	(![unameit_isa_protected_attribute $display_attr] &&
	![unameit_isa_computed_attribute $class $display_attr])} {
	    lappend settable_attrs $display_attr
	}
    }

    set selection_uuid_list {}
    foreach uuid $uuid_list {
	if {![cequal $uuid none]} {
	    catch {unset tmp}
	    array set tmp [eval unameit_get_attribute_values {$uuid} new\
		    $settable_attrs]
	}

	set args {}
	foreach settable_attr $settable_attrs {
	    if {[info exists clone_attr_p] &&
	    [cequal $settable_attr $clone_attr]} {
		set value $clone_attr_uuid
	    } else {
		if {[cequal $uuid none]} {
		    set attr_p $class_s($settable_attr)
		    set value [unameit_get_widget_value $attr_p]
		} else {
		    set value $tmp($settable_attr)
		}
	    }

	    lappend args $settable_attr $value

	    ## Check syntax here. The create call will check the syntax
	    ## below, but it will not know how to display the item if
	    ## it gets an error because the item has not yet been created!
	    unameit_check_syntax $class $settable_attr $class $value db
	}

	set new_uuid [uuidgen]

	set new_uuid [eval unameit_create {$class} {$new_uuid} $args]

	lappend selection_uuid_list $new_uuid

	unameit_set_ws_uuids $toplevel_p [list $new_uuid] 1
    }

    ## Don't update the screen if we are cloning and replacing an attr. It
    ## will be done elsewhere.
    if {![info exists clone_attr_p]} {
	set class_s(uuids^) [unameit_sort_uuids $selection_uuid_list]

	## Redisplay working set
	unameit_fill_in_ws_window $toplevel_p
	
	## Fill in data for item
	unameit_fill_in_class_data $class_p

	## Refresh the preview window
	unameit_refresh_preview_window
    }
}

proc unameit_revert {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s
    set attr $class_s(attr^)

    if {[lempty $class_s(uuids^)]} return

    set uuid_list $class_s(uuids^)
    unameit_revert_items $uuid_list
    unameit_fill_in_class_data $class_p
    unameit_update_ws_labels $toplevel_p $uuid_list
    unameit_refresh_preview_window
}

proc unameit_delete_uuids {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s
    set attr $class_s(attr^)

    if {[lempty $class_s(uuids^)]} return

    set uuid_list $class_s(uuids^)
    unameit_apply_focus_field $toplevel_p
    unameit_delete_items $uuid_list
    unameit_update_ws_labels $toplevel_p $uuid_list
    unameit_refresh_preview_window
}

proc unameit_empty_form {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s
    set attr $class_s(attr^)
    upvar #0 [set attr_p $class_s($attr)] attr_s

    ## If we are on an item, try to apply to focus field and popup a
    ## dialog box if the user made changes.
    if {[info exists class_s(uuids^)]} {
	unameit_apply_focus_field $toplevel_p 1
    } else {
	## If on a pointer field, disable the pointer.
	switch [unameit_get_widget_type $class $attr] {
	    menu -
	    list_box {
		if {![unameit_pointer_is_disabled $attr_p]} {
		    unameit_disable_pointer_entry $attr_p
		}
	    }
	}
    }
    
    ## Unset the uuids^ field
    catch {unset class_s(uuids^)}

    ## Clear object description
    unameit_nullify_object_description $toplevel_p

    ## Trash the contents of the widgets
    unameit_iterate_over_class $class_p {
	## Enable widget if we are on a readonly class.
	unameit_enable_${widget_type}_class_bindings $attr_p
	
	## Clear out field
	unameit_clear_${widget_type}_field $attr_p
    }

    ## Clear working set selection
    unameit_select_ws_entries $toplevel_p ""

    ## This redisables the widgets if need be
    unameit_item_mode $toplevel_p

    ## Set the item menus appropriately since we are no longer looking at an
    ## object.
    unameit_set_item_menus $class_p
}

proc unameit_run_all_query {toplevel_p} {
    global unameitPriv
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s

    set query(Class) $class
    set query_result\
	[unameit_query\
	    [array get query]\
	    [list\
		-timeOut $unameitPriv(queryTimeOut)\
		-maxRows $unameitPriv(queryMaxRows)]]

    unameit_set_ws_uuids $toplevel_p $query_result 0
    if {[ordered_list_size class_s] > 0} {
	set class_s(uuids^) [get_nth_from_ordered_list class_s 0]
    } else {
	catch {unset class_s(uuids^)}
    }

    if {![info exists class_s(uuids^)]} {
	unameit_empty_form $toplevel_p
    } else {
	unameit_fill_in_class_data $class_p
    }

    unameit_fill_in_ws_window $toplevel_p
}

proc unameit_query_callback {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)

    unameit_apply_focus_field $toplevel_p

    set creation_code [format {
	upvar #0 [set toplevel_p [winfo toplevel $popup]] toplevel_s
	set toplevel_s(mode^) query
	set class %s

	unameit_create_scrollable $toplevel_p object_box^ canvas {x y} 1 ""
	set class_fields [unameit_create_class_fields\
		$toplevel_p.object_box^.canvas $class]
	pack $class_fields

	set toplevel_s(class^) $class
	set toplevel_s($class) $class_fields
	upvar #0 $class_fields class_s

	unameit_query_mode $toplevel_p

	pack $toplevel_p.object_box^ -side top -fill both -expand 1

	set label [label $toplevel_p.message^]
	unameit_add_wrapper_binding $label
	pack $label -side bottom -fill x

	set check_button_frame [frame $toplevel_p.check_buttons^]
	unameit_add_wrapper_binding $check_button_frame
	pack $check_button_frame -side bottom -fill x

	set append [checkbutton $check_button_frame.append^\
		-variable ${toplevel_p}(append^) -text append -takefocus 0]
	unameit_add_wrapper_binding $append
	pack $append -side left -expand 1

	set deleted [checkbutton $check_button_frame.deleted^\
		-variable ${toplevel_p}(deleted^) -text deleted -takefocus 0]
	unameit_add_wrapper_binding $deleted
	pack $deleted -side right -expand 1

	## Copy data from parent window form if not on an item
	upvar #0 [set parent_toplevel_p [winfo toplevel [winfo parent\
		$toplevel_p]]] parent_toplevel_s
	upvar #0 [set parent_class_p $parent_toplevel_s($class)]\
		parent_class_s
	if {![info exists parent_class_s(uuids^)]} {
	    unameit_iterate_over_class $parent_class_p {
		upvar class_s query_class_s

		switch $widget_type {
		    check_box -
		    radio_box -
		    choice {
			continue
		    }
		}
		unameit_set_${widget_type}_value $query_class_s($attr)\
			[unameit_get_${widget_type}_value $attr_p]
	    }
	}
    } [list $class]]

    set popdown_code {
	global unameitPriv
	upvar #0 [set toplevel_p [winfo toplevel [winfo parent $popup]]]\
		toplevel_s
	upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s
	
	if {$button_hit == 0} {
	    unameit_apply_focus_field $popup

	    upvar #0 $popup query_toplevel_s
	    set class $query_toplevel_s(class^)
	    upvar #0 [set query_class_p $query_toplevel_s($class)]\
		    query_class_s

	    set query(Class) $class
	    unameit_iterate_over_class $query_class_p {
		upvar query query

		if {![empty [set value [unameit_get_widget_value $attr_p]]]} {
		    set value [unameit_check_syntax $class $attr $class\
			    $value query]
		    switch -- [unameit_get_attribute_syntax $class $attr] {
			time {
			    lassign [unameit_fuzzy_time $value] start end
			    set query($attr) [list >= $start <= $end]
			}
			default {
			    set operator\
				[unameit_get_operator $class $attr $value]
			    set query($attr) [list $operator $value]
			}
		    }
		} else {
		    set query($attr) {}
		}
	    }

	    ## Run the query
	    $popup.message^ configure -text "Running query..."

	    set options\
		[list\
		    -timeOut $unameitPriv(queryTimeOut)\
		    -maxRows $unameitPriv(queryMaxRows)]
	    if {$query_toplevel_s(deleted^)} {
		lappend options -deleted
	    }

	    set query_result [unameit_query [array get query] $options]

	    if {[lempty $query_result]} {
		$popup.message^ configure -text "No matches"
		error {} {} {UNAMEIT EIGNORE}
	    }

	    $popup.message^ configure -text ""
	}
    }
    ## Do this after the focus is restored in case any of the code inspects
    ## the focus.
    set after_focus_reset_code {
	if {$button_hit == 0} {
	    ## Set the new results for this class
	    unameit_set_ws_uuids $toplevel_p $query_result\
		    $query_toplevel_s(append^)
	    
	    if {[ordered_list_size class_s] > 0} {
		if {$query_toplevel_s(append^) &&
		[info exists class_s(uuids^)] &&
		[ordered_list_contains_value class_s\
			[lindex $class_s(uuids^) 0]]} {
		    set class_s(uuids^) [list [lindex $class_s(uuids^) 0]]
		} else {
		    set class_s(uuids^) [get_nth_from_ordered_list class_s 0]
		}
	    } else {
		catch {unset class_s(uuids^)}
	    }

	    if {[lempty $class_s(uuids^)]} {
		unameit_empty_form $toplevel_p
	    } else {
		unameit_fill_in_class_data $class_p
	    }

	    unameit_fill_in_ws_window $toplevel_p
	}
    }

    unameit_popup_nonmodal_dialog $toplevel_p.query^ $toplevel_p.message^\
	    "[unameit_display_item $class] Query" Query 0 {{Run Query}\
	    Cancel} $creation_code $popdown_code $after_focus_reset_code
}

proc unameit_commit_callback {toplevel_p} {
    global UNAMEIT_TOPLEVELS unameitPriv

    unameit_apply_focus_field $toplevel_p

    ## Get list of modified objects for each class in the schema.
    # Items that are both created and deleted are not returned by
    # unameit_get_cache_uuids.
    foreach uuid [unameit_get_cache_uuids 1] {
	array set tmp [unameit_get_attribute_values $uuid new Class]
	lappend mod_list($tmp(Class)) $uuid
    }

    ## Reset working sets for all classes in all toplevels.
    foreach tlevel_p [array names UNAMEIT_TOPLEVELS] {
	upvar #0 $tlevel_p tlevel_s

	if {[info exists tlevel_s(class^)]} {
	    set tlevel_class $tlevel_s(class^)
	} else {
	    catch {unset tlevel_class}
	}

	foreach class [unameit_get_class_list] {
	    if {![info exists tlevel_s($class)]} {
		continue
	    }

	    upvar #0 [set class_p $tlevel_s($class)] class_s

	    ## Set working set appropriately.
	    if {[info exists mod_list($class)]} {
		unameit_set_ws_uuids $tlevel_p $mod_list($class) 0 $class
	    } elseif {[cequal $tlevel_s(mode^) item] &&
	    [cequal $tlevel_class $class] &&
	    [info exists class_s(uuids^)]} {
		set keep_list {}
		foreach uuid $class_s(uuids^) {
		    if {!([unameit_item_is $uuid created] &&
		    [unameit_item_is $uuid deleted])} {
			lappend keep_list $uuid
		    }
		}
		unameit_set_ws_uuids $tlevel_p $keep_list
            } else {
		init_ordered_list class_s
	    }

	    ## Trash uuids^ for class if not in new ws
	    if {[info exists class_s(uuids^)]} {
		set count 0
		set new_list {}
		foreach uuid $class_s(uuids^) {
		    if {![ordered_list_contains_value class_s $uuid]} {
			if {$count == 0} {
			    ## Trash the contents of the widgets
			    unameit_iterate_over_class $class_p {
				## Enable widget if we are on a readonly
				## class.
				unameit_enable_${widget_type}_class_bindings\
					$attr_p
	
				## Clear out field
				unameit_clear_${widget_type}_field $attr_p
			    }

			    if {[info exists tlevel_class] &&
			    [cequal $tlevel_class $class]} {
				unameit_item_mode $tlevel_p
			    }
			}
		    } else {
			lappend new_list $uuid
		    }
		    incr count
		}
		if {![lempty $new_list]} {
		    set class_s(uuids^) $new_list
		} else {
		    unset class_s(uuids^)
		}
	    }
	}

	unameit_redisplay_book $tlevel_p
    }
    
    ## Unset all completion cache values
    foreach var [array names unameitPriv complete^*] {
	unset unameitPriv($var)
    }

    unameit_print_message $toplevel_p Committing...
    set code [catch {unameit_commit} msg]
    unameit_print_message $toplevel_p ""
    if {$code} {
	global errorInfo errorCode
	return -code $code -errorinfo $errorInfo -errorcode $errorCode $msg
    }

    ## If the commit succeeds, we need to resort the working sets with
    ## modified objects because their database (i.e., original) name changed.
    foreach tlevel_p [array names UNAMEIT_TOPLEVELS] {
	upvar #0 $tlevel_p tlevel_s
	foreach class [unameit_get_class_list] {
	    if {[info exists tlevel_s($class)] &&
	    [info exists mod_list($class)]} {
		upvar #0 $tlevel_s($class) class_s
		eval set_ordered_list class_s [unameit_sort_uuids\
			[get_values_from_ordered_list class_s]]
	    }
	}
    }

    unameit_for_each_book unameit_redisplay_book
    unameit_refresh_preview_window
}

proc unameit_review {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s
    set attr $class_s(attr^)

    unameit_apply_focus_field $toplevel_p

    unameit_set_ws_uuids $toplevel_p [unameit_build_uuid_list_from_domain\
	    $class 0 1]

    if {[ordered_list_size class_s] > 0} {
	set class_s(uuids^) [list [get_nth_from_ordered_list class_s 0]]
	unameit_fill_in_class_data $class_p
    } else {
	unameit_empty_form $toplevel_p
    }

    unameit_fill_in_ws_window $toplevel_p
}

proc unameit_narrow_to_selection {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s

    unameit_apply_focus_field $toplevel_p

    if {[info exists class_s(uuids^)]} {
	set uuid_list $class_s(uuids^)
    } else {
	set uuid_list ""
    }
    unameit_set_ws_uuids $toplevel_p $uuid_list

    unameit_fill_in_ws_window $toplevel_p
}

proc unameit_edit_text_callback {attr_p} {
    upvar #0 $attr_p attr_s
    upvar #0 $attr_s(class_state^) class_s
    set class $class_s(class^)
    set toplevel_p [winfo toplevel $attr_p]
    set attr $attr_s(attr^)

    set attr_label [unameit_display_attr $class $attr]

    set code {
	## Create toplevel popup
	set popup_toplevel_p [winfo toplevel $popup]

	## Add text widget
	set text [text $popup_toplevel_p.text^ -state normal]
	pack $text -side top -fill both -expand 1

	## Fill in text widget
	upvar #0 [set toplevel_p [winfo toplevel [winfo parent\
		$popup_toplevel_p]]] toplevel_s
	set class $toplevel_s(class^)
	upvar #0 [set class_p $toplevel_s($class)] class_s
	set attr $class_s(attr^)
	set attr_p $class_s($attr)
	$text insert 0.0 [$attr_p.top^.text get 0.0 end]
	$text mark set insert 0.0

	## Focus on text widget
	focus $text
    }
    set return_code {
	if {$button_hit == 0} {
	    ## Extract information about parent class and attribute
	    set popup_toplevel_p [winfo toplevel $popup]
	    upvar #0 [set toplevel_p [winfo toplevel [winfo parent\
		    $popup_toplevel_p]]] toplevel_s
	    set class $toplevel_s(class^)
	    upvar #0 [set class_p $toplevel_s($class)] class_s
	    set attr $class_s(attr^)
	    set attr_p $class_s($attr)
	    if {[info exists class_s(uuids^)]} {
		set uuid [lindex $class_s(uuids^) 0]
	    } else {
		set uuid $class
	    }

	    # Run sanity check if text_list syntax
	    set syntax [unameit_get_attribute_syntax $class $attr]
	    set multiplicity [unameit_get_attribute_multiplicity $attr]
	    set widget_type [unameit_syntax_to_display_type $syntax\
		    $multiplicity]
	    if {[cequal $widget_type text_list]} {
		set value [unameit_get_list_from_text_widget $popup.text^\
			$uuid $attr]
	    } else {
		unameit_delete_trailing_newlines_from_text $popup.text^
		set value [$popup.text^ get 0.0 end]
	    }
	    unameit_check_syntax $class $attr $uuid $value db
	    unameit_set_${widget_type}_value $attr_p $value
	    unameit_automatic_apply $attr_p
	    if {[info exists class_s(uuids^)]} {
		unameit_set_object_description $toplevel_p\
			[lindex $class_s(uuids^) 0]
		unameit_update_ws_labels $toplevel_p $class_s(uuids^)
		unameit_refresh_preview_window
	    }
	}
    }
    ## We can't use OK as the default because we need to use Return as the
    ## return character in the text box.
    set button [unameit_popup_nonmodal_dialog $attr_p.text_dialog^\
	    $attr_p.label^ $attr_label $attr_label -1 {OK Cancel} $code\
	    $return_code {}]
}

#### 			Working set related routines

proc unameit_item_is {uuid type} {
    global unameitPriv

    ## Lazy evaluate these variables. We cannot call unameit_get_item_states
    ## until we have initialized the cache manager. We can't initialize the
    ## cache manager until we log in. We can't assume we are logged in when
    ## we create an interpreter, so we can't assign these variables when we
    ## create the interpreter.
    if {![info exists unameitPriv(created)]} {
	lassign [unameit_get_item_states] unameitPriv(created)\
		unameitPriv(updated) unameitPriv(deleted)
    }

    set item_state [unameit_get_item_state $uuid]
    
    switch $type {
	created {
	    return [expr $item_state&$unameitPriv(created)]
	}
	updated {
	    return [expr $item_state&$unameitPriv(updated)]
	}
	deleted {
	    return [expr $item_state&$unameitPriv(deleted)]
	}
    }
}

### This routine fill in the whole working set and sets the selection.
proc unameit_fill_in_ws_window {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 $toplevel_s($toplevel_s(class^)) class_s

    ## Nullify the listbox contents first
    $toplevel_p.working_set^.listframe^.fancylistbox delete 0 end

    set uuid_list [get_values_from_ordered_list class_s]

    set index 0
    foreach uuid $uuid_list {
	$toplevel_p.working_set^.listframe^.fancylistbox insert end\
		[unameit_get_label $uuid]
	unameit_set_listbox_item_state\
		$toplevel_p.working_set^.listframe^.fancylistbox $index $uuid
	incr index
    }
    unameit_update_ws_count $toplevel_p

    if {[info exists class_s(uuids^)]} {
	unameit_select_ws_entries $toplevel_p $class_s(uuids^)
    }
}

proc unameit_update_ws_count {toplevel_p} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 [set class_p $toplevel_s($toplevel_s(class^))] class_s

    set ws_count [ordered_list_size class_s]

    if {![lempty [set selection\
	    [$toplevel_p.working_set^.listframe^.fancylistbox\
	    curselection]]]} {
	set ws_selected [expr [lindex $selection 0]+1]
    }

    set msg "Count: "
    if {[info exists ws_selected]} {
	append msg "$ws_selected of "
    }
    append msg $ws_count
    $toplevel_p.working_set^.message^ configure -text $msg
}

proc unameit_update_ws_labels {toplevel_p uuid_list} {
    upvar #0 $toplevel_p toplevel_s
    upvar #0 $toplevel_s($toplevel_s(class^)) class_s

    foreach uuid $uuid_list {
	set index [get_index_from_ordered_list class_s $uuid]

	$toplevel_p.working_set^.listframe^.fancylistbox delete $index
	$toplevel_p.working_set^.listframe^.fancylistbox insert $index\
		[unameit_get_label $uuid]

	unameit_set_listbox_item_state\
		$toplevel_p.working_set^.listframe^.fancylistbox $index $uuid
    }

    if {[info exists class_s(uuids^)]} {
	unameit_select_ws_entries $toplevel_p $class_s(uuids^)
    } else {
	unameit_select_ws_entries $toplevel_p ""
    }
}

proc unameit_select_ws_entries {toplevel_p uuid_list} {
    upvar #0 $toplevel_p toplevel_s
    set class $toplevel_s(class^)
    upvar #0 [set class_p $toplevel_s($class)] class_s

    $toplevel_p.working_set^.listframe^.fancylistbox selection clear 0 end

    set count 0
    foreach uuid $uuid_list {
	set index [get_index_from_ordered_list class_s $uuid]
	$toplevel_p.working_set^.listframe^.fancylistbox selection set $index
	if {$count == 0} {
	    $toplevel_p.working_set^.listframe^.fancylistbox see $index
	}
	incr count
    }
    unameit_update_ws_count $toplevel_p
}

proc unameit_set_ws_uuids {toplevel_p uuids {append 0} {use_class ""}} {
    upvar #0 $toplevel_p toplevel_s

    if {[empty $use_class]} {
	set use_class $toplevel_s(class^)
    }

    upvar #0 [set class_p $toplevel_s($use_class)] class_s

    if {$append} {
	## Eliminate duplicates
	eval add_to_ordered_list class_s $uuids
    } else {
	eval set_ordered_list class_s $uuids
    }

    eval set_ordered_list class_s [unameit_sort_uuids\
	    [get_values_from_ordered_list class_s]]
}


####			Miscellaneous

proc unameit_set_completion_value {uuid_list} {
    global unameitPriv

    if {[llength $uuid_list] == 1} {
	set uuid [lindex $uuid_list 0]
	array set tmp [unameit_get_attribute_values $uuid new Class]
	set class $tmp(Class)
	set unameitPriv(complete^$class) $uuid
    }
}

### For queries, this routine inspects the value and returns the operator
### to use in the query.
proc unameit_get_operator {class attr value} {
    set syntax [unameit_get_attribute_syntax $class $attr]
    set mult [unameit_get_attribute_multiplicity $attr]

    if {[cequal $mult Scalar]} {
	switch -- $syntax {
	    string -
	    address -
	    enum -
	    choice -
	    text -
	    code {
		if {[regexp {[*?]} $value]} {
		    return ~
		} else {
		    return =
		}
	    }
	    default {
		return =
	    }
	}
    } else {
	#
	# Contains is the most natural for UI queries on sets
	#
	return contains
    }
}

proc unameit_fuzzy_time {time} {
    #
    # Use %Y to avoid year 2000 problems, also %D is UNIX specific
    # (see Tcl docs on clock command)
    #
    lassign [clock format $time -format {%m/%d/%Y %H %M %S}] day hour min sec

    if {$hour == 0 && $min == 0 && $sec == 0} {
	set start [clock scan $day]
	set end [clock scan "$day + 1 day"]
    } else {
	set start [clock scan "$day $hour:00"]
	set end [clock scan "$day $hour:00 + 1 hour"]
    }
    return [list $start $end]
}

proc unameit_list_has_regexps {list} {
    foreach value $list {
	if {[regexp {[*?]} $value]} {
	    return 1
	}
    }
    return 0
}

proc unameit_welcome_text {} {
    append result "                         Welcome to UName*It\
	    [unameit_get_server_version]\n"
    append result "      Copyright \251 1995, 1996, 1997 Enterprise\
	    Systems Management Corp.\n"
    append result "                         All rights reserved.\n\n"
    return $result
}

### The contents of the greeting window are cached in case we get
### disconnected from the server. In this case, we can still display the
### greeting window information. The greeting is displayed on the first screen
### after logging in so after immediately logging in the cache is populated.
proc unameit_get_greeting_window_info {} {
    global unameitPriv(greeting)

    if {![info exists unameitPriv(greeting)]} {

	## This invalidates old clients
	if {[catch {unameit_get_cache_mgr_version} v] || $v < 3.0} {
	    tk_dialog .wrongversion {Wrong Version}\
		    {Using old version of unameit with new TOI} error 0 OK
	    exit 1
	}
	append unameitPriv(greeting) [unameit_welcome_text]
	append unameitPriv(greeting) [unameit_get_license_terms]
    }

    return $unameitPriv(greeting)
}

proc unameit_is_prot_or_comp {class attr} {
    return [expr [unameit_isa_protected_attribute $attr] ||\
	    [unameit_isa_computed_attribute $class $attr]]
}

## Set the buttons on the main window to enable or disabled
proc unameit_set_buttons {widget state args} {
    foreach button $args {
	$widget.button_bar^.[s2w $button] configure -state $state
    }
}

### Newly created items get their updated label; old items get the database
### label.
proc unameit_get_label {uuid} {
    if {[unameit_item_is $uuid created]} {
	return [unameit_get_new_label $uuid]
    } else {
	return [unameit_get_db_label $uuid]
    }
}

proc unameit_set_ws_bindings {toplevel_p} {
    foreach tuple {{Control-p -1} {Control-n 1} {Up -1} {Down 1}} {
	lassign $tuple key_seq relative
	bind $toplevel_p <$key_seq> [list unameit_wrapper\
		[list unameit_advance_ws_selection $toplevel_p $relative]]
    }
}

proc unameit_unset_ws_bindings {toplevel_p} {
    foreach key_seq {Control-p Control-n Up Down} {
	bind $toplevel_p <$key_seq> ""
    }
}

proc unameit_get_canon_style {widget} {
    upvar #0 [winfo toplevel $widget] toplevel_s

    assert {[info exists toplevel_s(mode^)]}

    if {[cequal $toplevel_s(mode^) item]} {
	return display
    } else {
	return query
    }
}

proc unameit_mail_bug_report {msg errorCode errorInfo} {
    if {[file exists /usr/bin/mailx]} {
	set mailprog /usr/bin/mailx
    } elseif {[file exists /bin/mailx]} {
	set mailprog /bin/mailx
    } elseif {[file exists /usr/ucb/Mail]} {
	set mailprog /usr/ucb/Mail
    } elseif {[file exists /usr/ucb/mail]} {
	set mailprog /usr/ucb/mail
    } else {
	return
    }
    exec $mailprog unameit-traces@esm.com << [format\
	    "%s\nerrorCode: %s\nerrorInfo:\n%s" $msg $errorCode $errorInfo]
}

proc unameit_popup_error_dialog {button_list default text} {
    unameit_popup_modal_dialog .error Error Error $default $button_list\
	    [format {
	## Create top
	set top [frame $w.top^ -relief raised -bd 1]
	pack $top -side top -fill both -expand 1

	## Add message
	option add *Dialog.msg^.wrapLength 6i widgetDefault
	set msg [label $w.msg^ -justify left -text %s]
	pack $msg -in $top -side right -expand 1 -fill both -padx 3m -pady 3m

	## Add error bitmap
	set bitmap [label $w.bitmap^ -bitmap error]
	pack $bitmap -in $top -side left -padx 3m -pady 3m
    } [list $text]] {}
}

proc bgerror {msg} {
    global errorCode errorInfo
    
    set savederrorCode $errorCode
    set savederrorInfo $errorInfo

    ## Handle errors internally generated by the TOI.
    lassign $errorCode esys ecode
    switch -- $esys.$ecode {
	UNAMEIT.EIGNORE {
	    # EIGNORE is used to break out of callbacks
	    return
	}
	UNAMEIT.ELITERALERROR {
	    unameit_popup_error_dialog OK 0 $msg
	    return
	}
    }
    switch -- [unameit_error_get_text msg $errorCode] {
	other -
	unknown {
	    set text "Unknown error occurred:\n$msg" 
	    if {[unameit_popup_error_dialog {OK {Send bug report}} 1 $text]
	    == 1} {
		unameit_mail_bug_report $msg $savederrorCode $savederrorInfo
	    }
	}
	internal {
	    set text "Internal error occurred\n$msg"
	    if {[unameit_popup_error_dialog {OK {Send bug report}} 1 $text]
	    == 1} {
		unameit_mail_bug_report $msg $savederrorCode $savederrorInfo
	    }
	}
	default {
	    unameit_popup_error_dialog OK 0 $msg
	}
    }
}

proc unameit_get_enumeration_values {class attr} {
    return [unameit_get_attribute_mdata_fields $class $attr\
	    unameit_enum_attribute_values]
}

proc unameit_widget_size {w orientation_opt} {
    expr [$w cget $orientation_opt] +\
	    2*([$w cget -bd] + [$w cget -highlightthickness])
}

proc unameit_get_main_menu_data {} {
    set menu_data(New^) {Special New}
    set menu_data(Dismiss^) {Special Dismiss}
    set menu_data(Exit^) {Special Exit}
    set menu_data(Connect^) {Special Connect}
    set menu_data(Login^) {Special {Log In}}
    set menu_data(About^) {Special About}
    set menu_data(Preview^) {Special Preview}
    set menu_data(Save^) {Special Save}
    
    array set menu_class_info [unameit_menu_info]

    foreach uuid [array names menu_class_info] {
	lassign $menu_class_info($uuid) class label group
	if {[empty $group] || [empty $label]} {
	    continue
	}
	set menu_data($class) [list $group $label]
    }

    array get menu_data
}

proc unameit_is_standard_menu_field {field} {
    string match *^ $field
}

proc unameit_syntax_to_display_type {syntax multiplicity} {
    set map(string.Scalar) entry
    set map(string.Set) text_list
    set map(string.Sequence) text_list
    set map(integer.Scalar) entry
    set map(integer.Set) text_list
    set map(integer.Sequence) text_list
    set map(autoint.Scalar) entry
    set map(address.Scalar) entry
    set map(enum.Scalar) radio_box
    set map(enum.Set) check_box
    set map(list.Scalar) text_list
    set map(qbe.Scalar) nested_window
    set map(rspec.Scalar) text_list
    set map(vlist.Scalar) text_list
    set map(pointer.Scalar) menu
    set map(pointer.Set) list_box
    set map(pointer.Sequence) list_box
    set map(choice.Scalar) choice
    set map(text.Scalar) text
    set map(code.Scalar) text
    set map(time.Scalar) entry

    if {[info exists map($syntax.$multiplicity)]} {
	return $map($syntax.$multiplicity)
    }

    error "Don't know how to display $multiplicity $syntax"
}

proc unameit_set_focus {class_p} {
    upvar #0 $class_p class_s
    set toplevel_p [winfo toplevel $class_p]
    set class $class_s(class^)

    if {![info exists class_s(attr^)]} {
	if {[llength $class_s(focus_list^)] == 0} {
	    focus $toplevel_p
	    return
	}
	set class_s(attr^) [lindex $class_s(focus_list^) 0]
    }
    set attr $class_s(attr^)
    set attr_p $class_s($attr)
    set widget_type [unameit_get_widget_type $class $attr]
    focus [lindex [unameit_get_main_${widget_type}_widget $attr_p] 0]
}

proc unameit_iterate_over_class {class_p body} {
    upvar #0 $class_p class_s

    set class $class_s(class^)

    foreach attr [unameit_get_displayed_attributes $class] {
	set syntax [unameit_get_attribute_syntax $class $attr]
	set multiplicity [unameit_get_attribute_multiplicity $attr]
	set widget_type [unameit_syntax_to_display_type $syntax $multiplicity]
	upvar #0 [set attr_p $class_s($attr)] attr_s
	set attr $attr_s(attr^)

	eval $body
    }
}

proc unameit_iterate_over_enums {attr_p body} {
    upvar #0 $attr_p attr_s
    upvar #0 [set class_p $attr_s(class_state^)] class_s
    set class $class_s(class^)
    set attr $attr_s(attr^)

    set enums [unameit_get_enumeration_values $class $attr]

    for {set i 0} {$i < [llength $enums]} {incr i} {
	set enum [lindex $enums $i]
	set widget $attr_p.[s2w $enum]

	eval $body
    }
}

proc unameit_get_widget_type {class attr} {
    set syntax [unameit_get_attribute_syntax $class $attr]
    set multiplicity [unameit_get_attribute_multiplicity $attr]
    return [unameit_syntax_to_display_type $syntax $multiplicity]
}

### Same as apply_focus_field except it only applies the focus field if the
### focus is on a different attribute
proc unameit_apply_focus_field_if_different_attr {attr_p} {
    set toplevel_p [winfo toplevel $attr_p]

    upvar #0 [focus -lastfor $toplevel_p] widget_s
    set focus_attr_p $widget_s(attr_state^)

    if {[cequal $attr_p $focus_attr_p]} return

    unameit_apply_focus_field $toplevel_p
}

### This routine does an automatic apply on the field with the focus.
### The display_dialog_box parameter is simply passed to
### unameit_automatic_apply. That routine uses it to put up a dialog box
### if the attribute has changed (only for pointer fields).
proc unameit_apply_focus_field {toplevel {display_dialog_box 0}} {
    global unameitPriv
    upvar #0 $toplevel toplevel_s

    switch $toplevel_s(mode^) {
	item -
	query {}
	default {
	    return
	}
    }

    set focus [focus -lastfor $toplevel]

    upvar #0 $focus attr_s

    unameit_automatic_apply $attr_s(attr_state^) $display_dialog_box
}

proc unameit_switch_focus {widget} {
    upvar #0 $widget widget_s
    upvar #0 $widget_s(attr_state^) attr_s
    upvar #0 $attr_s(class_state^) class_s
    upvar #0 [set toplevel_p [winfo toplevel $widget]] toplevel_s

    set class $class_s(class^)
    set attr $attr_s(attr^)

    set mode $toplevel_s(mode^)
    set widget_type [unameit_get_widget_type $class $attr]

    ## Don't focus on protected/computed fields in item mode. We can't.
    if {[cequal $mode query] || ([cequal $mode item] &&
    ![unameit_is_prot_or_comp $class $attr])} {
	focus $widget
	set class_s(attr^) $attr
    }
}

# $ Header: /u/ra/raines/cvs/tk/fancylb/fancylb.tk,v 1.3 1996/01/30 03:49:32 raines Exp $
####################################################################
#
# FANCYLB.TK v2.0	- by Paul Raines
#
# This file contains code for a "listbox" using the text widget that
# supports all features of the normal tk4.0 listbox along with some
# additional features such as text tags and embedded windows. For the
# most part, you can replace your normal 'listbox' command with
# 'fancylistbox'. See the include README file for details.
#
#
# COPYRIGHT:
#     Copyright 1993-1996 by Paul Raines (raines@slac.stanford.edu)
#
#     Permission to use, copy, modify, and distribute this
#     software and its documentation for any purpose and without
#     fee is hereby granted, provided that the above copyright
#     notice appear in all copies.  The University of Pennsylvania
#     makes no representations about the suitability of this
#     software for any purpose.  It is provided "as is" without
#     express or implied warranty.
#
# DISCLAIMER:
#     UNDER NO CIRCUMSTANCES WILL THE AUTHOR OF THIS SOFTWARE OR THE
#     UNIVERSITY OF PENNSYLVANIA BE RESPONSIBLE FOR ANY DIRECT OR
#     INCIDENTAL DAMAGE ARISING FROM THE USE OF THIS SOFTWARE AND ITS
#     DOCUMENTATION. THE SOFTWARE HEREIN IS PROVIDED "AS IS" WITH NO
#     IMPLIED OBLIGATION TO PROVIDE SUPPORT, UPDATES, OR MODIFICATIONS.
#
# HISTORY:
#  v1.0 
#     93-08-25    released original version
#
#  v1.1
#     93-08-26	  fixed configure bug
#		  added offset option to curselection
#
#  v1.2
#     93-09-28    added flb_convndx to handle "end" index and errors
#		    (thanks to Norm (N.L.) MacNeil)
#		  created 'destroy' procedure to safely destroy widget
#		    and added catches to all 'renames'
#		  added configure option -selectrelief to specify
#		    relief for selection tag
#		  fixed problem with deleting last element when
#		    it was the single selection
#     93-12-08    changed so configure will return results
#
#  v1.3
#     94-05-17    added "item configure" and "item clear" commands
#
#  v1.4
#     94-06-18    fixed bug with delete removing selline tag
#
#  v1.5
#     94-11-15    fixed insert bug with curtndx
#
#  v2.0 (Renamed to fancylistbox)
#     96-01-14    updated to tk4.0 listbox interface
#		  moved several commands out of case statement to
#		    speed up processing of Listbox bindings
#
#     96-01-15    added support for embedded windows and searches
#
#  v2.1
#     96-01-27    fixed item configure bug with tags
#		  fixed "end" index bug
#		  update get command to tk4.0
#		  added "selection at"
#
###############################################################

proc flb_init {} {
    global flb
    set flb(debug) 0
    set flb(version) 2.0
    bind Flb_Bind <FocusIn> {
      %W_text tag configure activetag -underline 1
    }
    bind Flb_Bind <FocusOut> {
      %W_text tag configure activetag -underline 0
    }
    bind Flb_Bind <KeyPress> {
      set flb(presscur) $flb(%W,curtndx)
      set flb(worry) 0
    }
    bind Flb_Bind <ButtonPress> {
      set flb(presscur) $flb(%W,curtndx)
    }
    bind Flb_Bind <B1-Motion> {
      set flb(worry) 0
    }
    bind Flb_Bind <ButtonRelease-1> {
      flb_selection %W 3 selection worry
    }
    bind Flb_Bind <KeyRelease> {
      flb_selection %W 3 selection worry
    }
    bind Flb_Label <ButtonPress> {
      set flb(presscur) $flb($flb(%W,list),curtndx)
    }
    bind Flb_Label <B1-Motion> {
      set flb(worry) 0
      set tkPriv(x,y) [flb_convcoord_lbl %W @%x,%y]
      scan $tkPriv(x,y) "@%%d,%%d" tkPriv(x) tkPriv(y)
      tkListboxMotion $flb(%W,list) [$flb(%W,list) index $tkPriv(x,y)]
      break
    }
    bind Flb_Label <B1-Leave> {
      scan [flb_convcoord_lbl %W @%x,%y] "@%%d,%%d" tkPriv(x) tkPriv(y)
      tkListboxAutoScanLBL $flb(%W,list)
      break
    }
    bind Flb_Label <ButtonRelease-1> {
      flb_selection $flb(%W,list) 3 selection worry
    }
}

proc flb_configure { flbname args } {
  global flb

  if {[set ndx [lsearch $args -selectrelief]] != -1} {
    set flb($flbname,selectrelief) [lindex $args [expr $ndx+1]]
    set args [lreplace $args $ndx [expr $ndx+1]]
  }
  if {[set ndx [lsearch $args -selectmode]] != -1} {
    set flb($flbname,selectmode) [lindex $args [expr $ndx+1]]
    set args [lreplace $args $ndx [expr $ndx+1]]
  }

  set ret [eval "${flbname}_text configure $args"]

  ${flbname}_text configure -insertbackground \
      [${flbname}_text cget -background]

  ${flbname}_text tag configure selline \
      -background  [${flbname}_text cget -selectbackground] \
      -foreground  [${flbname}_text cget -selectforeground] \
      -borderwidth [${flbname}_text cget -selectborderwidth] \
      -relief $flb($flbname,selectrelief)

  return $ret
}

proc flb_confget { flbname args } {
  global flb

  if [llength $args] {set all 0} else {set all 1}
  set ret {}

  if {[set ndx [lsearch $args -selectrelief]] != -1 || $all} {
    lappend ret [list -selectrelief selectRelief Relief \
		     flat $flb($flbname,selectrelief)]
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }
  if {[set ndx [lsearch $args -selectmode]] != -1 || $all} {
    lappend ret [list -selectmode selectMode SelectMode browse \
		     $flb($flbname,selectmode)]
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }

  if {[llength $args] || $all} {
    set ret [concat $ret [eval "${flbname}_text configure $args"]]
  }

  return $ret
}

proc flb_cget { flbname args } {
  global flb

  if [llength $args] {set all 0} else {set all 1}
  set ret {}

  if {[set ndx [lsearch $args -selectrelief]] != -1 || $all} {
    lappend ret $flb($flbname,selectrelief)
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }
  if {[set ndx [lsearch $args -selectmode]] != -1 || $all} {
    lappend ret $flb($flbname,selectmode)
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }

  if {[llength $args] || $all} {
    set ret [concat $ret [eval "${flbname}_text cget $args"]]
  }

  return $ret
}

# the actual creation of fancy listbox procedure
proc fancylistbox { flbname args } {
  global flb

  text $flbname
  $flbname mark set active 1.0
  $flbname mark set anchor 1.0
  $flbname mark gravity anchor left
  $flbname configure -wrap none -cursor left_ptr
  $flbname tag configure activetag -underline 0

  if {[catch "rename $flbname ${flbname}_text" errmsg]} {
    rename ${flbname}_text {}
    rename $flbname ${flbname}_text
  }

  set flb($flbname,curtndx) 0.0
  set flb($flbname,selectrelief) raised
  set flb($flbname,tags) 0
  set flb($flbname,selectmode) browse
  
  eval "flb_configure $flbname $args"

  # Set up default bindings    
  bindtags ${flbname} \
      "${flbname} Flb_Bind Listbox [winfo toplevel $flbname] all"
  bind $flbname <Destroy> "flb_destroy $flbname"

  # setup the procedure
  proc $flbname {args} "eval \"flb_process $flbname \$args\""

  if {![info exist flb(worry)]} { 
    set flb(worry) 1 
    set flb(presscur) 0.0
  }
  return $flbname
}

# convert a listbox index to text index
proc flb_convndx {flbname lndx} {
  if {$lndx == "end"} {
    return [${flbname}_text index "end-2l linestart"]
  } elseif {$lndx == "active"} {
    return [${flbname}_text index active]
  } elseif {$lndx == "anchor"} {
    return [${flbname}_text index anchor]
  } elseif {[string first . $lndx] == 0} {
    return [${flbname}_text index $lndx]
  } elseif {[string first @ $lndx] > -1} {
    if {[catch "${flbname}_text index $lndx" res]} {
      error "bad listbox index in $flbname: $lndx"
    } else {
      return $res
    }    
  } else {
    if {[catch "expr $lndx+1" res]} {
      error "bad listbox index in $flbname: $lndx"
    } else {
      return $res.0
    }
  }
}

proc flb_selection {flbname cnt args} {
  global flb

  if {$cnt == 1} {
    error "too few args: should be \"$flbname selection option ?index?\""
  }

  set lastcur $flb($flbname,curtndx)
  case [lindex $args 1] {
    {anchor} {
      if {$cnt == 3} {
	set ndx [flb_convndx $flbname [lindex $args 2]]
	${flbname}_text mark set anchor "$ndx linestart"
      } else {
	error "wrong # args: should be $flbname selection anchor index"
      }
    }
    {clear} {
      if {$cnt > 1 && $cnt < 5} {
	if {[llength $args] == 2} {
	  ${flbname}_text tag remove selline 0.0 end
	  set flb($flbname,curtndx) 0.0
	} else {
	  set fndx [flb_convndx $flbname [lindex $args 2]]
	  if {$cnt == 4} {
	    set lndx [flb_convndx $flbname [lindex $args 3]]
	  } else { set lndx $fndx }
	  if {[${flbname}_text compare $fndx >= $lndx]} {
	    set ndx $fndx; set fndx $lndx; set lndx $ndx
	  }
	  ${flbname}_text tag remove selline $fndx \
	      [${flbname}_text index "$lndx lineend + 1 chars"]
	  if {[${flbname}_text compare $lastcur >= $fndx] &&
	      [${flbname}_text compare $lastcur <= $lndx]} {
	    set flb($flbname,curtndx) 0.0
	  }
	}
      } else {
	error "wrong # args: should be $flbname selection clear ?first? ?last?"
      }
    }
    {includes} {
      if {$cnt == 3} {
	set ndx [flb_convndx $flbname [lindex $args 2]]
	if {[lsearch [${flbname}_text tag names $ndx] selline] > -1} {
	  return 1
	} else {return 0}
      } else {
	error "wrong # args: should be $flbname selection includes index"
      }
    }
    {set at} {
      if {$cnt == 3 || $cnt == 4} {
	set start [lindex $args 2]
	if {$cnt == 4} {
	  set stop [lindex $args 3]
	} else { set stop $start }

	set fndx [flb_convndx $flbname $start]
	set lndx [flb_convndx $flbname $stop]
	if {[${flbname}_text compare $fndx >= $lndx]} {
	    set ndx $fndx; set fndx $lndx; set lndx $ndx
	}
	set fndx [${flbname}_text index "$fndx linestart"]
	if {[${flbname}_text compare $fndx >= "end -1l linestart"]} {
	  set fndx [${flbname}_text index "$fndx -1l linestart"]
	}

	if {[lsearch {single browse} $flb($flbname,selectmode)] > -1} {
	  ${flbname}_text tag remove selline 0.0 end
	  set flb($flbname,curtndx) 0.0
	}

	${flbname}_text tag add selline $fndx \
	    [${flbname}_text index "$lndx lineend + 1 chars"]
	${flbname}_text tag remove selline "end -1l linestart" end

	if {[lindex $args 1] == "at" || \
		($flb($flbname,curtndx) == 0.0 && $flb(worry))} {
	  set flb($flbname,curtndx) $fndx
	  set flb(presscur) $fndx
	}
      } else {
	error "wrong # args: should be $flbname selection set first ?last?"
      }
    }
    {worry} { set flb(worry) 1 }
    default {
      error "bad select option: must be anchor, clear, includes or set"
    }
  }

  set worry [expr "$flb($flbname,curtndx) == 0.0 && $flb(worry)"]
  if {$flb($flbname,curtndx) != $lastcur || $worry} {
    if {$lastcur != 0.0} {
      ${flbname}_text insert $lastcur+1c " "
      ${flbname}_text delete $lastcur
    }
    if {$worry} {
      if {[lsearch [${flbname}_text tag names $flb(presscur)] selline] > -1} {
	set flb($flbname,curtndx) $flb(presscur)
      }	else {
	set rngs [${flbname}_text tag ranges selline]
	if {[string length $rngs]} {
	  foreach tndx $rngs {
	    if {$flb(presscur) < $tndx} {
	      set flb($flbname,curtndx) $tndx
	      set flb(presscur) $tndx
	      break
	    }
	  }
	  if {$flb($flbname,curtndx) == 0.0} {
	    set tndx [lindex $rngs [expr [llength $rngs]-1]]
	    set flb($flbname,curtndx) [${flbname}_text index $tndx-1l]
	    set flb(presscur) $flb($flbname,curtndx)
	  }
	}
      }
    }
    if {$flb($flbname,curtndx) != 0.0} {
      ${flbname}_text insert $flb($flbname,curtndx)+1c ">"
      ${flbname}_text delete $flb($flbname,curtndx)
    }
  }

  # ${flbname}_text delete "end -1l linestart" "end -1c"
  return {}
}

proc flb_delete {flbname cnt args} {
  global flb
  if {$cnt > 1 && $cnt < 4} {
    set lndx ""
    set ndx [flb_convndx $flbname [lindex $args 1]]
    if {[llength $args] == 3} {
      if {[lindex $args 1] == "end"} {return ""}
      set lndx [flb_convndx $flbname [lindex $args 2]]
    } else {
      set lndx $ndx
    }

    # Remove useless item tags, but not the selline tag
    set tndx $ndx
    while {[${flbname}_text compare $tndx <= $lndx] && \
	       [${flbname}_text compare $tndx < end]} {
      set tagname [flb_itemtag $flbname $tndx 1]
      if [string length $tagname] {
	${flbname}_text tag delete $tagname
      }
      set tndx [${flbname}_text index "$tndx +1l"]
    }

    ${flbname}_text delete $ndx "$lndx lineend +1c"

    # see if we still have "first" selection and adjust
    if {$flb($flbname,curtndx) >= $ndx && $flb($flbname,curtndx) <= $lndx} {
      set flb($flbname,curtndx) 0.0
      set rngs [${flbname}_text tag ranges selline]
      if {[string length $rngs]} {
	for {set i 0} {$i < [llength $rngs]} {incr i 2} {
	  set tndx [lindex $rngs $i]
	  if {$ndx <= $tndx} {
	    set flb($flbname,curtndx) $tndx
	    break
	  }
	}
	if {$flb($flbname,curtndx) == 0.0} {
	  set tndx [lindex $rngs [expr [llength $rngs]-1]]
	  set flb($flbname,curtndx) [${flbname}_text index $tndx-1l]
	}
	${flbname}_text insert $flb($flbname,curtndx)+1c ">"
	${flbname}_text delete $flb($flbname,curtndx)
      }
    } elseif {$flb($flbname,curtndx) > $lndx} {
      set tmp [expr [lindex [split $lndx .] 0]-[lindex $args 1]]
      set flb($flbname,curtndx) [${flbname}_text index $flb($flbname,curtndx)-${tmp}l]
    }
    return ""
  } else {
    error "wrong # args: should be $flbname delete first ?last?"
  } 
}

proc flb_itemtag {flbname ndx {query 0}} {
  global flb

  set tagname [${flbname}_text tag names $ndx]
  set gndx [lsearch -glob $tagname flbtag*]
  if {$gndx < 0} {
    if $query {
      set tagname {}
    } else {
      set tagname flbtag[incr flb($flbname,tags)]
      ${flbname}_text tag add $tagname $ndx "$ndx lineend"
    }
  } else {
    set tagname [lindex $tagname $gndx]
  }
  return $tagname
}

proc flb_item {flbname cnt args} {
  global flb

  if {$cnt == 1} {
    error "too few args: should be $flbname item option ?arg arg ...?"
  }
  set cmd [lindex $args 1]

  if {$cmd == "configure"} {
    if {$cnt > 2} {
      set ndx [flb_convndx $flbname [lindex $args 2]]
      set tagname [flb_itemtag $flbname $ndx 0]
      eval "${flbname}_text tag configure $tagname [lrange $args 3 end]"
    } else {
      error "wrong # args: should be $flbname item configure index ?option value ...?"
    }
    return ""
  }
  if {$cmd == "clear"} {
    if {$cnt > 2} {
      foreach item [lrange $args 2 end] {
	set ndx [flb_convndx $flbname $item]
	set tagname [flb_itemtag $flbname $ndx 1]
	if {[string length $tagname]} {
	  ${flbname}_text tag delete $tagname
	}
      }
    } else {
      error "wrong # args: should be $flbname item clear index ?index ...?"
    }
    return ""
  }

  error "bad item option: must be configure or clear"
}

proc flb_window {flbname cnt args} {
  global flb

  set opt [lindex $args 1]
  if {$opt == "names"} {
    return [${flbname}_text window names]
  }
  if {[lsearch {cget configure create} $opt] < 0} {
    error "bad window option: must be cget, configure, create or names"
  }
  set ndx [lindex $args 2]
  set char 0
  if {[string first . $ndx] > 0} {
    set ndx [split $ndx .]
    set char [lindex $ndx 1]
    set ndx [lindex $ndx 0]
  }
  incr char ;# get past '>' column
  set ndx [flb_convndx $flbname $ndx]
  set max [${flbname}_text index "$ndx lineend"]
  set ndx [${flbname}_text index "$ndx linestart +${char}c"]
  if [${flbname}_text compare $ndx > $max] { set ndx $max }
  set fargs [lrange $args 3 end]
  set ret [eval "${flbname}_text window $opt $ndx $fargs"]
  set w [${flbname}_text window cget $ndx -window]
  if [info exists flb($w,list)] {
    set flb($w,list) $flbname
  }
  return $ret
}

proc flb_search {flbname cnt args} {
  global flb

  foreach opt {-forw -back -count} {
    if {[string first $opt $args] > -1} {
      error "invalid search switch: should be -exact, -regexp, or -nocase"
    }
  }

  for {set i 1} {[string first - [lindex $args $i]] == 0} {incr i} { }
  incr i
  if {$i != $cnt} {
    error "wrong # args: should be $flbname search ?switches? pattern"
  }
  set fargs [lrange $args 1 end]

  set flist {}
  set start 1.0
  set tw ${flbname}_text
  while {[string length [set ndx [eval "$tw search $fargs $start end"]]]} {
    set start [$tw index "$ndx lineend +1c"]
    set y [lindex [split $ndx .] 0]
    incr y -1
    lappend flist $y
  }

  return $flist
}

proc flb_destroy {flbname} {
  if {[winfo exists $flbname]} {
    destroy $flbname
  }
  catch "rename ${flbname}_text {}"
  catch "rename $flbname {}"
}

# setup the procedure
proc flb_process {flbname args} {
  global flb

  # puts stderr "FAKE: $args"

  set cnt [llength $args]
  set cmd [lindex $args 0]

  if {[lsearch {scan xview yview compare tag} $cmd] > -1} {
    return [eval "${flbname}_text $args"]
  }

  if {$cmd == "index"} {
    if {$cnt == 2} {
      set ndx [flb_convndx $flbname [lindex $args 1]]
      return [expr [lindex [split $ndx .] 0]-1]
    } else {
      error "wrong # args: should be $flbname index index"
    }
  }

  if {$cmd == "selection"} {
    return [eval "flb_selection $flbname $cnt $args"]
  }

  if {$cmd == "cget"} {
      return [flb_cget $flbname [lindex $args 1]]
  }

  if {$cmd == "activate"} {
    set ndx [flb_convndx $flbname [lindex $args 1]]
    if {[${flbname}_text compare $ndx >= "end -1l linestart"]} {
      set ndx [${flbname}_text index "$ndx -1l linestart"]
    }
    ${flbname}_text tag remove activetag 0.0 end
    ${flbname}_text mark set active $ndx
    ${flbname}_text tag add activetag "$ndx linestart" "$ndx lineend"
    return ""
  }

  case $cmd {
    {delete item window search} {
      return [eval "flb_$cmd $flbname $cnt $args"]
    }
    {bbox} {
      set ndx [flb_convndx $flbname [lindex $args 1]]
      return [lrange [${flbname}_text dlineinfo $ndx] 0 3]
    }
    {configure} {
      if {$cnt < 2} {
	return [eval "flb_confget $flbname [lrange $args 1 end]"]
      } else {
	return [eval "flb_configure $flbname [lrange $args 1 end]"]
      }
    }
    {cursingle} {
      if {$cnt == 1} {
	# return empty if no "first" selection
	if {$flb($flbname,curtndx) == 0.0} {return ""}
	set ndx [lindex [split $flb($flbname,curtndx) .] 0]
	return [expr $ndx-1]
      } else {
	error "wrong # args: should be $flbname cursingle"
      } 
    }
    {curselection} {
      if {$cnt > 0 && $cnt < 3} {
	# return list of selected item indices
	if {$cnt == 2} {
	  set offset [lindex $args 1]
        } else {
	  set offset 0
	}
	set lsel ""
	set ranges [${flbname}_text tag ranges selline]
	for {set line 0} {$line < [llength $ranges]} {incr line} {
	  set ndx [lindex [split [lindex $ranges $line] .] 0]
	  incr line
	  set last [lindex [split [lindex $ranges $line] .] 0]
	  for {set i $ndx} {$i < $last} {incr i} {
	    lappend lsel [expr $i-1+$offset] 
	  }    
	}
	return $lsel
      } else {
	error "wrong # args: should be $flbname cursingle"
      } 
    }
    {debug} { set flb(debug) [lindex $args 1]}
    {destroy} {
      if {$cnt == 1} {
        if {[winfo exists $flbname]} {
	  destroy $flbname
	}
        catch "rename ${flbname}_text {}"
	catch "rename $flbname {}"
      } else {
	error "wrong # args: should be $flbname destroy"
      } 
    }
    {get} {
      if {$cnt == 2 || $cnt == 3} {
	set ndx [flb_convndx $flbname [lindex $args 1]]
	if {$cnt == 3} {
	  set lndx [flb_convndx $flbname [lindex $args 2]]
	} else { set lndx $ndx }
	set result {}
	set tndx $ndx
	while {[${flbname}_text compare $tndx <= $lndx] && \
		   [${flbname}_text compare $tndx < end]} {
	  lappend result [${flbname}_text get $tndx+1c "$tndx lineend"]
	  set tndx [${flbname}_text index "$tndx +1l"]
	}
	return $result
      } else {
	error "wrong # args: should be $flbname get first ?last?"
      } 
    }
    {insert} {
      if {$cnt > 2} {
        set ndx [lindex $args 1]
        if {$ndx == "end"} {
	  set ndx [${flbname}_text index end]
        } else {
	  set ndx [flb_convndx $flbname $ndx]
        }
	if {$ndx <= $flb($flbname,curtndx)} { 
	  set flb($flbname,curtndx) \
	      [expr $flb($flbname,curtndx)+[llength $args]-2]
	}
	set start $ndx
	foreach line [lrange $args 2 end] {
	  ${flbname}_text insert $ndx " $line\n"
	  set ndx [${flbname}_text index $ndx+1l]
	}
	${flbname}_text tag remove selline $start $ndx
	return ""
      } else {
        if {$cnt == 1} {
	  error "wrong # args: should be $flbname insert index ?element ...?"
	}
      } 
    }
    {isselected} {
      if {$cnt != 2} {
	error "wrong number of args: should be $flbname isselected ndx"
      }
      set ndx [flb_convndx $flbname [lindex $args 1]]
      if {[lsearch [${flbname}_text tag names $ndx] selline] > -1} {
	return 1
      } else {return 0}
    }
    {nearest} {
      if {$cnt == 2} {
	set y [lindex $args 1]
	set ndx [${flbname}_text index @0,$y]
	set ndx [expr [lindex [split $ndx .] 0]-1]
	set sz [${flbname}_text index end]
	set sz [expr [lindex [split $sz .] 0]-1]
	if {$ndx >= $sz} {set ndx [expr $sz-1]}
	return $ndx
      } else {
	error "wrong # args: should be $flbname nearest y"
      } 
    }
    {see} {
      if {$cnt == 2} {
	set ndx [flb_convndx $flbname [lindex $args 1]]
	${flbname}_text see $ndx
      } else {
	error "wrong # args: should be $flbname see y"
      }
    }
    {size} {
      if {$cnt == 1} {
	set ndx [flb_convndx $flbname end]
	return [lindex [split $ndx .] 0]
      } else {
	error "wrong # args: should be $flbname size"
      } 
    }
    default {
      error "bad option \"[lindex $args 0]\": should be [list activate, \
	  bbox, cget, configure, cursingle, curselection, delete, get, index, \
          insert, nearest, scan, selection, size, or yview]"
    }
  }
}

proc fancylabel { flblname args } {
  global flb

  label $flblname
  $flblname configure -cursor left_ptr 
  eval "$flblname configure $args"

  if {[catch "rename $flblname ${flblname}_label" errmsg]} {
    rename ${flblname}_label {}
    rename $flblname ${flblname}_label
  }

  set flb($flblname,list) {}
  
  # Set up default bindings    
  bindtags ${flblname} \
      "${flblname} Flb_Label Listbox [winfo toplevel $flblname] all"
  bind $flblname <Destroy> "flb_destroy_lbl $flblname"

  # setup the procedure
  proc $flblname {args} "eval \"flb_process_lbl $flblname \$args\""

}

proc flb_convcoord_lbl {flblname ndx} {
  global flb
  if {[string first @ $ndx] != 0} {return $ndx}
  scan $ndx "@%d,%d" x y
  set lb $flb($flblname,list)
  set adj [${lb}_text bbox $flblname]
  if ![llength $adj] { set adj {0 0} }
  set ndx @[expr $x+[lindex $adj 0]],[expr $y+[lindex $adj 1]]
  return $ndx
}

proc tkListboxAutoScanLBL {w} {
  global tkPriv
  set x $tkPriv(x)
  set y $tkPriv(y)

  if {$y >= [winfo height $w]} {
    ${w}_text yview scroll 1 units
  } elseif {$y < 0} {
    ${w}_text yview scroll -1 units
  } elseif {$x >= [winfo width $w]} {
    ${w}_text xview scroll 2 units
  } elseif {$x < 0} {
    ${w}_text xview scroll -2 units
  }
  tkListboxMotion $w [$w index @$x,$y]
  set tkPriv(afterId) [after 50 tkListboxAutoScanLBL $w]
}

proc flb_destroy_lbl {flblname} {
  global flb
  catch "unset flb($flblname,list)"
  if [winfo exists $flblname] {
    destroy $flblname
  }
  catch "rename ${flblname}_label {}"
  catch "rename $flblname {}"
}

proc flb_process_lbl {flblname args} {
  global flb

  set cmd [lindex $args 0]

  set haslist 0
  set lb $flb($flblname,list)
  if [winfo exists $lb] {
    if [catch {${lb}_text index $flblname}] {
      set flb($flblname,list) {}
    } else {
      set haslist 1
    }
  }

  if {$cmd == "configure"} {
    set islabel 1
    foreach opt {-select -setgrid -takefocus -xscroll -yscroll} {
      if {[string first $opt $args] > -1} {
	set islabel 0
	break
      }
    }

    if $islabel {
      return [eval "${flblname}_label $args"]
    } else {
      if $haslist {
	return [eval "$lb $args"]
      } else {
	error "$flblname has not associated fancylistbox"
      }
    }
  }

  if {$cmd == "cget"} {
    if [catch {eval "${flblname}_label $args"} ret] {
      if $haslist {
	return [eval "$lb $args"]
      } else {
	error "$flblname has not associated fancylistbox"
      }      
    } else {
      return $ret
    }
  } 

  if $haslist {
    set ndx [lindex $args 1]
    if {[string first @ $ndx] == 0} {
      scan $ndx "@%d,%d" x y
      set adj [${lb}_text bbox $flblname]
      if ![llength $adj] { set adj {0 0} }
      set ndx @[expr $x+[lindex $adj 0]],[expr $y+[lindex $adj 1]]
    }
    if {[llength $args] > 2} {
      set fargs [lrange $args 2 end]
    } else { set fargs {} }
    return [eval "$lb $cmd $ndx $fargs"]
  } else {
    error "$flblname has not associated fancylistbox"
  }      
}

