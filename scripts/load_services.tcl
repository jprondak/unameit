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
# $Id: load_services.tcl,v 1.2.12.1 1997/08/28 18:29:16 viktor Exp $

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

proc load_services {option} {
    upvar 1 $option options

    set datadir 	$options(DataDir)
    set services_file 	$options(Services)

    #
    # Load the pre-parsed database files
    #
    oid_heap_open $datadir

    #
    # Get lists of oids in each cell and org
    # Get the default region, its cell, and the org.
    #
    if {![get_cell_oid $datadir RootOid .]} {
	error "No root cell in cache data"
    }

    #
    # Load new people
    #
    set fh [open $services_file r]
    
    while {[gets $fh line] != -1} {
	log_debug $line
	set line [string trim $line]
	regsub -all -- "\[\040\t]+" $line "\040" line
	#
	# Split off comment
	#
	regexp {^([^#]*)#?(.*)$} $line x line item(comment)
	set line [string trim $line]
	set item(comment) [string trim $item(comment)]
	#
	# Ignore empty/comment lines.
	#
	switch -- $line "" continue

	set parts [split $line]
	if {[llength $parts] < 2} {
	    log_reject "Malformed services entry: $line"
	    continue
	}
	set aliases [lassign $parts name proto_port]

	if {![regexp {^([1-9][0-9]*)/(.+)$} $proto_port x port proto]} {
	    log_reject "Malformed services entry: $line"
	    continue
	}

	switch -- $proto {
	    udp -
	    tcp {
		set item(Class) ${proto}_service
		set port_attr ${proto}_port
	    }
	    default {
		log_reject "Unsupported protocol: $proto in $line"
		continue
	    }
	}

	#
	# Canonicalize the fields
	#
	if {[catch {
	    set name [dump_canon_attr $item(Class) ip_service_name $name]
	    set port [dump_canon_attr $item(Class) $port_attr $port]
	}]} {
	    global errorCode
	    log_reject "$line: $errorCode"
	    continue
	}

	if {![get_service_name $datadir oid $proto $name]} {
	    if {[get_service_port $datadir oid $proto $port]} {
		log_reject "Duplicate port number: $line"
		continue
	    }
	    set item(ip_service_name) $name
	    set item($port_attr) $port
	    set item(owner) $RootOid
	    set oid [oid_heap_create_a $datadir item]
	    unset item
	} else {
	    log_ignore "$proto service $name already exists: $line"
	    # FALL THROUGH TO ALIASES
	}

	foreach alias $aliases {
	    #
	    set item(Class) ${proto}_service_alias
	    if {[catch {
		set alias [dump_canon_attr $item(Class) ip_service_name $alias]
	    }]} {
		global errorCode
		log_reject "$line: $errorCode"
		continue
	    }
	    if {[get_service_name $datadir soid $proto $alias]} {
		log_ignore "$proto service alias $alias already exists: $line"
		continue
	    }
	    set item(ip_service_name) $alias
	    set item(owner) $oid
	    oid_heap_create_a $datadir item
	    unset item
	}
    }
    close $fh

    oid_heap_close $datadir
}

# check input options and files
if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {f	LoadOptions(Services)		$optarg}
    check_files LoadOptions \
	    d DataDir \
	    f Services
} problem]} {
    puts $problem
    puts "Usage: unameit_load services\n\
	    \[-W -R -C -I -D\]\tlogging options \n\
	    -d data 	name of directory made by unameit_load copy_checkpoint\n\
	    -f services	file containing services records"
    exit 1
}
load_services LoadOptions
