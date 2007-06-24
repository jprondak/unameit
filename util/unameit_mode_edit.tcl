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
# $Id: unameit_mode_edit.tcl,v 1.8.10.1 1997/08/28 18:29:50 viktor Exp $
#

#
# UNameIt Mode Editor
#
# Globals used:
#
#   arrays:
#	umeParam - current screen value
#	umeDefault - default values for umeParam
#	umeCurrent - values from current files
#	umeConfig - config variable
#	umeDialog - information used by these routines
#
#	umetHostFile - host file for a mode
#	umetSiteFile - site file for a mode
#
#   lists:
#	umeParamOrder - list of umeParam names in screen order
#
#   scalars:
#	umetEditMode - name of mode to create/delete/edit
#	bound to radiobuttons and an entry
#	monitored by umet_mode_selected to configure active menu items
#
#	umetModeConfiguration - cached value of menu configuration,
#	set by umet_mode_configure
#
# We do not add fields for Site file unless we are writing it.
#
# TBD - let the user edit the preview box and use the result?
#
# TBD - add Delete Mode and Copy Mode
#

package require Config


proc umet_yesno {message {title "UNameIt Mode Editor"}} {
    cequal "yes" [tk_messageBox -icon question -type yesno \
            -title $title \
            -parent . -message $message]
}

proc umet_error {message {title "UNameIt Mode Editor"}} {
    global errorInfo
    #append message "\n" $errorInfo
    tk_messageBox -icon error -type ok -title $title \
	    -parent . -message $message
}

proc umet_message {message {title "UNameIt Mode Editor"}} {
    tk_messageBox -icon info -type ok -title $title \
	    -parent . -message $message
}

###########################################################################
#
# Transfer the dialog values from umeParam to umeConfig, using the keys
# in umeConfigKey.
#
proc ume_param_to_config {} {
    global umeParam umeConfig umeCurrent umeDialog umeConfigKey

    foreach {editor_label key} [array get umeConfigKey] {
	set umeConfig($key) $umeParam($editor_label)
    }
}
proc ume_config_to_current {} {
    global umeParam umeConfig umeCurrent umeDialog umeConfigKey

    foreach {editor_label key} [array get umeConfigKey] {
	if {! [info exists umeConfig($key)]} continue
	set umeCurrent($editor_label) $umeConfig($key)
    }
}

###########################################################################
#
# Add a field to the form. If a default is provided, use it. 
# Do NOT add the field if it is a Sitefile item and we are not writing
# the sitefile.
#
proc ume_writing_sitefile {} {
    global umeDialog
    cequal $umeDialog(Sitefile_Usage) "write_sitefile"
}

proc ume_isa_site_param {key} {
    string match Site/* $key
}

proc add_field {editor_label key args} {
    global umeDefault umeParamOrder umeConfigKey

    if {[ume_isa_site_param $key] && ![ume_writing_sitefile]} return

    if {[llength $args] > 0} {
	lassign $args umeDefault($editor_label) 
    } 
    set umeConfigKey($editor_label) $key
    lappend umeParamOrder $editor_label
}


###########################################################################
#
proc ume_quit {} {
    global umeDialog 
    destroy $umeDialog(Top)
}

###########################################################################
#
# Write out the host file and possibly the site file.
proc ume_save {} {
    global umeDialog umeConfig

    ume_param_to_config

    if {[ume_writing_sitefile]} {
	ume_format_config_file umeConfig stuff Site
	write_file $umeDialog(SiteFile) $stuff
    }
    ume_format_config_file umeConfig stuff Host
    write_file $umeDialog(HostFile) $stuff

    ume_quit
}


###########################################################################
#
# Build the form for a unameit client.
#
proc unameit_client_init {} {
    global umeParam umeDialog umeParamOrder env
    set umeParamOrder {}
    set mode $umeDialog(Mode)
    set operation $umeDialog(Operation)

    set default_domain ""
    catch {set default_domain [exec domainname]}

    set fqdn ""
    set host [info hostname]
    catch {set fqdn [set host [host_info official_name [info hostname]]]}

    if {![regexp {\.} $fqdn] && [regexp {\.} $default_domain]} {
	set fqdn $host.$default_domain
    }

    add_field "Local FQDN" \
	    Host/All/All/client_instance \
	    $fqdn

    add_field "Unameit Service" \
	    Site/All/All/service \
	    unameit-$mode

    add_field "Unameit Server" \
	    Site/All/All/server_host 

    add_field "Unameit Server FQDN" \
	    Site/All/All/server_instance 
}

###########################################################################
#
# Build a form for a unameit server.
#
proc unameit_server_init {} {
    global umeParam umeDialog umeParamOrder env
    set umeParamOrder {}
    set mode $umeDialog(Mode)
    set operation $umeDialog(Operation)

    set default_domain ""
    catch {set default_domain [exec domainname]}

    set fqdn ""
    set host [info hostname]
    catch {set fqdn [set host [host_info official_name [info hostname]]]}

    if {![regexp {\.} $fqdn] && [regexp {\.} $default_domain]} {
	set fqdn $host.$default_domain
    }
    
    set etc [unameit_filename UNAMEIT_ETC]

    add_field "NIS/DNS Domain" \
	    Host/upull/All/domain \
	    $default_domain

    add_field "Local FQDN" \
	    Host/All/All/client_instance \
	    $fqdn

    add_field "Unameit Data Directory" \
	    Host/All/All/data \
	    /var/unameit-$mode

    add_field "Unameit Service" \
	    Site/All/All/service \
	    unameit-$mode

    add_field "Unameit Server" \
	    Site/All/All/server_host \
	    $host

    add_field "Unameit Server FQDN" \
	    Site/All/All/server_instance \
	    $fqdn

    add_field "Upull Service" \
	    Site/Upull/All/service \
	    upull-$mode

    add_field "Upull Server" \
	    Host/upull/All/server_host \
	    $host

    add_field "Upull Server FQDN" \
	    Host/upull/All/server_instance \
	    $fqdn

    add_field "Unisqlx Database Name" \
	    Host/All/unisqlx/dbname \
	    $mode

    add_field "Unisqlx Database Size Kb" \
	    Host/All/unisqlx/dbsize \
	    32000KB

    add_field "Unisqlx Database Directory" \
	    Host/All/unisqlx/databases \
	    /var/unameit-$mode/dbdata

    add_field "Unisqlx Database Logs" \
	    Host/All/unisqlx/dblogs \
	    /var/unameit-$mode/dblogs

    add_field "Unisqlx Num Data Buffers Kb" \
	    Host/All/unisqlx/num_data_buffers \
	    32000KB

    add_field "Unisqlx Num Log Buffers Kb" \
	    Host/All/unisqlx/num_log_buffers \
	    2000KB

    add_field "Unisqlx Checkpoint Interval Kb" \
	    Host/All/unisqlx/checkpoint_interval \
	    4000KB
			
}

###########################################################################
#
# Build a form for a upull server.
#
proc upull_server_init {} {
    global umeParam umeDialog umeParamOrder env
    set umeParamOrder {}
    set mode $umeDialog(Mode)
    set operation $umeDialog(Operation)

    set default_domain ""
    catch {set default_domain [exec domainname]}

    set fqdn ""
    set host [info hostname]
    catch {set fqdn [set host [host_info official_name [info hostname]]]}

    if {![regexp {\.} $fqdn] && [regexp {\.} $default_domain]} {
	set fqdn $host.$default_domain
    }
    
    set etc [unameit_filename UNAMEIT_ETC]

    add_field "NIS/DNS Domain" \
	    Host/upull/All/domain \
	    $default_domain

    add_field "Local FQDN" \
	    Host/All/All/client_instance \
	    $fqdn

    add_field "Unameit Data Directory" \
	    Host/All/All/data \
	    /var/unameit-$mode

    add_field "Upull Service" \
	    Site/Upull/All/service \
	    upull-$mode

    add_field "Upull Server" \
	    Host/upull/All/server_host \
	    $host

    add_field "Upull Server FQDN" \
	    Host/upull/All/server_instance \
	    $fqdn
}

###########################################################################
#
proc upull_client_init {} {
    upull_server_init
}

###########################################################################
#
# Set all parameter values.
#
proc ume_set_params {from} {
    global umeParam $from
    foreach f [array names umeParam] {
	set umeParam($f) ""
    }
    array set umeParam [array get $from]
}

proc ume_defaults {} {
    ume_set_params umeDefault
}

proc ume_currents {} {
    ume_set_params umeCurrent
}

#
# Set single parameter value.
#
proc ume_set_param {editor_label from} {
    global umeParam 
    upvar #0 $from data
    if {[info exists data($editor_label)]} {
	set umeParam($editor_label) $data($editor_label)
    } else {
	set umeParam($editor_label) ""
    }
}

###########################################################################
#
proc ume_default {editor_label} {
    ume_set_param $editor_label umeDefault
}

###########################################################################
#
proc ume_current {editor_label} {
    ume_set_param $editor_label umeCurrent
}

###########################################################################
#
# Display a dialog suitable for changing values in umeParam
# The parameters are in umeDialog
#
proc ume_dialog {} {
    global umeParam umeParamOrder umeDialog
    set top $umeDialog(Top)
    catch {destroy $top}
    toplevel $top
    pack [frame $top.sep -bg black -height 2] -fill x
    pack [frame $top.file_entries] -fill x    
    pack [frame $top.buttons] -fill x
    pack [button $top.buttons.okay -text "Okay" \
	    -command ume_save] \
	    -side left
#    pack [button $top.buttons.preview -text "Preview" \
#	    -command ume_preview_files] \
#	    -side left
    pack [button $top.buttons.defaults -text "Restore Default Values" \
	    -command ume_defaults] \
	    -side left
    pack [button $top.buttons.current -text "Restore Current Values" \
	    -command ume_currents] \
	    -side left
    pack [button $top.buttons.abort -text "Quit" \
	    -command "destroy $umeDialog(Top)"] \
	    -side left

    set fnum 0
    foreach label $umeParamOrder {
	incr fnum
	set fe $top.file_entries.f$fnum
	pack [frame $fe -borderwidth 1 -relief ridge] -fill x
	pack [label $fe.label -text $label -width 30 -anchor w] -side left
	pack [button $fe.current -text Current \
		-command [list ume_current $label]] \
		-side right
	pack [button $fe.default -text Default \
		-command [list ume_default $label]] \
		-side right
	pack [entry $fe.entry -textvariable umeParam($label) -width 45] \
		-side right -fill x -expand 1
    }
    wm title $top $umeDialog(Title)
}

###########################################################################
#
# Check the listed files and make sure that they do not already exist.
proc ume_new_files {args} {
    set message ""
    foreach f $args {
	if {[file exists $f]} {
	    append message "$f already exists\n"
	}
    }
    if {! [cequal "" $message]} {
	append message "Do you wish to overwrite?"
	if {! [umet_yesno $message]} {
	    error "Operation aborted."
	}
    }

    foreach f $args {
	write_file $f " "
	file delete $f
    }
}

###########################################################################
#
#
# Check the listed files and make sure that they are writable.
#
proc ume_old_files {args} {
    set message ""
    foreach f $args {
	if {! [file exists $f]} {
	    append message "$f not found\n"
	}
 	if {! [file writable $f]} {
	    append message "$f can not be modified\n"
	}
   }
    if {! [cequal "" $message]} {
	error $message
    }
}

###########################################################################
#
# Put the configuration file information into the format of a config file.
# These are sorted by application and module, with application and module
# lines written at appropriate times. Only the type wanted is included.
#
proc ume_format_config_file {config_var file_var file_type} {
    upvar 1 $config_var config \
	    $file_var output

    set output ""

    set current_app ""
    set current_module ""
    append output "Format 1.0\n"

    foreach param [lsort [array names config $file_type/*]] {
	set value $config($param)
	lassign [split $param /] file app module parameter
	if {! [cequal $app $current_app]} {
	    append output "\nApplications $app\n"
	    set current_app $app
	    set current_module ""
	}
	if {! [cequal $module $current_module]} {
	    append output "Modules $module\n"
	    set current_module $module
	}
	if {! [regexp -- {^[A-Z]} $parameter]} {
	    append output "\t$parameter\t$value\n"
	}
    }
}

###########################################################################
#
# Preview the file. 
#
proc ume_preview_files {} {
    global umeDialog umeConfig
    set top $umeDialog(Top)

    ume_param_to_config

    foreach type {Site Host} {

	ume_format_config_file umeConfig stuff $type

	set mb $top.preview$type
	catch {destroy $mb}
	toplevel $mb
	wm transient $mb $top
	wm title $mb "$type file $umeDialog(${type}File)"
	
	pack [button $mb.quit -command "destroy $mb" -text OK] -side bottom
	
	set text $mb.text
	set sb $mb.vsb
	
	text $text -yscrollcommand "$sb set" -tabs {1c 8c}
	scrollbar $sb -command "$text yview"
	pack $sb -side right -fill y
	pack $text -side left
	$text insert end $stuff
	$text configure -state disabled
    }
}

###########################################################################
#
# generate an error if var is NOT on the list of valid options
proc ume_check_var {var optlist what} {
    if {[lsearch -exact $optlist $var] < 0} {
	set opts [join $optlist ", "]
	error "invalid $what '$var': must be one of $opts."
    }
}

###########################################################################
#
# Do the work. Create a dialog box based on:
#	class of server to talk to; 	unameit | upull
#	class of software to set up; 	server | client
#	read site file or write it;	read_sitefile | write_sitefile
#	new mode or old;		create | edit
#	name of mode; e.g		training
#
# use_site means to read the values in the site file, which
# must already exist, even during a create operation.
# NOTE: a server should never do create & read_sitefile.


proc ume_edit {top class type sitefile_usage operation mode} {
    ume_check_var $class {unameit upull} "application class"
    ume_check_var $type {server client} "software type"
    ume_check_var $sitefile_usage {read_sitefile write_sitefile} \
	    "sitefile usage"
    ume_check_var $operation {create edit} "operation"

    foreach v {umeDialog umeConfigKey umeConfig umeDefault umeCurrent} {
	global $v
	catch {unset $v}
    }

    set umeDialog(Class) $class
    set umeDialog(Type) $type
    set umeDialog(Sitefile_Usage) $sitefile_usage
    set umeDialog(Operation) $operation
    set umeDialog(Mode) $mode
    set umeDialog(Top) $top
    set umeDialog(Title) "UNameIt Mode $mode"
    set umeDialog(HostDir) \
	    [unameit_filename UNAMEIT_ETC]
    set umeDialog(SiteFile) \
	    [unameit_filename UNAMEIT_CONFIG $umeDialog(Mode).conf]
    set umeDialog(HostFile) \
	    [file join $umeDialog(HostDir) $umeDialog(Mode).conf]
    set umeDialog(SiteFileDefaults) \
	    [unameit_filename UNAMEIT_INSTALL unameit.conf]
    set umeDialog(HostFileDefaults) \
	    [unameit_filename UNAMEIT_INSTALL unameit_root.conf]

    # create the directory if necessary
    if {! [file isdirectory $umeDialog(HostDir)]} {
	file mkdir $umeDialog(HostDir)
    }

    # Set umeParamOrder with the information needed to build the dialog.
    # Default values are set in umeDefault.
    [join [list $class $type init] _ ]

    # we always read the defaults.
    read_config_file umeConfig Site $umeDialog(SiteFileDefaults)
    read_config_file umeConfig Host $umeDialog(HostFileDefaults)

    # Set some calculated defaults. These are not on the forms.
    set umeConfig(Site/All/ukrbv/keytab) \
	    [unameit_filename UNAMEIT_ETC $mode.keytab]
    set umeConfig(Site/All/ukrbiv/srvtab) \
	    [unameit_filename UNAMEIT_ETC $mode.srvtab]

    # Read or create configuration files.
    switch -- $operation {
	create {
	    switch -- $sitefile_usage {
		read_sitefile {
		    read_config_file umeConfig Site $umeDialog(SiteFile)
		    ume_new_files $umeDialog(HostFile) 
		}
		write_sitefile {
		    ume_new_files $umeDialog(HostFile) $umeDialog(SiteFile)
		}   
	    }

	    # copy the defaults to the dialog.
	    ume_defaults
	}

	edit {
	    read_config_file umeConfig Site $umeDialog(SiteFile)
	    read_config_file umeConfig Host $umeDialog(HostFile)

	    # Copy values from umeConfig to umeCurrent.
	    ume_config_to_current

	    # copy current to the dialog
	    ume_currents
	}
    }
    # build the dialog. 
    ume_dialog 
}

###########################################################################
#
# Return true if a mode is selected.
#
proc umet_mode_to_edit {} {
    global umetEditMode
    set umetEditMode [string trim $umetEditMode]
    return [expr [string length $umetEditMode] > 0]
}

###########################################################################
#
# Update the buttons containing the modes.
#
proc umet_set_modes {fvar dir} {
    upvar #0 $fvar Files 
    catch {unset Files}
    foreach file [glob -nocomplain [file join $dir *.conf]] {
	set config [file tail $file]
	set mode [file rootname $config]
	set Files($mode) $file
    }
}

proc umet_modes_update {} {
    global umetSiteFile umetHostFile

    # Update the global arrays of the modes in existence.
    
    umet_set_modes umetSiteFile [unameit_filename UNAMEIT_CONFIG] 
    umet_set_modes umetHostFile [unameit_filename UNAMEIT_ETC]

    foreach b [winfo children .modes] {
	if {$b != ".modes.e"} {
	    destroy $b
	}
    }

    foreach mode [lsort [array names umetSiteFile]] {
	pack [radiobutton .modes.b$mode \
		-variable umetEditMode \
		-value $mode \
		-text $mode \
		-anchor w] -fill x -expand 1
    }
}
###########################################################################
#
# Return a list of command items.
proc umet_menu_entries {menu} {
    set entries {}
    for {set i 0} {$i <= [$menu index last]} {incr i} {
	lvarcat entries [umet_cascade_entries $menu $i]
    }
    return $entries
}

proc umet_cascade_entries {menu entry} {
    set type [$menu type $entry]
    switch -- $type {
	command {
	    return [list $menu $entry]
	}
	cascade {
	    return [umet_menu_entries [$menu entrycget $entry -menu]]
	}
    }
    return {}
}

###########################################################################
#
# Reconfigure the mode entries based on the selected mode.
# The Mode pulldown is entry 1 on .menubar
#
# Modes are no_mode or have_HostFile.have_sitefile

proc umet_mode_configure {} {

    global umetModeConfig umetEditMode umetHostFile umetSiteFile

    if {! [info exists umetModeConfig]} {
	set umetModeConfig ""
    } 

    if {! [umet_mode_to_edit]} {
	set newmode no_mode 
    } else {
	if {[info exists umetHostFile($umetEditMode)]} {
	    set hf "have_hostfile"
	} else {
	    set hf "no_hostfile"
	}
	if {[info exists umetSiteFile($umetEditMode)]} {
	    set hs "have_sitefile"
	} else {
	    set hs "no_sitefile"
	}
	set newmode "$hf.$hs"
    }
    if {$newmode == $umetModeConfig} return

    foreach {menu entry} [umet_cascade_entries .menubar 1] {

	set command [$menu entrycget $entry -command]
	lassign $command doit toit stype operation sitefile_usage
	set state disabled
	switch -- $newmode {
	    no_mode {
	    }
	    no_hostfile.no_sitefile {
		switch -- "$operation.$sitefile_usage" {
		    create.write_sitefile {
			set state normal
		    }
		}
	    }
	    no_hostfile.have_sitefile {
		switch -- "$operation.$sitefile_usage" {
		    create.read_sitefile {
			set state normal
		    }
		}
	    }
		
	    have_hostfile.no_sitefile {
		# (somewhat anomolous)
		switch -- $operation {
		    create {
			set state normal
		    }
		}
	    }
		
	    have_hostfile.have_sitefile {
		switch -- $operation {
		    edit {
			set state normal
		    }
		}
	    }
		
	    default {
		error "woops"
	    }
	}
	$menu entryconfigure $entry -state $state
    }
    set umetModeConfig $newmode
}

#
# Reconfigure the Start Menu menu. This is similar to the above routine,
# but there are no cascades, and the items are all enabled if a mode
# is selected. State is normal or disabled, or "" if unknown. 
# The menu is #2 on the menubar.
#

proc umet_start_menu_configure {} {
    global umetStartMenuConfig umetEditMode

    if {! [info exists umetStartMenuConfig]} {
	set umetStartMenuConfig "" 
    } 

    set newmode normal
    if {! [umet_mode_to_edit]} {
	set newmode disabled
    }
    if {$newmode == $umetStartMenuConfig} return

    foreach {menu entry} [umet_cascade_entries .menubar 2] {
	$menu entryconfigure $entry -state $newmode
    }

    set umetStartMenuConfig $newmode
}

###########################################################################
#
# Procedures to add/delete shortcuts from start menu or desktop.
# The selected mode is added or deleted by adding or deleting a shortcut
# with the name "UNameIt <mode>" from either the personal or shared
# UNameIt folder. 
#

proc umet_start_menu {operation which} {
    global umetEditMode

    if {![umet_mode_to_edit]} {
	error "Please enter a mode to $operation."
    }

    package require Shortcuts
    set linkdir [unameit_special_folder $which]
    set link "UNameIt ${umetEditMode}.lnk"
    exec -- explorer.exe $linkdir &
    sleep 1
    switch -- $operation {
	add {
	    set arguments "$umetEditMode unameit"
	    unameit_make_shortcut $linkdir $link unameit_wm $arguments 
	}

	delete {
	    unameit_delete_shortcut $linkdir $link
	}
    }

}

proc umet_edit {apptype stype operation sitefile_usage} {
    global umetEditMode 

    catch {destroy .wizard}
    
    if {![umet_mode_to_edit]} {
	error "Please enter name of mode to $operation."
    }

    ume_edit .wizard $apptype $stype $sitefile_usage \
	    $operation $umetEditMode
    bind .wizard <Destroy> umet_modes_update
}

###########################################################################
#
proc umet_sep {w {side top}} {
    frame $w -height 3 -bg blue
    pack $w -side $side -fill x -expand 1 -pady 20
}

###########################################################################
#
pack [label .instructions -text "Enter or select the name of a mode."] -pady 10
pack [frame .left] -side left -fill both
pack [label .left.mode -text "Mode:"]
pack [frame .modes] -fill x -expand 1 -anchor n
pack [entry .modes.e -textvariable umetEditMode] -fill x -expand 1

###########################################################################
#
# Menu Construction
# 
#	
#	
#	
set mb [menu .menubar -borderwidth 4 -tearoff 0]

menu $mb.file -tearoff 0
$mb.file add command -label Exit -underline 1 -command exit

menu $mb.mode -title "Create or Edit Mode" -tearoff 0 \
	-postcommand umet_mode_configure

menu $mb.mode.unameit_server -tearoff 0
$mb.mode add cascade -label "UNameIt Server" -menu $mb.mode.unameit_server
$mb.mode.unameit_server add command \
	-label "Create Site File and Host File" \
	-command "umet_edit unameit server create write_sitefile"
$mb.mode.unameit_server add command \
	-label "Edit Site File and Host File" \
	-command "umet_edit unameit server edit write_sitefile"

menu $mb.mode.unameit_client -tearoff 0
$mb.mode add cascade -label "UNameIt Client" -menu $mb.mode.unameit_client
$mb.mode.unameit_client add command \
	-label "Create Site File and Host File" \
	-command "umet_edit unameit client create write_sitefile"
$mb.mode.unameit_client add command \
	-label "Create Host File only" \
	-command "umet_edit unameit client create read_sitefile"
$mb.mode.unameit_client add command \
	-label "Edit Site File and Host File" \
	-command "umet_edit unameit client edit write_sitefile"
$mb.mode.unameit_client add command \
	-label "Edit Host File only" \
	-command "umet_edit unameit client edit read_sitefile"

menu $mb.mode.upull_server -tearoff 0
$mb.mode add cascade -label "Upull Server" -menu $mb.mode.upull_server
$mb.mode.upull_server add command \
	-label "Create Site File and Host File" \
	-command "umet_edit upull server create write_sitefile"
$mb.mode.upull_server add command \
	-label "Create Host File only" \
	-command "umet_edit upull server create read_sitefile"
$mb.mode.upull_server add command \
	-label "Edit Site File and Host File" \
	-command "umet_edit upull server edit write_sitefile"
$mb.mode.upull_server add command \
	-label "Edit Host File only" \
	-command "umet_edit upull server edit read_sitefile"

menu $mb.mode.upull_client -tearoff 0
$mb.mode add cascade -label "Upull Client" -menu $mb.mode.upull_client
$mb.mode.upull_client add command \
	-label "Create Site File and Host File" \
	-command "umet_edit upull client create write_sitefile"
$mb.mode.upull_client add command \
	-label "Create Host File only" \
	-command "umet_edit upull client create read_sitefile"
$mb.mode.upull_client add command \
	-label "Edit Site File and Host File" \
	-command "umet_edit upull client edit write_sitefile"
$mb.mode.upull_client add command \
	-label "Edit Host File only" \
	-command "umet_edit upull client edit read_sitefile"

$mb add cascade -label File -underline 0 -menu $mb.file
$mb add cascade -label Mode -underline 0 -menu $mb.mode

if {$tcl_platform(platform) == "windows"} {
    menu $mb.startmenu -title "Start Menu" -tearoff 0 \
	-postcommand umet_start_menu_configure

    $mb.startmenu add command \
	    -label "Add To Personal Start Menu" \
	    -command "umet_start_menu add CurrentUser"
    
    $mb.startmenu add command \
	    -label "Add To Start Menu for All Users"  \
	    -command "umet_start_menu add AllUsers"
    
    $mb.startmenu add command \
	    -label "Delete From Personal Start Menu" \
	    -command "umet_start_menu delete CurrentUser"
    
    $mb.startmenu add command \
	    -label "Delete From Start Menu for All Users" \
	    -command "umet_start_menu delete AllUsers" 
    
    $mb add cascade -label "Start Menu" -underline 0 -menu $mb.startmenu
}

. configure -menu $mb

umet_modes_update
umet_mode_configure

wm title . "UNameIt Mode Editor"
wm minsize . 300 200

interp alias {} bgerror {} umet_error

