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
# $Id: load_users.tcl,v 1.32.12.1 1997/08/28 18:29:16 viktor Exp $
#

# Create user_login, person, and automount entries given:
#	data directory
#	/etc/passwd file
# 	name of default region
#	name of automount map file
#	name of automount map to be produced (or used)
#	mount point of automount_map
#
# There are 3 types of groups: user_group, system_group and group
#
# Application Logins (class login) are unique by name and uid in the region,
# and are owned by the region.
# User Logins (class user_login) are unique by name and uid in the cell,
# and are owned by the region.
# System Logins (class system_login) are not handled here.

# The person must already be present in the organization.

# The automount map file has the format of 'ypcat -k mapname', i.e. 
#
#	key [options] host:directory[:&]
#
# The automount map has the following fields set:
#
#	mount_point	string, set to mount point from command line
#	mount_opts	string, set to options from automount map file
#	name		string, set to name from command line
#
# User_logins are a subclass of automount entries, so automounts are
# NOT produced for any line of the automount map file that defines
# a mount point for a user. All other lines produce automount entries.
# Fields set in either the user_login or automount instance are:
#
#	owner		oid of the containing cell
#	name
#	unix_pathname
#	auto_map	oid of corresponding automount_map
#	nfs_server	oid of host

# Processing:
# First, the automount map file is read and the entries to be made are
# stored. 
# Second, the mail alias file is read and all entries like
#	user:user@host
# are used to set the user's mailhost.
# Then the user_login and automount classes are processed in
# the data directory, using the stored information. Automounts are
# not created if they match users which are automounted.

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB read_aliases.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

###########################################################################
#
# Save up automount information. This is almost a complete set of fields, so 
# the entire instance can be generated. Also needed are auto_map and owner,
# which are invariant for all these instances.
#
# request_number is the name of a variable to use as a key for the request,
# and then to increment 
# 
# key is the same as 'name' field of automount or user_login
#
# Secondary automounts are owned by the primary automount.
# Append the secondaries to a list. 

proc set_automount_request {key host pathname} {
    global AmRequest SecAmRequest

    log_debug "automount $key, $host, $pathname"

    if {! [info exists AmRequest($key)]} {
	set AmRequest($key) [list nfs_server $host unix_pathname $pathname]
    } else {
	lappend SecAmRequest($key)\
	    [list nfs_server $host unix_pathname $pathname]
    }
}

###########################################################################
#
# Write out all undeleted automounts. This is called 
# just before closing.
#
proc save_automounts {datadir auto_map} {
    global AmRequest SecAmRequest RegionOid

    foreach key [array names AmRequest] {
	catch {unset F}
	array set F $AmRequest($key)
	set F(Class) automount
	set F(name)  $key
	set F(owner) $RegionOid
	set F(auto_map) $auto_map

	if {[is_duplicate_automount $datadir F]} {
	    log_ignore "automount $key is already present"
	    continue
	}
	oid_heap_create_a $datadir F

	# TBD - secondary automounts 
    }
}

###########################################################################
#
# Parse the auto map file and save the entries.
#  
proc parse_automap_file {datadir automap_file} {
    global OrgOid OrgOf

    set requests 0

    set fh [open $automap_file r]
    
    while {[gets $fh line] != -1} {
	log_debug $line

	#
	# Parse the record
	# Comments start with #
	# key [options] host:dir[:&]
	# options start with a -
	# Entry lines are split on whitespace
	#
	set line [string trim $line]
	if {[cequal "" $line]} continue
	if {[regexp {^#} $line]} continue
	
	regsub -all -- "\[ \t\]+" $line " " line
	set pieces [split $line]

	if {[llength $pieces] < 2} {
	    log_reject "ignoring line (not enough fields): $line"
	    continue
	}

	set key [lindex $pieces 0]
	set options [lindex $pieces 1]

	# If the second field starts with - it is options.
	if {[string match -* $options]} {
	    if {[llength $pieces] < 3} {
		log_reject "ignoring line (no spec): $line"
		continue
	    }

	    set speclist [lrange $pieces 2 end]
	} else {
	    set speclist [lrange $pieces 1 end]
	}

	# Process each mount point
	# only the first one is a primary mountpoint
	foreach spec $speclist {
	    
	    # Split spec into host and pathname
	    set pieces [split $spec :]
	    set hostname [lindex $pieces 0]
	    set pathname [join [lrange $pieces 1 end] :]

	    # Find a host or server alias to use
	    if {! [lookup_host_oid $datadir host $hostname]} {
		log_reject "automount $key: unknown host $hostname"
		continue
	    }
	    
	    #save this on the todo list
	    set_automount_request $key $host $pathname
	}
    }
    close $fh
    return $requests
}

###########################################################################
#
# Split gecos into fullname and other information.
# Other information is anything after ','
# Returns false if the string cannot be processed.
#
proc split_gecos {gecos p_fullname p_otherstuff} {
    upvar 1 $p_fullname fullname \
	    $p_otherstuff otherstuff
    set gecos [string trim $gecos]
    set fullname $gecos
    set otherstuff ""
    if {[regexp -- {([^,]*),(.*)} $gecos junk fullname otherstuff]} {
	set fullname [string trim $fullname]
	set otherstuff [string trim $otherstuff]
	if {! [cequal "" $otherstuff]} {
	    set otherstuff "&, $otherstuff"
	}
    }
}

proc set_legal_shell {sname shell class} {
    upvar 1 $sname myshell
    global LoadLegalShells
    
    # If needed, set a list of legal shells
    if {![array exists LoadLegalShells]} {
	foreach s [unameit_get_attribute_mdata_fields $class shell \
		unameit_enum_attribute_values] {
	    set LoadLegalShells($s) 1
	}
    }
    
    set dir [file dirname $shell]
    set exe [file tail $shell]
    if {[cequal /bin $dir] && [info exists LoadLegalShells($exe)]} {
	set myshell $exe
    } else {
	set myshell $shell
    }
}

###########################################################################
#
# Set standard login fields 
# a new application login can be created in a domain, as long
# as there are no conflicts with user_logins in the organization.
# The class is set in item(Class).
#
proc process_login {datadir item name password uid gid shell} {

    upvar 1 $item F

    global \
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    DomainNames CellNames RegionNames Orgnames \
	    OidsUpTree \
	    RegionOid OrgOid CellOid
    
    #
    # Canonicalize the fields
    #
    if {[catch {
	set name [dump_canon_attr $F(Class) name $name]
	set uid [dump_canon_attr $F(Class) uid $uid]
    }]} {
	global errorCode
	log_reject "$name, $uid, $gid: invalid data, $errorCode"
	return 0
    }

    # 
    # If this is a duplicate login name and/or uid, ignore it.
    # For application_logins, other application_logins only collide
    # in this domain. For user_logins, there can be no collisions
    # at all in the org.
    #
    set is_dupname [lookup_user_login_oid_by_name $datadir dupname \
	    $name OidsInOrg($OrgOid)]
    set is_dupuid [lookup_user_login_oid_by_uid $datadir dupuid \
	    $uid OidsInOrg($OrgOid)]

    # 
    # Set the name of the list of OIDs to look in based on the class
    #
    if {!$is_dupname && !$is_dupuid} {
	switch -- $F(Class) {
	    user_login {
		set oid_list_name OidsInOrg($OrgOid)
	    }
	    application_login {
		set oid_list [list $RegionOid]
		set oid_list_name oid_list
	    }
	}

	#
	# Now look for the name and/or uid
	#
	set is_dupname [lookup_appsys_login_oid_by_name $datadir dupname\
		$name $oid_list_name]
	set is_dupuid [lookup_appsys_login_oid_by_uid $datadir dupuid\
		$uid $oid_list_name]
    }

    if {$is_dupname && $is_dupuid && [cequal $dupname $dupuid]} { 
	log_ignore "$name $uid already present"
	return 0
    }

    if {$is_dupname} {
	log_reject "$name $uid: duplicate name"
	return 0
    }
    
    if {$is_dupuid} {
	log_reject "$name $uid: duplicate uid"
	return 0
    }	

    #
    # Get group OID. User_logins must have a primary group which
    # is a user group. Same for application group and login.
    #
    switch -- $F(Class) {
	user_login {
	    set got_gid [lookup_user_group_oid_by_gid $datadir \
		    goid $gid OidsInOrg($OrgOid)]
	}
	application_login {
	    set got_gid [lookup_user_group_oid_by_gid $datadir \
		    goid $gid OidsInOrg($OrgOid)]
	    if {! $got_gid} {
		set got_gid [lookup_application_group_oid_by_gid $datadir \
			goid $gid OidsUpTree($RegionOid)]
	    }
	}
    }
    if {! $got_gid} {
	log_reject "$name $uid: $gid is invalid primary group for this login"
	return 0
    }

    set F(name) $name
    set F(uid) $uid
    set F(password) $password
    set F(primary_group) $goid

    # remove /bin if the shell is a standard shell in /bin
    set_legal_shell F(shell) $shell $F(Class)

    return 1
}

#
# Return true if this automount is present, or if a user is
# automounted in the same place.
#
proc is_duplicate_automount {datadir v} {
    upvar 1 $v item

    lookup_automount $datadir oid $item(name) $item(auto_map) $item(owner)
}

###########################################################################
# 
# Check the unix_pathname of the item and set the
# automount information
#
# Break up the pathname into directory parent path and directory
# e.g. 
#	$F(unix_pathname) is /home/alpha/joe 
# then
#	parent is /home/alpha 
#	dir is joe
#
# If the directory parent is the same as the new automount map's and
# the directory is the same as the user name and
# there is a key entry in the new automount map with the same name
# then
# 1 set the nfs_server, auto_map, and unix_pathname
# 2 delete the automount with the same key
#
# name and unix_pathname must be set in F

proc process_automount {datadir item mapname mount_point auto_map_oid} {
    upvar 1 $item F
    global AmRequest 

    #
    # Set defaults
    # 
    array set F [list auto_map "" nfs_server ""]

    set head [file dirname $F(unix_pathname)]
    set tail [file tail $F(unix_pathname)]

    log_debug "$head $mount_point, $tail $F(name)"

    #
    # If the name or parent are inappropriate, just return
    #
    if {! [cequal $head $mount_point] ||  ! [cequal $tail $F(name)]} {
	log_debug "not an automount"
	return 1
    }

    #
    # See if there is a new AmRequest with this name
    # If so, put the information into the item and delete the AmRequest.
    #

    if {[info exists AmRequest($tail)]} {
	array set F $AmRequest($tail)
	set F(auto_map) $auto_map_oid
	unset AmRequest($tail)
    }

    return 1
}

###########################################################################
#
# Parse the alias file and find the entries of the form
#
# 	user_login:user_login@host.xyz.com
#
# set umh(user_login) to the OID of host.xyz.com,
# but only if the host is within the cell. Issue a warning if
# it is not within the cell.
#
#

proc set_mailhost {datadir aliases_file mailserver} {
    global OidsInCell CellOid CellOf forwardList mailHost RegionOid
    
    set fh [open $aliases_file r]
    
    while {[mgets $fh alias members]} {
	switch -- [llength $members] {
	    0 continue
	    1 {}
	    default {
		set forwardList($alias) 1
		continue
	    }
	}

	set mc [lindex $members 0]
	set member [lindex $mc 0]

	if {[lookup_location $datadir $member user domain host domain_oid] &&
		[cequal $user $alias]} {
	    #	
	    if {![cequal $host ""]} {
		if {[lookup_canon_host $datadir oid host_oid\
			$host $domain_oid]} {
		    if {![cequal $host_oid $mailserver]} {
			# Use explicit mailhost
			set mailHost($user) $oid
		    }
		    # Use default mailhost.
		    continue
		}
		# Use forward list.
	    } elseif {[cequal $domain_oid $RegionOid]} {
		# Use default mailhost.
		continue
	    }
	    # Use forward list
	}
	# If not a mailhost, map to indirect list.
	set forwardList($alias) 1
    }
    close $fh
}


###########################################################################
#
# Process the input file.
#
proc load_users {option} {
    upvar 1 $option options
    global mailHost forwardList\
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    DomainNames CellNames RegionNames Orgnames \
	    OidsUpTree \
	    RegionOid OrgOid CellOid

    set datadir 	$options(DataDir)
    set login_class	$options(LoginClass)
    set login_file	$options(LoginFile)
    set default_region	$options(Region)

    oid_heap_open $datadir
    get_domain_oids $datadir $default_region


    #
    # Create a new map or find the old one. 
    # Save the oid, since it will be used for the
    # auto_map field of new automounts and user_logins.
    # not used for application_logins

    if {[cequal user_login $login_class]} {

	set mapname	$options(MapName)
	set mount_point	$options(MountPoint)
	set mount_opts	$options(MountOptions)

	if {![get_automount_map_oid $datadir auto_map_oid $mapname $CellOid]} {
	    set auto_map_oid [oid_heap_create_l $datadir \
		    Class automount_map \
		    owner $CellOid \
		    name $mapname \
		    mount_point $mount_point \
		    mount_opts $mount_opts]
	}

	log_debug "automount map oid $auto_map_oid"

	parse_automap_file $datadir $options(AutomountFile) 

	set mailserver [get_mailhost $datadir $RegionOid mailhost]
	set aliases_file 	$options(AliasesFile)
	set_mailhost $datadir $aliases_file $mailserver 
    }


    #
    # Make new logins of the requested class
    # NOTE: a failure partway through may leave unused objects,
    #
    set login_fh [open $login_file r]
    
    while {[gets $login_fh line] >= 0} {
	log_debug $line

	#
	# Parse the record
	# login:password:uid:gid:gecos:home_dir:shell
	#
	set line [string trim $line]
	if {[regexp {^#} $line]} continue
	if {[cequal "" $line]} continue

	set junk [lassign [split $line :] \
		name password uid gid gecos home_dir shell]

	# Set default values
	catch {unset F}
	array set F [list Class $login_class \
		unix_pathname $home_dir \
		owner $RegionOid]
	
	if {! [process_login $datadir F $name $password $uid $gid $shell]} {
	    continue
	}
	
	#
	# If this is a new user_login, find the person in the org with this
	# name.
	# Then check the automount information.
	#
	if {[cequal user_login $login_class]} {

	    split_gecos $gecos person_name F(gecos)

	    if {! [lookup_person_oid $datadir person_oid \
		    $person_name OidsInOrg($OrgOid)]} {
		log_reject "cannot find user $person_name"
		continue
	    }
	    set F(person) $person_oid
	    
	    if {! [process_automount $datadir F \
		    $mapname $mount_point $auto_map_oid]} {
		continue
	    }

	    if {[info exists mailHost($name)]} {
		set F(mailbox_route) $mailHost($name)
	    } elseif {[info exists forwardList($name)]} {
		set F(mailbox_route)\
		    [oid_heap_create_l $datadir\
			Class mailing_list\
			owner $RegionOid \
			name "$name-forward"]
	    } else {
		set F(mailbox_route) ""
	    }
	}

	#
	# Create a new instance. 
	#
	oid_heap_create_a $datadir F
    }

    close $login_fh

    #
    # We create automounts that do not belong to users, but only when
    # we are processing user logins.
    #
    if {[cequal user_login $login_class]} {
	save_automounts $datadir $auto_map_oid
    }

    oid_heap_close $datadir
    return
}

if {[catch {
    array set LoadOptions [list \
	    LoginClass		user_login 	\
	    MountOptions	-rw,hard,intr 	]
    get_options LoadOptions \
	    {c	LoadOptions(LoginClass)		$optarg} \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {f	LoadOptions(AliasesFile)	$optarg} \
	    {l	LoadOptions(LoginFile)		$optarg} \
	    {a	LoadOptions(AutomountFile)	$optarg} \
	    {n	LoadOptions(MapName)		$optarg} \
	    {p	LoadOptions(MountPoint)		$optarg} \
	    {o	LoadOptions(MountOptions)	$optarg} \
	    {r	LoadOptions(Region)  		$optarg} 

    check_options LoadOptions \
	    d DataDir \
	    r Region \
	    c LoginClass \
	    l LoginFile

    check_files LoadOptions \
	    d DataDir \
	    f AliasesFile \
	    l LoginFile

    switch -- $LoadOptions(LoginClass) {
	user_login {
	    check_options LoadOptions \
		    f AliasesFile \
		    a AutomountFile \
		    n MapName \
		    p MountPoint \
		    o MountOptions 
	    check_files LoadOptions \
		    a AutomountFile 
	}
	application_login {
	}
	default {
	    error "unsupported login class $LoadOptions(LoginClass)"
	}
    }

} problem]} {
    puts $problem
    puts "Usage: unameit_load users\n\
	    \[ -W -R -C -I \] logging options \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-r region_name	name of this domain (e.g. mktng.xyz.com) \n\
	-c class	user_login or application_login \n\
	-l logins  	file containing login entries \n\
	-a automounts 	file containing automount entries \n\
	-f aliases 	aliases file \n\
	-n map_name 	automount map name (e.g. auto_home) \n\
	-p mount_point	automount map mount point (e.g. /home) \n\
	-o mount_options  automount options (e.g. -rw,hard,intr)"
    exit 1
}
load_users LoadOptions
