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
# $Id: unameit_addprincs.tcl,v 1.7.8.1 1997/08/28 18:29:43 viktor Exp $
#

# Add the principals used by unameit into the kerberos database.
# This should be run on the host which will use the keytab.
# Flags are passed to kadmin for use in authentication.
#
# V5 principals are added with random keys, and entries are extracted
# into the configured keytab file.
#
# Start up TCL with this file as input. 
# TCL treats the following line as a continuation of this comment \
exec tcl -n $0 "$@"

package require Config

###########################################################################
# 
# Get a parameter from the configuration
#
proc gcv {param app} {
    global unameitConfig
    unameit_config_ne unameitConfig $param ukrbv $app
}

###########################################################################
# 
# Print out message until a blank line. Kadmin finishes with a
# blank line and a beep and a warning about the credential cache which
# may prove alarming to inexperienced users.
proc put_msg {msgv} {
    upvar 1 $msgv msg
    foreach line [split $msg "\n"] {
	if {[cequal "" [string trim $line]]} {
	    return
	}
	puts $line
    }
}

#
###########################################################################
# 
# Add the principals to the database. kadmin returns a bad status,
# so we ignore it.
#
proc addprincs {ccache} {
    foreach utility [list upull unameit] {
	set princ "[gcv service $utility]/[gcv client_instance $utility]"
	set keytab [gcv keytab $utility]
	catch {exec kadmin -c $ccache -q "addprinc -randkey $princ"} msg
	put_msg msg
	catch {exec kadmin -c $ccache -q "ktadd -k $keytab $princ"} msg
	put_msg msg
    }
}

###########################################################################
# 
# Main
#

unameit_getconfig unameitConfig [file tail $argv0]

#
# Kinit to a temporary file
#
set admin [lindex $argv 0]
if {[cequal "" $admin]} {
    error "name of admin principal must be supplied"
}

set ccache /tmp/unameit_cc_[id process]
exec kinit -c $ccache -S kadmin/admin $admin >@stdout 2>@stderr <@stdin 

#
# Add the principals and extract the keys.
#
if {[catch {addprincs $ccache} msg]} {
    puts "Error! $msg"
}

#
# Destroy the temporary credential cache.
#
exec kdestroy -c $ccache
