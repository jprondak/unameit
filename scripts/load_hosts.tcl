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
# $Id: load_hosts.tcl,v 1.39.10.2 1997/09/23 21:59:40 simpson Exp $

# Each IP address maps through an index into its owner. The owner is the
# host oid. A host may be multi-homed or contain secondary IP addresses
# so multiple IP addresses can map to the same host.

# The logic for adding a host probably should be:
#
# if IP address is already owned by a host
#     if name corresponding to IP address is the same as the host name
#     or one of the host's aliases,
#         then the host is already present. Add any non-existent aliases.
#     else
#	  record mismatch
#     fi
# else
#     if we find a host name on this IP line of the form <host>-<if> where
#     <host> exists
#         if <host>-<if> exists
#             # this IP address hasn't been seen or it would be caught
#	      # in the above if statement
#	      this is a secondary IP address for this interface
#	  else
#             this is a new interface record for <host>
#	  fi
#     else if one of the hosts on the line matches an existing host name
#	  # IP address hasn't been seen or it would be caught above
#	  this is a secondary address for the host
#     else
#         this is a new host record.
#     fi
# fi
#
# The logic for adding a host is:
#
# Suck in netmasks file
# for each line in the hosts file
#   Take the first host name entry on the line. If it contains a valid
#   domain use it; otherwise, use the default domain.
#   Reject the host name if it looks like a server type.
#   if the IP address is in use
#     if a host with this name exists (the original domain on the end
#     is ignored)
#	This host is a duplicate. Skip it.
#     else
#       This IP address is in use. Complain. Don't create host.
#     fi
#   elseif this host name already exists (the host name must be the
#   first name on each line even for secondary interfaces and addresses)
#     If the name is a host alias, reject it.
#     if one of the aliases contains a pattern such as <host>-<if> and
#     if this interface exists
#       Create a secondary address
#     else
#       Create a secondary interface record
#     fi
#   else
#     Create a new host record.
#   fi
#   Foreach alias on the host line
#     if alias is a server type
#       Create server alias record
#       continue
#     fi
#     if alias already exists, continue
#     Create alias
#   loop
# loop
#
# NOTE: addresses 00000000 and 7f000001 are ignored. These are
# nullhost and localhost.

# If a host is created with a new network, the network (and maybe the
# subnetwork) are created, owned by the same region as the host.

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB networks.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]


#
# Check the ip address for validity. Return 0 if bogus.
# Create a network and/or a subnetwork if needed.
#
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

proc load_hosts {option} {

    upvar 1 $option options
    global netmask\
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    RegionNames CellNames OrgNames \
	    RegionOid CellOid OrgOid

    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set hosts_file 	$options(HostsFile)
    set default_mask	$options(Netmask)
    set netmasks_file 	$options(NetmasksFile)
    set host_class	$options(HostClass)
    #
    # Load the pre-parsed database files
    #
    oid_heap_open $datadir

    #
    # Get lists of oids in each cell and org
    # Get the default region, its cell, and the org.
    # Routine raises an error if region not found.
    #
    get_domain_oids $datadir $default_region
    
    set MyOrgOids $OidsInOrg($OrgOid)

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
    # Load new hosts
    #
    set fh [open $hosts_file r]
    
    while {[gets $fh line] != -1} {
	#
	# Deal with comments
	#
	regexp {^([^#]*)#?(.*)$} $line x line comment
	set line [string trim $line]
	set comment [string trim $comment]
	if {[cequal "" $line]} {
	    continue
	}

	regsub -all -- "\[ \t\]+" $line " " line

	#
	# Parse into fields
	#
	set aliases [lassign [split $line] ip cname]

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
	    
	if {[catch {
	    set name [dump_canon_attr $host_class name $name]
	    set ip [dump_canon_attr $host_class ipv4_address $ip]
	}]} {
	    global errorCode
	    log_reject "$name $ip: bad format, $errorCode"
	    continue
	}

	# 
	# We do not allow host names that look like server types
	#
	if {[get_server_type_oid_by_name $datadir x $name]} {
	    log_reject "$name $ip: server type cannot be used as a host name"
	    continue
	}

	#
	# Process the alias names, getting nice names and the regions
	# The nice names will be keys in domain
	# The data for domain are lists of locations
	# aliases will be changed to the list of nice aliases (unqualified)
	#
	catch {unset domain}
	set_domain domain aliases $datadir 

	if {[get_ipv4_owner_oid $datadir ip_owner $ip]} {
	    log_debug "address $ip is in use by $ip_owner"

	    if {[lookup_hostname_oid $datadir x $name MyOrgOids]} {
		#
		# A host exists with this name,
		# and this ipv4_address is owned by it, it is a duplicate
		# and should be ignored. We will process the
		# aliases.
		#
		log_ignore "$cname, $ip, already exists"
	    } else {
		# However, a duplicate IP address is an error. We
		# discard the entire line.
		#
		log_reject "$cname; address $ip is in use by $ip_owner"
		continue
	    }

	} elseif {[lookup_hostname_oid $datadir owner $name MyOrgOids]} {
	    #
	    # Reject host_alias entries with new IP addresses.
	    #
	    if {! [oid_get_class $datadir oclass $owner]} {
		error "lost Class of OID $owner"
	    }
	    if {[cequal host_alias $oclass]} {
		log_reject "$name: cannot add new address for a host alias"
		continue
	    }

	    #
	    # Check the IP address and make a new network if needed.
	    #
	    if {! [check_ip_address $datadir $ip $default_mask]} {
		log_reject "$name: invalid IP address $ip"
		continue
	    }

	    #
	    # This is a new IP address for an existing
	    # host, make an interface record for it. 
	    # If there is an alias of the form name-x use
	    # x as the interface name. Otherwise use "", which will 
	    # cause the creation routine to generate a name like ifN
	    # where N is the number of interfaces for the host.
	    # NOTE: if name-x already exists, this is a secondary
	    # IP address, not a secondary interface.
	    #

	    catch {unset ifname}
	    set pattern "^$name-(\[a-zA-Z0-9\]+)\$"
	    foreach alias $aliases {
		if {[regexp -- $pattern $alias junk ifname]} {
		    break
		}
	    }
	    set isa_secaddr 0
	    if {[info exists ifname]} {
		set isa_secaddr [lookup_hostname_oid $datadir x "$name-$ifname" \
			MyOrgOids]

	    } else {
		set ifname ""
	    }

	    #
	    # Create either a secondary interface or a secondary address
	    #
	    if $isa_secaddr {
		oid_heap_create_l $datadir \
			Class ipv4_secondary_address \
			owner $owner \
			ipv4_address $ip comment $comment
		log_create "secondary address $ip added to $name"
	    } else {
		oid_heap_create_l $datadir \
			Class ipv4_interface \
			owner $owner \
			ifname $ifname \
			ipv4_address $ip comment $comment
		log_create "interface $ifname added to $name"
	    }
	} else {
	    #
	    # New Host
	    #

	    #
	    # Check the IP address and make a new network if needed.
	    #
	    if {! [check_ip_address $datadir $ip $default_mask]} {
		log_reject "$name: invalid IP address $ip"
		continue
	    }

	    #
	    # fill in interface name using algorithm from above
	    #
	    catch {unset pattern}
	    set ifname ""
	    append pattern ^ $name {-([a-zA-Z0-9]+)$}
	    foreach alias $aliases {
		if {[regexp -- $pattern $alias junk ifname]} {
		    break
		}
	    }

	    # HPL hack
	    set mail Yes
	    if {[regexp -nocase -- {no smtp} $comment]} {
		set mail No
	    }

	    set oid [oid_heap_create_l $datadir \
		    Class $host_class \
		    owner $region \
		    name $name \
		    ipv4_address $ip \
		    ifname $ifname \
		    comment $comment \
		    receives_mail $mail]
	}

	#
	# Each alias not already present will be saved as a host_alias
	# record with the owner set to $host_oid, or a server_alias
	# owned by the domain.
	#
	set host_name $name
	if {! [lookup_hostname_oid $datadir host_oid $name MyOrgOids]} {
	    error "bug: lost oid of newly created host $name"
	}

	foreach name $aliases {
	    foreach location $domain($name) {
		log_debug "processing alias $name in $location"

		#
		# Create a server alias in that location 
		# if this alias is a server type
		#
		if {[get_server_type_oid_by_name $datadir server_type_oid $name]} {
		    if {[get_server_alias_oid $datadir x $server_type_oid $location]} {
			log_ignore "$name: server alias already present"
			continue
		    }
		    
		    set oid [oid_heap_create_l $datadir \
			    Class server_alias \
			    name $name \
			    server_type $server_type_oid \
			    owner $location \
			    primary_server $host_oid ]
		    continue
		}
		
		#
		# Default - create a host_alias. Look for it in the org and
		# in the . cell.
		#
		if {[lookup_hostname_oid $datadir already $name MyOrgOids]} {
		    log_ignore "$name: host already present"
		    continue
		}
		set oid [oid_heap_create_l $datadir \
		    name $name \
		    owner $host_oid \
		    Class host_alias ]
	    }
	}
    }
    close $fh

    oid_heap_close $datadir
    return
}

#
# Process a list of aliases, returning a variable
# e.g. domain where domain(name) is set to the region OID,
# and name is the unqualified name.
#
# Ignore things outside the organization.
#
#
proc set_domain {varname listname datadir} {
    upvar 1 $varname domain \
	    $listname aliases 
    global RegionOid OrgOid OrgOids OrgOf LoadOptions

    set default_region $LoadOptions(Region)
    
    foreach aliase $aliases {

	log_debug "alias <$aliase>"

	# 
	# Get OID of domain. If the alias is not qualified, 
	# use the default domain.
	#
	if {[split_domain $aliase region name]} {
	    if {! [get_domain_oid $datadir region_oid $region]} {
		log_warn "$aliase is not in a valid region,\
			    using $default_region"
		set region_oid $RegionOid
		continue
	    }
	    if {! [cequal $OrgOid $OrgOf($region_oid)]} {
		log_reject "$aliase: outside of organization"
		continue
	    }
	} else {
	    set region_oid $RegionOid
	}
	if [catch {
	    set name [dump_canon_attr host_alias name $name]
	}] {
	    global errorCode
	    log_reject "$aliase: bad format, $errorCode"
	    continue
	}

	if {[info exists domain($name)]} {
	    lappend domain($name) $region_oid
	} else {
	    set domain($name) [list $region_oid]
	}
    }
    set aliases [array names domain]
}

# check input options and files
if {[catch {
    get_options LoadOptions \
	    {c	LoadOptions(HostClass)		$optarg} \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {r	LoadOptions(Region)  		$optarg} \
	    {m	LoadOptions(Netmask)	        $optarg} \
	    {M	LoadOptions(NetmasksFile)       $optarg} \
	    {f	LoadOptions(HostsFile)		$optarg} 
    check_options LoadOptions \
	    c HostClass \
	    d DataDir \
	    m Netmask \
	    M NetmasksFile\
	    f HostsFile \
	    r Region
    check_files LoadOptions \
	    d DataDir \
	    M NetmasksFile \
	    f HostsFile
} problem]} {
    puts stderr $problem
    puts stderr [format {Usage: unameit_load hosts
[-W -R -C -I -D]	logging options
-c class		computer, router or hub
-d data 		name of directory made by unameit_load copy_checkpoint
-m netmask		default netmask for any created networks
-M netmasks		netmasks file
-r region_name		name of this domain (e.g., mktng.xyz.com)
-f hosts		file containing hosts, addresses and aliases
}]
    exit 1
}

load_hosts LoadOptions
