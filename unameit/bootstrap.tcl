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
# Note that only one of 
#	use_password
#	use_ccache
#	use_keytab
# should be true. These are derived from the authentication login
# type rather than being directly in the configuration (see 
# unameit_auth_configure_client).
#
# Globals
#	
#	unameitPriv - miscellaneous
#	unameitLogin - parameters needed for the current auth model
#	unameitConfig - the configuration parameters
#
# 	window-name(cursor^)
#	window-name(busy^)
#

####				Miscellaneous

#
# Initial error handler.  A more fully featured one is used once we
# connect to the server.  All errors are fatal for now.
#
proc bgerror {msg} {
    global errorCode
    catch {unameit_error_get_text msg $errorCode}
    tk_messageBox -message $msg -type ok -icon error -title Error
    exit 1
}

#
# The busy routines set toplevel windows and their children into an
# unresponsive state. Commands are:
#	unameit_busy normal 
#	unameit_busy busy
#	unameit_busy status (just to check)
# The original state of the window is returned.
#

#
# Internal procedure. Recursively set window and children to busy.
# Does not descend to toplevel children, or to
# windows that have appeared since the toplevel was set busy,
# since they have not had their cursor saved.
#
proc unameit_busy_do_children {window} {
    upvar #0 $window winvar

    set winvar(cursor^) [$window cget -cursor]

    $window configure -cursor watch

    foreach w [winfo children $window] {
	if {! [cequal $w [winfo toplevel $w]]} {
	    unameit_busy_do_children $w
	}
    }
}

proc unameit_busy_undo_children {window} {
    upvar #0 $window winvar

    if {[info exists winvar(cursor^)]} {
	$window configure -cursor $winvar(cursor^)

	foreach w [winfo children $window] {
	    if {! [cequal $w [winfo toplevel $w]]} {
		unameit_busy_undo_children $w
	    }
	}
    }
}

proc unameit_busy {command window} {
    if {! [cequal $window [winfo toplevel $window]]} {
	error "unameit_busy: '$window' is not a toplevel"
    }

    upvar #0 $window winvar

    # save state to return later
    if {[info exists winvar(busy^)]} {
	set old_state $winvar(busy^)
    } else {
	set old_state normal
    }

    # Return if the command is just status, or if the state is
    # not changing.
    switch -- $command {
	status -
	$old_state {
	    return $old_state
	}

	normal {
	    unameit_busy_undo_children $window
	}

	busy {
	    unameit_busy_do_children $window
	}

	default {
	    error "bad command '$command' for unameit_busy"
	}
    }

    set winvar(busy^) $command
    return $old_state
}

proc unameit_set_attr_from_focus {old_focus} {
    ## Trash old reference and create new reference separately in case
    ## we have embedded forms.

    ## Trash old attribute reference
    upvar #0 $old_focus old_focus_s
    if {[info exists old_focus_s(attr_state^)]} {
	upvar #0 $old_focus_s(attr_state^) old_attr_s
	if {[info exists old_attr_s(class_state^)]} {
	    upvar #0 $old_attr_s(class_state^) old_class_s
	    catch {unset old_class_s(attr^)}
	}
    }

    ## Set new reference
    upvar #0 [focus -lastfor $old_focus] new_focus_s
    if {[info exists new_focus_s(attr_state^)]} {
	upvar #0 $new_focus_s(attr_state^) new_attr_s
	if {[info exists new_attr_s(class_state^)]} {
	    upvar #0 $new_attr_s(class_state^) new_class_s
	    set new_class_s(attr^) $new_attr_s(attr^)
	}
    }
}

# Sets up standard callbacks. Which callback to set up are passed in in args.
proc unameit_set_standard_callbacks {toplevel class2window_var args} {
    global unameitPriv
    upvar 1 $class2window_var class2window
    set fields_path $toplevel.object_box^.canvas.fields^

    foreach op $args {
	lassign $class2window($op) menu index
	switch $op {
	    Dismiss^ {
		$menu entryconfigure $index -command\
			[list unameit_delete_toplevel $toplevel]
	    }
	    Exit^ {
		$menu entryconfigure $index -command [list unameit_wrapper\
			[list unameit_exit_application $toplevel]]
	    }
	    New^ {
		$menu entryconfigure $index -command unameit_new_window
	    }
	    Connect^ {
		$menu entryconfigure $index -command [list unameit_wrapper\
			[format {
		    if {[catch {unameit_connect_and_authorize %s} msg]} {
			unameit_print_message %s $msg
		    } else {
			unameit_print_message %s {}
		    }
		} [list $toplevel] [list $toplevel] [list $toplevel]]]
	    }
	    Preview^ {
		$menu entryconfigure $index\
			-command [list unameit_wrapper unameit_preview_window]
	    }
	    default {
		error "Unknown callback $op"
	    }
	}
    }
}

## String to widget name routine. Converts a string into a valid widget
## path name component.
proc s2w {label} {
    ## Remove periods and circumflexes. Circumflexes are put into internal
    ## names so they don't clash with names defined in the metaschema.
    ## Remove blanks. A lot of Tk routines don't like spaces in the
    ## widget name.
    regsub -all {[.^ ]*} $label "" label

    ## If first letter of label name is caps, lowercase it. Window names can't
    ## start with a capital letter.
    append good_label [string tolower [string range $label 0 0]] \
	    [string range $label 1 end]

    return $good_label
}

proc unameit_exit_application {w} {
    global unameitPriv

    # If we haven't logged in yet, the subsystems are not initialized.
    # unameit_preview_cache will not work if the subsystems are not
    # initialized.
    if {$unameitPriv(subsystems_initialized) &&
	    ![empty [unameit_preview_cache]]} {
	switch -- [tk_messageBox -parent $w\
		-icon warning -title "Exit?" -type okcancel -default cancel\
		-message "There are uncommitted changes.  Really exit?"] {
	    cancel return
	}
    }
    exit
}

proc unameit_delete_toplevel {toplevel} {
    global UNAMEIT_TOPLEVELS

    if {[array size UNAMEIT_TOPLEVELS] == 1} {
	unameit_exit_application $toplevel
    } else {
	## Destroy window. Variables get cleaned up automatically by
	## destroy binding.
	destroy $toplevel

	## Delete from toplevel list
	unset UNAMEIT_TOPLEVELS($toplevel)
    }
}

proc assert {c} {
    uplevel 1 [format {
	if "!(%s)" {
	    error {Assertion error: %s}
	}
    } $c $c]
}

####			Connection related routines

proc unameit_try_to_connect {toplevel} {
    global errorCode unameitPriv unameitConfig 

    ## Disconnect if we were already connected. If we are not connected,
    ## this command has no effect.
    unameit_disconnect_from_server

    ## Alias unameitConfig vars so we can use the short names.
    foreach index {retries backoff} {
	set $index [unameit_config unameitConfig $index]
    }
    upvar #0 unameitPriv(service) service
    upvar #0 unameitPriv(server_host) server_host

    while {1} {
	unameit_print_message $toplevel "Connecting to $server_host:$service..."
	if {[set code [catch {unameit_connect_to_server $server_host $service}\
		msg]]} {
	    lassign $errorCode e1 e2 e3
	    switch -- $e1.$e2.$e3 UNAMEIT.CONN.EAGAIN {} default {
		return -code $code -errorcode $errorCode\
			"Could not connect to $server_host:$service"
	    }
	    if {$retries == 0} {
		error "Could not connect to $server_host:$service"
	    }
	    unameit_print_message_and_wait $toplevel\
		    "Could not connect to $server_host:$service" 1
	    unameit_print_message_and_wait $toplevel\
		    "Sleeping $backoff seconds...($server_host:$service)" $backoff
	    set backoff [expr $backoff*2]
	    incr retries -1
	} else {
	    unameit_print_message $toplevel ""
	    return
	}
    }
}

#
# Some of these may have changed, so we just reset all of them.
# This is not the most efficient, but it is safest, and it only happens
# at login.
#
proc unameit_connect_and_authorize {toplevel} {
    global unameitLogin unameitConfig

    unameit_try_to_connect $toplevel

    unameit_authorize_login_a unameitLogin

    #
    # Clear secret parameters: presumably passwords.
    #
    set auth $unameitLogin(authentication)
    foreach param $unameitLogin(auth_parameters) {
	if {[unameit_config_secret unameitConfig $param $auth]} {
		set unameitLogin($param) ""
	}
    }
}

####		Top level window and state transition routines

proc unameit_create_login_screen {toplevel} {
    global unameitLogin unameitPriv unameitConfig
    upvar #0 $toplevel toplevel_s

    set toplevel_s(mode^) login

    ## Set title to UName*It
    wm title $toplevel "$unameitPriv(mode): UName*It"
    wm iconname $toplevel $unameitPriv(mode)

    if {[winfo exists $toplevel.message^]} {
	pack $toplevel.message^ -side bottom -fill x
    } else {
	set message_area [unameit_create_message_area $toplevel]
	pack $message_area -side bottom -fill x
    }

    ## Cache menus for fast startup
    set no_cache [catch {array set login_menubar $unameitPriv(login_menubar)}]

    ## Build the login menu
    set menu_data(Dismiss^) {Special Dismiss}
    set menu_data(Exit^) {Special Exit}
    set menubar [unameit_build_menubar $toplevel login_menubar^ menu_data\
	    class2window login_menubar login]
    unameit_set_menubar_type $toplevel login

    if {$no_cache} {
	set unameitPriv(login_menubar) [array get login_menubar]
    }

    ## Set up the standard callbacks
    unameit_set_standard_callbacks $toplevel class2window Dismiss^ Exit^


    ## Add the ESM logo
    set logo [label $toplevel.esmlogo^ -bg white] ;# make bg same as logo
    unameit_add_wrapper_binding $logo

    pack $logo -side left -fill both
    if {[catch {image create photo esmlogo\
	    -file [unameit_filename UNAMEIT_TOILIB esmlogo.gif]}] == 0} {
	$toplevel.esmlogo^ configure -image esmlogo
    }

    ## Add the login entry boxes, based on authentication parameters.
    set auth $unameitLogin(authentication)
    set entry_list [frame $toplevel.login_entries^]

    # determine fields that appear
    set fields {}
    foreach param $unameitLogin(auth_parameters) {
	if {! [unameit_config_hidden unameitConfig $param $auth]} {
	    lappend fields $param
	}
    }

    foreach param $fields {
	set wname $param
	append wname ^
	set new_entry [unameit_create_entry $entry_list $wname \
		[unameit_config_label unameitConfig $param $auth] \
		unameitLogin($param)]
	pack $new_entry -side top -expand y -fill both

	# If it is secret, show *
	if {[unameit_config_secret unameitConfig $param $auth]} {
	    $new_entry.entry^ configure -show *
	}

	# If it is readonly, disable it
	if {[unameit_config_readonly unameitConfig $param $auth]} {
	    $new_entry.entry^ configure -state disabled
	}
    }
    pack $entry_list -side right -expand y -fill both

    ## Set the input focus to the appropriate field
    if {[info exists unameitLogin(login)] && [empty $unameitLogin(login)]} {
	focus $toplevel.login_entries^.login^.entry^
    } elseif {[winfo exists $toplevel.login_entries^.password^.entry^]} {
	focus $toplevel.login_entries^.password^.entry^
    } elseif {[winfo exists $toplevel.login_entries^.keytab^.entry^]} {
	focus $toplevel.login_entries^.keytab^.entry^
    } 
    ## Add the Log In and Clear buttons
    set clear_cmd [format {
	foreach f [list %s] {
	    if {![unameit_config_readonly unameitConfig $f [list %s]]} {
		set unameitLogin($f) {}
	    }
	}
    } $fields $auth]

    set button_frame [unameit_make_button_list $entry_list buttons^\
	    [list login {Log In} [list unameit_wrapper\
	        [list unameit_login_to_server $toplevel]]]\
	    [list clear Clear $clear_cmd]]
    pack $button_frame -side bottom

    ## Bind the return key to the login procedure
    bind $toplevel <Return> [list unameit_wrapper\
	    [list unameit_login_to_server $toplevel]]
}

proc unameit_login_to_server {toplevel} {
    global unameitPriv errorCode

    ## Connect
    if {[catch {unameit_connect_and_authorize $toplevel} msg]} {
	unameit_error_get_text msg $errorCode
	unameit_print_message $toplevel $msg
	return
    }

    ## Initialize subsystems if need be
    if {!$unameitPriv(subsystems_initialized)} {
	unameit_print_message $toplevel "Initializing subsystems..."
	unameit_initialize_cache_mgr
	unameit_initialize_schema_mgr
	set unameitPriv(subsystems_initialized) 1
	unameit_print_message $toplevel ""
    }

    ## Get TOI code if need be and
    ## set up fancylistbox bindings
    if {![info exists unameitPriv(toi_loaded)]} {
	unameit_print_message $toplevel "Getting TOI code..."
	source [unameit_filename UNAMEIT_TOILIB toi.tcl] 
	flb_init
	set unameitPriv(toi_loaded) 1
	unameit_print_message $toplevel ""
    }

    ## This may make a call to the server which may fail. If it fails, the
    ## login window hasn't been broken down yet.
    set greeting_text [unameit_get_greeting_window_info]

    ## Set menubar type and grab menubar info if needed. We have to grab
    ## it now because it may make a call to the server.
    if {[unameit_can_modify_schema]} {
	set type schema
    } else {
	set type normal
    }
    if {![winfo exists $toplevel.${type}_menubar^]} {
	set no_cache [catch {array set main_menubar\
		$unameitPriv(${type}_main_menubar)}]
	if {$no_cache} {
	    array set menu_data [unameit_get_main_menu_data]
	}
    }

    # *** From here on we cannot contact the server. The login window
    # *** will be destroyed and the greeting window created.

    ## Nullify so it can't be inspected.
    set unameitLogin(password) ""

    ## Unbind the return key.
    bind $toplevel <Return> ""

    ## Trash login window subwidgets
    destroy $toplevel.login_menubar^
    destroy $toplevel.esmlogo^
    destroy $toplevel.login_entries^

    ## Create menubar
    if {![winfo exists $toplevel.${type}_menubar^]} {
	set menubar [unameit_build_menubar $toplevel ${type}_menubar^\
		menu_data class2window main_menubar $type]
	if {$no_cache} {
	    set unameitPriv(${type}_main_menubar) [array get main_menubar]
	}

	## Set up menubar callbacks
	unameit_set_standard_callbacks $toplevel class2window Dismiss^\
		Exit^ New^ Connect^ Preview^

	## Set up class menubar callbacks
	unameit_set_class_menubar_callbacks $toplevel class2window

	upvar #0 $toplevel toplevel_s

	## Record locations of some menu items. The bindings
	## for these change in the menu as we switch states. Record this
	## on a toplevel basis because the menu paths will differ for
	## each toplevel.
	set toplevel_s(${type}_login_menu_loc) $class2window(Login^)
	set toplevel_s(${type}_about_menu_loc) $class2window(About^)
	set toplevel_s(${type}_preview_menu_loc) $class2window(Preview^)
	set toplevel_s(${type}_save_menu_loc) $class2window(Save^)

	## Set up login callback
	lassign $class2window(Login^) menu index
	$menu entryconfigure $index -command [list unameit_wrapper\
		[list unameit_about_box_to_login $toplevel]]
    }
    unameit_set_menubar_type $toplevel $type

    ## Call entry point in downloaded code.
    unameit_create_greeting_window $toplevel $greeting_text

    if {[info exists unameitPriv(source_file)] &&
    ![info exists unameitPriv(source_file_read)]} {
	set unameitPriv(source_file_read) 1
	source $unameitPriv(source_file)
    }
}

#### 		Miscellaneous window routines

proc unameit_create_message_area {widget} {
    set label [label $widget.message^ -wraplength 6i -justify left]
    unameit_add_wrapper_binding $label
    return $label
}

proc unameit_print_message {widget message} {
    $widget.message^ configure -text $message
    update idletasks
}

proc unameit_print_message_and_wait {widget message seconds} {
    upvar #0 $widget widget_s
    unameit_print_message $widget $message
    after [expr $seconds*1000] set widget_s(timer^) 1
    tkwait variable widget_s(timer^)
}

proc unameit_make_button_list {parent frame_name args} {
    # Create the outer frame.
    set framew [frame $parent.$frame_name]
    unameit_add_wrapper_binding $framew

    foreach tuple $args {
	lassign $tuple w_name label command
	set button [button $framew.$w_name -text $label -command $command]
	unameit_add_wrapper_binding $button
	pack $button -side left -expand 1 -padx 1m -pady 1m
    }

    return $framew
}

proc unameit_delete_toplevel_if_not_busy {toplevel} {
    global unameitPriv

    if {$unameitPriv(mutex)} {
	return
    }
    set code [catch {unameit_busy status $toplevel} busy]
    if {$code == 0 && $busy == "busy"} {
	return
    }
    unameit_delete_toplevel $toplevel
}

proc unameit_get_new_toplevel {} {
    global unameitPriv UNAMEIT_TOPLEVELS

    ## Create toplevel window
    set toplevel [toplevel .top$unameitPriv(toplevel_count)^]
    unameit_add_wrapper_binding $toplevel
    incr unameitPriv(toplevel_count)

    set UNAMEIT_TOPLEVELS($toplevel) 1

    ## Set the window title and icon name
    wm title $toplevel "$unameitPriv(mode): UName*It"
    wm iconname $toplevel $unameitPriv(mode)
    
    ## Set up the deletion callback
    wm protocol $toplevel WM_DELETE_WINDOW\
	    [list unameit_delete_toplevel_if_not_busy $toplevel]
    catch {wm iconbitmap $toplevel\
	    @[unameit_filename UNAMEIT_TOILIB unameit.icon]}

    ## Initialize the global variable to nothing
    global $toplevel
    set ${toplevel}() 1; unset ${toplevel}()

    return $toplevel
}

####				Menu related routines

proc unameit_sort_path_lists {a b} {
    for {set i 0}\
	{[cequal [lindex $a $i] [lindex $b $i]] &&
         ![empty [lindex $a $i]]}\
	{incr i} {
    }
    return [string compare [lindex $a $i] [lindex $b $i]]
}

proc unameit_sort_top_level_menus {a b} {
    switch -exact $a {
	Schema {
	    return -1
	}
	Special {
	    return 1
	}
    }
    switch -exact $b {
	Schema {
	    return 1
	}
	Special {
	    return -1
	}
    }
    return [string compare $a $b]
}

proc unameit_tuple_to_id {path id2tuple_var tuple2id_var id_counter_var} {
    upvar 1 $id2tuple_var id2tuple
    upvar 1 $tuple2id_var tuple2id
    upvar 1 $id_counter_var id_counter

    if {![info exists tuple2id($path)]} {
	set tuple2id($path) [set id [incr id_counter]]
	set id2tuple($id) $path
	return $id
    }
    return $tuple2id($path)
}

proc unameit_id_to_tuple {id id2tuple_var} {
    upvar 1 $id2tuple_var id2tuple

    return $id2tuple($id)
}

### When we get a path list like
###     b b
###     b c
###     a b c
###     a b e
###     a c e
###     a d b
### we have a forest of trees. To store a forest of trees, we need to use
### separate variables for each tree. To do this, we use the first
### element of each path as a variable name and upvar it. The list of
### variables created is returned by this routine.
###    Next we notice that the same name can be used at different levels
### in the same (and different) trees. These labels must be unique. To
### make them unique, we make a mapping from
###		(path) = <id>
### and create the trees using ids instead. We return a forest of
### trees indexed by the id and a id -> (path)
### mapping table.
proc unameit_create_compressed_menu_forest {ordered_path_list id2tuple_var\
	tuple2id_var id_counter_var} {
    upvar 1 $id2tuple_var id2tuple
    upvar 1 $tuple2id_var tuple2id
    upvar 1 $id_counter_var id_counter

    foreach path $ordered_path_list {
	## The menu button name is the name of the first element.
	set menu_button [lindex $path 0]

	## Add it to the return value if not already there.
	set vars($menu_button) 1

	upvar 1 $menu_button tree

	## Create the id tree
	set path_len [llength $path]
	for {set i 0} {$i < $path_len} {incr i} {
	    set subpath [lrange $path 0 $i]
	    set id [unameit_tuple_to_id $subpath id2tuple tuple2id id_counter]
	    if {$i == $path_len-1} {
		set tree($id) ""
	    } else {
		set next_subpath [lrange $path 0 [expr $i+1]]
		set next_id [unameit_tuple_to_id $next_subpath id2tuple\
			tuple2id id_counter]
		if {![info exists tree($id)]} {
		    set tree($id) ""
		}
		if {[lsearch $tree($id) $next_id] == -1} {
		    # The paths are already sorted so the tree will get
		    # created in the correct sort order.
		    lappend tree($id) $next_id
		}
	    }
	}
    }

    ## Now all the trees of ids are created. Compress them.
    foreach var [array names vars] {
	upvar 1 $var tree
	unameit_compress_menu_tree [unameit_tuple_to_id $var id2tuple\
		tuple2id id_counter] tree "" id2tuple tuple2id
    }
    
    return [array names vars]
}

proc unameit_compress_menu_tree {node node_list_var parent id2tuple_var\
	tuple2id_var} {
    upvar 1 $node_list_var node_list
    upvar 1 $id2tuple_var id2tuple
    upvar 1 $tuple2id_var tuple2id

    ## If there is only one descendent, compress this node.
    while {[llength $node_list($node)] == 1} {
	## If we are the top node, don't compress. Top node is menu
	## button.
	if {[empty $parent]} {
	    break
	}

	## Check to see if the child is a leaf node. If so, just move it
	## up with its name; otherwise, concat the two names.
	set child_is_leaf [expr [llength $node_list($node_list($node))]==0]
	if {!$child_is_leaf} {
	    set child_label [lindex $id2tuple($node_list($node)) end]
	    set new_label [list [lindex $id2tuple($node) end] $child_label]
	    set new_path [concat\
		    [lrange $id2tuple($node) 0\
	    			     [expr [llength $id2tuple($node)]-2]]\
		    [list $new_label]]
	    set id2tuple($node_list($node)) $new_path
	    set tuple2id($new_path) $node_list($node)
	}
	set parent_index [lsearch -exact $node_list($parent) $node]
	set node_list($parent) [lreplace $node_list($parent) $parent_index\
		$parent_index $node_list($node)]
	set tmp $node_list($node)
	unset node_list($node)
	set node $tmp
    }

    if {[llength $node_list($node)] == 0} {
	return
    }

    foreach child $node_list($node) {
	unameit_compress_menu_tree $child node_list $node id2tuple tuple2id
    }
}

####				Entry routines

proc unameit_create_entry {parent w_name label entry_var} {
    ## Create the outer frame containing the label and entry frame
    set framew [frame $parent.$w_name]
    unameit_add_wrapper_binding $framew

    ## Create and pack the label
    set label [label $framew.label -text $label -width 16 -anchor e]
    unameit_add_wrapper_binding $label
    pack $framew.label -side left -fill y -ipadx 1m -ipady 1m

    ## Create and pack the entry frame and widget
    set entry [entry $framew.entry^ -width 32 -textv $entry_var]
    unameit_add_wrapper_binding $entry
    ## Note that we don't make $entry a sibling of $entry_frame. We want
    ## prevent $entry_frame from being mentioned in the option database.
    pack $entry -expand y -fill x -padx 1m -pady 1m -side right

    ## Set up bindings for the new entry
    bind $entry <Tab> {unameit_wrapper {focus [tk_focusNext %W]}}
    bind $entry <Shift-Tab> {unameit_wrapper {focus [tk_focusPrev %W]}}

    return $framew
}


#### 				Initialization routines

proc unameit_make_subsystem_interpreters {} {
    ## Create interpreters
    interp create cache_mgr
    interp create schema_mgr

    ## Load Tcl procedures
    load {} Cache_mgr cache_mgr
    load {} Schema_mgr schema_mgr
}

proc unameit_cross_subsystem_apis {} {
    ## Initialize cross commands between interpreters
    foreach command [cache_mgr eval unameit_get_schema_mgr_commands] {
	interp alias schema_mgr $command cache_mgr $command
    }
    foreach command [schema_mgr eval unameit_get_cache_mgr_commands] {
	interp alias cache_mgr $command schema_mgr $command
    }
}

proc unameit_export_subsystem_apis {args} {
    ## Export APIs to each interpreter.
    foreach mgr {cache_mgr schema_mgr} {
	foreach interp $args {
	    if {[cequal $mgr $interp]} continue

	    foreach routine [$mgr eval unameit_get_interface_commands] {
		interp alias $interp $routine $mgr $routine
	    }
	}
    }
}

proc unameit_set_option_resources {} {
    #
    # Turn off focusing for buttons, scrollbars, listboxes and radiobuttons
    #
    option add Unameit*Button.takeFocus 0 startupFile
    option add Unameit*Scrollbar.takeFocus 0 startupFile
    option add Unameit*Listbox.takeFocus 0 startupFile
    option add Unameit*Radiobutton.takeFocus 0 startupFile
    option add Unameit*Checkbutton.takeFocus 0 startupFile
    #
    # Turn on gridding for all listboxes
    #
    option add Unameit*Listbox.setGrid 1 startupFile
    #
    # Turn off wrapping for text boxes
    #
    option add Unameit*Text.wrap none startupFile
    #
    # Get rid of highlight border for radio and check buttons
    #
    option add Unameit*Radiobutton.highlightThickness 0 startupFile
    option add Unameit*Checkbutton.highlightThickness 0 startupFile
    #
    # Anchor Radiobuttons and Checkbuttons west
    #
    option add Unameit*Radiobutton.anchor w startupFile
    option add Unameit*Checkbutton.anchor w startupFile
    #
    # Get rid of exporting selection for listboxes. Needed so lists of
    # pointers selection doesn't disappear when you popup a dialog with a
    # listbox.
    #
    option add Unameit*Listbox.ExportSelection 0 startupFile
    #
    # Don't make menus tearoff
    #
    option add Unameit*Menu.tearOff 0 startupFile

    ## Remove the return binding from radiobuttons and checkbuttons
    bind Radiobutton <Key-Return> ""
    bind Checkbutton <Key-Return> ""


    ## Adjust tk colour scheme based on user selected background colour.
    ## helps with CDE which tramples all over Tk's default resources.
    switch -- [set bg [option get . background Background]] "" {} default {
	. conf -bg $bg
	tk_setPalette $bg
    }
}

####		Mutual exclusion routines

proc unameit_mutex {w} {
    global unameitPriv

    if {$unameitPriv(mutex)} {
	return -code break
    }
    set code [catch {unameit_busy status [winfo toplevel $w]} busy]
    if {$code == 0 && $busy == "busy"} {
	return -code break
    }
}

## Add Wrapper as the first entry, followed by the toplevel name (for
## accelerators) then the rest of the tags in their order.
proc unameit_add_wrapper_binding {widget} {
    set bindtags [bindtags $widget]
    set length [llength $bindtags]
    bindtags $widget [eval list Wrapper\
	    {[lindex $bindtags [expr $length-2]]}\
	    [lrange $bindtags 0 [expr $length-3]]\
	    [lrange $bindtags [expr $length-1] end]]
}

proc unameit_wrapper {script} {
    global unameitPriv

    set unameitPriv(mutex) 1
    if {[set code [catch $script msg]]} {
	global errorCode errorInfo

	set unameitPriv(mutex) 0
	return -code $code -errorcode $errorCode -errorinfo $errorInfo $msg
    }
    set unameitPriv(mutex) 0
}

### 				Main program
proc unameit_start {} {
    global argv0 argv unameitPriv unameitLogin unameitConfig env tcl_platform

    catch {memory init on}

    package require Config
    package require Error

    ## Withdraw the main window. It is not used. Toplevels are created
    ## separately.
    wm withdraw .

    if {$tcl_platform(platform) == "unix"} {
	## Set up session management info. By doing this, CDE is able to 
	## restart UName*It when you use the Exit button in CDE.
	set cmd0 [unameit_filename UNAMEIT_BIN unameit]
	wm client . [info hostname]
	wm command . [lvarcat cmd [list $cmd0] $argv]
    } else {
	# This initializes the socket libraries on Windows. Socket functions
	# fail if this is not done.
	info hostname
    }

    ## Set up some miscellaneous non-configurable variables.
    set unameitPriv(subsystems_initialized) 0

    unameit_getconfig unameitConfig unameit
    set auth_type [unameit_config unameitConfig authentication]
    package require $auth_type

    ## Copy authentication variables to unameitLogin
    unameit_auth_configure_client unameitConfig unameitLogin $auth_type

    ## Preinstall default values.
    set unameitPriv(queryMaxRows) 257
    set unameitPriv(queryTimeOut) 10

    ## Copy non-module dependent values to unameitPriv
    unameit_configure_app unameitConfig unameitPriv
    set unameitPriv(mode) $env(UNAMEIT_MODE)


    ## Make the sub interpreters
    unameit_make_subsystem_interpreters

    ## Set up internal cache/schema manager communication.
    unameit_cross_subsystem_apis

    ## Export APIs
    unameit_export_subsystem_apis {} cache_mgr schema_mgr

    ## Set up cache manager callouts to TOI
    foreach tuple {{unameit_get_objs_in_books unameit_get_objs_in_book}} {
	lassign $tuple alias real_cmd
	cache_mgr alias $alias unameit_for_each_book $real_cmd
    }
    cache_mgr alias unameit_cache_mgr_busy unameit_cache_mgr_busy
    cache_mgr alias unameit_cache_mgr_unbusy unameit_cache_mgr_unbusy

    ## Initialize toplevel vars
    global UNAMEIT_TOPLEVELS
    set unameitPriv(toplevel_count) 0
    set UNAMEIT_TOPLEVELS() 1; unset UNAMEIT_TOPLEVELS()

    ## Set options and read user defaults
    unameit_set_option_resources

    ## Set up focus binding so that it automatically sets up the correct
    ## global state when the focus changes.
    foreach binding {<Tab> <Shift-Tab>} {
	bind all $binding {+unameit_set_attr_from_focus %W}
    }

    ## Set up destroy binding on all widgets that cleans up the global
    ## state for the widget.
    bind all <Destroy> {catch {unset %W}}

    ## Set up mutual exclusion code
    set unameitPriv(mutex) 0
    bind Wrapper <B1-Motion> {unameit_mutex %W}
    bind Wrapper <ButtonPress> {unameit_mutex %W}
    bind Wrapper <ButtonRelease> {unameit_mutex %W}
    bind Wrapper <Any-KeyPress> {unameit_mutex %W}
    bind Wrapper <Any-KeyRelease> {unameit_mutex %W}

    ## Create a new window. 
    set toplevel [unameit_get_new_toplevel]
    unameit_create_login_screen $toplevel

    # try to login unless user needs to enter passwords
    if {!$unameitLogin(use_password)} {
	unameit_login_to_server $toplevel
    }
}

#### 	Utility macros

proc empty {s} {cequal $s ""}

