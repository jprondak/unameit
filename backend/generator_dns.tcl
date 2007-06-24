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
# $Id: generator_dns.tcl,v 1.2.14.1 1997/08/28 18:25:28 viktor Exp $
#

uplevel #0 {set tcl_interactive [fstat stdout tty]}

global unameitConfig
set datadir [unameit_config unameitConfig data]
set DUMPDIR [file join $datadir data dump.$VERSION]
set GENDIR [file join $datadir data gen.$VERSION]

#
# Create the subdirectory
#
file mkdir $GENDIR

#
# These files are used by pull_main.tcl or upulld. If we copy them to 
# the gen directory then we don't need to copy the dump directories 
# from pull server to pull server.
#
foreach tuple {{server_aliases server_aliases} {networks dump_networks}\
        {canon_hosts canon_hosts} {secondary_ifs secondary_ifs}\
	{regions regions}} {
    lassign $tuple dump_name gen_name

    set dump_fd [open $DUMPDIR/$dump_name r]
    set gen_fd [atomic_open $GENDIR/$gen_name 0444]

    copyfile $dump_fd $gen_fd	;# TclX command

    close $dump_fd
    atomic_close $gen_fd
}

#
# Run the perl scripts
#
foreach program [list\
	[unameit_filename UNAMEIT_BACKEND gen_inaddr.pl]\
	[unameit_filename UNAMEIT_BACKEND gen_named.pl]] {
    set short_program [file tail $program]

    ## Skip known programs. By processing everything else, we allow users
    ## to add their own scripts.
    switch $short_program {
	atomic_io.pl -
	libtools.pl -
	data_files.pl -
	getopts.pl {
	    continue
	}
    }

    __diagnostic [unameit_time {
	__diagnostic -nonewline "$short_program..."
	if {[catch {
		exec [unameit_filename UNAMEIT_BACKEND perl] \
			-I[unameit_filename UNAMEIT_BACKEND] $program \
			-i $DUMPDIR -o $GENDIR
		} result] != 0} {
	    error "Generator script $program failed: $result"
	}
    }]
}

#
# Create an empty path_list file
#
atomic_close [atomic_open $GENDIR/path_list 0444]
