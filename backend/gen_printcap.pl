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
require "data_files.pl";
require 'libtools.pl';

$full_canonical = 1;

($#ARGV == -1) || die "Usage: $0\n";

open(F, "<$printer_type_file") || die "Cannot open $printer_type_file\n";
while (<F>) {
    chop;
    ($name,$cell,$rest) = split(':',$_,3);
    $file_data{$cell} .= "$name:$rest\n";
}
close(F);
&dump_to_files("printer_type.cell", *file_data);
undef %file_data;

open(F, "<$printer_file") || die "Cannot open $printer_file\n";
while (<F>) {
    chop;
    ($name,$cell,$host,$template,$rest) = split(':',$_,5);
    if (!$full_canonical) {
	$host =~ s/^([^.]*).*$/$1/;
    }
    $file_data{$cell} .=
	"$host $template $name lp=:rm=$host:rp=$template:mx#0:$rest\n";
}
close(F);
&dump_to_files("printer.cell", *file_data);
undef %file_data;

open(F, "<$printer_alias_file") || die "Cannot open $printer_alias_file\n";
while (<F>) {
    chop;
    ($name,$owner,$type,$printer) = split(':', $_);
    if ($type eq 'host') {
	$hfile_data{$owner} .= "$name $printer\n";
    } else {
	$file_data{$owner} .= "$name $printer\n";
    }
}
close(F);
&dump_to_files("printer_alias.region", *file_data);
&dump_to_files("printer_alias.host", *hfile_data);

