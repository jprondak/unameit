#
# Copyright (c) 1995, 1997 Enterprise Systems Management Corp.
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
# $Id: volinit.tcl,v 1.7.58.1 1997/10/04 23:12:29 viktor Exp $
#

set top_cell\
    [unameit_decode_items -result\
	[unameit_qbe cell [list name = $env(UNAMEIT_CELL)]]]

unameit_create os_family [set s41x [uuidgen]]\
    os_name SunOS os_release_name 4.1.X

unameit_create os [uuidgen]\
	os_name SunOS os_release_name 4.1.1 os_family $s41x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 4.1.2 os_family $s41x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 4.1.3 os_family $s41x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 4.1.3_U1 os_family $s41x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 4.1.4 os_family $s41x

unameit_create os_family [set s5x [uuidgen]]\
    os_name SunOS os_release_name 5.X

unameit_create os [uuidgen]\
	os_name SunOS os_release_name 5.0 os_family $s5x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 5.1 os_family $s5x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 5.2 os_family $s5x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 5.3 os_family $s5x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 5.4 os_family $s5x
unameit_create os [uuidgen]\
	os_name SunOS os_release_name 5.5 os_family $s5x

unameit_create abi [set sparc [uuidgen]] machine_name sparc
unameit_create machine [uuidgen] abi $sparc machine_name sun4
unameit_create machine [uuidgen] abi $sparc machine_name sun4c
unameit_create machine [uuidgen] abi $sparc machine_name sun4m
unameit_create machine [uuidgen] abi $sparc machine_name sun4d
unameit_create machine [uuidgen] abi $sparc machine_name sun4e
unameit_create machine [uuidgen] abi $sparc machine_name sun4u

unameit_create ipv4_network [uuidgen] \
    name acmenet \
    owner $top_cell \
    ipv4_net_start 128.112.0.0 \
    ipv4_net_bits 16 \
    ipv4_net_mask 255.255.255.0 \
    ipv4_net_type Fixed

unameit_commit
