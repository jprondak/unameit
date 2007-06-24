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

# ESM awk script to replace multi.awk script on Solaris.
{
  ip = $1
  canon = $2
  if (canon2aliases[canon] == "") {
    ## Host definition line found.
    ips_seen[ip] = 1
    if (NF == 5) {
      # E.g., 192.9.200.1 disneyland disneyland.esm.com disneyland-le0
      # 	disneyland-le0.esm.com
      canon2aliases[canon] = " " canon " " $3 " "
      canon2ips[canon] = ip
      canonline[canon] = $2 " " $3

      canon2aliases[$4] = " " $4 " " $5 " "
      canon2ips[$4] = ip
      canonline[$4] = $3 " " $4 " " $5 " " $6
    } else if (NF == 7) {
      # E.g., 192.9.200.1 disneyland disneyland.west.esm.com disneyland.esm.com
      #    disneyland-le0 disneyland-le0.west.esm.com disneyland-le0.esm.com
      canon2aliases[canon] = " " canon " " $3 " " $4 " "
      canon2ips[canon] = ip
      canonline[canon] = $2 " " $3 " " $4

      canon2aliases[$5] = " " $5 " " $6 " " $7 " "
      canon2ips[$5] = ip
      canonline[$5] = $2 " " $3 " " $4 " " $5 " " $6 " " $7
    } else {
      # E.g., 127.0.0.1 nullhost
      #  or
      # 192.9.200.1 disneyland disneyland.west.esm.com disneyland.esm.com
      #  etc.
      canon2ips[canon] = ip
      canon2aliases[canon] = " "
      canonline[canon] = canon
      for (i = 2; i <= NF; i++) {
	# The following search skips
	# 127.0.0.1 localhost localhost
	if (index(canon2aliases[canon], " " $i " ")) {
	  continue
	}
	canon2aliases[canon] = canon2aliases[canon] $i " "
	if (i != 2) {
	  canonline[canon] = canonline[canon] " " $i
        }
      }
    }
  } else if (ips_seen[ip] == 1) {
    ## Host alias or server alias
    for (i = 3; i <= NF; i++) {
      canon2aliases[canon] = canon2aliases[canon] $i " "
    }
  } else if (NF == 2 || canon2aliases[$3] != "") {
    ## Secondary IP address
    next
  } else {
    ## Secondary interface.
    canon2ips[canon] = canon2ips[canon] "," ip
    canon2ips[$3] = ip
    canonline[$3] = canon
    canon2aliases[$3] = " "
    for (i = 3; i <= NF; i++) {
      canon2aliases[$3] = canon2aliases[$3] $i " "
      canonline[$3] = canonline[$3] " " $i
    }
  }
}
END {
  ## Output each host line
  for (canon in canon2aliases) {
    ip_list = canon2ips[canon]
    if (index(ip_list,",")) {
      multi_homed = 1
      split(ip_list,ips,",")
      first_ip = ips[1]
    } else {
      multi_homed = 0
      first_ip = ip_list
    }

    cline = canonline[canon]

    len = split(canon2aliases[canon],foo)
    for (i in foo) {
      alias=foo[i]
      if (multi_homed && alias == canon) {
	printf("YP_MULTI_%s\t%s\t%s\n", alias, ip_list, canon)
      } else {
        printf("%s\t%s\t%s %s\n", alias, first_ip, cline, alias)
      }
    }
  }
}
