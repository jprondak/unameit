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

open(F, "<$user_group_file") || die "Cannot open $user_group_file\n";
while (<F>) {
    chop;
    ($name,$cell,$region,$gid,$logins) = split(/:/);
    &add_group_entry($cell,$name,$gid,$logins);
}
close(F);
&dump_to_files_by_region("user_groups.region", *double_array, 1);
&clear_autoarray_vars;
undef %double_array;

open(F, "<$group_file") || die "Cannot open $group_file\n";
while (<F>) {
    chop;
    ($name,$region,$gid,$logins) = split(/:/);
    &add_group_entry($region,$name,$gid,$logins);
}
close(F);
&dump_to_files_by_region("groups.region", *double_array, 1);
&clear_autoarray_vars;
undef %double_array;

open(F, "<$os_group_file") || die "Cannot open $os_group_file\n";
while (<F>) {
    chop;
    ($name,$region,$rest) = split(/:/,$_,3);
    $data{$region} .= "$name:$rest\n";
}
close(F);
&dump_to_files("os_groups.region", *data);
undef %data;

open(F, "<$system_group_file") || die "Cannot open $system_group_file\n";
while (<F>) {
    chop;
    ($name,$region,$template,$gid,$logins) = split(/:/);
    if (! defined $double_array{$region}) {
	*tmp = sprintf("autoarray%s", $autoarray_count++);
	$double_array{$region} = *tmp;
    }
    *array = $double_array{$region};
    $array{"$gid$name"} = "$name:$template:$gid:$logins\n";
}
close(F);
&dump_to_files_by_region("system_groups.region", *double_array, 1);

sub add_group_entry {
    local($region,$name,$gid,$logins) = @_;

    if (! defined $double_array{$region}) {
	*tmp = sprintf("autoarray%u", $autoarray_count++);
	$double_array{$region} = *tmp;
    }
    *array = $double_array{$region};
    $array{"$gid$name"} = "$name:*:$gid:$logins\n";
}
