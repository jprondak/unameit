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
# $Id: configdb.tcl,v 1.2.12.1 1997/08/28 18:29:39 viktor Exp $
#

# Package Configdb - database about configuration parameters.
#
# Fields:
#  Name:
#	system		All | unix | windows - same as tcl_platform(platform)
#	file		Host | Site
#	application	All | Unameit | Upull | <application>
#	module		All | <application>
#	parameter	the keyword used to identify the parameter
#  
#  Values:
#	default		the default value of this parameter
#	label		if present, the default value of name.label
#	readonly	if present, the default value of name.readonly
#	hidden		if present, the default value of name.hidden
#	secret		if present, the default value of name.hidden
#
#  Editor Information:
#	editor_label	label used in editors
#	help		help text

package require Config
package require Fancylistbox

###########################################################################
#
# Read in the configuration database.
# Store each array variable in ConfigDb_N where N is a number.
#
proc configdb_read {filename} {
    global ConfigDbEntries
    set ConfigDbEntries 0
    set cf [open $filename r]
    while {-1 < [lgets $cf entry]} {
	upvar #0 Configdb_$ConfigDbEntries p
	catch {unset p}
	set p(system) All
	array set p $entry
	if {[info exists p(parameter)]} {
	    incr ConfigDbEntries
	} else {
	    catch {unset p}
	    continue
	}
    }
    close $cf
}

#
# Write out the configuration database. Remove any x.y parameters that
# are blank. 
#
proc configdb_write {filename} {
    global ConfigDbEntries 
    set cf [open $filename w]
    for {set i 0} {$i < $ConfigDbEntries} {incr i} {
	upvar #0 Configdb_$i p
	if {[array exists p]} {

	    # remove blank options
	    foreach option [configdb_parameter_options] {
		if {[info exists p($option)]} {
		    set p($option) [string trim $p($option)]
		    if {[string length $p($option)] <= 0} {
			unset p($option)
		    }
		}
	    }
	    
	    # save data
	    puts $cf [array get p]
	}
    }
    close $cf
}


###########################################################################
#
#			Dialog Routines
#
# If a parameter is selected, set vname to the name of the array that 
# corresponds to the line, and return TRUE. Otherwise, return FALSE.
# Also sets lname to the line number that was selected.
#
proc configdb_param_selected {lname vname} {
    global ConfigDbDialogLine
    upvar #0 ConfigDbDialogInfo dbinfo
    set lb $dbinfo(Parameters)
    foreach lbsel [$lb curselection] {
	upvar 1 $lname l
	set l $lbsel

	upvar 1 $vname c
	set c $ConfigDbDialogLine($lbsel)

	return 1
    }
    return 0
}

###########################################################################
#
# Construction routines - an entry, a text, a separator.
#
proc configdb_param_entry {box title var {state normal}} {
    pack [frame $box] -fill x -expand 1
    label $box.field -text "$title:" -anchor w -width 20
    pack $box.field  -side left
    entry $box.value -textvariable $var -state $state 
    pack $box.value -fill x -expand 1 -side left
}

proc configdb_param_text {box title} {
    pack [frame $box] -fill x -expand 1
    label $box.field -text "$title:" -anchor w 
    pack $box.field -fill x -expand 1
    text $box.value -height 5
    pack $box.value -fill x -expand 1
}

proc configdb_param_sep {box} {
    pack [frame $box -bg blue -height 3] -fill x -expand 1
}

# destroy variables if the box is destroyed.
proc configdb_param_destroy {} {
    catch {uplevel #0 unset CDbPInfo}
    catch {uplevel #0 unset CDbPDate}
}

###########################################################################
#
# Copy the data from a parameter into the dialog box, or go the other way.
# 
proc configdb_param_get {} {
    upvar #0 CDbPInfo pinfo
    upvar #0 CDbPData data

    upvar #0 ConfigDbDialogInfo dbinfo
    upvar #0 $pinfo(Var) p

    # Update the parameter array using the data array
    array set p [array get data]
    set p(help) [$pinfo(Help) get 1.0 end]

    # Update the display line on the dialog
    set lnum $pinfo(Line)
    set lb $dbinfo(Parameters)
    set line "$p(system)\t$p(file)\t$p(application)\t$p(module)\t$p(parameter)\t$p(default)"
	
    $lb delete $lnum 
    $lb insert $lnum $line
}

proc configdb_param_set {} {
    upvar #0 CDbPInfo pinfo
    upvar #0 $pinfo(Var) p
    upvar #0 CDbPData data

    # remove the previous data
    foreach f [array names data] {
	set data($f) ""
    }
    set data(help) ""

    # update data with parameter data
    array set data [array get p]
    $pinfo(Help) delete 1.0 end
    $pinfo(Help) insert end $data(help)
}

###########################################################################
#
# Bring up the dialog box for parameter editing.
#
# Data fields from the form are bound to CDbPData.
# CDbPData is the array whose elements are bound to the fields of the
# dialog.
# CDbPInfo(Var) is the name of the array that is currently being edited.
# CDbPInfo(Line) is the line number in the ConfigDbDialog.
#
proc configdb_param_edit {} {

    upvar #0 CDbPInfo pinfo
    if {! [configdb_param_selected pinfo(Line) pinfo(Var)]} return

    upvar #0 ConfigDbDialogInfo dbinfo

    #
    # If the window already exists, raise it. 
    #
    if {[info exists pinfo(Toplevel)]} {
	set t $pinfo(Toplevel)
	wm deiconify $t
	raise $t $dbinfo(Toplevel)
    } else {
	set pinfo(Toplevel) [toplevel $dbinfo(Toplevel).param]
	set t $pinfo(Toplevel)
	bind $t <Destroy> configdb_param_destroy
	wm title $t "Edit Parameter"
	wm group $t $dbinfo(Toplevel)
	set s disabled 

	pack [label $t.lname -text Parameter] -fill x -expand 1
	configdb_param_entry $t.file File CDbPData(file) $s
	configdb_param_entry $t.app Application CDbPData(application) $s
	configdb_param_entry $t.module Module CDbPData(module) $s
	configdb_param_entry $t.parameter Parameter CDbPData(parameter) $s
	configdb_param_sep $t.sep1

	pack [label $t.lvalue -text Values] -fill x -expand 1
	configdb_param_entry $t.default Default CDbPData(default)
	configdb_param_entry $t.label Label CDbPData(label)
	configdb_param_entry $t.readonly Readonly CDbPData(readonly)
	configdb_param_entry $t.hidden Hidden CDbPData(hidden)
	configdb_param_entry $t.secret Secret CDbPData(secret)
	configdb_param_sep $t.sep2

	pack [label $t.leditors -text "Editor Information"] -fill x -expand 1
	configdb_param_entry $t.elabel "Editor Label" CDbPData(editor_label)
	configdb_param_text $t.help Help 
	set pinfo(Help) $t.help.value
	configdb_param_sep $t.sep3

	pack [frame $t.bbox] -side bottom -fill x -expand 1
	set bb $t.bbox
	set b1 [button $bb.ok -text OK -command "configdb_param_get; wm withdraw $t"]
	set b2 [button $bb.apply -text Apply -command configdb_param_get]
	set b3 [button $bb.cancel -text Cancel -command "wm withdraw $t"]
	pack $b1 $b2 $b3 -side left 
    }
	
    configdb_param_set
}

#
# Construct a dialog with information from the configuration database.
# This is information about the parameters, including defaults, but does
# not contain actual values from configuration files.
#
proc configdb_dialog {} {
    global ConfigDbEntries ConfigDbDialogLine
    upvar #0 ConfigDbDialogInfo dbinfo

    #
    # If the window already exists, raise it. 
    #
    if {[info exists dbinfo(Toplevel)]} {
	wm deiconify $dbinfo(Toplevel)
	raise $dbinfo(Toplevel)
	return
    } 
    
    set dbinfo(Toplevel) [toplevel .top]

    set t $dbinfo(Toplevel)
    set dbinfo(EditBox) $t.editbox

    wm title $t "Configuration Parameters"

    # 
    # Put the buttons at the bottom.
    #
    set f [frame $t.bbox]
    pack $f -side bottom -fill x 
    button $f.save -text Save -command "configdb_save_file"
    button $f.quit -text Quit -command "exit"
    pack $f.save $f.quit -side left -expand 1

    set f [frame $t.data]
    pack $f -side top
 
   #
    # We use a single line text field as a label, so we can make
    # tabstops that line up with the columns in the text area.
    #
    set f [frame $t.fdata]
    pack $f -fill x -expand 1

    set f [frame $f.fdata]
    pack $f -side left -fill x -expand 1
    set tabs {2c 4c 7c 10c 18c}
    set width 100
    pack [text $f.title -width $width -height 1 -tabs $tabs] -fill x -expand 1
    $f.title insert end "System\tFile\tApp/Class\tModule\tParameter\tDefault"
    $f.title configure -state disabled

    set lb $f.data
    pack [fancylistbox $lb -width $width -height 20 -tabs $tabs] -fill x -expand 1
    set dbinfo(Parameters) $lb

    pack [scrollbar $t.fdata.vsb -command "$dbinfo(Parameters) yview"] -side left -fill y
    set dbinfo(VSB) $t.fdata.vsb

    $lb configure -yscrollcommand "$dbinfo(VSB) set"


    #
    # Set up the bindings.
    # A button click selects and highlights a line.
    # Double-1 activates edit on the selected line.

    bind $lb <Button-1> "focus $lb"
    bind $lb <KeyPress-Delete> "configdb_param_delete"
    bind $lb <KeyPress-Return> "configdb_param_edit"
    bind $lb <Double-1> "configdb_param_edit"
    bind $lb <Select> "puts selected"

    # Make a set of line-name pairs
    set lines {}
    for {set i 0} {$i < $ConfigDbEntries} {incr i} {
	upvar #0 Configdb_$i p
	set line "$p(system)\t$p(file)\t$p(application)\t$p(module)\t$p(parameter)\t$p(default)"
	lappend lines [list $line Configdb_$i]
    }

    # Sort the line-name pairs, and save the name of the variable 
    # associated with the line.
    set i 0
    foreach entry [lsort $lines] {
	lassign $entry line ConfigDbDialogLine($i)
	$lb insert end $line
	incr i
    }
}

proc configdb_parameter_options {} {
    list readonly hidden label secret
}

package provide Configdb 1.0
