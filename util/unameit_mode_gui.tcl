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
# $Id: unameit_mode_gui.tcl,v 1.4.12.1 1997/08/28 18:29:51 viktor Exp $
#

#
# 		NOT CURRENTLY IN USE. see ccpowell
#
# Mode Maintenance Utility GUI. This is a wish script.
#
# All information about a configuration is kept in umg_X_T and umg_config_X_T,
# where X is the mode name, and T is Host or Site. 
# Multiple configurations can be displayed, each with its own mode. 
#
#

package require Config
package require Fancylistbox
# TBD package require Shortcuts
flb_init

###########################################################################
#
proc umg_info_label {parent name field value} {
    set box $parent.f$name
    pack [frame $box] -fill x
    label $box.field -text "$field :" -anchor w -width 20
    pack $box.field -side left
    label $box.value -text $value -anchor w 
    pack $box.value -side left -fill x -expand 1
}

###########################################################################
#
# This will be called when the edit window is destroyed. Do NOT invoke
# this command directly or the edit window will be brain-damaged.
#
proc umg_destroy_mode {mode type} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config

    catch {unset config}
    catch {unset modeinfo}
}

###########################################################################
#
# Construct a dialog with information from the site file or host file.
#
proc umg_mode_display {mode type filename} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config

    #
    # If the window already exists, raise it. 
    #
    if {[info exists modeinfo(Toplevel)]} {
	wm deiconify $modeinfo(Toplevel)
	raise $modeinfo(Toplevel)
	return
    } 
    
    set modeinfo(Mode) $mode
    set modeinfo(Type) $type
    set modeinfo(File) $filename
    set modeinfo(Toplevel) [toplevel .top_${mode}_${type}]

    set t $modeinfo(Toplevel)
    wm title $t "Mode Editor : $mode $type"

    set modeinfo(EditBox) $t.editbox

    #
    # If the edit box goes away for any reason, get rid of the globals.
    #
    bind $t <Destroy> "umg_destroy_mode $mode $type"

    # 
    # Put the buttons at the bottom.
    #
    set f [frame $t.bbox]
    pack $f -side bottom -fill x 
    button $f.preview -text Preview -command "umg_preview_file $mode $type"
    button $f.save -text Save -command "umg_save_file $mode $type"
    button $f.quit -text Dismiss -command "destroy $t"
    pack $f.preview $f.save $f.quit -side left -expand 1

    set f [frame $t.info]
    pack $f -side top
    umg_info_label $f mode Mode $mode
    umg_info_label $f type "File Type" $type
    umg_info_label $f filename "File Name" $filename 
    umg_info_label $f host "Host" [info hostname]

    #
    # We use a single line text field as a label, so we can make
    # tabstops that line up with the columns in the text area.
    #
    set f [frame $t.fdata]
    pack $f -fill x -expand 1

    set f [frame $f.fdata]
    pack $f -side left -fill x -expand 1
    set tabs {3c 6c 12c}
    set width 75
    pack [text $f.title -width $width -height 1 -tabs $tabs] -fill x -expand 1
    $f.title insert end "App/Class\tModule\tParameter\tValue"
    $f.title configure -state disabled

    pack [fancylistbox $f.data -width $width -height 20 -tabs $tabs] -fill x -expand 1
    set modeinfo(Parameters) $f.data

    pack [scrollbar $t.fdata.vsb -command "$modeinfo(Parameters) yview"] -side left -fill y
    set modeinfo(VSB) $t.fdata.vsb

    $f.data configure -yscrollcommand "$modeinfo(VSB) set"

    #
    # Set up the bindings.
    # A button click selects and highlights a line.
    # Double-1 activates edit on the selected line.

    bind $f.data <Button-1> "focus $f.data"
    bind $f.data <KeyPress-Delete> "umg_param_delete $mode $type"
    bind $f.data <KeyPress-Return> "umg_param_edit $mode $type"
    bind $f.data <Double-1> "umg_param_edit $mode $type"
    bind $f.data <Button-2> "focus $f.data; umg_param_menu $f.data"

    #
    # Read the configuration file, and insert the information into the box.
    #
    catch {unset config}
    read_config_file config $type $filename
    foreach {param} [lsort [array names config]] {
	set value $config($param)
	lassign [split $param /] type app module parameter
	$f.data insert end "$app\t$module\t$parameter\t$value"
    }
}


proc trace {msg} {
    tk_messageBox -icon info -type ok -title Hi -parent . -message $msg
}

###########################################################################
#
# Edit the currently selected line. This may occur in response to a 
# double click or to a keyboard command.
#
proc umg_param_edit {mode type} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config
    
    set listbox $modeinfo(Parameters)
    set sel [$listbox curselection]

    set editbox $modeinfo(EditBox)
    if {[winfo exists $editbox]} {
	destroy $editbox
    }
    
    if {[cequal "" $sel]} {
	tk_messageBox -icon info -type ok \
		-title "Instructions" -parent $modeinfo(Toplevel) \
		-message "Please select an item to edit."
	return
    }

    #
    # Get the first selected line
    #
    lassign [$listbox get $sel] line
    set value [lassign $line app module parameter]

    toplevel $editbox
    wm transient $editbox $modeinfo(Toplevel)
    wm title $editbox "Edit Parameter : $mode $type"

    set f [frame $editbox.f]
    pack $f -fill x 

    # Display the description of this variable
    umg_info_label $f mode Mode $mode
    umg_info_label $f type Type $type
    umg_info_label $f app "Application/Class" $app
    umg_info_label $f module "Module" $module
    umg_info_label $f parameter "Parameter" $parameter

    set modeinfo(EditBoxValue) $f.entry
    pack [entry $f.entry -width 40]
    $f.entry insert 0 $value

    set f [frame $editbox.bbox]
    pack $f -side bottom -fill x 
    button $f.ok -text OK -command "umg_param_update $mode $type $sel"
    button $f.quit -text Cancel -command "destroy $editbox"
    pack $f.ok $f.quit -side left -expand 1
    focus $modeinfo(EditBoxValue)
}

###########################################################################
#
# If an edit box okays a change, this gets called.
#
proc umg_param_update {mode type sel} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config
    
    set listbox $modeinfo(Parameters)

    set entry $modeinfo(EditBoxValue)
    if {![winfo exists $entry]} {
	return
    }

    lassign [$listbox get $sel] line
    set old_value [lassign $line app module parameter]
    set value [$entry get]
    set key $type/$app/$module/$parameter

    set config($key) $value
    $listbox delete $sel
    $listbox insert $sel "$app\t$module\t$parameter\t$value"

    destroy $modeinfo(EditBox)
}


###########################################################################
#
# Delete the currently selected line. This is disabled during parameter
# editing.
#
proc umg_param_delete {mode type} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config

    set listbox $modeinfo(Parameters)
    set sel [$listbox curselection]

    set editbox $modeinfo(EditBox)
    if {[winfo exists $editbox]} {
	raise $editbox
	return
    }
    
    foreach param [lsort -integer -decreasing $sel] {
	$listbox delete $param
    }
}

###########################################################################
#
# Preview the file. 
#
proc umg_preview_file {mode type} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config

    umg_format_config_file config stuff

    set mb .preview
    catch {destroy $mb}
    toplevel $mb
    wm transient $mb .
    wm title $mb "Preview of $modeinfo(File)"

    pack [button $mb.quit -command "destroy $mb" -text OK] -side bottom

    set text $mb.text
    set sb $mb.vsb

    text $text -yscrollcommand "$sb set" -tabs {1c 7c}
    scrollbar $sb -command "$text yview"
    pack $sb -side right -fill y
    pack $text -side left
    $text insert end $stuff

}

###########################################################################
#
# Save the file. 
#
proc umg_save_file {mode type} {
    set dialog_var umg_${mode}_${type}
    set config_var umg_config_${mode}_${type}
    upvar #0 $dialog_var modeinfo
    upvar #0 $config_var config

    umg_format_config_file config stuff
    write_file $modeinfo(File) $stuff
}

###########################################################################
#
# Put the configuration file information into the format of a config file.
# These are sorted by application and module, with application and module
# lines written at appropriate times.
#
proc umg_format_config_file {config_var file_var} {
    upvar 1 $config_var config
    upvar 1 $file_var output

    set output ""

    set current_app ""
    set current_module ""
    if {[info exists config(Format)]} {
	append output "Format $config(Format)\n"
    }
    foreach param [lsort [array names config]] {
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
# Create a listbox, and set bindings so that activating the item
# will bring up an edit box for the mode and type.
#
# The global umgModelb contains the following types of values:
# umgModelb(listboxes) contains a list of listboxes that have been made
# umgModelb($listbox) contains the type of the listbox
# umgModelb($listbox-$number) contains mode, type and filename

# Set mtf to {mode type filename} for the first selected entry found.
# There should only be one selected (if any).
# Returns true if mtf was set. If no entry is selected, returns false
# and leaves mtf unchanged.

proc umg_modelb_selected {mtfv} {
    global umgModelb
    foreach lb $umgModelb(listboxes) {
	set nums [$lb.lb curselection]
	if {[lempty $nums]} continue

	lassign $nums num
	set key ${lb}_${num}
	if {[info exists umgModelb($key)]} {
	    upvar 1 $mtfv mtf
	    set mtf $umgModelb($key)
	    return 1
	}
    }
    return 0
}


#edit whichever one(s) is selected
proc umg_modelb_edit {} {
    if {[umg_modelb_selected mtf]} {
	lassign $mtf mode type filename
	umg_mode_display $mode $type $filename
    }
}

proc umg_modelb {lb type} {
    global umgModelb

    frame $lb
    set listbox $lb.lb
    set scrollbar $lb.sb 
    listbox $listbox -height 5 -yscrollcommand "$scrollbar set"
    scrollbar $scrollbar -command "$listbox yview"
    pack $listbox -side left
    pack $scrollbar -side right -fill y
    bind $listbox <Double-1> "umg_modelb_edit"
    if {! [info exists umgModelb(listboxes)]} {
	set umgModelb(listboxes) {}
    }
    lappend umgModelb(listboxes) $lb
    set umgModelb($lb) $type
    return $lb
}

proc umg_modelb_insert {lb mode filename} {
    global umgModelb

    set type $umgModelb($lb)
    set num [$lb.lb index end]
    $lb.lb insert $num $mode
    set key ${lb}_${num}
    set umgModelb($key) [list $mode $type $filename]
}


###########################################################################
#
# Return a list of the modes in existence.
#
proc umg_site_modes {} {
    set modes {}
    foreach f [lsort [glob -nocomplain [unameit_filename UNAMEIT_CONFIG *.conf]]] {
	set config [file tail $f]
	set mode [file rootname $config]
	lappend modes $mode $f
    }
    return $modes
}
    
proc umg_host_modes {} {
    set modes {}
    foreach f [lsort [glob -nocomplain [unameit_filename UNAMEIT_ETC unameit *.conf]]] {
	set config [file tail $f]
	set mode [file rootname $config]
	lappend modes $mode $f
    }

    return $modes
}

proc umg_user_modes {} {
    set modes {}
    foreach f [lsort [glob -nocomplain [file join ~ .unameit *.conf]]] {
	set config [file tail $f]
	set mode [file rootname $config]
	lappend modes $mode $f
    }

    return $modes
}
###########################################################################
#
# Procedures to add/delete shortcuts from start menu or desktop.
# The selected mode is added or deleted by adding or deleting a shortcut
# with the name "UNameIt <mode>" from either the personal or shared
# UNameIt folder. NOTE: to be valid, the configuration file should be
# on the shared list; we may want to enforce this someday.
#
# TBD - the icon is specifically set to the setup icon. We may want
# to use different icons.

proc umg_modelb_add_sc {which} {
    package require Shortcuts

    if {![umg_modelb_selected mtf]} return
    
    set message ""
    lassign $mtf mode type filename
    set linkdir [file join [unameit_special_folder $which]]
    if {! [file exists $linkdir]} {
	file mkdir $linkdir
	set message "The folder $linkdir has been created. "
    }

    set link [file join $linkdir "UNameIt ${mode}.lnk"]
    set path [unameit_filename unameit_wm]
    set arguments "$mode unameit"
    set icon_file [unameit_filename setup]
    shortcut_create $link $path $arguments $icon_file 0

    append message "UNameIt $mode has been added to $which."
    tk_messageBox -icon info -type ok -title "UName*It Mode Added" \
	    -parent . -message $message
    return
}


proc umg_modelb_delete_sc {which} {
    package require Shortcuts
    if {![umg_modelb_selected mtf]} return
    
    lassign $mtf mode type filename
    set linkdir [file join [unameit_special_folder $which]]
    if {[file exists $linkdir]} {
	set link [file join $linkdir "UNameIt ${mode}.lnk"]
	if {[file exists $link]} {
	    file delete -- $link
	    set message "UNameIt $mode has been deleted from $which."
	} else {
	    set message "UNameIt $mode did not exist for $which."
	}
    } else {
	set message "The UNameIt folder for $which did not exist."
    }
    tk_messageBox -icon info -type ok -title "UName*It Mode Deletion" \
	    -parent . -message $message
}



###########################################################################
#

set mb [menu .menubar]
set mbf [menu $mb.file]

$mb add cascade -label File -underline 0 -menu $mbf
$mbf add command -label Edit -underline 0 -command umg_modelb_edit
$mbf add command -label "Add To Personal Start Menu" \
	-underline 0 -command "umg_modelb_add_sc CurrentUser"
$mbf add command -label "Add To Start Menu for All Users" \
	-command "umg_modelb_add_sc AllUsers"
$mbf add command -label "Delete From Personal Start Menu" \
	-underline 0 -command "umg_modelb_delete_sc CurrentUser"
$mbf add command -label "Delete From Start Menu for All Users" \
	-command "umg_modelb_delete_sc AllUsers"
$mbf add command -label Exit -underline 1 -command exit

. configure -menu $mb


pack [label .shared -text {These are the shared configuration files.}]
set type Site
set lb [umg_modelb .lb$type $type]
pack $lb
foreach {mode filename} [umg_site_modes] {
    umg_modelb_insert $lb $mode $filename
}

set host [info hostname]
set type Host
set text "These are configuration files on host $host."
pack [label .host -text $text] -pady 5
set lb [umg_modelb .lb$type $type]
pack $lb
foreach {mode filename} [umg_host_modes] {
    umg_modelb_insert $lb $mode $filename
}

set user "All Users"
catch {set user $env(USERNAME)}
catch {set user $env(USER)}
set type User
set text "These are configuration files for the user $user."
pack [label .user -text $text] -pady 5
set lb [umg_modelb .lb$type $type]
pack $lb
foreach {mode filename} [umg_user_modes] {
    umg_modelb_insert $lb $mode $filename
}


wm title . "Mode Editor"
