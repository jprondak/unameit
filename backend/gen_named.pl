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

$rec_mail = 0;
$primary = 100;
$secondary = 200;

%root_servers = ("a.root-servers.net", "198.41.0.4",
		 "b.root-servers.net", "128.9.0.107",
		 "c.root-servers.net", "192.33.4.12",
		 "d.root-servers.net", "128.8.10.90",
		 "e.root-servers.net", "192.203.230.10",
		 "f.root-servers.net", "192.5.5.241",
		 "g.root-servers.net", "192.112.36.4",
		 "h.root-servers.net", "128.63.2.53",
		 "i.root-servers.net", "192.36.148.17",
		 "j.root-servers.net", "198.41.0.10",
		 "k.root-servers.net", "193.0.14.129",
		 "l.root-servers.net", "198.32.64.12",
		 "m.root-servers.net", "198.32.65.12");

&parse_regions_file;
&read_hosts;
&read_server_aliases;
&create_SOAs;
&create_host_records;
&create_server_alias_cnames;
&create_host_alias_cnames;
&create_secondary_ifs;
&create_region_MXs;
&dump_to_files("named.region", *file_data);
&create_db_cache;

sub get_mail_host {
    local($region) = @_;
    local($copy) = $region;
    local(@parts,$curstr,$retval);

    if (defined $cache{$region}) {
	return $cache{$region};
    }
    @parts = split(/\./, $region);
    do {
	$curstr = join('.',@parts);
	if (defined $mailhost{$curstr}) {
	    $retval = $mailhost{$curstr};
	    $cache{$copy} = $retval;
	    return $retval;
	}
    } while ((shift(@parts),@parts));

    if (defined $mailhost{'.'}) {
	$retval = $mailhost{'.'};
	$cache{'.'} = $retval;
	return $retval;
    }

    return '';
}

sub read_hosts {
    local($j,$name,$scope,$owner,$_);

    open(F, "<$canon_hosts_file") ||
	die "Cannot open $canon_hosts_file\n";
    while (<F>) {
	chop;
	($j,$j,$name,$scope,$owner) = split(/\|/);
	$hosts{"$name@$owner"} = $_;
    }
    close(F);
}

sub read_server_aliases {
    local($name,$scope,$j,$host,$hscope,$howner,$main_chunk);

    open(F, "<$server_aliases_file") ||
	die "Cannot open $server_aliases_file\n";
    while (<F>) {
	chop;
	($name,$scope,$stype,$rest) = split(' ',$_,4);
	if ($stype eq "mailhost") {
	    foreach $chunk (split(' ',$rest)) {
		($host,$hscope,$howner) = split(/@/,$chunk);
		if (! defined $mailhost{$scope}) {
		    $mailhost{$scope} = "$host@$howner";
		} else {
		    $mailhost{$scope} . = " $host@$howner";
		}
		$is_mailhost{"$host.$howner"} = 1;
	    }
	}
	if ($stype eq "dnsserver") {
	    $dns{$scope} = $_;
	}
	$server_aliases{"$name@$scope"} = $_;
    }
    exit(0) if %dns == 0;	# Exit if no DNS server aliases
    close(F);
}

sub create_SOAs {
    local($region,$name,$scope,$host,$hscope,$howner,$stype,$rest,$j,$temp);
    local($upper,$lower,$serial,$tail);
    
    foreach $region (keys %dns) {
	($name,$scope,$stype,$rest) = split(' ',$dns{$region},4);
	($temp) = split(' ',$rest);
	($host,$hscope,$howner) = split(/@/,$temp);
	($tail = $out_dir) =~ s:.*/::;
	($j,$upper,$lower) = split(/\./,$tail);
	$serial = ($upper*100000)+$lower;
	$file_data{$region} .=
	    "\@\tIN SOA\t$host".&d($howner).". " .
	      "postmaster".&d($howner).". (\n" .
	    "\t\t$serial\t; Serial\n" .
	    "\t\t10800\t; Refresh after 3 hours\n" .
	    "\t\t3600\t; Retry after 1 hour\n" .
	    "\t\t604800\t; Expire after 1 week\n" .
	    "\t\t86400 )\t; Minimum TTL of 1 day\n" .
	    ";--------------------------- Name Servers -----------------\n";
	&output_name_servers($region,split(' ',$rest));
	&add_line($region,
	    ";----------------------------------------------------------\n");
    }
}

sub create_host_records {
    local($index,$j,$ip,$host,$scope,$owner,$if,$gets_mail,$mailhost);
    local($cell,$org_oid,$c,$mailhost_list);

    foreach $index (keys %hosts) {
	($j,$ip,$host,$scope,$owner,$if,$j,$gets_mail) =
	    split(/\|/,$hosts{$index});

	# This prevents outputting a "localhost." record if we do not have
	# an internal root name server. In this case, we let the Internet
	# root level nameservers handle "localhost.".
	next if (! defined $dns{'.'} && $owner eq '.');
	next if ($host eq 'localhost');

	&add_line($owner, "$host".&d($owner).".\tIN A\t$ip\n");
	if ($if ne '') {
	    &add_line($owner, "$host-$if".&d($owner).".\tIN A\t$ip\n");
	}

	($cell,$org_oid) = &get_cell_and_oid($owner);

	foreach $c (split(/ /,$org_oid_2_cells{$org_oid})) {
	    next if ($c eq '.' && !defined $dns{'.'});
	    next if ($c eq $owner);
	    &add_line($c,
		"$host".&d($c).".\tIN CNAME\t$host".&d($owner).".\n");
	    if ($if ne '') {
		&add_line($c,
	        "$host-$if".&d($c).".\tIN CNAME\t$host-$if".&d($owner).".\n");
	    }
	}

	$mailhost_list = &get_mail_host($owner);
	$i = 0;
	foreach $mailhost (split(' ',$mailhost_list)) {
	    $mailhost =~ s/@/./;
	    if ($i == 0) {
		&add_line($owner, "$host".&d($owner).
			  ".\tIN MX\t$primary $mailhost.\n")
		    if ("$host.$owner" ne $mailhost && $mailhost ne '');
	    } else {
		&add_line($owner, "$host".&d($owner).
			  ".\tIN MX\t$secondary $mailhost.\n")
		    if ("$host.$owner" ne $mailhost && $mailhost ne '');
	    }
	    $i++;
	}
	&add_line($owner,
		  "$host".&d($owner).".\tIN MX\t$rec_mail $host".
		  &d($owner).".\n")
	    if ($gets_mail eq 'Yes' || defined $is_mailhost{"$host.$owner"});
    }
}

sub create_server_alias_cnames {
    local($index,$name,$scope,$host,$hscope,$howner,$j,$main_chunk);

    foreach $index (keys %server_aliases) {
	($name,$scope,$j,$main_chunk) = split(' ',$server_aliases{$index});

	next if (! defined $dns{'.'} && $scope eq '.');

	($host,$hscope,$howner) = split(/@/,$main_chunk);
	&add_line($scope,
	    "$name".&d($scope).".\tIN CNAME\t$host".&d($howner).".\n");
    }
}

sub create_host_alias_cnames {
    local($name,$scope,$host,$hscope,$howner,$cell,$org_oid,$c);

    open(F, "<$host_aliases_file") || die "Cannot open $host_aliases_file\n";
    while (<F>) {
	chop;
	($name,$scope,$host,$hscope,$howner) = split;

	next if (! defined $dns{'.'} && $scope eq '.');

	&add_line($scope,
	    "$name".&d($scope).".\tIN CNAME\t$host".&d($howner).".\n");

	if ($hscope ne $howner) {
	    &add_line($howner,
	      "$name".&d($howner).".\tIN CNAME\t$host".&d($howner).".\n");
	}

	($cell,$org_oid) = &get_cell_and_oid($scope);
	foreach $c (split(/ /,$org_oid_2_cells{$org_oid})) {
	    next if $cell eq $c;
	    &add_line($c,
		"$name".&d($c).".\tIN CNAME\t$host".&d($howner).".\n");
	}
    }
    close(F);
}

sub create_secondary_ifs {
    local($if,$ip,$j,$host,$scope,$owner,$c);

    open(F, "<$secondary_ifs_file") || die "Cannot open $secondary_ifs_file\n";
    while (<F>) {
	chop;
	($if,$ip,$j,$host,$scope,$owner) = split(/\|/);
	# Secondary interface names MUST be specified.
	&add_line($owner, "$host".&d($owner).".\tIN A\t$ip\n");
	&add_line($owner, "$host-$if".&d($owner).".\tIN A\t$ip\n");

	($cell,$org_oid) = &get_cell_and_oid($owner);

	foreach $c (split(/ /,$org_oid_2_cells{$org_oid})) {
	    next if ($c eq '.' && !defined $dns{'.'});
	    next if ($c eq $owner);
	    if ($if ne '') {
		&add_line($c,
	        "$host-$if".&d($c).".\tIN CNAME\t$host-$if".&d($owner).".\n");
	    }
	}
    }
    close(F);
}

sub create_region_MXs {
    local($name,$mailhost);

    foreach $name (keys %tree) {
	next if (! defined $dns{'.'} && $name eq '.');

	$mailhost_list = &get_mail_host($name);
	$i = 0;
	foreach $mailhost (split(' ',$mailhost_list)) {
	    $mailhost =~ s/@/./;
	    if ($i == 0) {
		&add_line($name, &nd($name).".\tIN MX\t$primary $mailhost.\n");
		if ($wildcard_mx{$name} eq 'Yes') {
		    &add_line($name,
			      '*'.&d($name).".\tIN MX\t$primary $mailhost.\n");
		}
	    } else {
		&add_line($name, &nd($name).
			  ".\tIN MX\t$secondary $mailhost.\n");
		if ($wildcard_mx{$name} eq 'Yes') {
		    &add_line($name, '*'.&d($name).
			      ".\tIN MX\t$secondary $mailhost.\n");
		}
	    }
	    $i++;
	}
    }
}

sub output_name_servers {
    local($region,@name_servers) = @_;
    local($owner,$ip,$host,$scope,$index,$ips);

    foreach $index (@name_servers) {
	($host,$scope,$owner,$ips) = split(/@/,$index);
	$file_data{$region} .= &nd($region).".\tIN NS\t$host".&d($owner).".\n";
	foreach $ip (split(/,/,$ips)) {
	    $file_data{$region} .= "$host".&d($owner).".\tIN A\t$ip\n";
	}
    }
}

sub create_db_cache {
    local($fd,$j,$host,$hscope,$howner,$rest,$ip,$index,$ips);

    $fd = &atomic_open("$out_dir/db.cache", 0644);
    if (defined $dns{"."}) {
	($j,$j,$j,$rest) = split(' ',$dns{"."},4);
	foreach $index (split(' ',$rest)) {
	    ($host,$hscope,$howner,$ips) = split(/@/,$index);
	    &atomic_print($fd, ".\t\t99999999 IN NS\t$host".&d($howner).".\n");
	    foreach $ip (split(/,/,$ips)) {
		&atomic_print($fd,
			      "$host".&d($howner).".\t99999999 IN A\t$ip\n");
	    }
	}
    } else {
	foreach $index (keys %root_servers) {
	    &atomic_print($fd, ".\t\t99999999 IN NS\t$index.\n");
	    foreach $ip (split(' ',$root_servers{$index})) {
		&atomic_print($fd, "$index.\t\t99999999 IN A\t$ip\n");
	    }
	}
    }
    &atomic_close($fd);
}

sub add_line {
    local($region,$line) = @_;

    $file_data{$region} .= $line;

    # Output localhost AFTER doing the above in case we are outputting an
    # SOA record which must go at the beginning.
    if (! defined $localhost{$region}) {
	$localhost{$region} = 1;
	$file_data{$region} .= "localhost".&d($region).".\tIN A\t127.0.0.1\n";
    }
}
