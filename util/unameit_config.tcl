#!/bin/sh
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
# $Id: unameit_config.tcl,v 1.4 1997/03/24 23:09:14 ccpowell Exp $
#

# Print out configuration items.
# 
# start this as tcl \
exec tcl -n $0 "$@"

set usage {unameit_config application module param [param...]}

package require Config
set params [lassign $argv app module]
unameit_getconfig c $app

if {[llength $params] == 0} {
    puts stderr "usage: $usage"
    exit 1
}

foreach param $params {
    puts [unameit_config c $param $module $app]
}
