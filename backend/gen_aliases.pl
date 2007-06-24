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

open(F, "<$region_mailing_lists") || die "Cannot open $region_mailing_lists\n";
while (<F>) {
    chop;
    ($name,$region) = split(' ');
    $file_data{$region} .= "$name@$region\n";
}
close(F);
&dump_to_files("mailing_list.region", *file_data);
undef %file_data;

open(F, "<$cell_mailing_lists") || die "Cannot open $cell_mailing_lists\n";
while (<F>) {
    chop;
    ($name,$cell) = split(' ');
    $file_data{$cell} .= "$name@$cell\n";
}
close(F);
&dump_to_files("mailing_list.cell", *file_data);
undef %file_data;

open(F, "<$drops_file") || die "Cannot open $drops_file\n";
while (<F>) {
    chop;
    ($name,$region,$host,$rest) = split(' ',$_,4);
    $file_data{$host} .= "$name@$region: $rest\n";
}
close(F);
&dump_to_files("maildrop.host", *file_data);
undef %file_data;

open(F, "<$postmaster_lists_file") ||
    die "Cannot open $postmaster_lists_file\n";
while (<F>) {
    chop;
    ($name,$region,$rest) = split(' ',$_,3);
    $file_data{$region} .= "$name@$region: $rest\n";
}
close(F);
&dump_to_files("postmaster.region", *file_data);
undef %file_data;
