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
# $Id: load_dns.tcl,v 1.1.12.2 1997/09/23 21:59:40 simpson Exp $
#

# Loads a DNS zone from a DNS server. The named-xfer program that comes with
# the bind distribution is used to talk to a named DNS server and get the
# zone information.

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB networks.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

proc usage {{text ""}} {
    global argv0

    error [format {
%sUsage: %s <args_as_below>
[-W] [-R] [-C] [-I] [-D]	Logging options
-z zone				Zone to dump
-d data_dir			unameit_load copy_checkpoint dir
-m netmask			Default netmask for new networks
-M netmasks_file		Netmasks file (/dev/null if none)
} $text $argv0]
}

proc parse_options {} {
    global options

    if {[catch {
	get_options options\
		{d options(data_dir) $optarg}\
		{r options(zone) $optarg}\
		{m options(netmask) $optarg}\
		{M options(netmasks_file) $optarg}
	check_options options\
		d data_dir\
		m netmask\
		M netmasks_file\
		r zone
	check_files options\
		d data_dir\
		M netmasks_file
    } msg]} {
	usage $msg\n
    }
}
	    
proc check_ip_address {datadir hexip default_mask} {
    global RegionOid netmask

    if {! [get_top_net $hexip topnet toplast topmask]} {
	return 0
    }

    #
    # If the toplevel network does not exist, create it with
    # the default netmask. If it does exist, we will use the
    # mask if we create a subnetwork.
    #
    if {! [get_netmask $datadir mask $topnet]} {
	if {[info exists netmask($topnet)]} {
	    set mask $netmask($topnet) 
	} else {
	    set mask $default_mask 
	}

	oid_heap_create_l $datadir \
		Class 		ipv4_network \
		name 		[auto_net $topnet] \
		owner 		$RegionOid \
		ipv4_net_netof 	"" \
		ipv4_net_start 	$topnet \
		ipv4_net_end $toplast \
		ipv4_net_mask 	$mask \
		ipv4_net_type	Fixed
    }

    #
    # If the mask is empty, the top level network is VLSM and we do not
    # know how to determine the containing subnet. So we assume that
    # it's okay.
    #
    switch -- $mask "" {return 1}

    #
    # See if this address is subnetted - if so, and if the subnet
    # does not exist, create it.
    #
    set subnet [unameit_address_and $hexip $mask]
    set subnet_last [unameit_address_or $subnet \
	    [unameit_address_mask ffffffff $mask]]
    #
    # Check this address against broadcast addresses.
    #
    switch -- $hexip $subnet - $subnet_last {
	log_warn "$hexip is a broadcast address"
	return 0
    }

    #
    # Create the subnet if needed.
    #
    if {! [get_network_oid $datadir x $subnet]} {
	oid_heap_create_l $datadir \
		Class 		ipv4_network \
		name 		[auto_net $subnet] \
		owner 		$RegionOid \
		ipv4_net_netof 	"" \
		ipv4_net_start 	$subnet \
		ipv4_net_end $subnet_last \
		ipv4_net_mask 	$mask \
		ipv4_net_type	Fixed
    }
    return 1
}

proc transfer_zone_file {server zone dest} {
    ## Unfortunately, named-xfer returns a 1 exit status. Fooey.
    file delete -- $dest
    catch {exec named-xfer -z $zone -f $dest -s 0 $server}
    if {![file exists $dest]} {
	error "named-xfer failed"
    }
}

proc load_netmasks_file {file} {
    global netmasks

    ## Following line may raise error if file doesn't exist.
    set fd [open $file r]
    while {[gets $fd line] != -1} {
	## Trash comments
	regsub {#.*} $line {} line
	set line [string trim $line]
	if {[cequal $line ""]} continue

	## Trim white space
	regsub -all "\[\t \]+" $line " " line

	## Parse
	scan $line %s%s ip mask

	## Add zeros on end of IP if needed
	append ip [replicate .0 [expr 4-[llength [split $ip .]]]]

	## Change to hex
	if {[catch {
	    set ip [dump_canon_attr ipv4_network ipv4_net_start $ip]
	    set mask [dump_canon_attr ipv4_network ipv4_net_start $mask]
	}]} {
	    log_warn "invalid IP address or netmask: $ip $mask"
	    continue
	}

	set netmasks($ip) $mask
	log_debug "setting netmask of $ip to $mask"
    }
    close $fd
}

proc load_records {file rec_type func} {
    global errorCode errorInfo options pass

    if {![info exists pass]} {
	set pass 1
    } else {
	incr pass
    }

    if {[catch {open $file r} fd]} {
	file delete $file
	error $fd $errorInfo $errorCode
    }
    
    while {[gets $fd line] != -1} {
	## Skip comments
	if {[cequal [crange $line 0 0] {;}]} continue

	## Reset origin
	if {[cequal [crange $line 0 6] \$ORIGIN]} {
	    scan $line %s%s junk origin
	    regsub {\.$} $origin "" origin
	    log_debug "setting origin to $origin"
	    if {[get_domain_oid $options(data_dir) origin_oid $origin]} {
		catch {unset bogus_origin}
	    } else {
		set bogus_origin $origin
		if {$pass == 1} {
		    log_warn "\$ORIGIN $origin not in DB.\
			    Skipping records for it."
		}
	    }
	    catch {unset host}		;# Reset for continuation lines.
	    continue
	}

	if {[info exists bogus_origin]} {
	    # For an SOA record, we see an $ORIGIN like "com.". get_domain_oid
	    # fails on this record and we skip all the records for it.
	    continue
	}

	if {![info exists origin]} {
	    # This should never happen.
	    error "Never saw an \$ORIGIN statement in $file!"
	}

	if {[regexp "^\[ \t\]" $line]} {
	    # Continuation of previous line.

	    if {![info exists host]} {
		# This should never happen.
		error "Continue line\n\t$line\nwith no previous host record!"
	    }

	    # Skip lines that don't contain a value.
	    if {[set n [scan $line %s%s%s%s domain type value1 value2]]\
		    < 3} continue
	    if {$n == 3} {
		set args $value1
	    } else {
		set args [list $value1 $value2]
	    }
	} else {
	    # New host line.
	    if {[set n [scan $line %s%s%s%s%s host domain type value1\
		    value2]]\
		    < 4} continue
	    if {$n == 4} {
		set args $value1
	    } else {
		set args [list $value1 $value2]
	    }
	}

	## Skip non Internet records.
	if {![cequal $domain IN] || ![cequal $type $rec_type]} continue

	if {[catch {dump_canon_attr computer name $host} host]} {
	    if {$pass == 1} {
		log_reject "malformed host name $host: $errorCode"
	    }
	    break
	}

	$func $origin_oid $origin $host $args
    }

    close $fd
}

proc record_host_info {region_oid region host arg_list} {
    global host_info options errorCode

    lassign $arg_list ip

    ## Reject host names that look like server types.
    if {[get_server_type_oid_by_name $options(data_dir) junk $host]} {
	log_reject "$host rejected: server type cannot be used as\
		host name"
	break
    }
	
    if {[cequal $host localhost]} {
	log_ignore "ignoring localhost in $region"
	return
    }

    if {[catch {dump_canon_attr computer ipv4_address $ip} ip]} {
	log_reject "malformed IP address $ip: $errorCode"
	return
    }

    ## Check the IP address and create the network if need be.
    if {![check_ip_address $options(data_dir) $ip $options(netmask)]} {
	log_reject "invalid IP address $ip for host $host"
	return
    }
    
    lappend host_info([list $host $region_oid]) $ip
}

proc match_host_interface {indices tuple ip if_index_var} {
    global host_info
    upvar 1 $if_index_var if_index

    lassign $tuple host region_oid

    foreach index $indices {
	if {![info exists host_info($index)]} continue

	lassign $index cur_host cur_region_oid

	## Skip if we are processing the same index passed in or if we are
	## processing a host in another region.
	if {[cequal $host $cur_host] ||
	![cequal $region_oid $cur_region_oid]} continue

	## Skip multi-homed host records that look like interfaces.
	if {[llength $host_info($index)] > 1} continue
	
	if {[regexp ^$host $cur_host]} {
	    if {[cequal $host_info($index) $ip]} {
		set if_index $index
		return 1
	    }
	}
    }

    return 0
}

proc create_host {host region_oid if_name ip} {
    global receives_mail options

    if {[info exists receives_mail($host)]} {
	set mail $receives_mail($host)
    } else {
	set mail Yes
    }
    oid_heap_create_l $options(data_dir)\
	    Class computer\
	    owner $region_oid\
	    name $host\
	    ipv4_address $ip\
	    ifname $if_name\
	    receives_mail $mail
}

proc create_hosts {} {
    global host_info OidsInOrg OrgOid options

    set host_info_indices [array names host_info]
    set org_oids $OidsInOrg($OrgOid)
    foreach tuple [lsort $host_info_indices] {
	## We trash interface host names as we go along so we have to skip
	## over these deleted indices when we encounter them.
	if {![info exists host_info($tuple)]} continue

	lassign $tuple host region_oid

	foreach ip $host_info($tuple) {
	    catch {unset ip_found}
	    
	    if {[get_ipv4_owner_oid $options(data_dir) owner_oid $ip]} {
		oid_heap_get_data_a $options(data_dir) temp $owner_oid
		if {[cequal $host $temp(name)]} {
		    log_ignore "$host with IP $ip already exists"
		} else {
		    log_reject "cannot create $host with IP $ip.\
			    $ip in use by $temp(name)."
		}
		set ip_found 1
		# Fall through because we want to trash the <host>-<if>
		# indices below before continuing.
	    }

	    if {[match_host_interface $host_info_indices $tuple $ip\
		    if_index]} {
		lassign $if_index if_index_host
		regsub ^$host $if_index_host "" if_name
		set if_name [crange $if_name 1 end]
		unset host_info($if_index)
		set lookup_host $host-$if_name
	    } else {
		set if_name ""
		set lookup_host $host
	    }

	    if {[info exists ip_found]} continue

	    if {[lookup_hostname_oid $options(data_dir) owner_oid\
		    $lookup_host org_oids]} {
		log_reject "cannot create host $lookup_host with IP $ip.\
			Name is in use with different IP address."
		continue
	    }
	    if {[lookup_hostname_oid $options(data_dir) owner_oid\
		    $host org_oids]} {
		oid_heap_create_l $options(data_dir)\
			Class ipv4_interface\
			owner $owner_oid\
			ifname $if_name\
			ipv4_address $ip
	    } else {
		create_host $host $region_oid $if_name $ip
	    }
	}
    }
	    
}

proc record_mx_info {region_oid region host arg_list} {
    global priorities receives_mail

    lassign $arg_list priority mailhost
    lassign [split $mailhost .] mailhost	;# Trash domain. Don't care.

    if {[catch {dump_canon_attr computer name $mailhost}\
	    mailhost]} {
	log_reject "malformed MX target host $mailhost"
	return
    }

    ## Use the highest priority MX record to determine if the host receives
    ## mail.
    if {[info exists priorities($host)] &&
    $priorities($host) < $priority} {
	return
    }

    set priorities($host) $priority
    if {[cequal $host $mailhost]} {
	set receives_mail($host) Yes
    } else {
	set receives_mail($host) No
    }
}

proc add_cname_record {region_oid region host arg_list} {
    global options errorCode
    global OidsInOrg OrgOid OidSuperclass

    ## Got a CNAME record. Try to create a host alias or server alias.
    
    set ref_host [lindex $arg_list 0]

    lassign [split $ref_host .] short_host

    if {[catch {dump_canon_attr computer name $short_host}\
	    short_host]} {
	log_reject "malformed CNAME target host $short_host: $errorCode"
	return
    }
    
    if {[cequal $host $short_host]} {
	log_ignore "skipping self referential CNAME $host"
	return
    }

    set org_oids $OidsInOrg($OrgOid)

    if {[lookup_hostname_oid $options(data_dir) owner_oid $short_host\
	    org_oids]} {
	if {![oid_get_class $options(data_dir) class $owner_oid]} {
	    error "Cannot map from oid $owner_oid to its class"
	}
	
	if {[info exists OidSuperclass($class)]} {
	    set class $OidSuperclass($class)
	}
	
	if {[cequal $class Host]} {
	    ## The target is a valid host. Now check to see if the
	    ## the name is a server type name.
	    if {[get_server_type_oid_by_name $options(data_dir)\
		    server_type_oid $host]} {
		if {[get_server_alias_oid $options(data_dir) junk\
			$server_type_oid $region_oid]} {
		    log_ignore "server alias $host in $region already\
			    exists"
		    return
		} else {
		    ## Create new server alias.
		    oid_heap_create_l $options(data_dir)\
			    Class server_alias\
			    name $host\
			    server_type $server_type_oid\
			    owner $region_oid\
			    primary_server $owner_oid
		    return
		}
	    } elseif {[lookup_hostname_oid $options(data_dir) junk $host\
		    org_oids]} {
		## Alias already exists. Skip it.
		log_ignore "host alias $host in $region already exists"
		return
	    } else {
		## Create new host alias.
		oid_heap_create_l $options(data_dir)\
			Class host_alias\
			name $host\
			owner $owner_oid
		return
	    }
	}
    }
}

### Loads a zone file created by named-xfer. It uses a four pass algorithm.
### The first pass inspects the MX records to determine which hosts receive
### mail.  The second pass loads all the A records that don't look like 
### secondary interfaces. The third pass loads all A records that look like 
### secondary interfaces. During this pass, both secondary ifs and hosts 
### may be created. During the fourth pass, CNAMEs are processed. They can't 
### be created until all the hosts are created.
proc load_zone_file {file} {
    load_records $file MX record_mx_info
    load_records $file A record_host_info
    create_hosts
    load_records $file CNAME add_cname_record
}

#### 				Start of main program

parse_options

set server [exec sh -c "(echo set type=NS; echo $options(zone)) | nslookup\
| grep 'nameserver =' | awk ' {print \$NF}'"]
log_debug "Using name server $server"

oid_heap_open $options(data_dir)

## Load the oids for the cells and regions and verify that the zone
## given exists.
get_domain_oids $options(data_dir) $options(zone)

## Load netmasks file
load_netmasks_file $options(netmasks_file)

## Contact the server and put the zone information in a temporary file.
set tmp_file /tmp/zone
transfer_zone_file $server $options(zone) $tmp_file

if {[catch {load_zone_file $tmp_file} msg]} {
    oid_heap_close $options(data_dir)
    error $msg $errorInfo $errorCode
}

oid_heap_close $options(data_dir)

file delete $tmp_file
