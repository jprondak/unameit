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
#
# System libraries
require "getopts.pl";

# Local libraries
require "data_files.pl";
require "libtools.pl";

&read_hosts;
&write_hosts;

&clear_autoarray_vars;

&read_regular_aliases;
&write_regular_aliases;

&clear_autoarray_vars;

&read_secondary_ifs;
&write_secondary_ifs;

&clear_autoarray_vars;

&read_secondary_ips;
&write_secondary_ips;

&dump_to_files("hosts.region", *file_data);

&clear_autoarray_vars;

%file_data = ();
&read_server_aliases;
&write_server_aliases;

&dump_to_files("server_aliases.region", *file_data);

sub read_hosts {
    local($j,$name,$owner,$ip,$if,$hex_ip_addr,$region,$scope,@temp);

    open(CANON_HOSTS, "<$canon_hosts_file") ||
	die "Cannot open $canon_hosts_file\n";
    while (<CANON_HOSTS>) {
	chop;
	($j,$ip,$name,$scope,$owner,$if) = split(/\|/);
	$hosts{"$name@$scope"} = $_;
	$hex_ip_addr = &ipTohex($ip);
	if (! defined $ip_array_sym_ptrs_by_region{$scope}) {
	    *tmp = sprintf("autoarray%u", $autoarray_count++);
	    $ip_array_sym_ptrs_by_region{$scope} = *tmp;
	}
	*array = $ip_array_sym_ptrs_by_region{$scope};
	$array{$hex_ip_addr} = "$name@$scope";
    }
    close(CANON_HOSTS);
}

# Fills in the %file_data associative array
sub write_hosts {
    local($region,$owner,$hosts_index);
    local($uuid,$ip,$scope,$if,$host);

    foreach $region (keys %ip_array_sym_ptrs_by_region) {
	*tmp = $ip_array_sym_ptrs_by_region{$region};
        foreach $hex_ip (sort keys %tmp) {
	    $hosts_index = $tmp{$hex_ip};
	    ($uuid,$ip,$host,$scope,$owner,$if) =
		split(/\|/,$hosts{$hosts_index});
	    $file_data{$region} .= sprintf("%s %s %s %s",
	          $ip, $host, $host . &d($owner),
		  $scope eq $owner ? "" : $host . &d($scope));
	    if ($if ne "") {
		$file_data{$region} .= sprintf(" %s %s %s",
	          "$host-$if", "$host-$if" . &d($owner),
		  $scope eq $owner ? "" : "$host-$if" . &d($scope));
	    }
	    $file_data{$region} .= "\n";
	}
    }
}
	
sub read_regular_aliases {
    local($alias,$alias_scope);

    open(REGULAR_ALIASES, "<$host_aliases_file") ||
	die "Cannot open $host_aliases_file\n";
    undef %alias_array_sym_ptrs_by_region;
    while (<REGULAR_ALIASES>) {
	chop;
	($alias,$alias_scope) = split;
	if (!defined $alias_array_sym_ptrs_by_region{$alias_scope}) {
	    *tmp = sprintf("autoarray%u", $autoarray_count++);
	    $alias_array_sym_ptrs_by_region{$alias_scope} = *tmp;
	}
	*array = $alias_array_sym_ptrs_by_region{$alias_scope};
	$array{$alias} = $_;
    }
    close(REGULAR_ALIASES);
}

sub write_regular_aliases {
    local($region,$a,$alias,$scope,$j,$main_chunk,$referent_host,$j,$ip,$ips);
    local($referent_scope,$hex_ip,%ips,$referent_owner,$uuid);

    foreach $region (keys %alias_array_sym_ptrs_by_region) {
	%ips = ();
	*array = $alias_array_sym_ptrs_by_region{$region};
	foreach $a (sort keys %array) {
	    ($alias,$scope,$referent_host,$referent_scope,$referent_owner) =
		split(' ',$array{$a});
	    ($uuid,$ip) = split(/\|/,$hosts{"$referent_host@$referent_scope"});
	    $hex_ip = &ipTohex($ip);
	    $ips{$hex_ip} .= sprintf("%s %s %s %s %s\n",
		     $ip, $referent_host, $alias.&d($referent_owner),
		     $referent_owner eq $referent_scope
				     ? "" : $alias.&d($scope), $alias);
	}
	foreach $hex_ip (sort keys %ips) {
	    $file_data{$region} .= $ips{$hex_ip};
	}
    }
}    

sub read_secondary_ifs {
    local($ip,$j,$ref_owner,$ref_scope,$hex_ip_addr,$if);

    open(SECONDARY_IFS, "<$secondary_ifs_file") ||
	die "Cannot open $secondary_ifs_file\n";
    while (<SECONDARY_IFS>) {
	chop;
	($if,$ip,$j,$j,$ref_scope,$ref_owner) = split(/\|/);
	if (!defined $ifs_array_sym_ptrs_by_region{$ref_scope}) {
	    *tmp = sprintf("autoarray%u", $autoarray_count++);
	    $ifs_array_sym_ptrs_by_region{$ref_scope} = *tmp;
	}
	*array = $ifs_array_sym_ptrs_by_region{$ref_scope};
	$hex_ip_addr = &ipTohex($ip);
	$array{"$hex_ip_addr$if"} = $_;
    }
    close(SECONDARY_IFS);
}

sub write_secondary_ifs {
    local($region,$key,$if,$ip,$j,$referent_host,$referent_scope);
    local($referent_owner);

    foreach $region (keys %ifs_array_sym_ptrs_by_region) {
	*array = $ifs_array_sym_ptrs_by_region{$region};
	foreach $key (sort keys %array) {
	    ($if,$ip,$j,$referent_host,$referent_scope,$referent_owner) =
		split(/\|/,$array{$key});
	    $file_data{$region} .= sprintf("%s %s %s %s %s\n", $ip,
		 $referent_host, "$referent_host-$if",
	         "$referent_host-$if".&d($referent_owner),
		 $referent_scope eq $referent_owner ? "" :
			   "$referent_host-$if".&d($referent_scope));
	}
    }
}
	
sub read_secondary_ips {
    local($ip,$j,$ref_owner,$ref_scope,$hex_ip_addr);

    open(SECONDARY_IPS, "<$secondary_ip_file") ||
	die "Cannot open $secondary_ip_file\n";
    undef %ip_array_sym_ptrs_by_region;
    while (<SECONDARY_IPS>) {
	chop;
	($ip,$j,$j,$ref_scope,$ref_owner) = split(/\|/);
	if (!defined $ip_array_sym_ptrs_by_region{$ref_scope}) {
	    *tmp = sprintf("autoarray%u", $autoarray_count++);
	    $ip_array_sym_ptrs_by_region{$ref_scope} = *tmp;
	}
	*array = $ip_array_sym_ptrs_by_region{$ref_scope};
	$array{$ip} = $_;
    }
    close(SECONDARY_IPS);
}

sub write_secondary_ips {
    local($region,$key,$if,$ip,$j,$referent_host,$referent_scope);
    local($referent_owner);

    foreach $region (keys %ip_array_sym_ptrs_by_region) {
	*array = $ip_array_sym_ptrs_by_region{$region};
	foreach $key (sort keys %array) {
	    ($ip,$if,$referent_host,$referent_scope,$referent_owner) =
		split(/\|/,$array{$key});
	    $file_data{$region} .= sprintf("%s %s", $ip,
				   $referent_host);
	    if ($if ne "") {
		$file_data{$region} .= sprintf(" %s %s %s",
		"$referent_host-$if",					       
		"$referent_host-$if".&d($referent_owner),
		$referent_scope ne $referent_owner ?
		   "$referent_host-$if".&d($referent_scope) : "");
	    }
	    $file_data{$region}. = "\n";
	}
    }
}
	
sub read_server_aliases {
    local($alias,$alias_scope,$stype);

    open(SERVER_ALIASES, "<$server_aliases_file") ||
	die "Cannot open $server_aliases_file\n";
    while (<SERVER_ALIASES>) {
	chop;
	($alias,$alias_scope,$stype) = split;
	
	next if $alias_scope eq '.'; # Can't have server alias for
				     # whole Internet!
	if (!defined $alias_array_sym_ptrs_by_region2{$alias_scope}) {
	    *tmp = sprintf("autoarray%u", $autoarray_count++);
	    $alias_array_sym_ptrs_by_region2{$alias_scope} = *tmp;
	}
	*array = $alias_array_sym_ptrs_by_region2{$alias_scope};
	$array{$stype} = $_;
    }
    close(SERVER_ALIASES);
}

sub write_server_aliases {
    local($region,$a,$alias,$scope,$j,$main_chunk,$referent_host,$ip,$ips);
    local($referent_owner);

    foreach $region (keys %alias_array_sym_ptrs_by_region2) {
	*array = $alias_array_sym_ptrs_by_region2{$region};
	foreach $a (keys %array) {
	    ($alias,$scope,$j,$main_chunk) = split(' ',$array{$a});
	    ($referent_host,$j,$referent_owner,$ips) = split(/@/,$main_chunk);
	    ($ip) = split(/,/, $ips);
	    $file_data{$region} .= "$ip $referent_host".&d($referent_owner)
		." $alias.$scope\n";
	}
    }
}    

1;
