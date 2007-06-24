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
# $Id: load_persons.tcl,v 1.6.12.1 1997/08/28 18:29:15 viktor Exp $

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB read_aliases.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

# Data Format of the Input File
# Each line is a subclass of person.
# Each line contains attribute=value; attribute=value
# Class is a mandatory attribute and must be a concrete subclass of person
# NOTE: Class is capitalized, so it will not collide with an attribute
# named class. 
#
# attribute and value will be trimmed

#
# Split the line into attribute value pairs,
# canonicalize the attributes,
# and set the fields in array $p_item.
#
proc prepare_record {p_item line} {
    global PersonClasses

    upvar 1 $p_item item

    foreach av [split $line ";"] {
	set av [string trim $av]
	if {[cequal "" $av]} {
	    continue
	}
	if {! [regexp -- {([^=]*)=(.*)} $av junk field value]} {
	    error "bad phrase '$av'"
	}
	set field [string trim $field]
	set item($field) [string trim $value]
    }

    if {! [info exists item(Class)]} {
	error "person has no Class"
    }

    set class $item(Class)

    if {! [info exists PersonClasses($class)]} {
	error "$class is not a valid person class"
    }

    foreach {field value} [array get item] {
	if {[cequal Class $field]} {
	    continue
	}
	if {[unameit_is_pointer $field]} {
	    error "$field is not a supported type"
	}
	set item($field) [unameit_check_syntax $class $field "" $item($field) db ]
    }
}

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

	if {[lookup_location $datadir $member person domain host domain_oid] &&
		[cequal $person $alias]} {
	    #	
	    if {![cequal $host ""]} {
		if {[lookup_canon_host $datadir oid host_oid\
			$host $domain_oid]} {
		    if {![cequal $host_oid $mailserver]} {
			# Use explicit mailhost
			set mailHost($person) $oid
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

proc load_persons {option} {
    upvar 1 $option options
    global \
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    RegionNames CellNames OrgNames \
	    RegionOid CellOid OrgOid

    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set person_file 	$options(Persons)
    set aliases_file	$options(Aliases)

    #
    # Load the pre-parsed database files
    #
    oid_heap_open $datadir

    global PersonClasses
    foreach class [concat person [unameit_get_subclasses person]] {
	if {! [unameit_is_readonly $class]} {
	    set PersonClasses($class) person
	}
    }

    #
    # Get lists of oids in each cell and org
    # Get the default region, its cell, and the org.
    #
    get_domain_oids $datadir $default_region

    set mailhub [get_mailhost $datadir $RegionOid mailhub]

    set_mailhost $datadir $aliases_file $mailhub 

    #
    # Load new people
    #
    set fh [open $person_file r]
    
    while {[gets $fh inline] != -1} {
	log_debug $inline

	#
	# Parse the record
	#
	if {[regexp {^#} $inline]} continue
	set line [string trim $inline]
	if {[cequal "" $line]} continue

	catch {unset item}
	if {[catch {prepare_record item $line} msg]} {
	    log_reject "$inline: $msg"
	    continue
	}
	#
	# Skip already loaded data, i.e. a person with the
	# same name.
	#
	set fullname $item(fullname)
	if {[regexp {^([^,]*), *(.*)$} $fullname x last_name rest]} {
	    regsub -all , $rest {} rest
	    set fullname "$rest $last_name"
	}
	if {[lookup_person_oid $datadir person_oid \
		    $fullname OidsInOrg($OrgOid)]} {
	    log_ignore "$inline: $item(fullname) already present"
	    continue
	}

	if {[info exists item(name)] && ![cequal $item(name) ""]} {
	    set name $item(name)
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
	set item(owner) $RegionOid
	oid_heap_create_a $datadir item
    }
    close $fh

    oid_heap_close $datadir
}

# check input options and files
if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {r	LoadOptions(Region)  		$optarg} \
	    {f	LoadOptions(Persons)		$optarg} \
	    {a	LoadOptions(Aliases)		$optarg}
    check_options LoadOptions \
	    d DataDir \
	    f Persons \
	    r Region
    check_files LoadOptions \
	    d DataDir \
	    f Persons \
	    a Aliases
} problem]} {
    puts $problem
    puts "Usage: unameit_load persons\n\
	    \[-W -R -C -I -D\]\tlogging options \n\
	    -d data 	name of directory made by unameit_load copy_checkpoint\n\
	    -r region_name	name of this domain (e.g. mktng.xyz.com) \n\
	    -f persons	file containing personnel records\n\
	    -a aliases	mail aliases file"
    exit 1
}
load_persons LoadOptions
