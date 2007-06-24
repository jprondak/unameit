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
# $Id: unameit_setup.tcl,v 1.8.10.1 1997/08/28 18:30:14 viktor Exp $
#

# 		Windows UNAMEIT_SETUP.TCL
# 
# Determine which type of setup to use.
# 
# Get location of UNAMEIT.
# 
# Get location of UNAMEIT_ETC.
# 
# If requested, update registry.
#
# If requested, make entries on the 'All Users' Start Menu.
# 
# The key in the Registry uses the unameit version that is compiled in.
# It is passes in as an argument.

# TBD - change the "file removed" to a confirmation dialog.

interp alias {} bgerror {} setup_error

proc setup_param {w label param} {
    frame $w
    pack $w -fill x -expand 1
    pack [label $w.label -text $label] -fill x
    pack [entry $w.entry -width 50 -textvariable Setup($param)] \
	    -side left -fill x -expand 1
    pack [button $w.current -text Current \
	    -command "set Setup($param) \$RegistryValues($param)"] \
	    -side right
    pack [button $w.default -text Default \
	    -command "set Setup($param) \$SetupDefaults($param)"] \
	    -side right
}

proc setup_sep {w {side top}} {
    frame $w
    pack $w -side $side -fill x -expand 1
    pack [frame $w.blank1 -height 10] -fill x -expand 1
    pack [frame $w.line -height 3 -bg blue] -fill x -expand 1
    pack [frame $w.blank2 -height 10] -fill x -expand 1
}

proc setup_label {w text} {
    pack [frame $w] -fill x -expand 1
    pack [label $w.label -wrap 500 -text $text -justify left -anchor w] -fill x -expand 1
    pack [frame $w.sep -height 5] -fill x -expand 1
}

proc setup_buttons {w} {
    pack [frame $w] -fill x -expand 1
    pack [button $w.setreg -text "Set Registry" \
	    -command "setup_registry 1"] -side left -padx 5
    pack [button $w.setaumenu -text "Set Start Menu for All Users" \
	    -command "setup_menu AllUsers 1 "] -side left -padx 5
    pack [button $w.setcumenu -text "Set Start Menu for Current User" \
	    -command "setup_menu CurrentUser 1"] -side left -padx 5
    pack [button $w.exit -text Exit -command exit] -side left -padx 5
}

proc setup_advanced {} {
    global Setup SetupDefaults

    set top [toplevel .setup]
    wm title $top "UNameIt Setup"
    set host [info hostname]
    pack [label $top.title -text "Setup UNameIt on $host"] -fill x -expand 1
    setup_sep $top.tsep

    setup_label $top.lunameit "\
	    Enter the location of the UNameIt software,\
	    as this host knows it.\
	    Include the drive letter if this is a mapped drive."
    setup_param $top.unameit "UNameIt Software Location:" Root
    setup_sep $top.sep1

    setup_label $top.letc "\
	    Enter the name of a directory for UNameIt\
	    configuration files on this host."

    setup_param $top.unameit_etc "UNameIt Directory on The Host:" etc
    setup_sep $top.sep2

    setup_buttons $top.bbox 
}


proc setup_message {message} {
    tk_messageBox -icon info -type ok -title "UNameIt Setup" \
	    -parent . -message $message
}

proc setup_error {message} {
    global errorInfo
    #append message $errorInfo
    tk_messageBox -icon error -type ok -title "UNameIt Setup" \
	    -parent . -message $message
}

proc setup_yesno {message} {
    cequal "yes" [tk_messageBox -icon question -type yesno \
	    -title "UNameIt Setup" \
	    -parent . -message $message]
}

proc setup_registry {{announce 0}} {
    global Setup env

    registry set $Setup(key) Root $Setup(Root)
    registry set $Setup(key) etc $Setup(etc)

    # update env so unameit_filename will work correctly
    set env(UNAMEIT) $Setup(Root)
    set env(UNAMEIT_ETC) $Setup(etc)
    if {$announce} {
	setup_message "The Registry is now set on this host."
    }
}

proc setup_menu {which {announce 0}} {
    global Setup
    set dir [unameit_special_folder $which]
    file mkdir $dir
    exec -- explorer.exe $dir &
    sleep 1
    unameit_make_shortcuts $dir
}

proc setup_check_reg {} {
    global Setup RegistryValues

    catch {unset RegistryValues}
    array set RegistryValues {Root "" etc ""}
    
    registry set $Setup(key)
    set vnames [registry values $Setup(key)]
    foreach vname $vnames {
	set RegistryValues($vname) [registry get $Setup(key) $vname]
    }
}


###########################################################################

proc setup_start {} {
    package require Shortcuts
    package require Wizard
    global SetupDefaults

    setup_check_reg
    catch {destroy .start}
    set top [toplevel .start]
    set bbox [frame $top.bbox]
    wm title $top "UNameIt Setup"
    set host [info hostname]
    pack [label $top.title -text "Setup UNameIt on $host"] -fill x -expand 1
    setup_sep $top.tsep

    pack $bbox -side bottom -fill x -expand 1
    pack [button $bbox.cancel -text Quit \
	    -command exit] -side right -padx 5
    pack [button $bbox.advanced -text "Advanced Setup"\
	    -command "destroy .start; setup_advanced"] -side right -padx 5
    pack [button $bbox.next -text Wizard \
	    -command "destroy .start; setup_wizard"] -side right -padx 5

    setup_label $top.msg "\
	    UNameIt $SetupDefaults(version)\n\n\
	    The UNameIt Setup Wizard will guide you through the\
	    installation procedure. After answering the questions\
	    the choices that you have made will be displayed. At\
	    that point you can choose to finish or change your choices.\n\
	    You can choose Advanced Setup to alter or modify\
	    the current installation. You should only do this\
	    If you are an experienced UNameIt installer."
    setup_sep $top.sep
}

###########################################################################

proc setup_unameit {top} {
    global SetupDefaults

    setup_label $top.lunameit "\
	    Enter the location of the UNameIt software,\
	    as this host knows it.\
	    Include the drive letter if this is a mapped drive.\
	    The software is currently running from \n\n\
	    \t$SetupDefaults(Root).\n\n\
	    To see the default location push Default.\n\
	    To see the current location push Current.\n\
	    "
    setup_param $top.unameit "UNameIt Software Location:" Root
}

proc setup_unameit_check {} {
    global Setup env
    if {[file exists [file join $Setup(Root) bin unameit.exe]]} {
	# update env so unameit_filename will work correctly
	set env(UNAMEIT) $Setup(Root)
	return okay
    }
    if {! [file exists $Setup(Root)]} {
	setup_error "$Setup(Root) does not exist."
    } else {
	setup_error "There is no unameit executable in $Setup(Root)."
    }
    return stay
}

###########################################################################

proc setup_unameit_etc {top} {

    setup_label $top.lunameit "\
	    Enter the name of a directory for UNameIt\
	    files on this host.\n\
	    To see the default location push Default.\n\
	    To see the current location push Current.\n\
	    "
    setup_param $top.unameit_etc "UNameIt Directory on The Host:" etc
}


proc setup_unameit_etc_check {} {
    global Setup env
    if {[file exists $Setup(etc)]} {
	if {[file isdirectory $Setup(etc)]} {
	    # update env so unameit_filename will work correctly
	    set env(UNAMEIT_ETC) $Setup(etc)
	    return okay
	} else {
	    setup_error "The directory $Setup(etc) exists, but it is not a directory"
	}
    } else {
	 if {[setup_yesno "The directory $Setup(etc) does not exist.\n\
		Do you wish to create it?"]} {
	    file mkdir $Setup(etc)
	    return okay
	}
    }
    return stay
}

###########################################################################
proc root_name {name} {
    global env
    file nativename [file join $env(windir) $name]
}

proc krb5_param {w label {default ""}} {
    global Krb5Setup

    # The parameter name is the label made into a word
    regsub -all -- { } $label _ param
    set Krb5Setup($param) $default

    pack [frame $w] -fill x -expand 1
    pack [label $w.label -text $label -width 25 -anchor w] -side left
    pack [entry $w.entry -width 50 -textvariable Krb5Setup($param)] \
	    -side left -fill x -expand 1
    pack [button $w.default -text Default \
	    -command "set Krb5Setup($param) $default"] \
	    -side right
}


proc setup_krb5 {top} {
    global Setup Krb5Setup

    set krb5_ini [root_name krb5.ini]

    if {[file exists $krb5_ini]} {
	set Setup(WriteKrb5Ini) 0
	set Setup(NewKrb5Ini) 0
	setup_label $top.k "\
		You have a Kerberos 5 configuration file in \n\n\
		\t[file nativename $krb5_ini]\n\n\
		Please make sure that the configuration is correct."
    
	pack [radiobutton $top.krb5_okay \
		-text "Kerberos Configuration is Okay" \
		-variable Setup(WriteKrb5Ini) \
		-value 0 \
		-anchor w] -fill x -expand 1
	
	pack [radiobutton $top.krb5_replace \
		-text "Replace Kerberos Configuration with new parameters." \
		-variable Setup(WriteKrb5Ini) \
		-value 1 \
		-anchor w] -fill x -expand 1

	package require Textview
	textview .wizard .wizard.krb5ini $krb5_ini [read_file $krb5_ini]
    } else {
	set Setup(WriteKrb5Ini) 1
	set Setup(NewKrb5Ini) 1
	setup_label $top.k "\
		For Kerberos 5 to run properly, this host requires a \
		configuration file\n\n\
		\t[file nativename $krb5_ini]\n\n\
		Currently, there is no such file. \
		Would you like to create one?"

	pack [radiobutton $top.krb5_yes \
		-text "Yes, Create One Now" \
		-variable Setup(WriteKrb5Ini) \
		-value 1 \
		-anchor w] -fill x -expand 1
	
	pack [radiobutton $top.krb5_replace \
		-text "No, I Will Create One Later" \
		-variable Setup(WriteKrb5Ini) \
		-value 0 \
		-anchor w] -fill x -expand 1
    }
}

proc setup_krb5_params {top} {
    global Setup Krb5Setup
    set krb5_ini [root_name krb5.ini]

    if {! $Setup(WriteKrb5Ini)} {
	setup_label $top.k "\
		The existing Kerberos 5 configuration file will be used."
	return
    }

    if {$Setup(NewKrb5Ini)} {
	setup_label $top.k "\
		Enter the parameters needed for the new configuration file\n\n\
		\t[file nativename $krb5_ini]\n\n\
		Currently, there is no such file. \
		Enter the parameters and this file will \
		be created."
    } else {
	setup_label $top.k "\
		The parameters that you enter will be used to replace \
		the current configuration file\n\n\
		\t[file nativename $krb5_ini]\n\n"
    }
    krb5_param $top.kr "Kerberos Realm"
    krb5_param $top.dd "Default Domain" 
    krb5_param $top.kh "KDC Server Host" 
    krb5_param $top.kp "KDC Server Port" 88
    krb5_param $top.ah "KDC Admin Host"
    krb5_param $top.ap "KDC Admin Port" 749
    krb5_param $top.p "Administrator Principal" "joeuser/admin"
    set Krb5Setup(KDC_Configuration_File) [root_name kdc.ini]
    set Krb5Setup(Client_Configuration_File) $krb5_ini
    set Krb5Setup(KDC_Admin_Directory) [root_name krb5kdc]
}

proc setup_krb5_check {} {
    global Setup Krb5Setup

    if {! $Setup(WriteKrb5Ini)} {
	return okay
    }

    set ini [read_file [unameit_filename krb5_config]]
    set ini [subst -nocommands -nobackslash $ini]
    write_file $Krb5Setup(Client_Configuration_File) $ini
    return okay
}
    


###########################################################################

proc setup_start_menu {top} {
    global Setup

    setup_label $top.lunameit "\
	    You can add a folder of UNameIt commands to the Start\
	    Button for All Users. If you do so, the UNameIt commands\
	    will be available for all users on this host.\
	    This is recommended.\n\
	    "
    pack [checkbutton $top.sm -text "Add to Start Button for All Users" \
	    -variable Setup(sm) -anchor w] -fill x -expand 1
    return 0
}

###########################################################################
#
# Display the parameters about to be used. The check callback
# performs the actual work and returns 1 if successful.

proc setup_finish {top} {
    global Setup

    set message "\
	    You have chosen the following options:\n\n\
	    UNameIt software will be located at:\n\
	    $Setup(Root)\n\n\
	    UNameit files on this host will be in:\n\
	    $Setup(etc)\n\n"
    if {$Setup(sm)} {
	append message "UNameIt will be added to the Start Button for All Users.\n"
    } else {
	append message "UNameIt will NOT be added to the Start Button.\n"
    }
    append message "\nTo finish, push Next.\nTo start over, push Cancel."
    setup_label $top.lunameit $message
    return 0
}

proc setup_finish_check {} {
    global Setup

    setup_registry 0
    if {$Setup(sm)} {
	setup_menu AllUsers 0
    }
    return okay
}

###########################################################################
#

proc setup_done {top} {
    global Setup

    set message "UNameIt is now installed on this host. You can create or edit modes later using the 'Edit Configurations' application on the Start Menu. Do you wish to start this application now?"
    setup_label $top.lunameit $message
    pack [radiobutton $top.edit_mode_yes \
	    -text "Yes, Edit Configurations Now" \
	    -variable Setup(edit_now) \
	    -value 1 \
	    -anchor w] -fill x -expand 1

    pack [radiobutton $top.edit_mode_no \
	    -text "No, I will do it later." \
	    -variable Setup(edit_now) \
	    -value 0 \
	    -anchor w] -fill x -expand 1
    return 0
}

###########################################################################
#

proc setup_wizard {} {
    global Setup

    set procs {
	setup_unameit "UNameIt Software Location" setup_unameit_check
	setup_unameit_etc "Host Files for UNameIt" setup_unameit_etc_check
	setup_start_menu "Start Menu" ""
	setup_krb5 "Kerberos 5 Configuration" ""
	setup_krb5_params "Kerberos 5 Configuration" setup_krb5_check
	setup_finish "Check Installation Parameters" setup_finish_check
	setup_done "Installation Complete" ""
    }
    set result [wizard_run .wizard "UNameIt Setup" $procs]
	
    if {$result != "okay"} {
	setup_start
	return
    }

    if {$Setup(edit_now)} {
	package require Config
	exec [unameit_nativename unameit_win] \
		[unameit_nativename wishx] \
		[unameit_filename unameit_mode_edit]
    }

    exit
}


###########################################################################

wm withdraw .

# set defaults  
array set SetupDefaults { \
	Root C:\\unameit \
	etc C:\\unameit \
	sm 1 \
	edit_now 1
    }
array set SetupDefaults $argv
set SetupDefaults(key) "HKEY_LOCAL_MACHINE\\$SetupDefaults(top_key)\\$SetupDefaults(version)"
array set Setup [array get SetupDefaults]

after idle setup_start
