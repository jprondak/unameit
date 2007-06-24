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

set root_oid(cell) oG.IIZ702R073kU.65b.VU
set root_oid(ipv4_network) oHvXD3702R073kU.65b.VU
set root_oid(role) o3btp3702R073kU.65b.VU
set unrestored(cell) cell.dat
set unrestored(computer) computer.dat
set unrestored(ipv4_network) ipv4_network.dat
set unrestored(role) role.dat
set unrestored(server_type) server_type.dat
set fields(cell) {name cellorg relname wildcard_mx owner modby mtran comment mtime}
set fields(computer) {name ifname os machine receives_mail owner modby mtran comment mtime ifaddress ipv4_network ipv4_address}
set fields(ipv4_network) {name owner ipv4_net_netof ipv4_net_start ipv4_net_end ipv4_net_bits ipv4_net_mask ipv4_net_type comment modby mtran mtime}
set fields(role) {role_name owner unameit_role_create_classes unameit_role_update_classes unameit_role_delete_classes modby mtran comment mtime}
set fields(server_type) {server_type_name name owner one_per_host modby mtran comment mtime}
set instances(cell) 1
set instances(computer) 1
set instances(ipv4_network) 6
set instances(role) 7
set instances(server_type) 9
set subclasses(abi) {}
set subclasses(abstract_computer) {computer server_alias}
set subclasses(abstract_host) {host_alias abstract_computer computer server_alias}
set subclasses(authorization) {}
set subclasses(cell) {}
set subclasses(computer) {}
set subclasses(host) {terminal_server computer hub router}
set subclasses(host_alias) {}
set subclasses(host_console) {}
set subclasses(host_or_region) {region host terminal_server computer hub router cell}
set subclasses(host_principal) {}
set subclasses(hub) {}
set subclasses(interface_or_host_or_region) {host_or_region region host terminal_server computer hub router cell ipv4_abstract_interface ipv4_interface}
set subclasses(ipv4_abstract_interface) {ipv4_interface host terminal_server computer hub router}
set subclasses(ipv4_dynamic_range) {}
set subclasses(ipv4_interface) {}
set subclasses(ipv4_network) {}
set subclasses(ipv4_node) {ipv4_secondary_address ipv4_abstract_interface ipv4_interface host terminal_server computer hub router}
set subclasses(ipv4_range) {ipv4_dynamic_range ipv4_static_range}
set subclasses(ipv4_secondary_address) {}
set subclasses(ipv4_static_range) {}
set subclasses(machine) {}
set subclasses(machine_spec) {machine abi}
set subclasses(named_item) {ipv4_network organization server_type interface_or_host_or_region host_or_region region host terminal_server computer hub router cell ipv4_abstract_interface ipv4_interface abstract_host host_alias abstract_computer server_alias}
set subclasses(organization) {}
set subclasses(os) {}
set subclasses(os_family) {}
set subclasses(os_spec) {os os_family}
set subclasses(os_specific) {}
set subclasses(principal) host_principal
set subclasses(region) cell
set subclasses(role) {}
set subclasses(router) {}
set subclasses(server_alias) {}
set subclasses(server_type) {}
set subclasses(terminal_server) {}
set subclasses(unix_pathname) {}
set oid2classname(ipv4_secondary_address) ipv4_secondary_address
set oid2classname(host) host
set oid2classname(computer) computer
set oid2classname(hub) hub
set oid2classname(terminal_server) terminal_server
set oid2classname(router) router
set oid2classname(host_console) host_console
set oid2classname(os_spec) os_spec
set oid2classname(os_family) os_family
set oid2classname(os) os
set oid2classname(os_specific) os_specific
set oid2classname(machine_spec) machine_spec
set oid2classname(abi) abi
set oid2classname(machine) machine
set oid2classname(server_type) server_type
set oid2classname(server_alias) server_alias
set oid2classname(named_item) named_item
set oid2classname(role) role
set oid2classname(interface_or_host_or_region) interface_or_host_or_region
set oid2classname(abstract_host) abstract_host
set oid2classname(abstract_computer) abstract_computer
set oid2classname(host_or_region) host_or_region
set oid2classname(host_alias) host_alias
set oid2classname(organization) organization
set oid2classname(region) region
set oid2classname(cell) cell
set oid2classname(ipv4_network) ipv4_network
set oid2classname(ipv4_abstract_interface) ipv4_abstract_interface
set oid2classname(ipv4_interface) ipv4_interface
set oid2classname(unix_pathname) unix_pathname
set oid2classname(principal) principal
set oid2classname(host_principal) host_principal
set oid2classname(authorization) authorization
set oid2classname(ipv4_node) ipv4_node
