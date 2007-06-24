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
# $Id: load_group_users.tcl,v 1.18.12.1 1997/08/28 18:29:07 viktor Exp $
#

# This procedures adds users into groups. It cannot be performed until
# after users and groups have been added.


source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

proc load_group_users {option} {

    upvar 1 $option options
    global \
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    DomainNames CellNames RegionNames Orgnames \
	    OidsUpTree \
	    RegionOid OrgOid CellOid
    global errorCode

    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set group_class	$options(GroupClass)
    set group_file	$options(GroupFile)

    oid_heap_open $datadir
    get_domain_oids $datadir $default_region
    switch -- $group_class {
	user_group -
	application_group {}
	default {
	    error "unsupported group type $group_class"
	}
    }

    #
    # Read the entries and add the members to the groups.
    #
    set group_fh [open $group_file r]
    
    while {[gets $group_fh line] != -1} {
	log_debug $line

	#
	# Parse the record
	# group:password:gid:members
	#
	if {[regexp {^#} $line]} continue
	set line [string trim $line]
	if {[cequal "" $line]} continue

	set junk [lassign [split $line :] name password gid members]
	set members [split $members ,]

	#
	# Canonicalize the fields
	#
	if {[catch {
	    set name [dump_canon_attr $group_class name $name]
	    set gid [dump_canon_attr $group_class gid $gid]
	}]} {
	    log_warn "$errorCode: $line"
	    continue
	}

	switch -- $group_class {
	    user_group {
		set got_gid [lookup_user_group_oid_by_gid $datadir \
			group_oid $gid OidsInCell($CellOid)]
	    }
	    application_group {
		set got_gid [lookup_application_group_oid_by_gid $datadir \
			group_oid $gid OidsUpTree($RegionOid)]
	    }
	    default {
		error "unsupported group type $group_class"
	    }
	}
	if {! $got_gid} {
	    log_reject "no such group $name"
	    continue
	}

	foreach member $members {
	    #
	    # Create a new instance of group_member for every member. 
	    #
	    if {[catch {set member [dump_canon_attr application_login name $member]}]} {
		log_reject "$errorCode: $member"
		continue
	    }
	    set got_login [lookup_login $datadir login_oid $member $RegionOid]
	    
	    if {! $got_login} {
		log_reject "no such user $member"
		continue
	    }

	    #
	    # Check to see if it is here already.
	    #
	    if {[get_group_member_oid $datadir dummy $group_oid $login_oid]} {
		log_ignore "$member already in $name"
		continue
	    }

	    oid_heap_create_l $datadir \
		    Class group_member \
		    gm_login $login_oid \
		    owner $group_oid
	}
    }
    close $group_fh
    oid_heap_close $datadir
    return
}

# test case
if [catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {r	LoadOptions(Region)  		$optarg} \
	    {c	LoadOptions(GroupClass)		$optarg} \
	    {f	LoadOptions(GroupFile)		$optarg} 
    check_options LoadOptions \
	    d DataDir \
	    f GroupFile \
	    c GroupClass \
	    r Region
    check_files LoadOptions \
	    d DataDir \
	    f GroupFile
} problem] {
    puts $problem
    puts "Usage: unameit_load groups_users\n\
	    \[ -W -R -C -I \] logging options \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-r region_name	name of this domain (e.g. mktng.xyz.com) \n\
	-c class	user_group or application_group \n\
	-f group_file	file containing group entries"
    exit 1
}

load_group_users LoadOptions
