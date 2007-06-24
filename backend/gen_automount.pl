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

# Set full_canonical to 0 to get short host names
$full_canonical = 1;

$usage = "Usage: $0\n";
($#ARGV == -1) || die $usage;

open(F, "<$automount_map_file") || die "Cannot open $automount_map_file\n";
while (<F>) {
    chop;
    ($name,$cell,$dir,$options) = split(' ',$_,4);
    $file_data{$cell} .= "$dir $name $options\n";
}
close(F);
&dump_to_files("automount_map.cell", *file_data);
undef %file_data;

open(F, "<$region_automount_file") ||
    die "Cannot open $region_automount_file\n";
while (<F>) {
    chop;
    ($name,$owner,$map,@host_dir_pairs) = split;
    $file_data{$owner} .= "$map $name";
    while ($host = shift @host_dir_pairs) {
	$dir = shift @host_dir_pairs;

	if (!$full_canonical) {
	    $host =~ s/^([^.]*).*$/$1/;
	}

	$file_data{$owner} .= " $host:$dir";
    }
    $file_data{$owner} .= "\n";
}
close(F);
&dump_to_files("automount.region", *file_data);
undef %file_data;

open(F, "<$host_automount_file") || die "Cannot open $host_automount_file\n";
while (<F>) {
    ($name,$auto_host,$map,@host_dir_pairs) = split;
    $file_data{$auto_host} .= "$map $name";
    while ($host = shift @host_dir_pairs) {
	$dir = shift @host_dir_pairs;

	if (!$full_canonical) {
	    $host =~ s/^([^.]*).*$/$1/;
	}

	$file_data{$auto_host} .= " $host:$dir";
    }
    $file_data{$auto_host} .= "\n";
}
close(F);
&dump_to_files("automount.host", *file_data);
undef %file_data;

open(F, "<$user_automount_file") || die "Cannot open $user_automount_file\n";
while (<F>) {
    ($name,$cell,$map,$host,$dir) = split;
    if (!$full_canonical) {
	$host =~ s/^([^.]*).*$/$1/;
    }
    $file_data{$cell} .= "$map $name $host:$dir\n";
}
close(F);
&dump_to_files("automount.cell", *file_data);
undef %file_data;
