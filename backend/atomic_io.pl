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

package atomic_io;

require 'sys.ph';

$FH_index = 0;

sub main'atomic_open {
    local($file_name, $mode) = @_;
    local($FH) = "atomic_io'AFH".$FH_index++;
    local(@fcntl_buf,$ddev,$fdev,$dino,$fino,$dnlink,$fnlink,$junk);
    $file_name{$FH} = $file_name;
    $temp_name{$FH} = $file_name.".tmp";
    $file_mode{$FH} = $mode;
    while (1) {
	open($FH, ">>$temp_name{$FH}") ||
	    die "Cannot open $temp_name{$FH}\n";
	@fcntl_buf = (&F_WRLCK, 0, 0, 0, 0, 0);
	if (!fcntl($FH, &F_SETLK, pack("ssllss", @fcntl_buf))) {
	    next if ($! == &EINTR);
	    die "Setting file lock failed: $!\n";
	}
	($ddev,$dino,$junk,$dnlink) = eval "stat($FH)";
	($fdev,$fino,$junk,$fnlink) = lstat($temp_name{$FH});
	if (! -f _) {
	    die "$temp_name{$FH} is not a regular file\n";
	}
	if (!$dino) {
	    die "fstat failed: $!\n";
	}
	next if ($ddev != $fdev || $dino != $fino);
	if ($fnlink != 1) {
	    unlink($temp_name{$FH}) ||
		die "Cannot unlink $temp_name{$FH}: $!\n";
	    next;
	}
	last;
    } continue {
	close($FH);
    }
    seek($FH, 0, 0);
    eval "truncate($FH, 0);";
    syscall(&SYS_fchmod, fileno($FH), $mode|0200);
    return $FH;
}

sub main'atomic_print {
    local($FH) = shift(@_);
    print $FH "@_" || die "Write failed\n";
}

sub main'atomic_printf {
    local($FH) = shift(@_);
    local($printf_string) = shift(@_);
    printf ($FH $printf_string, @_) || die "Write failed\n";
}

sub main'atomic_abort {
    local($FH) = @_;

    if (!defined($file_name{$FH})) {
	die "File handle not not opened with atomic_open\n";
    }
    unlink "$file_name{$FH}.tmp";
    close($FH);
    delete $file_name{$FH};
    delete $file_mode{$FH};
}

sub main'atomic_close {
    local($FH) = @_;

    if (!defined($file_name{$FH})) {
	die "File handle not not opened with atomic_open\n";
    }
    local($dev,$ino) = lstat($file_name{$FH});

    if ($ino) {
	if (! -f _) {
	    die "Target file is not a regular file\n";
	}
    }
    &flush($FH) ||
	die "Could not flush buffers for $temp_name{$FH}\n";
    if (defined &SYS_fsync) {
	syscall(&SYS_fsync, fileno($FH)) &&
	    die "Cannot sync $FH: $!\n";
    } elsif (defined &SYS_fdsync) {
	syscall(&SYS_fdsync, fileno($FH), &O_SYNC) &&
	    die "Cannot sync $FH: $!\n";
    } else {
	die "Don't know how to fsync!\n";
    }
    if (!rename($temp_name{$FH}, $file_name{$FH})) {
	close($FH);
	die("rename($temp_name{$FH}, $file_name{$FH}): $!\n");
    }
    syscall(&SYS_fchmod, fileno($FH), $file_mode{$FH});
    close($FH);
    delete $file_name{$FH};
    delete $file_mode{$FH};
}

sub flush {
    local($old) = select(shift);
    $| = 1;
    print "";
    $| = 0;
    select($old);
}

1;
