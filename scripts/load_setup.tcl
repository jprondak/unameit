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

proc load_setup_dialog {} {

    global LoadSetup 

    if {[winfo exists .lf]} {
	wm deiconify .lf
	raise .lf
	return
    }

    toplevel .lf
    pack [label .lf.dir -text "Directory: [pwd]"] -anchor w
    pack [frame .lf.sep -bg black -height 2] -fill x

    pack [frame .lf.file_entries] -fill x    
    
    pack [frame .lf.buttons] -fill x
    pack [button .lf.buttons.dismiss -text Dismiss -command "wm withdraw .lf"] \
	    -side left
    pack [button .lf.buttons.defaults -text "Restore Default Setup" -command load_setup_defaults] \
	    -side left
    pack [button .lf.buttons.read -text "Read Setup" -command load_setup_get] \
	    -side left
    pack [button .lf.buttons.save -text "Save Setup" -command load_setup_put] \
	    -side left

    set fnum 0
    foreach f [lsort [array names LoadSetup]] {
	incr fnum
	set fe .lf.file_entries.f$fnum
	pack [frame $fe] -fill x
	pack [label $fe.label -text $f -width 20 -anchor w] -side left
	pack [entry $fe.entry -textvariable LoadSetup($f)] \
		-side right -fill x -expand 1 
    }
    wm title .lf "LoadRunner Input File Setup"
    wm group .lf .
}

#
# Read the configuration file
#
proc load_setup_get {} {

    global LoadSetup
    if {! [file readable $LoadSetup(Setup)]} {
	tk_dialog .warning "LoadRunner WARNING" \
		"LoadRunner Input File Setup file $LoadSetup(Setup) \
		could not be read. \
		Check Input File Setup." \
		"" 0 okay
	return
    }

    set conf { *([^ ]+) +([^ ]+)}
    set s [open $LoadSetup(Setup) r]
    while {0 <= [gets $s line]} {
	regsub -all -- "\t" $line " " line
	regexp -- $conf $line junk param value

	if {[cequal "" $param]} {
	    continue(Setup)
	}
	set LoadSetup($param) $value
    }

    close $s
}

proc load_setup_put {} {

    global LoadSetup 

    set s [open $LoadSetup(Setup) w]
    foreach f [lsort [array names LoadSetup]] {
	puts $s [format "%-30s %s" $f $LoadSetup($f)]
    }
    close $s
}

proc load_setup_defaults {} {
    global LoadSetup

    array set LoadSetup [list \
	    Aliases			aliases	\
	    ApplicationGroups		application_groups \
	    ApplicationLogins		application_logins \
	    Automounts			automounts \
	    Computers			hosts \
	    DefaultRegion		your.domain.name \
	    Domains			domains \
	    Hubs			hubs \
	    Logfile			load.log \
	    MountPoint			/home \
	    MapName			auto_home \
	    MountOptions		-rw,hard,intr \
	    Netgroups			netgroups \
	    Netmasks			netmasks \
	    Netmask			ffffff00 \
	    Networks			networks \
	    Persons			persons \
	    Routers			routers \
	    Services			services \
	    Setup			load.conf \
	    UserGroups			user_groups \
	    UserLogins			user_logins \
	    CacheDirectory		data \
	]
}
