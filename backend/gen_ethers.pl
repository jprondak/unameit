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

$full_canonical = 1;
$usage = "Usage: $0\n";
($#ARGV == -1) || die $usage;

sub add_colons {
    local($addr) = @_;

    for ($i = 0, $result = '';
	 $i < length($addr);
	 $i += 2) {
	if ($i != 0) {
	    $result .= ':';
	}
	$result .= substr($addr,$i,2);
    }
    return $result;
}

$fd = &atomic_open("$out_dir/ethers", 0644);

open(F, "<$secondary_ifs_file") || die "Cannot open $secondary_ifs_file\n";
while (<F>) {
    chop;
    ($ifname,$ip,$mac,$hname,$cell,$region) = split(/\|/);
    next if ($mac eq "");
    $mac = &add_colons($mac);
    if ($full_canonical) {
	&atomic_print($fd, "$mac\t$hname-$ifname.$region\n");
    } else {
	&atomic_print($fd, "$mac\t$hname-$ifname\n");
    }
}
close(F);

open(F, "<$canon_hosts_file") || die "Cannot open $canon_hosts_file\n";
while (<F>) {
    chop;
    ($j,$j,$hname,$cell,$region,$ifname,$mac) = split(/\|/);
    next if ($mac eq "");
    $mac = &add_colons($mac);
    if ($ifname ne "") {
	$hifname = "$hname-$ifname";
    } else {
	$hifname = $hname;
    }
    if ($full_canonical) {
	&atomic_print($fd, "$mac\t$hifname.$region\n");
    } else {
	&atomic_print($fd, "$mac\t$hifname\n");
    }
}
close(F);

&atomic_close($fd);
