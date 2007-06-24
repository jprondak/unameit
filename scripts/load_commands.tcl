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
# $Id: load_commands.tcl,v 1.12.10.1 1997/08/28 18:29:04 viktor Exp $
#

#
# This file contains procedures that build commands to run load scripts,
# using parameters from the global LoadSetup.

package require Config

proc find_script {script} {
    unameit_filename UNAMEIT_LOADLIB $script
}

proc find_exe {exe} {
    foreach dir [list UNAMEIT_BIN UNAMEIT_SBIN] {
	set x [unameit_filename $dir $exe]
	if {[file executable $x]} {
	    return $x
	}
    }
    error "cannot find $exe in unameit"
}

proc server_stop {c} {
    upvar 1 $c command
    set command [list [find_exe unameit_shutdown]]
    return 1
}

proc server_start {c} {
    upvar 1 $c command
    set command [list [find_exe unameitd]]
    return 1
}

proc server_load {c} {
    upvar 1 $c command
    global LoadSetup env
    set command\
	[list [find_exe unameitd] [find_script load_adaptive.tcl]\
	    $LoadSetup(CacheDirectory)/newdata.tcl]
    return 1
}

proc copy_checkpoint {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script dat_to_heap.tcl] \
	    -d $LoadSetup(CacheDirectory)]
    return 1
}

#proc dump_heap {c} {
#    upvar 1 $c command
#    global LoadSetup 
#
#    set command [list [find_exe unameitcl] [find_script heap_to_html.tcl] \
#	    -d $LoadSetup(CacheDirectory) \
#	    -h $LoadSetup(HtmlDirectory)]
#    return 1
#}

proc heap_to_dat {c} {
    upvar 1 $c command
    global LoadSetup 

    set command [list [find_exe unameitcl] [find_script heap_to_dat.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -c $LoadSetup(CacheDirectory)]
    return 1
}

proc load_aliases {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_aliases.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -f $LoadSetup(Aliases) \
	    -r $LoadSetup(DefaultRegion) ]
    return 1
}

proc load_domains {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_domains.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -f $LoadSetup(Domains)]
    return 1
}

proc load_hosts {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_hosts.tcl] \
	    -c computer \
	    -d $LoadSetup(CacheDirectory) \
	    -m $LoadSetup(Netmask) \
	    -M $LoadSetup(Netmasks) \
	    -f $LoadSetup(Computers) \
	    -r $LoadSetup(DefaultRegion) ]    
    return 1
}

proc load_dns {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_dns.tcl] \
	    -d $LoadSetup(CacheDirectory)\
	    -m $LoadSetup(Netmask)\
	    -M $LoadSetup(Netmasks)\
	    -r $LoadSetup(DefaultRegion)]
    return 1
}

proc load_persons {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_persons.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -f $LoadSetup(Persons) \
	    -r $LoadSetup(DefaultRegion)\
	    -a $LoadSetup(Aliases)]
    return 1
}

proc load_routers {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_hosts.tcl] \
	    -c router \
	    -d $LoadSetup(CacheDirectory) \
	    -m $LoadSetup(Netmask) \
	    -M $LoadSetup(Netmasks) \
	    -f $LoadSetup(Routers) \
	    -r $LoadSetup(DefaultRegion) ]    
    return 1
}

proc load_hubs {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_hosts.tcl] \
	    -c hub \
	    -d $LoadSetup(CacheDirectory) \
	    -m $LoadSetup(Netmask) \
	    -M $LoadSetup(Netmasks) \
	    -f $LoadSetup(Hubs) \
	    -r $LoadSetup(DefaultRegion) ]    
    return 1
}

proc load_user_groups {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_groups.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -c user_group \
	    -f $LoadSetup(UserGroups) ]
    return 1
}

proc load_application_groups {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_groups.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -c application_group \
	    -f $LoadSetup(ApplicationGroups) ]
    return 1
}

proc load_system_groups {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_groups.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -c system_group \
	    -f $LoadSetup(SystemGroups) ]
    return 1
}

proc load_user_logins {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_users.tcl] \
	    -c user_login \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -l $LoadSetup(UserLogins) \
	    -f $LoadSetup(Aliases) \
	    -a $LoadSetup(Automounts) \
	    -n $LoadSetup(MapName) \
	    -p $LoadSetup(MountPoint) \
	    -o $LoadSetup(MountOptions) ]
    return 1
}

proc load_application_logins {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_users.tcl] \
	    -c application_login \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -l $LoadSetup(ApplicationLogins) \
	    -f $LoadSetup(Aliases) ]
    return 1
}

#
# NOTE: This is not currently done by load_users
#
proc load_system_logins {c} {
    global LoadSetup 
    upvar 1 $c command
    set command [list [find_exe unameitcl] [find_script load_users.tcl] \
	    -c system_login \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -l $LoadSetup(SystemLogins) \
	    -a $LoadSetup(Automounts) \
	    -f $LoadSetup(Aliases) \
	    -n $LoadSetup(MapName) \
	    -p $LoadSetup(MountPoint) \
	    -o $LoadSetup(MountOptions) ]
    return 1
}

proc load_user_group_members {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_group_users.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -c user_group \
	    -f $LoadSetup(UserGroups) ]
    return 1
}

proc load_application_group_members {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_group_users.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -c application_group \
	    -f $LoadSetup(ApplicationGroups)  ]
    return 1
}

#
# NOTE: This is not currently done by load_group_users
#
proc load_system_groups_members {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_group_users.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -c system_group \
	    -f $LoadSetup(SystemGroups)  ]
    return 1
}

proc load_netgroups {c} {
    upvar 1 $c command
    global LoadSetup 

    set command [list [find_exe unameitcl] [find_script load_netgroups.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -f $LoadSetup(Netgroups) \
	    -r $LoadSetup(DefaultRegion) ]
    return 1
}

proc load_generate {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_generate.tcl] \
	    -d $LoadSetup(CacheDirectory)]
    return 1
}

proc load_networks {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_networks.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -r $LoadSetup(DefaultRegion) \
	    -m $LoadSetup(Netmask) \
	    -M $LoadSetup(Netmasks) \
	    -n $LoadSetup(Networks) ]
    return 1
}

proc load_services {c} {
    upvar 1 $c command
    global LoadSetup 
    set command [list [find_exe unameitcl] [find_script load_services.tcl] \
	    -d $LoadSetup(CacheDirectory) \
	    -f $LoadSetup(Services)]
    return 1
}
