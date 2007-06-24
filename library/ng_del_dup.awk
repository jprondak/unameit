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

# Eliminates duplicated host names in forward netgroup files.
/\([a-z0-9]/ {
  line = $1
  prev = ""
  for (i = 2; i <= NF; i++) {
    if (index($i,"(") && (("a" <= substr($i,2,1) && substr($i,2,1) <= "z") || ("0" <= substr($i,2,1) && substr($i,2,1) <= "9"))) {
      cur_host = substr($i,2,index($i,",")-2)
      if (index(cur_host,".") && !index(prev,".")) {
	short = substr(cur_host,1,index(cur_host,".")-1)
	if (short == prev) {
	  continue
	} else {
	  line = line " " $i
	}
      } else if (index(prev,".") && !index(cur_host,".")) {
	short = substr(prev,1,index(prev,".")-1)
	if (short == cur_host) {
	  continue
	} else {
	  line = line " " $i
	}
      } else {
	line = line " " $i
      }
      prev = cur_host
    } else {
      line = line " " $i
      prev = ""
    }
  }
  print line
  next
}
{
   print
}
