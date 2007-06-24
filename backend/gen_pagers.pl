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
require "libtools.pl";

$usage = "Usage: $0\n";
($#ARGV == -1) || die $usage;

open(F, "<$providers_file") || die "Cannot open $providers_file\n";
while (<F>) {
    chop;
    ($name,$scope,$data_num,$operator_num,$support_num) = split(/\|/,$_);
    if (! defined $double_array{$scope}) {
	*tmp = sprintf("autoarray%u", $autoarray_count++);
	$double_array{$scope} = *tmp;
    }
    *array = $double_array{$scope};
    $array{$name} = "$name@$scope|$data_num|$operator_num|$support_num\n";
}
close(F);
&dump_to_files_by_region("providers.region", *double_array);
