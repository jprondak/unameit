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

## Do shell locations first.
open(F, "<$shell_location") || die "Cannot open $shell_location\n";
while (<F>) {
    chop;
    ($owner,$shell_name,$path) = split;
    $file_data{$owner} .= "$shell_name $path\n";
}
close(F);
&dump_to_files("shell_location.region", *file_data);
undef %file_data;

open(F, "<$user_login_file") || die "Cannot open $user_login_file\n";
while (<F>) {
    chop;
    ($login,$scope,$owner,$password,$uid,$gid,$gecos,$shell,
     $mount_point,$map,$enabled,$remote_dir) = split(/:/,$_,13);
    &add_pw_entry($scope,$login,$password,$uid,$gid,$gecos,
		  $map,$remote_dir,$shell,$enabled);
}
close(F);
&dump_to_files_by_region("user_logins.region", *double_array, 1);
undef %double_array;
&clear_autoarray_vars;

open(F, "<$login_file") || die "Cannot open $login_file\n";
while (<F>) {
    chop;
    ($login,$owner,$password,$uid,$gid,$gecos,$dir,$shell) = split(/:/);
    &add_pw_entry($owner,$login,$password,$uid,$gid,$gecos,
		  "",$dir,$shell,1);
}
close(F);
&dump_to_files_by_region("logins.region", *double_array, 1);
undef %double_array;
&clear_autoarray_vars;

open(F, "<$os_login_file") || die "Cannot open $os_login_file\n";
while (<F>) {
    chop;
    ($name,$region,$rest) = split(/:/,$_,3);
    $data{$region} .= "$name:$rest\n";
}
close(F);
&dump_to_files("os_logins.region", *data);
undef %data;

open(F, "<$system_login_file") || die "Cannot open $system_login_file\n";
while (<F>) {
    chop;
    ($name,$region,$template,$password,$uid,$rest) = split(/:/,$_,6);
    if (! defined $double_array{$region}) {
	*tmp = sprintf("autoarray%s", $autoarray_count++);
	$double_array{$region} = *tmp;
    }
    *array = $double_array{$region};
    $array{"$uid$name"} = sprintf("%s:%s:%s:%s:%s\n", $name, $template,
				  $password, $uid, $rest);
}
close(F);
&dump_to_files_by_region("system_logins.region", *double_array, 1);

sub add_pw_entry {
    local($region,$login,$password,$uid,$gid,$gecos,$map,
	  $remote_dir,$shell,$enabled) = @_;
    local($dir);

    $dir = ($map eq "" ? $remote_dir : "\$$map");
    if (!$enabled) {
	$password = '*';
	$shell = '/bin/true';
	$dir = '/';
    }
    if (! defined $double_array{$region}) {
	*tmp = sprintf("autoarray%u", $autoarray_count++);
	$double_array{$region} = *tmp;
    }
    *array = $double_array{$region};
    $array{"$uid$login"} = sprintf("%s:%s:%u:%u:%s:%s:%s\n", $login,
		       $password, $uid, $gid, $gecos, $dir, $shell);
}
