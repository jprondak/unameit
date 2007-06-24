#! /opt/bin/tclx
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
# $Id: atomic.tcl,v 1.3 1996/11/12 01:07:17 viktor Exp $
#

#
# Routines for atomic file update
#
# NOTE: need tclX
#
proc atomic_complain_tmpfs_bug {} {
    catch {
	puts stderr "File locking appears broken on your system"
	puts stderr "\tCould be SunOS.4.1.X tmpfs bug"
    }
}
#
# Carefully open a working file
#
proc atomic_open {path mode {bakext {}}} {
    global atomicPriv errorCode
    while 1 {
	set fh [open $path.tmp {WRONLY CREAT} [expr 0200|$mode]]
	if {[catch {flock -write -nowait $fh} gotit] != 0} {
	    set ecode $errorCode
	    if {[string compare [lindex $ecode 0] POSIX] == 0} {
		switch -exact [lindex $ecode 1] {
		    EINTR {
			catch {close $fh}
			continue
		    }
		    EINVAL {
			catch {close $fh}
			atomic_complain_tmpfs_bug
			return -code error -errorcode $ecode \
			    "flock($path.tmp): $gotit"
		    }
		    default {
			catch {close $fh}
			return -code error -errorcode $ecode \
			    "flock($path.tmp): $gotit"
		    }
		}
	    } else {
		catch {close $fh}
		return -code error -errorcode $ecode \
		    "flock($path.tmp): $gotit"
	    }
	}
	if {$gotit != 1} {
	    catch {close $fh}
	    return -code error "flock($path.tmp): File busy"
	}
	#
	# Get file handle info
	#
	if {[catch {fstat $fh stat fh_stat} err] != 0} {
	    set ecode $errorCode
	    catch {close $fh}
	    return -code error -errorcode $ecode \
		"fstat($fh): $path: $err"
	}
	#
	# Make sure our file handle is for a regular file
	#
	switch -- $fh_stat(type) file {} default {
	    catch {close $fh}
	    error "$path.tmp($fh_stat(type)): Is not a regular file"
	}
	#
	# If destination exists,  make sure it is a regular file or symlink
	#
	if {[catch {file lstat $path path_stat}] == 0} {
	    switch -- $fh_stat(type) link - file {} default {
		catch {close $fh}
		error "${path}($path_stat(type)): Is not a regular file"
	    }
	}
	#
	# Make sure tmp file still exists
	#
	if {[catch {file lstat $path.tmp tmp_stat}] != 0} {
	    catch {close $fh}
	    continue
	}
	#
	# Make sure tmp file is a regular file.
	#
	if {[string compare $tmp_stat(type) file] != 0} {
	    catch {close $fh}
	    error "$path.tmp($tmp_stat(type)): Is not a regular file"
	}
	#
	# Make sure our lock is still the temp file
	#
	if {$fh_stat(ino) != $tmp_stat(ino) ||
	    $fh_stat(dev) != $tmp_stat(dev)} {
	    catch {close $fh}
	    continue
	}
	#
	# Just in case it is linked to the final file
	#
	if {$tmp_stat(nlink) > 1} {
	    file delete -- $path.tmp
	    catch {close $fh}
	    continue
	}
	break
    }
    if {[catch {ftruncate -fileid $fh 0} err] == 1} {
	set ecode $errorCode
	catch {close $fh}
	return -code error -errorcode $ecode "ftruncate($path.tmp, 0): $err"
    }
    keylset atomicPriv($fh) path $path
    keylset atomicPriv($fh) mode $mode
    keylset atomicPriv($fh) bakext $bakext
    keylset atomicPriv($fh) ino $fh_stat(ino)
    keylset atomicPriv($fh) dev $fh_stat(dev)
    return $fh
}
#
# Commit the working file
#
proc atomic_close {fh} {
    global atomicPriv errorCode
    #
    # Get file handle info
    #
    if {[catch {fstat $fh stat fh_stat} err] != 0} {
	set ecode $errorCode
	catch {close $fh}
	return -code error -errorcode $ecode "fstat($fh): $err"
    }
    #
    if {![info exists atomicPriv($fh)]} {
	catch {close $fh}
	return -code error \
	    "File handle '$fh' not opened with atomic_open"
    }
    set path [keylget atomicPriv($fh) path]
    set mode [keylget atomicPriv($fh) mode]
    set bakext [keylget atomicPriv($fh) bakext]
    set ino [keylget atomicPriv($fh) ino]
    set dev [keylget atomicPriv($fh) dev]
    if {$ino != $fh_stat(ino) || $dev != $fh_stat(dev)} {
	catch {close $fh}
	return -code error \
	    "File handle '$fh' not opened with atomic_open"
    }
    if {[catch {file lstat $path path_stat}] == 0} {
	switch -- $path_stat(type) link - file {} default {
	    atomic_abort $fh
	    error "${path}($path_stat(type)): Is not a regular file"
	}
	if {[string compare $bakext ""] != 0} {
	    if {[catch {file lstat $path.$bakext bak_stat}] == 0} {
		if {[string compare $bak_stat(type) file] != 0} {
		    atomic_abort $fh
		    error\
			"$path.$bakext($bak_stat(type)): Is not a regular file"
		}
	    }
	    file delete -- $path.$bakext
	    if {[catch {link $path $path.$bakext} err] != 0} {
		set ecode $errorCode
		atomic_abort $fh
		return -code error -errorcode $ecode \
		    "link($path.$bakext,$path): $err"
	    }
	}
    }
    if {[catch {flush $fh} err] != 0} {
	set ecode $errorCode
	atomic_abort $fh
	return -code error -errorcode $ecode \
	    "flush: $err: $fh($path.tmp)"
    }
    sync $fh
    unset atomicPriv($fh)
    #
    # Can't turn off write bit until we rename the file
    # Close *after* renaming to avoid race condition
    #
    set code [catch {
	file rename -force -- $path.tmp $path
	chmod -fileid $mode $fh
	close $fh
    } err]
    if {$code != 0} {
	return -code $code -errorcode $errorCode "$path: $err"
    }
    return
}
#
# Abort the working file
#
proc atomic_abort {fh} {
    global atomicPriv errorCode
    #
    # Get file handle info
    #
    fstat $fh stat fh_stat
    if {![info exists atomicPriv($fh)]} {
	catch {close $fh}
	return -code error \
	    "File handle '$fh' not opened with atomic_open"
    }
    set path [keylget atomicPriv($fh) path]
    set ino [keylget atomicPriv($fh) ino]
    set dev [keylget atomicPriv($fh) dev]
    #
    unset atomicPriv($fh)
    #
    if {$ino != $fh_stat(ino) || $dev != $fh_stat(dev)} {
	catch {close $fh}
	return -code error \
	    "File handle '$fh' not opened with atomic_open"
    }
    #
    # Unlink before releasing the lock
    #
    file delete -- $path.tmp
    catch {close $fh}
    return
}
