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
# $Id: heap_to_dat.tcl,v 1.4 1997/03/18 23:50:15 ccpowell Exp $
#

#
# Copy .dat files into a checkpoint directory from a heap directory.
#
source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB dump_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]
source [unameit_filename UNAMEIT_LOADLIB networks.tcl]

if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {c	LoadOptions(CheckpointDir)	$optarg} 
    check_options LoadOptions \
	    d DataDir \
	    c CheckpointDir
    check_files LoadOptions \
	    d DataDir \
	    c CheckpointDir
} problem ]} {
    puts $problem
    puts "Usage: unameit_load heap_to_dat \n\
	-d data 	name of directory made by unameit_load copy_checkpoint \n\
	-c checkpoint	unameit checkpoint directory"
    exit 1
}

oid_heap_output_dat $LoadOptions(CheckpointDir) $LoadOptions(DataDir)

