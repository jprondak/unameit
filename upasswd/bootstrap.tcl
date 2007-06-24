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
# $Id: bootstrap.tcl,v 1.9.8.1 1997/08/28 18:29:33 viktor Exp $
#

proc unameit_connect_proc {server service login passwd} {
    global errorCode unameitPriv 
    #
    set retries [unameit_config unameitPriv retries]
    set backoff [unameit_config unameitPriv backoff]
    while 1 {
	set ok [catch {unameit_connect $server $service} err]
	if {$ok == 0} break
	lassign $errorCode e1 e2 e3
	switch -- $e1.$e2.$e3 UNAMEIT.CONN.EAGAIN {} default {
	    return -code error -errorcode $errorCode $err
	}
	if {$retries == 0} break
	puts "failed to connect to $server:$service; waiting..."
	sleep $backoff
	set backoff [expr $backoff * 2]
	incr retries -1
    }
    if {$ok != 0} {
	return -code error -errorcode $errorCode \
	    "$server:$service retry count exceeded"
    }
    unameit_authorize upasswd kinit $login $passwd
    unameit_send_auth upasswd
    unameit_authorize upasswd kdestroy
}

proc unameit_start {} {
    global argv0 unameitPriv 

    package require Config
    package require Error

    unameit_getconfig unameitPriv upasswd

    set server [unameit_config unameitPriv server_host]
    set service [unameit_config unameitPriv service]
    set command [file tail $argv0]

    #
    # Get login name for real uid.
    #
    if {[catch {id user} login]} {
	puts stderr \
	    [format "%s: uid %d not in password file" $command [id userid]]
	exit 1
    }
    puts stderr "Changing password file entry for $login"
    #
    # Get old password.
    #
    set oldpass [getpass "Old Password:"]
    #
    # Do we change the password or the shell?
    #
    switch -glob -- $command {
	*chsh {
	    set chsh 1
	    set cmd [list unameit_change_shell [unameit_new_shell]]
	}
	default {
	    set chsh 0
	    set cmd [list unameit_change_password [unameit_new_pass]]
	}
    }
    #
    # Try to change in UName*It
    #
    if {[catch {
	unameit_connect_proc $server $service $login $oldpass
	unameit_send $cmd
    } result]} {
	global errorCode
	unameit_error_get_text result $errorCode
	if {$chsh} {
	    puts stderr "UName*It shell not changed"
	} else {
	    puts stderr "UName*It password not changed"
	}
	puts stderr $result
	exit 1
    }
    if {$chsh} {
	puts "UName*It shell changed"
    } else {
	puts "UName*It password changed"
    }

    #
    # Try to change data in NIS
    # UName*It returns new value of password or shell
    #
    if {$chsh} {
	yp_change_shell $login $oldpass $result
	puts "NIS shell changed"
    } else {
	yp_change_passwd $login $oldpass $result
	puts "NIS password changed"
    }
}


proc unameit_new_shell {} {
    puts -nonewline "New Shell: "
    flush stdout
    if {[gets stdin shell] == -1} {
	puts stderr "Shell not changed"
	exit 1
    }
    set shell
}

proc unameit_new_pass {} {
    set retries 5
    set ok 0
    while {$retries} {
	set newpass [getpass "New Password:"]
	incr retries -1
	#
	# Insert quality checks here!  Don't pass password as argument
	# to processes,  since "ps" run by another user might reveal
	# the password.
	#
	set len [string length $newpass]
	if {$len >= 8} {
	    set ok 1
	    break
	}
	if {$len < 6} {
	    puts stderr "Password is too short"
	    continue
	}

	#
	# Allow mixed combinations of upper/lower case letters and digits
	# anything containing other chars
	#
	set types 0
	foreach char [split $newpass {}] {
	    if {[ctype lower $char]} {
		set types [expr $types | 1]
	    } elseif {[ctype upper $char]} {
		set types [expr $types | 2]
	    } elseif {[ctype digit $char]} {
		set types [expr $types | 4]
	    } else {
		set types [expr $types | 8]
	    }
	}
	if {$types & 1 && $types & ~1 ||
		$types & 2 && $types & ~2 ||
		$types & 4 && $types & ~4 ||
		$types & 8} {
	    set ok 1
	    break
	}
	puts stderr "Password has weak character mix"
	continue
    }
    if {$ok == 0} {
	puts stderr "Retry count exceeded"
	exit 1
    }
    #
    # Make sure the password is what the user really wanted
    #
    if {[string compare $newpass [getpass "Retype new password:"]] != 0} {
	puts stderr "Mismatch - password unchanged."
	exit 1
    }
    #
    # Crypt it with a random salt
    #
    set newpass [unameit_crypt $newpass]
}
