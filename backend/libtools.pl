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
#This file contains useful procs for the backend programs
#
require 'atomic_io.pl';

sub hexToip {
    local($h) = @_;
    local($ip,$i);
    
    for ($i = 1, $ip = ''; $i*2 <= length($h); $i++) {
	if ($i != 1) {
	    $ip .= '.';
	}
	$ip .= hex(substr($h,($i-1)*2,2));
    }
    return $ip;
}

sub ipTohex {
    local(@tmp);
    @tmp = split(/\./, $_[0]);
    return sprintf("%02x" x @tmp, @tmp);
}

sub numerically { $a <=> $b; }

# This routines is passed a file name and an associative array indexed by
# region. The associative array values should be file contents. The
# associative array is indexed by a region. The routine concatenates the
# file name passed in with the region and writes out the file contents
# atomically.
# E.g., &dump_to_files("hosts", *hosts_file_data);
sub dump_to_files {
    local($file_name,*file_data) = @_;
    local($index,$fd);
    
    foreach $index (keys %file_data) {
	$fd = &atomic_open("$out_dir/$file_name.$index", 0644);
	&atomic_print($fd, $file_data{$index});
	&atomic_close($fd);
    }
}

# This subroutine creates a set of output files prefixed by
# $file_name. The data for the files is contained in "a" which is
# an associative array indexed by symbol table entries. Each one of these
# symbol table entries is in turn an associative array so "a" contains a
# list of lists.
sub dump_to_files_by_region {
    local($file_name,*a,$numerically) = @_;
    local($fd,$region,$index);
    
    foreach $region (keys %a) {
	$fd = &atomic_open("$out_dir/$file_name.$region", 0644);
	*tmp = $a{$region};
	foreach $index ($numerically ?
			(sort numerically keys %tmp) :
			(sort keys %tmp)) {
	    &atomic_print($fd, $tmp{$index});
	}
        &atomic_close($fd);
    }
}

%common_bit_table = (
    "0f", 0,
    "07", 1, "8f", 1,
    "03", 2, "47", 2, "8b", 2, "cf", 2,
    "01", 3, "23", 3, "45", 3, "67", 3, "89", 3, "ab", 3, "cd", 3, "ef", 3
);

sub count_matching_bits {
    local($start_addr,$end_addr) = @_;
    local($i,$bits,$s_char,$e_char);
    
    if ($start_addr =~ /\./) {
	$start_addr = &ipTohex($start_addr);
    }
    if ($end_addr =~ /\./) {
	$end_addr = &ipTohex($end_addr);
    }
    $start_addr =~ tr/A-F/a-f/;
    $end_addr =~ tr/A-F/a-f/;
    for ($i = 0, $bits = 0; $i < 8; $i++) {
	$s_char = substr($start_addr,$i,1);
	$e_char = substr($end_addr,$i,1);
	if ($s_char ne $e_char) {
	    return $bits + $common_bit_table{"$s_char$e_char"};
	}
	$bits += 4;
    }
    return $bits;
}

sub trim_net_via_common_bits {
    local($net,$common_bits) = @_;
    local(@split_net,$last_index);

    if ($net !~ /\./) {
	$net = &hexToip($net);
    }
    @split_net = split(/\./,$net);
    $last_index = int(($common_bits-1) / 8);
    return join('.',@split_net[0..$last_index]);
}

sub concat {
    local(*array,$index,$value) = @_;
    if (! defined $array{$index}) {
	$array{$index} = $value;
    } else {
	$array{$index} .= " $value";
    }
}

# Global variable used for creating anonymous "autoarray" variables
$autoarray_count = 0;

# This routine deletes all associative array global variables that start
# with "autoarray". (Actually it only deletes all their indices).
sub clear_autoarray_vars {
    local($name);

    foreach $name (grep(/^autoarray.*/, keys %_main)) {
	eval "undef %$name";
    }
    $autoarray_count = 0;
}

# This routine is useful for benchmarking
sub print_time {
    local($message) = @_;
    local($diff);

    if ($oldlocaltime == 0) {
	print $message, "\n";
    } else {
	$diff = time - $oldlocaltime;
	printf "%s: elapsed %u hours, %u minutes, %u secs\n", $message,
	int($diff / (60*60)), int($diff / 60), $diff % 60;
    }
    $oldlocaltime = time;
}

# This routine converts a string into another string twice as long consisting
# only of hexidecimal characters. Each character in the original string
# is converted to a two character string consisting of the hexidecimal value
# of the ascii character. This function is useful for mapping strings to 
# Perl identifier names that are unique.
sub str_to_hex {
    local($s) = @_;
    join('', grep($_=sprintf("%02x",ord), split('',$s)));
}

### This function returns the empty string if the domain passed in is
### ., otherwise it returns ".<domain>".
sub d {
    local($domain) = @_;

    if ($domain eq '.') {
	return '';
    } else {
	return '.' . $domain;
    }
}

### This function is like &d() except it doesn't prepend a dot.
sub nd {
    local($domain) = @_;

    if ($domain eq '.') {
	return '';
    } else {
	return $domain;
    }
}

sub breadth_first {
    return &real_breadth_first($a,$b);
}

# Sort passes arguments as $a and $b and this routine is called recursively
# so it needs to get its arguments from @_.
sub real_breadth_first {
    local($a,$b) = @_;
    local(@a,@b);

    if ($a eq '.') {
	return -1;
    }
    if ($b eq '.') {
	return 1;
    }

    @a = split(/\./, $a);
    @b = split(/\./, $b);

    if (@a != @b) {
	if (@a > @b) {
	    return 1;
	} else {
	    return -1;
	}
    }

    if ($a[0] ne $b[0]) {
	return $a[0] <=> $b[0];
    } else {
	return &real_breadth_first(join('.',@a[1..$#a]),join('.',@b[1..$#b]));
    }
}

### This routine sucks in the regions file and creates a tree representation
### and sets up arrays for the organizations. The following variables are
### filled in: %tree, %parent, %org_oid, %org_oid_2_cells and %wildcard_mx.
sub parse_regions_file {
    local($oid,$region,$parent_oid,$org_oid,$wildcard_mx);
    local(%regions,%oid2region,%region2parentoid);

    open(F, "<$region_file") || die "Cannot open $region_file\n";
    while (<F>) {
	chop;
	($oid,$region,$parent_oid,$wildcard_mx,$org_oid) = split(' ');

	$wildcard_mx{$region} = $wildcard_mx;

	$regions{$region} = 1;
	$oid2region{$oid} = $region;
	$region2parentoid{$region} = $parent_oid;

	# Perl undefines $org_oid if there are only 3 fields.
	if (defined $org_oid) {
	    $org_oid{$region} = $org_oid;
	    if (! defined $org_oid_2_cells{$org_oid}) {
		$org_oid_2_cells{$org_oid} = $region;
	    } else {
		$org_oid_2_cells{$org_oid} .= ' ' . $region;
	    }
	}
    }
    close(F);

    ## Build in memory tree
    foreach $region (sort breadth_first keys %regions) {
	$tree{$region} = "";
	
	## Compute the parent of the node. The root is its own parent.
	if ($region eq '.') {
	    $parent{'.'} = '.';
	    next;
	} else {
	    if (! defined $parent{$region}) {
		$parent{$region} = $oid2region{$region2parentoid{$region}};
	    } else {
		$parent{$region} .= ' ' .
		    $oid2region{$region2parentoid{$region}};
	    }
	}
    }
}

### This function returns the cell and oid of the organization for a region.
### It assumes that &parse_regions_file has been called first.
sub get_cell_and_oid {
    local($region) = @_;

    while (! defined $org_oid{$region}) {
	last if $region eq '.';
	$region = $parent{$region};
    }

    ($region,$org_oid{$region});
}

1;
