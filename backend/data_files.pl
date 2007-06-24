#! /usr/bin/perl
#
# $Id: $
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

# All the gen scripts take a -i option and -o which are the directories
# for the input files and output files respectively. The code below removes
# the -i and -o options from the argument list and leaves the argument list
# in @ARGV as usual.
@ARGV_COPY = ();
while ($el = shift @ARGV) {
    if (substr($el,0,2) eq "-i") {
	if (length($el) == 2) {
	    $#ARGV == -1 && die "Argument must be given to -i option\n";
	    $in_dir = $ARGV[0];
	    shift @ARGV;
	} else {
	    $in_dir = substr($el, 2);
	}
	next;
    }
    if (substr($el,0,2) eq "-o") {
	if (length($el) == 2) {
	    $#ARGV == -1 && die "Argument must be given to -o option\n";
	    $out_dir = $ARGV[0];
	    shift @ARGV;
	} else {
	    $out_dir = substr($el, 2);
	}
	next;
    }
    push(@ARGV_COPY,$el);
}
!defined $in_dir && die "-i option not given\n";
!defined $out_dir && die "-o option not given\n";
@ARGV = @ARGV_COPY;
	
# host files
$canon_hosts_file       	= "$in_dir/canon_hosts";
$host_aliases_file      	= "$in_dir/host_aliases";
$secondary_ip_file      	= "$in_dir/secondary_ip";
$secondary_ifs_file     	= "$in_dir/secondary_ifs";
$host_aliases_file      	= "$in_dir/host_aliases";
$server_aliases_file		= "$in_dir/server_aliases";

# Printcap files
$printer_type_file		= "$in_dir/printer_type";
$printer_file			= "$in_dir/printers";
$printer_alias_file		= "$in_dir/printer_alias";

# Login files
$os_login_file			= "$in_dir/os_logins";
$login_file			= "$in_dir/logins";
$system_login_file		= "$in_dir/system_logins";
$user_login_file		= "$in_dir/user_logins";
$shell_location			= "$in_dir/shell_location";

# Mailing lists
$mailing_lists_file		= "$in_dir/mailing_lists";
$postmaster_lists_file		= "$in_dir/postmaster_lists";
$drops_file			= "$in_dir/drops";
$region_mailing_lists		= "$in_dir/region_mailing_lists";
$cell_mailing_lists		= "$in_dir/cell_mailing_lists";

# Services files
$services_file			= "$in_dir/services";

# Netgroup files
$region_netgroup_file		= "$in_dir/region_netgroups";

# Automounts
$automount_map_file		= "$in_dir/automount_map";
$region_automount_file		= "$in_dir/region_automounts";
$host_automount_file		= "$in_dir/host_automounts";
$user_automount_file		= "$in_dir/user_automounts";

# Groups
$os_group_file			= "$in_dir/os_groups";
$group_file			= "$in_dir/groups";
$system_group_file		= "$in_dir/system_groups";
$user_group_file		= "$in_dir/user_groups";

# Networks
$networks_file			= "$in_dir/networks";

# Sybase Interfaces
$sybase_interfaces_file		= "$in_dir/sybase_interface";

# Pagers
$providers_file			= "$in_dir/providers";
$pagers_file			= "$in_dir/pagers";

# DHCP
$dhcp_server_identifier_file	= "$in_dir/dhcp_server_identifier";
$dhcp_networks_file		= "$in_dir/dhcp_networks";
$dhcp_static_hosts_file		= "$in_dir/dhcp_static_hosts";
$dhcp_dynamic_hosts_file	= "$in_dir/dhcp_dynamic_hosts";

# Other
$region_file			= "$in_dir/regions";
$os_file			= "$in_dir/os";
1;
