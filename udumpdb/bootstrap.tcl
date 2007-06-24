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
# Client boostrap code
#

proc unameit_start {} {
    global argv0 unameitPriv 
    package require Config
    package require Error

    set command [file tail $argv0]
    unameit_getconfig unameitPriv $command
    set service [unameit_config unameitPriv service]
    # Coerce server auth parameters == client auth paramers,  since
    # we always talk to *local* server.
    set authType [unameit_config unameitPriv authentication]
    set unameitPriv(server_instance)\
	[unameit_config unameitPriv client_instance $authType]
    set unameitPriv(server_realm)\
	[unameit_config unameitPriv client_realm $authType]

    #
    # Always request a database dump.
    #
    set script "unameit_dump\n"
    #
    # Maybe request a shutdown.
    #
    if {[string match *shutdown $command]} {
	set halt 1
	append script "unameit_shutdown\n"
    } else {
	set halt 0
    }

    if {[catch {
		unameit_connect localhost $service
		unameit_authorize_login unameitPriv
		unameit_send $script
	    } result]} {
	global errorCode errorInfo
	if {$halt} {
	    lassign $errorCode e1 e2 e3
	    switch -- $e1.$e2.$e3 UNAMEIT.CONN.EAGAIN - UNAMEIT.CONN.EIO return
	}
	unameit_error_get_text result $errorCode
	puts stderr $result
	exit 1
    }
}
