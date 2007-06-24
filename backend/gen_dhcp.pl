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
require 'data_files.pl';
require 'libtools.pl';

$usage = "Usage: $0\n";
($#ARGV == -1) || die $usage;

&read_server_aliases;

sub extract_ip_list {
    local($chunks) = @_;
    local($chunk,$result,$j,$ips,$ip);

    $result='';
    foreach $chunk (split(' ',$chunks)) {
	($j,$j,$j,$ips) = split(/@/,$chunk,4);
	foreach $ip (split(/,/,$ips)) {
	    if ($result eq '') {
		$result = $ip;
	    } else {
		$result .= ", $ip";
	    }
	}
    }
    return $result;
}

sub read_server_aliases {
    local($name,$scope,$chunks,$stype);

    open(F, "<$server_aliases_file") ||
	die "Cannot open $server_aliases_file\n";
    while (<F>) {
	chop;
	($name,$scope,$stype,$chunks) = split(' ',$_,4);
	if ($stype eq "dnsserver") {
	    $dns{$scope} = &extract_ip_list($chunks);
	}
	if ($stype eq "nisserver") {
	    $nis{$scope} = &extract_ip_list($chunks);
	}
    }
    close(F);
}

sub get_nis_ips {
    local($region) = @_;
    local($copy) = $region;
    local(@parts,$curstr,$retval);

    if (defined $niscache{$region}) {
	return $niscache{$region};
    }
    @parts = split(/\./, $region);
    do {
	$curstr = join('.',@parts);
	if (defined $nis{$curstr}) {
	    $retval = $nis{$curstr};
	    $niscache{$copy} = $retval;
	    return $retval;
	}
    } while ((shift(@parts),@parts));

    if (defined $nis{'.'}) {
	$retval = $nis{'.'};
	$niscache{'.'} = $retval;
	return $retval;
    }

    return '';
}

sub get_dns_ips {
    local($region) = @_;
    local($copy) = $region;
    local(@parts,$curstr,$retval);

    if (defined $dnscache{$region}) {
	return $dnscache{$region};
    }
    @parts = split(/\./, $region);
    do {
	$curstr = join('.',@parts);
	if (defined $dns{$curstr}) {
	    $retval = $dns{$curstr};
	    $dnscache{$copy} = $retval;
	    return $retval;
	}
    } while ((shift(@parts),@parts));

    if (defined $dns{'.'}) {
	$retval = $dns{'.'};
	$dnscache{'.'} = $retval;
	return $retval;
    }

    return '';
}

open(F, "<$dhcp_server_identifier_file") ||
    die "Cannot open $dhcp_server_identifier_file\n";
while (<F>) {
    chop;
    ($host,$ip) = split;
    $host_to_server_id{$host} = $ip;
}
close(F);

open(F, "<$dhcp_networks_file") ||
    die "Cannot open $dhcp_networks_file\n";
while (<F>) {
    chop;
    ($host,$nstart,$nend,$nmask,$region) = split;
    if (! defined $net_sym_ptrs_by_host{$host}) {
	*tmp = sprintf("autoarray%u", $autoarray_count++);
	$net_sym_ptrs_by_host{$host} = *tmp;
    }
    *array = $net_sym_ptrs_by_host{$host};
    $array{"$nstart,$nmask"} = "subnet $nstart netmask $nmask {\n" .
	"  option domain-name \"$region\";\n" .
        "  option nis-domain \"$region\";\n";
    $nis_ips = &get_nis_ips($region);
    if ($nis_ips ne '') {
	$array{"$nstart,$nmask"} .= "  option nis-servers $nis_ips;\n";
    }
    $dns_ips = &get_dns_ips($region);
    if ($dns_ips ne '') {
	$array{"$nstart,$nmask"} .= "  option domain-name-servers $dns_ips;\n";
    }
}
close(F);

open(F, "<$dhcp_dynamic_hosts_file") ||
    die "Cannot open $dhcp_dynamic_hosts_file\n";
while (<F>) {
    chop;
    ($host,$nstart,$nmask,$rstart,$rend,$lease) = split;
    *array = $net_sym_ptrs_by_host{$host};
    $array{"$nstart,$nmask"} .= "  range $rstart $rend;\n";

    ## Pick the shortest lease if one is defined.
    if ($lease ne '') {
	if (defined $leases{$host}) {
	    *array = $leases{$host};
	    if (defined $array{"$nstart,$nmask"}) {
		if ($lease < $array{"$nstart,$nmask"}) {
		    $array{"$nstart,$nmask"} = $lease;
		}
	    } else {
		$array{"$nstart,$nmask"} = $lease;
	    }
	} else {
	    *tmp = sprintf("autoarray%u", $autoarray_count++);
	    $leases{$host} = *tmp;
	    *array = $leases{$host};
	    $array{"$nstart,$nmask"} = $lease;
	}
    }
}
close(F);

## Add lease time and closing } to each network stanza.
foreach $host (keys %net_sym_ptrs_by_host) {
    *array = $net_sym_ptrs_by_host{$host};
    foreach $net (keys %array) {
	if (defined $leases{$host}) {
	    *array2 = $leases{$host};
	    if (defined $array2{$net}) {
		$array{$net} .= sprintf("  default-lease-time %d;\n",
				       $array2{$net});
	    }
	}

	$array{$net} .= "}\n";
    }
}

## Put all the above entries into an internal memory array divided by host.
foreach $host (keys %net_sym_ptrs_by_host) {
    $file_data{$host} .= "server-identifier $host_to_server_id{$host};\n" .
	"use-host-decl-names on;\n\n";
    *array = $net_sym_ptrs_by_host{$host};
    foreach $net (keys %array) {
	$file_data{$host} .= "$array{$net}\n";
    }
}

## Add the static host entries to the array for each host.
open(F, "<$dhcp_static_hosts_file") ||
    die "Cannot open $dhcp_static_hosts_file\n";
while (<F>) {
    chop;
    ($dhcp_host,$host,$region,$ip,$macaddr) = split;
    $file_data{$dhcp_host} .= "host $host.$region {\n" .
	"  hardware ethernet $macaddr;\n" .
	"  fixed-address $ip;\n" .
	"  option host-name \"$host\";\n" .
        "  option domain-name \"$region\";\n" .
	"  option nis-domain \"$region\";\n";
    $nis_ips = &get_nis_ips($region);
    if ($nis_ips ne '') {
	$file_data{$dhcp_host} .= "  option nis-servers $nis_ips;\n";
    }
    $dns_ips = &get_dns_ips($region);
    if ($dns_ips ne '') {
	$file_data{$dhcp_host} .= "  option domain-name-servers $dns_ips;\n";
    }
    $file_data{$dhcp_host} .= "}\n\n";
}
close(F);

&dump_to_files("dhcp.host", *file_data);

	    
