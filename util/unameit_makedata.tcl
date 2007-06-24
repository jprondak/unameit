#! /bin/sh
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
# $Id: unameit_makedata.tcl,v 1.5.10.1 1997/08/28 18:29:44 viktor Exp $
#

# Create a data directory using information from the configuration files.
# 
# Make the directory
# add a link to pull_main.tcl
# If schema.version does not exist
# untar the startup data and schema directories
# if no version file exists, create one for schema.version and data.version
#
# Start up TCL with this file as input. 
# TCL treats the following line as a continuation of this comment \
exec tcl -n $0 "$@"

package require Config
unameit_getconfig unameitConfig [file tail $argv0]

if {[set argv_len [llength $argv]] > 2} {
    error "Usage: $argv0 [demo]" 
}
if {$argv_len == 0} {
    set demo_mode 0
} else {
    set demo_mode 1
}

#
# Exit if the directory already exists
#
set datadir [file join [unameit_config_ne unameitConfig data] data]
if [file exists $datadir] {
    puts stderr "Warning: $datadir already exists!"
    puts stderr "Make sure it is not being used by another user."
} else {
    puts "Creating $datadir"
}

#
# Create the directory and cd to it.
#
file mkdir $datadir
cd $datadir

#
# Make a symbolic link to pull_main. Remove any previous link.
#
file delete pull_main.tcl
if {$demo_mode} {
    set pull_file demo_pull_main.tcl
} else {
    set pull_file pull_main.tcl
}
link -sym [unameit_filename UNAMEIT_BACKEND $pull_file] pull_main.tcl

#
# Unpack the starter schema and data dumps, then copy version files in.
#
foreach type [list schema data] {
    set vfile [unameit_filename UNAMEIT_BOOTLIB $type.version]
    set version [read_file -nonewline $vfile]
    if {[cequal $type data] && $demo_mode} {
	set fname demo_data.$version.tar.Z
    } else {
	set fname $type.$version.tar.Z
    }
    set tarfile [unameit_filename UNAMEIT_BOOTLIB $fname]
    exec zcat $tarfile | tar xf -
    if {! [file exists $type.version]} {
	file copy $vfile .
    }
}
