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
# $Id: load_netgroups.tcl,v 1.21.12.3 1997/09/29 23:09:54 simpson Exp $
#

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

## Create a netgroup and record the information on the netgroup for later 
## processing.
proc create_netgroup {datadir line} {
    global RegionOid errorCode ng_oid ng_elems
    upvar default_region default_region

    ## Trim whitespace.
    set line [string trim $line]

    ## Grab first field and skip comments.
    if {[scan $line %s name] != 1 || [regexp {^#} $name]} return

    ## Parse netgroup name and lookup domain.
    if {[regexp {^([^@]+)@(.+)$} $name junk short_name domain]} {
	if {[get_domain_oid $datadir domain_oid $domain] == 0} {
	    log_reject "netgroup $name domain $domain not found"
	    return
	}
    } else {
	set short_name $name
	set domain_oid $RegionOid
	set domain $default_region
    }
    
    ## Validate name.
    if {[catch {dump_canon_attr netgroup name $short_name} short_name]} {
	log_reject "netgroup $name name $short_name illegal: $errorCode"
	return
    }

    ## Try to lookup the netgroup to see if it exists.
    if {[get_netgroup_oid $datadir ng_oid $short_name $domain_oid]} {
	log_ignore "netgroup $name already in database"
	return
    }

    ## Create the SOB and set ng_oid.
    set F(Class) netgroup
    set F(name) $short_name
    set F(owner) $domain_oid
    set ng_oid($short_name@$domain)\
	    [oid_heap_create_a $datadir F]

    ## Set the elements for this netgroup.
    set ng_elems($short_name@$domain) [string range $line [clength $name] end]
}

proc create_netgroup_members {datadir} {
    global ng_oid ng_elems RegionOid
    upvar default_region default_region

    foreach tuple [array names ng_elems] {
	## Set and clean up members string.
	regsub -all -- "\[ \t\]+" $ng_elems($tuple) " " members
	while {[regsub -all -- {\(([^) ]*) +} $members {(\1} members]} {}
	set members [string trim $members]

	for {} {[scan $members %s member] == 1} {
	    set members [string trimleft [string range $members\
		    [clength $member] end]]
	    catch {unset F}
	} {
	    set F(Class) netgroup_member
	    switch -regexp -- $member {
		{^\(} {
		    if {![regexp {^\(([^,]*),([^,]*),[^)]*\)$} $member\
			    junk host user]} {
			log_reject "netgroup member $member for netgroup\
				$tuple garbled"
			continue
		    }
		    set host_oid ""; set user_oid ""
		    if {![cequal $host ""] && ![cequal $host -] &&
		    [lookup_host_oid $datadir host_oid $host] == 0} {
			log_reject "host $host in netgroup member $member\
				of netgroup $tuple not found"
			continue
		    }
		    if {![cequal $user ""] && ![cequal $user -] &&
		    [lookup_login $datadir user_oid $user $RegionOid] == 0} {
			log_reject "user $user in netgroup member $member\
				of netgroup $tuple not found"
			continue
		    }
		    set F(owner) $ng_oid($tuple)
		    set F(ng_host) $host_oid
		    set F(ng_user) $user_oid
		    set F(ng_ng) ""
		    oid_heap_create_a $datadir F
		}
		default {
		    ## Another netgroup.
		    if {[info exists ng_oid($member)]} {
			set F(ng_ng) $ng_oid($member)
		    } else {
			if {![regexp {^([^@]+)@(.+)$} $member junk\
				name domain]} {
			    set name $member
			    set domain $default_region
			    set domain_oid $RegionOid
			} else {
			    if {[get_domain_oid $datadir domain_oid\
				    $domain] == 0} {
				log_reject "domain $domain of netgroup\
					member $member of netgroup $tuple\
					not found"
				continue
			    }
			}
			if {[info exists ng_oid($name@$domain)]} {
			    set F(ng_ng) $ng_oid($name@$domain)
			} elseif {[get_netgroup_oid $datadir F(ng_ng)\
				$name $domain_oid] == 0} {
			    log_reject "netgroup member $member on netgroup\
				    $tuple not found"
			    continue
			}
		    }
		    set F(owner) $ng_oid($tuple)
		    set F(ng_host) ""; set F(ng_user) ""
		    oid_heap_create_a $datadir F
		}
	    }
	}
    }
}

proc load_netgroups {option} {

    upvar 1 $option options
    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set netgroups_file 	$options(NetgroupsFile)

    #
    # Load the pre-parsed database files
    #
    oid_heap_open $datadir

    #
    # Get lists of oids in each cell and org
    # Get the default region, its cell, and the org.
    #
    get_domain_oids $datadir $default_region
    
    set fh [open $netgroups_file r]
    while {[gets $fh line] != -1} {
	create_netgroup $datadir $line
    }
    close $fh

    create_netgroup_members $datadir

    oid_heap_close $datadir
    return
}


# test case
if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {f	LoadOptions(NetgroupsFile)	$optarg} \
	    {r	LoadOptions(Region)  		$optarg} 
    check_options LoadOptions \
	    d DataDir \
	    f NetgroupsFile \
	    r Region
    check_files LoadOptions \
	    d DataDir \
	    f NetgroupsFile

} problem]} {
    puts $problem
    puts "Usage: unameit_load netgroups \n\
	    \[ -W -R -C -I \] logging options \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-f netgroups	file containing netgroup entries for the domain \n\
	-r region_name	name of this domain (e.g. mktng.xyz.com)"
    exit 1
}

load_netgroups LoadOptions
