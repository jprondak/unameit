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
# $Id: load_groups.tcl,v 1.17.20.1 1997/08/28 18:29:07 viktor Exp $
#

# Application Groups (class group) are unique by name and gid in the region,
# and are owned by the region.
# User Groups (class user_group) are unique by name and gid in the cell,
# and are owned by the region.
# System Groups (class system_group) are not handled here.

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]


########################################################################### 
# Create group entries given:
#	data directory
#	class of group
#	/etc/group file
# 	name of default region
#
# There are 3 types of groups: user_group, system_group and group

proc load_groups {option} {
    upvar 1 $option options
    global \
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    DomainNames CellNames RegionNames Orgnames \
	    OidsUpTree \
	    RegionOid OrgOid CellOid

    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set group_class	$options(GroupClass)
    set group_file	$options(GroupFile)

    #
    # Load the pre-parsed database files
    #
    oid_heap_open $datadir

    #
    # Get lists of oids in each cell and org
    # Get the default region, its cell, and the org.
    #
    get_domain_oids $datadir $default_region
 
    #
    # Load new groups
    # Make entries of the requested class
    #
    set group_fh [open $group_file r]
    
    while {[gets $group_fh line] >= 0} {
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
	    global errorCode
	    log_reject "$line: $errorCode"
	    continue
	}

	# 
	# If this is a duplicate group name and/or uid, ignore it.
	# For application_groups, other application_groups only collide
	# in this domain. For user_groups, there can be no collisions
	# at all in the cell.
	#
	set is_dupname [lookup_user_group_oid_by_name $datadir \
		dupname $name OidsInCell($CellOid)]
	set is_dupgid [lookup_user_group_oid_by_gid $datadir \
		dupgid $gid OidsInCell($CellOid)]

	# 
	# Set the name of the list of OIDs to look in based on the class
	#
	if {!$is_dupname && !$is_dupgid} {
	    switch -- $group_class {
		user_group {
		    set oid_list_name OidsInCell($CellOid)
		}
		application_group {
		    set oid_list_name OidsUpTree($RegionOid)
		}
		default {
		    error "unsupported group class $group_class"
		}
	    }

	    #
	    # Now look for the name and/or gid
	    #
	    set is_dupname [lookup_application_group_oid_by_name $datadir \
		    dupname $name $oid_list_name]
	    set is_dupgid [lookup_application_group_oid_by_gid $datadir \
		    dupgid $gid $oid_list_name]
	}

	if {$is_dupname && $is_dupgid && [cequal $dupname $dupgid]} { 
	    log_ignore "$name $gid: already here"
	    continue
	}
	
	if {$is_dupname} {
	    log_reject "$name $gid: duplicate name"
	    continue
	}
	
	if {$is_dupgid} {
	    log_reject "$name $gid: duplicate gid"
	    continue
	}	

	#
	# Create a new instance. 
	#
	oid_heap_create_l $datadir \
		Class $group_class \
		name $name \
		gid $gid \
		owner $RegionOid
    }
    close $group_fh
    oid_heap_close $datadir
}


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
    puts "Usage: unameit_load groups \n\
	    \[ -W -R -C -I \] logging options \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-r region_name	name of this domain (e.g. mktng.xyz.com) \n\
	-c class	user_group or application_group \n\
	-f group_file	file containing group entries"
    exit 1
}

load_groups LoadOptions

