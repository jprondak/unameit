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
require 'data_files.pl';
require 'libtools.pl';

$usage = "Usage: $0\n";
($#ARGV == -1) || die $usage;

($tail = $out_dir) =~ s:.*/::;
($j,$upper,$lower) = split(/\./,$tail);
$serial = ($upper*100000)+$lower;
&parse_regions_file;
&read_networks;
&read_server_aliases;
&read_hosts_file;
&add_SOA_info;
&process_hosts_file;
&process_secondary_ifs;
&process_secondary_ip;
&create_inaddr_arpa;
&dump_to_files("inaddr", *file_data);

# You would think that routines such as this one that expects an IP address
# in dotted quad format could just check the input parameter to see if it
# contains a period or not and convert it to dotted quad if it doesn't. The
# problem is that a network such as 127 may be passed in.
sub strip_octet {
    local($ip)=@_;		# Should be dotted quad
    local(@ip);

    @ip = split(/\./,$ip);
    pop(@ip);
    return join('.', @ip);
}

sub add_SOA_info {
    local($addr,$ancestor_net,$name,$scope,$owner,$dns_server,$j);
    local($host,$rev_ancestor_net,$rest,$howner);

    foreach $addr (keys %network) {
	# 0 is the universe network
	next if ($addr eq '0' || $addr eq '224');
	next if $addr eq '127' && ! defined $dns{'.'};

	if ($addr eq '127') {
	    $ancestor_net = $addr;
	} else {
	    $ancestor_net = &ancestor_net_in_same_zone($addr);
	}
	if (! defined $file_data{$ancestor_net}) {
	    ($name,$owner) = split(' ',$network{$ancestor_net});
	    $dns_server = $dns{&get_dns_server_region($owner)};

	    ($host,$howner) = split('@',$dns_server);

	    $rev_ancestor_net = &reverse_ip($ancestor_net);
	    ($j,$j,$j,$rest) =
		split(' ',$server_aliases{$dns_server},4);
	    $file_data{$ancestor_net} =
		"\@\tIN SOA\t$host".&d($howner).". ".
		    "postmaster".&d($howner).". (\n" .
	        "\t\t$serial\t; Serial\n" .
	        "\t\t10800\t; Refresh after 3 hours\n" .
	        "\t\t3600\t; Retry after 1 hour\n" .
	        "\t\t604800\t; Expire after 1 week\n" .
		"\t\t86400 )\t; Minimum TTL of 1 day\n" .
	       ";--------------------------- Name Servers -----------------\n";
	    &output_name_servers($ancestor_net,$rev_ancestor_net,
				 split(' ',$rest));
	    $file_data{$ancestor_net} .=
	       ";----------------------------------------------------------\n";
	}
    }
}

# This routine is the heart of the file and algorithm for reverse
# address records. It looks for an ancestor network in the same DNS
# zone as the ip address passed in and returns it. For example,
# suppose you have three networks:
# 	128.6
#	128.6.15
#	128.6.15.240
# (The last network subnets on 4 bits.) We can only divide reverse
# address files on 8 bit boundaries so we check that the common bits is
# divisible by 8. We continue searching until we hit a
# network. If the network found is the first network we have found so
# far, then set the return value to it and keep searching. If a higher
# network divisible by 8 is found, check that they have the same DNS
# server. If they do, select the new network as the return value and
# continue searching. Otherwise, we've crossed a DNS zone boundary and
# we should return the previous value.
# 	In the example above, we first set the return value to
# 128.6.15 (an eight bit boundary). Then we check the network
# 128.6. If it is in the same zone as 128.6.15, we select it and
# keep searching for higher networks. (We won't find one.) If they are
# in different DNS zones, return 128.6.15.
sub ancestor_net_in_same_zone {
    local($ip) = @_;		# Should be dotted quad
    local($ret_val,$new_ip,$name,$scope,$owner,$old_server,$new_server);

    for ($new_ip = $ip, $ret_val = '';
	 length($new_ip) > 0;
	 $new_ip = &strip_octet($new_ip)) {
	next if ! defined $network{$new_ip} ||
	    $matching_bits{$new_ip} % 8 != 0;
	if ($ret_val eq '') {
	    $ret_val = $new_ip;
	} else {
	    ($name,$owner) = split(' ',$network{$ret_val});
	    $old_server = &get_dns_server_region($owner);
	    ($name,$owner) = split(' ',$network{$new_ip});
	    $new_server = &get_dns_server_region($owner);
	    if ($old_server eq $new_server) {
		$ret_val = $new_ip;
	    } else {
		return $ret_val;
	    }
	}
    }
    die "No ancestor network for $ip!\n" if $ret_val eq '';
    return $ret_val;
}

sub get_dns_server_region {
    local($region) = @_;
    local(@parts) = split(/\./,$region);

    return "." if $region eq ".";
    do {
	return join('.',@parts) if defined $dns{join('.',@parts)};
    } while ((shift(@parts),@parts));
    return ".";
}

# We have to read the hosts file before processing it because the
# information in here is used when we output the name server records.
sub read_hosts_file {
    local($j,$ip,$host,$scope,$owner);

    open(F, "<$canon_hosts_file") || die "Cannot open $canon_hosts_file\n";
    while (<F>) {
	chop;
	($j,$ip,$host,$scope,$owner) = split(/\|/);
	$hosts{"$host@$owner"} = $_;
    }
    close(F);
}

sub process_hosts_file {
    local($index,$ip,$host,$scope,$owner,$ancestor_net);

    foreach $index (keys %hosts) {
	($j,$ip,$host,$scope,$owner) = split(/\|/,$hosts{$index});
	next if ! defined $dns{'.'} && ($ip =~ /^127/ || $ip =~ /^224/);
	
	$ancestor_net = &ancestor_net_in_same_zone($ip);
	$file_data{$ancestor_net} .= &reverse_ip($ip) .
	    ".in-addr.arpa.\tIN PTR\t$host".&d($owner).".\n";
    }
}

sub process_secondary_ifs {
    local($j,$ip,$host,$scope,$owner,$ancestor_net);
    
    open(F, "<$secondary_ifs_file") || die "Cannot open secondary_ifs_file\n";
    while (<F>) {
	chop;
	($j,$ip,$j,$host,$scope,$owner) = split(/\|/);
	next if ! defined $dns{'.'} && ($ip =~ /^127/ || $ip =~ /^224/);

	$ancestor_net = &ancestor_net_in_same_zone($ip);
	$file_data{$ancestor_net} .= &reverse_ip($ip) .
	    ".in-addr.arpa.\tIN PTR\t$host".&d($owner).".\n";
    }
    close(F);
}

sub process_secondary_ip {
    local($j,$ip,$host,$scope,$owner,$ancestor_net);

    open(F, "<$secondary_ip_file") || die "Cannot open secondary_ip_file\n";
    while (<F>) {
	chop;
	($ip,$j,$host,$scope,$owner) = split(/\|/);
	next if ! defined $dns{'.'} && ($ip =~ /^127/ || $ip =~ /^224/);

	$ancestor_net = &ancestor_net_in_same_zone($ip);
	$file_data{$ancestor_net} .= &reverse_ip($ip) .
	    ".in-addr.arpa.\tIN PTR\t$host".&d($owner).".\n";
    }
    close(F);
}

sub read_networks {
    local($name,$owner,$addr,$last_addr,$shortened_net,$bits,$mask);
    
    open(F, "<$networks_file") || die "Cannot open $networks_file\n";
    while (<F>) {
	chop;
	($name,$owner,$addr,$last_addr,$mask) = split;
	$addr = &hexToip($addr);
	$last_addr = &hexToip($last_addr);
	$bits = &count_matching_bits($addr,$last_addr);
	$shortened_net = &trim_net_via_common_bits($addr,$bits);
	$network{$shortened_net} = $_;
	$matching_bits{$shortened_net} = $bits;
    }
    close(F);
}

sub read_server_aliases {
    local($name,$scope,$host,$hscope,$howner,$main_chunk,$stype);

    open(F, "<$server_aliases_file") ||
	die "Cannot open $server_aliases_file\n";
    while (<F>) {
	chop;
	($name,$scope,$stype,$main_chunk) = split;
	($host,$hscope,$howner) = split(/@/,$main_chunk);
	if ($stype eq "dnsserver") {
	    $server_aliases{"$host@$howner"} = $_;
	    $dns{$scope} = "$host@$howner";
	}
    }
    exit(0) if %dns == 0;	# If no dns server aliases, exit.
    close(F);
}

sub reverse_ip {
    local($ip) = @_;		# Should be dotted quad
    return join('.',reverse split(/\./, $ip));
}

sub output_name_servers {
    local($file_name,$rev_file_name,@name_servers) = @_;
    local($owner,$ip,$host,$scope,$index,$ips);

    foreach $index (@name_servers) {
	($host,$scope,$owner,$ips) = split(/@/,$index);
	$file_data{$file_name} .=
	    "$rev_file_name.in-addr.arpa.\tIN NS\t$host".&d($owner).".\n";
    }
}

sub create_inaddr_arpa {
    local($addr,$top_net,%nets_seen,$name,$scope,$owner,$dns_region,$host,$j);
    local($owner,$index,$i);

    if (defined $dns{"."}) {
	foreach $addr (keys %network) {
	    next if ($addr eq '0');
	    $top_net = &get_top_net($addr);
	    next if defined $nets_seen{$top_net};
	    $nets_seen{$top_net} = 1;
	    ($name,$owner) = split(' ',$network{$top_net});
	    $dns_region = &get_dns_server_region($owner);
	    if (! defined $file_data{"arpa"}) {
		($host,$owner) = split('@',$dns{"."});
		$file_data{"arpa"} =
			"\@\tIN SOA\t$host".&d($owner).". " .
			    "postmaster".&d($owner).". (\n" .
			"\t\t$serial\t; Serial\n" .
			"\t\t10800\t; Refresh after 3 hours\n" .
			"\t\t3600\t; Retry after 1 hour\n" .
			"\t\t604800\t; Expire after 1 week\n" .
			"\t\t86400 )\t; Minimum TTL of 1 day\n" .
	       ";--------------------------- Name Servers -----------------\n";
		}
	    ($j,$j,$j,$rest) =
		split(' ',$server_aliases{$dns{$dns_region}},4);

	    ## Only add once. Use 127 to only add once to file.
	    if ($addr eq '127') {
		## Add NS record for in-addr.arpa SOA
		foreach $index (split(' ',$rest)) {
		    ($host,$j,$owner) = split(/@/, $index);
		    $file_data{"arpa"} .=
			"in-addr.arpa.\tIN NS\t$host".&d($owner).".\n";
		}
	    }

	    &output_name_servers("arpa",&reverse_ip($top_net),
				 split(' ',$rest));
	}
    }
}

sub get_top_net {
    local($net) = @_;		# Should be dotted quad
    local($result) = '';

    for (; length($net) > 0; $net = &strip_octet($net)) {
	if (defined $network{$net}) {
	    $result = $net;
	}
    }
    return $result;
}
