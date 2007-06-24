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

# This file isn't run directly. It is sourced by other bash scripts.

# Set the unameit_dir variable before calling this routine. It is needed
# for the error message. Also, the "tcl", "krb5" and "unisqlx" variables
# should be set.
check_parts_integrity()
{
    for part in tcl krb5 unisqlx; do
        # Unfortunately we don't have version 2.0 of bash or we could just
        # say ${!part}. Version 2.0 has indirection built in.
        dir=/opt/$(eval echo \$$part)
        if [ ! -d $dir/. ]; then
	    ## Just continue if UniSQL/X doesn't exist. Client only
	    ## support such as SunOS 4.X doesn't have this directory.
	    [ $part = unisqlx ] && continue
	    echo "Bad parts list $unameit_dir/parts_list. $dir doesn't exist" \
	     1>&2
	    exit 1
        fi
    done    
}
