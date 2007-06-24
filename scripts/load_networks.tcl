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
# $Id: load_networks.tcl,v 1.28.10.2 1997/09/23 21:59:41 simpson Exp $

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB networks.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

proc load_networks {option} {

    upvar 1 $option options
    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set default_netmask	$options(Netmask)
    set netmasks_file 	$options(NetmasksFile)
    set networks_file	$options(NetworksFile)

    oid_heap_open $datadir
    if {! [get_domain_oid $datadir RegionOid $default_region]} {
	error "default domain $default_region is not in the database"
    }

    #
    # Load the netmasks file storing netmask($hexip) == $hexmask
    #
    set netmaskfh [open $netmasks_file r]
    
    while {[gets $netmaskfh line] != -1 } {
	#
	# Deal with comments
	#
	regsub {#.*} $line {} line
	set line [string trim $line]
	switch -- $line "" continue
	
	#
	# Trim white space
	#
	regsub -all "\[\t \]+" $line " " line

	#
	# parse it
	#
	set rest [lassign [split $line] ip mask]

	#
	# Do IP stuff
	#
	append ip [replicate ".0" [expr 4 - [llength [split $ip .]]]]
	
	#
	# turn the ip and mask into their hex equivalents
	#
	if {[catch {
	    set ip [dump_canon_attr ipv4_network ipv4_net_start $ip]
	    set mask [dump_canon_attr ipv4_network ipv4_net_start $mask]
	}]} {
	    global errorCode
	    log_warn "invalid ip or netmask: $ip $mask, from $line"
	    continue
	}

	#
	# store the mask by key of hexip
	#
	set netmask($ip) $mask
    }

    close $netmaskfh

    #
    # Load new networks
    #
    set in [open $networks_file r]
    
    while {[gets $in line] >= 0} {
	#
	# Deal with comments
	#
	regsub {#.*} $line {} line
	set line [string trim $line]
	switch -- $line "" continue

	#
	# Trim white space
	#
	regsub -all "\[\t \]+" $line " " line

	#
	# Parse into fields
	#
	set aliases [lassign [split $line] cname ip]
	if {![lempty $aliases]} {
	    log_warn "network aliases not supported: $line"
	}

	catch {unset F}
	
	#
	# If the name is not qualified, we use the default domain.
	# If the name has a domain, we look it up. If it is not an
	# existing domain, we change the domain to the default.
	#
	if {[split_domain $cname region name]} {
	    if {[get_domain_oid $datadir region $region]} {
		log_debug "$cname has owner $region"
	    } else {
		log_warn "$cname is not in a valid region, using $default_region"
		set region $RegionOid
	    }
	} else {
	    log_debug "using default domain"
	    set region $RegionOid
	}
	set F(owner) $region

	#
	# Do IP stuff
	#
	append ip [replicate ".0" [expr 4 - [llength [split $ip .]]]]

	if {[catch {
	    set F(name) [dump_canon_attr ipv4_network name $name]
	    set F(ipv4_net_start) [dump_canon_attr ipv4_network ipv4_net_start $ip]
	}]} {
	    global errorCode
	    log_reject "$line: $errorCode"
	    continue
	}
	
	#
	# Skip already loaded data
	#
	if {[get_network_oid $datadir oid $F(ipv4_net_start)]} {
	    continue
	}
	#
	# Compute top network info
	#
	switch -- $F(ipv4_net_start) 7f000000 continue
	#
	# Compute topip and lastip
	#
	if {! [get_top_net $F(ipv4_net_start) topip lastip topmask]} {
	    continue
	}

	if {[info exists netmask($topip)]} {
	    set mask $netmask($topip)
	} else {
	    set mask $default_mask
	}

	#
	# Validate mask (make sure it masks all network bits)
	#
	set hpart [unameit_address_mask $F(ipv4_net_start) $mask]
	switch -- $hpart 00000000 {} default {
	    log_reject "Network number incompatible with mask: $ip $mask"
	    continue
	}
	#
	# If subnet compute lastip using mask
	#
	switch -- $F(ipv4_net_start) $topip {} default {
	    set hpart [unameit_address_mask ffffffff $mask]
	    set lastip [unameit_address_or $F(ipv4_net_start) $hpart]
	}
	set F(ipv4_net_end) $lastip
	set F(Class) ipv4_network
	set F(ipv4_net_mask) $mask
	set F(ipv4_net_netof) ""
	set F(ipv4_net_type) Fixed
 	oid_heap_create_a $datadir F
    }
    close $in
    oid_heap_close $datadir
}


# test case
if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {m	LoadOptions(Netmask)		$optarg} \
	    {M	LoadOptions(NetmasksFile)	$optarg} \
	    {n	LoadOptions(NetworksFile)	$optarg} \
	    {r	LoadOptions(Region)  		$optarg} 
    check_options LoadOptions \
	    m Netmask \
	    r Region
    check_files LoadOptions \
	    d DataDir \
	    M NetmasksFile \
	    n NetworksFile 

} problem]} {
    puts $problem
    puts "Usage: unameit_load networks \n\
	    \[ -W -R -C -I \] logging options \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-r region_name	name of this domain (e.g. mktng.xyz.com) \n\
	-m netmasks 	default netmask \n\
	-M netmasks 	file containing netmasks \n\
	-n networks	file containing networks"
    exit 1
}

load_networks LoadOptions



