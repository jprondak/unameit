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

open(F, "<$services_file") || die "Cannot open $services_file\n";
while (<F>) {
    chop;
    ($name,$cell,$port_and_proto,$aliases) = split(/:/,$_,4);

    if (! defined $file_data{$cell}) {
	*tmp = sprintf("autoarray%u", $autoarray_count++);
	$file_data{$cell} = *tmp;
    }

    *array = $file_data{$cell};
    $array{$port_and_proto} = "$name\t$port_and_proto\t$aliases\n";
}
close(F);

&dump_to_files_by_region("services.cell", *file_data, 1);
