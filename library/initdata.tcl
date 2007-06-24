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
# $Id: initdata.tcl,v 1.22.20.1 1997/09/19 18:38:07 viktor Exp $

#
# Retrieve data class uuids
#
foreach class [unameit_decode_items -result\
	[unameit_qbe -all unameit_data_class unameit_class_name]] {
    upvar 0 $class class_item
    set cuuid($class_item(unameit_class_name)) $class
}

#
# Create role objects
#
set classes(dba) {}
#
lappend classes(rootadmin) abi
lappend classes(rootadmin) machine
lappend classes(rootadmin) os
lappend classes(rootadmin) os_family
lappend classes(rootadmin) server_type
#
lappend classes(celladmin) organization
lappend classes(celladmin) cell
#
lappend classes(netadmin) ipv4_network
lappend classes(netadmin) hub
lappend classes(netadmin) terminal_server
lappend classes(netadmin) router
#
lappend classes(regionadmin) region
lappend classes(regionadmin) server_alias
#
lappend classes(hostadmin) host_alias
lappend classes(hostadmin) computer
lappend classes(hostadmin) host_principal
lappend classes(hostadmin) host_netgroup
#
lappend classes(loginadmin) user_principal
lappend classes(loginadmin) user_login
lappend classes(loginadmin) user_group
lappend classes(loginadmin) user_netgroup
#
lappend classes(lpadmin) bsd_printer
lappend classes(lpadmin) bsd_printer_type
lappend classes(lpadmin) bsd_printer_alias
#
lappend classes(mailadmin) mailing_list
#
lappend classes(nfsadmin) automount_map
lappend classes(nfsadmin) automount
#
lappend classes(pageradmin) paging_provider
lappend classes(pageradmin) pager
#
lappend classes(personadmin) person
#
lappend classes(sysadmin) application_group
lappend classes(sysadmin) application_login
lappend classes(sysadmin) os_group
lappend classes(sysadmin) os_login
lappend classes(sysadmin) principal
lappend classes(sysadmin) shell_location
lappend classes(sysadmin) sybase_interface
lappend classes(sysadmin) system_group
lappend classes(sysadmin) system_login
lappend classes(sysadmin) tcp_service
lappend classes(sysadmin) udp_service

#
# Now build the role hierarchy
#
foreach {role owner} {
	dba ""
	rootadmin dba
	celladmin dba
	netadmin celladmin
	regionadmin celladmin
	sysadmin regionadmin
	hostadmin sysadmin
	loginadmin sysadmin
	mailadmin sysadmin
	nfsadmin sysadmin
	pageradmin sysadmin
	personadmin sysadmin
	lpadmin sysadmin} {
    #
    if {![cequal $owner ""]} {set owner $role_uuid($owner)}
    set role_uuid($role) [set uuid [uuidgen]]
    set cmd [list unameit_create role $uuid role_name $role owner $owner]
    #
    set clist {}
    foreach cname $classes($role) {
	lappend clist $cuuid($cname)
    }
    foreach op {create update delete} {
	lappend cmd unameit_role_${op}_classes $clist
    }
    eval $cmd
}

#
# Create root cell
#
unameit_create cell [set root_cell [uuidgen]] name .

#
# Create standard `protected' IP objects
#
unameit_create ipv4_network [set universe [uuidgen]]\
    name universe\
    owner $root_cell\
    ipv4_address 00000000\
    ipv4_last_address ffffffff\
    ipv4_mask {}\
    ipv4_mask_type Variable
#
unameit_create ipv4_network [set loopback [uuidgen]]\
    name loopback\
    owner $root_cell\
    ipv4_address 7f000000\
    ipv4_last_address 7fffffff\
    ipv4_mask ff000000\
    ipv4_mask_type Fixed
#
unameit_create ipv4_network [set multicast [uuidgen]]\
    name multicast\
    owner $root_cell\
    ipv4_address e0000000\
    ipv4_last_address efffffff\
    ipv4_mask f0000000\
    ipv4_mask_type Fixed
#
unameit_create computer [set localhost [uuidgen]]\
    name localhost\
    owner $root_cell\
    os ""\
    machine ""\
    ifaddress ""\
    ifname ""\
    ipv4_address 7f000001\
    receives_mail No

#
# Sadly while the list will be protected,  it will be possible
# to add members.  Presumably the mailadmin for "." will not be so foolish.
#
unameit_create mailing_list [set nobody [uuidgen]]\
    name nobody owner $root_cell

#
# The root object of each class are automatically protected.
#
udb_set_root mailing_list $nobody
udb_set_root computer $localhost

#
# Protect Loopback and Multicast networks from further updates
#
unameit_protect $loopback $multicast

#
# Create top organization
#
unameit_create organization [set org [uuidgen]] name "Your Organization"

#
# Create cell
#
unameit_create cell [set cell [uuidgen]] name "your.com" cellorg $org

#
# Create standard server types.
#
unameit_create server_type [uuidgen]\
    name mailhost server_type_name mailhost

unameit_create server_type [uuidgen] \
    name nisserver server_type_name nisserver one_per_host Yes

unameit_create server_type [uuidgen] \
    name ns server_type_name dnsserver

unameit_create server_type [uuidgen] \
    name pullserver server_type_name pullserver

unameit_create server_type [uuidgen] \
    name pagerserver server_type_name pagerserver

unameit_create server_type [uuidgen] \
    name loghost server_type_name loghost

unameit_create server_type [uuidgen] \
    name www server_type_name webserver

#
# Create automount map for home directories
#
unameit_create automount_map [uuidgen] \
    name auto_home mount_point /home mount_opts -rw,hard,intr owner $cell

unameit_commit

unameit_dump
