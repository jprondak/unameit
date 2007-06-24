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
# $Id: load_domains.tcl,v 1.24 1997/03/18 23:50:21 ccpowell Exp $

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

# Data Format of the Input File
# First 2 words are domain and class
# rest of the line is the organization (may be blank)


#
# Process domains given
#	data directory
#	list of domains (i.e. regions and cells)

# Cells and regions are created as listed.
# Organizations are created if they do not already exist.
# Organizations have . cell as owner.

proc load_domains {option} {

    upvar 1 $option options
    set datadir 	$options(DataDir)
    set domain_file	$options(DomainFile)

    oid_heap_open $datadir

    get_domain_oid $datadir dot_oid .

    log_debug "cell . is $dot_oid"

    #
    # Load new regions/cells
    #
    set domain_fh [open $domain_file r]
    
    while {[gets $domain_fh line] != -1} {
	log_debug $line

	#
	# Parse the record
	# First 2 words are domain and class
	# rest of the line is the organization
	#
	if {[regexp {^#} $line]} continue
	set line [string trim $line]
	if {[cequal "" $line]} continue
	regsub -all -- "\[ \t\]+" $line " " line

	set orgname [lassign [split $line] name class]
	#
	# Canonicalize the fields
	#
	if {[catch {
	    set name [dump_canon_attr $class name $name]
	    }]} {
		global errorCode
		log_reject "$name: $errorCode"
		continue
	    }
	#
	# Skip already loaded data, i.e. a cell or region with the
	# same name.
	#
	if {[get_domain_oid $datadir oid $name]} {
	    log_ignore "$name: already present"
	    continue
	}

	# Handle cell organization iff this is a cell and orgname is given
	if {[cequal cell $class] && ![cequal "" $orgname]} {
	    if {[catch {
		set orgname [dump_canon_attr organization name $orgname]
	    }]} {
		global errorCode
		log_reject "$orgname: $errorCode"
		continue
	    }

	    # create a new instance of organization if needed,
	    # otherwise use the one with the same name
	    if {! [get_organization_oid $datadir orgoid $orgname]} {
		set orgoid [oid_heap_create_l $datadir \
			Class organization \
			name $orgname \
			owner $dot_oid]
	    }
	    set cellorg $orgoid
	} else {
	    set cellorg ""
	}

	oid_heap_create_l $datadir \
		name $name \
		cellorg $cellorg \
		Class $class
    }
    close $domain_fh

    oid_heap_close $datadir
}

if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {f	LoadOptions(DomainFile)		$optarg} 
    check_options LoadOptions \
	    d DataDir \
	    f DomainFile
    check_files LoadOptions \
	    d DataDir \
	    f DomainFile
} problem ]} {
    puts $problem
    puts "Usage: unameit_load domains \n\
	    \[ -W -R -C -I \] logging options \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-f domains	file containing list of cells and regions"
    exit 1
}

load_domains LoadOptions
