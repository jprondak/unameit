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
# $Id: dat_to_heap.tcl,v 1.5.12.1 1997/08/28 18:28:59 viktor Exp $
#

#
# Copy .dat files from a checkpoint directory into a heap directory.
#
source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB dump_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} 
    check_options LoadOptions \
	    d DataDir 
} problem ]} {
    puts $problem
    puts "Usage: unameit_load copy_checkpoint\n\
	-d data 	name of directory to create"
    exit 1
}
	
set ddir [file join [unameit_config unameitPriv data] data]
set verfile [file join $ddir data.version]
set version [string trim [read_file $verfile]]
set dirname [file join $ddir data.$version]

proc dirs_same {dirold dirnew} {
    if {![file isdirectory $dirnew]} {return 0}
    set new [file join $dirnew test.tmp]
    set old [file join $dirold test.tmp]
    close [open $new w]
    set same [expr {
	[file isfile $old] && [file mtime $old] == [file mtime $new]
    }]
    file delete -force -- $new
    return $same
}

#
# Make sure we are not about to clobber the server's data directory.
#
if {[dirs_same $ddir $LoadOptions(DataDir)]} {
    error "Load data directory is same as server data directory"
}

make_directory $LoadOptions(DataDir)
oid_heap_input_dat $dirname $LoadOptions(DataDir)
