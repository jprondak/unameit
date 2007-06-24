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

set fields(abi) {machine_name owner modby mtran comment mtime}
set instances(abi) 5
set unrestored(abi) abi.dat
set fields(application_group) {name owner modby mtran comment mtime gid}
set instances(application_group) 3
set unrestored(application_group) application_group.dat
set fields(application_login) {name unix_pathname primary_group password gecos uid shell owner modby mtran comment mtime}
set instances(application_login) 1
set unrestored(application_login) application_login.dat
set fields(authorization) {principal role owner modby mtran comment mtime}
set instances(authorization) 25
set unrestored(authorization) authorization.dat
set fields(automount) {name unix_pathname owner modby mtran comment mtime auto_map nfs_server}
set instances(automount) 7
set unrestored(automount) automount.dat
set fields(automount_map) {mount_point mount_opts name owner modby mtran comment mtime}
set instances(automount_map) 14
set unrestored(automount_map) automount_map.dat
set fields(bsd_printer) {name bsd_printer_rm bsd_printer_rp bsd_printcap_sd owner modby mtran comment mtime}
set instances(bsd_printer) 3
set unrestored(bsd_printer) bsd_printer.dat
set fields(bsd_printer_alias) {name bsd_printer owner modby mtran comment mtime}
set instances(bsd_printer_alias) 1
set unrestored(bsd_printer_alias) bsd_printer_alias.dat
set fields(bsd_printer_type) {bsd_printcap1 bsd_printcap2 bsd_printcap3 name bsd_printcap_tc bsd_printcap_sd owner modby mtran comment mtime}
set instances(bsd_printer_type) 2
set unrestored(bsd_printer_type) bsd_printer_type.dat
set fields(cell) {name cellorg relname wildcard_mx owner modby mtran comment mtime}
set instances(cell) 11
set unrestored(cell) cell.dat
set fields(computer) {name ifname os machine receives_mail owner modby mtran comment mtime ifaddress ipv4_network ipv4_address}
set instances(computer) 53
set unrestored(computer) computer.dat
set fields(external_mail_address) {name owner modby mtran comment mtime}
set instances(external_mail_address) 3
set unrestored(external_mail_address) external_mail_address.dat
set fields(file_mailbox) {name unix_pathname mailbox_route preferred_mailbox owner modby mtran comment mtime}
set instances(file_mailbox) 3
set unrestored(file_mailbox) file_mailbox.dat
set fields(group_member) {gm_login owner modby mtran comment mtime}
set instances(group_member) 7
set unrestored(group_member) group_member.dat
set fields(host_alias) {name owner modby mtran comment mtime}
set instances(host_alias) 3
set unrestored(host_alias) host_alias.dat
set fields(host_console) {line console_of_host owner modby mtran comment mtime}
set instances(host_console) 1
set unrestored(host_console) host_console.dat
set fields(host_principal) {phost pname pinst prealm owner modby mtran comment mtime}
set instances(host_principal) 18
set unrestored(host_principal) host_principal.dat
set fields(hub) {name ifname owner modby mtran comment mtime ifaddress ipv4_network ipv4_address}
set instances(hub) 1
set unrestored(hub) hub.dat
set fields(ipv4_interface) {owner ifname ifaddress modby mtran comment mtime name ipv4_network ipv4_address}
set instances(ipv4_interface) 2
set unrestored(ipv4_interface) ipv4_interface.dat
set fields(ipv4_network) {name owner ipv4_net_netof ipv4_net_start ipv4_net_end ipv4_net_bits ipv4_net_mask ipv4_net_type comment modby mtran mtime}
set instances(ipv4_network) 52
set unrestored(ipv4_network) ipv4_network.dat
set fields(ipv4_secondary_address) {owner ipv4_network ipv4_address modby mtran comment mtime}
set instances(ipv4_secondary_address) 1
set unrestored(ipv4_secondary_address) ipv4_secondary_address.dat
set fields(machine) {abi machine_name owner modby mtran comment mtime}
set instances(machine) 7
set unrestored(machine) machine.dat
set fields(mailbox_alias) {name owner modby mtran comment mtime}
set instances(mailbox_alias) 4
set unrestored(mailbox_alias) mailbox_alias.dat
set fields(mailing_list) {name owner modby mtran comment mtime}
set instances(mailing_list) 12
set unrestored(mailing_list) mailing_list.dat
set fields(mailing_list_member) {ml_member owner modby mtran comment mtime}
set instances(mailing_list_member) 58
set unrestored(mailing_list_member) mailing_list_member.dat
set fields(netgroup) {comment modby name mtran owner mtime}
set instances(netgroup) 18
set unrestored(netgroup) netgroup.dat
set fields(netgroup_member) {comment ng_host modby mtran owner ng_ng mtime ng_user}
set instances(netgroup_member) 43
set unrestored(netgroup_member) netgroup_member.dat
set fields(organization) {name owner modby mtran comment mtime}
set instances(organization) 3
set unrestored(organization) organization.dat
set fields(os) {os_family os_name os_release_name owner modby mtran comment mtime}
set instances(os) 11
set unrestored(os) os.dat
set fields(os_family) {os_release_name os_name owner modby mtran comment mtime}
set instances(os_family) 7
set unrestored(os_family) os_family.dat
set fields(os_group) {gid base_group os_spec owner modby mtran comment mtime name}
set instances(os_group) 26
set unrestored(os_group) os_group.dat
set fields(os_login) {uid password unix_pathname base_login primary_group os_spec gecos shell owner modby mtran comment mtime name}
set instances(os_login) 9
set unrestored(os_login) os_login.dat
set fields(pager) {pager_pin pager_phone pager_provider pager_person owner modby mtran comment mtime}
set instances(pager) 2
set unrestored(pager) pager.dat
set fields(paging_provider) {provider_support_number provider_data_number provider_operator_number name owner modby mtran comment mtime}
set instances(paging_provider) 2
set unrestored(paging_provider) paging_provider.dat
set fields(person) {fullname person_phone name owner person_expiration modby mtran comment mtime mailbox_route preferred_mailbox}
set instances(person) 73
set unrestored(person) person.dat
set fields(principal) {pname pinst prealm owner modby mtran comment mtime}
set instances(principal) 2
set unrestored(principal) principal.dat
set fields(program_mailbox) {unix_pathname name mailbox_route preferred_mailbox owner modby mtran comment mtime}
set instances(program_mailbox) 1
set unrestored(program_mailbox) program_mailbox.dat
set fields(region) {relname name owner wildcard_mx modby mtran comment mtime}
set instances(region) 8
set unrestored(region) region.dat
set fields(role) {role_name owner unameit_role_create_classes unameit_role_update_classes unameit_role_delete_classes modby mtran comment mtime}
set instances(role) 39
set unrestored(role) role.dat
set fields(router) {name ifname owner modby mtran comment mtime ifaddress ipv4_network ipv4_address}
set instances(router) 2
set unrestored(router) router.dat
set fields(secondary_automount) {unix_pathname owner nfs_server modby mtran comment mtime}
set instances(secondary_automount) 3
set unrestored(secondary_automount) secondary_automount.dat
set fields(server_alias) {server_type primary_server secondary_servers server_type_one_per_host owner modby mtran comment mtime name}
set instances(server_alias) 28
set unrestored(server_alias) server_alias.dat
set fields(server_type) {server_type_name name owner one_per_host modby mtran comment mtime}
set instances(server_type) 8
set unrestored(server_type) server_type.dat
set fields(shell_location) {shell_path owner shell_name modby mtran comment mtime}
set instances(shell_location) 1
set unrestored(shell_location) shell_location.dat
set fields(sybase_interface) {sybase_name sybase_host owner tcp_port modby mtran comment mtime}
set instances(sybase_interface) 2
set unrestored(sybase_interface) sybase_interface.dat
set fields(system_group) {gid name template_group owner modby mtran comment mtime}
set instances(system_group) 27
set unrestored(system_group) system_group.dat
set fields(system_login) {uid name unix_pathname template_login password gecos primary_group shell owner modby mtran comment mtime}
set instances(system_login) 9
set unrestored(system_login) system_login.dat
set fields(tcp_service) {owner tcp_port ip_service_name modby mtran comment mtime}
set instances(tcp_service) 5
set unrestored(tcp_service) tcp_service.dat
set fields(tcp_service_alias) {owner ip_service_name modby mtran comment mtime}
set instances(tcp_service_alias) 3
set unrestored(tcp_service_alias) tcp_service_alias.dat
set fields(terminal_server) {lines base_tcp_port name ifname owner modby mtran comment mtime ifaddress ipv4_network ipv4_address}
set instances(terminal_server) 8
set unrestored(terminal_server) terminal_server.dat
set fields(udp_service) {owner udp_port modby mtran comment mtime ip_service_name}
set instances(udp_service) 5
set unrestored(udp_service) udp_service.dat
set fields(udp_service_alias) {owner ip_service_name modby mtran comment mtime}
set instances(udp_service_alias) 3
set unrestored(udp_service_alias) udp_service_alias.dat
set fields(user_group) {name owner modby mtran comment mtime gid}
set instances(user_group) 23
set unrestored(user_group) user_group.dat
set fields(user_login) {name unix_pathname person primary_group auto_map nfs_server password gecos uid shell owner modby mtran comment mtime mailbox_route preferred_mailbox}
set instances(user_login) 41
set unrestored(user_login) user_login.dat
set fields(user_principal) {plogin pname pinst prealm owner modby mtran comment mtime}
set instances(user_principal) 17
set unrestored(user_principal) user_principal.dat
set oid2classname(abi) abi
set oid2classname(abstract_automount) abstract_automount
set oid2classname(abstract_computer) abstract_computer
set oid2classname(abstract_host) abstract_host
set oid2classname(abstract_mailing_list) abstract_mailing_list
set oid2classname(aliasable_mailbox) aliasable_mailbox
set oid2classname(application_group) application_group
set oid2classname(application_login) application_login
set oid2classname(authorization) authorization
set oid2classname(automount) automount
set oid2classname(automount_map) automount_map
set oid2classname(bsd_printcap) bsd_printcap
set oid2classname(bsd_printer) bsd_printer
set oid2classname(bsd_printer_alias) bsd_printer_alias
set oid2classname(bsd_printer_type) bsd_printer_type
set oid2classname(cell) cell
set oid2classname(computer) computer
set oid2classname(external_mail_address) external_mail_address
set oid2classname(file_mailbox) file_mailbox
set oid2classname(generic_group) generic_group
set oid2classname(generic_login) generic_login
set oid2classname(group) group
set oid2classname(group_member) group_member
set oid2classname(host) host
set oid2classname(host_alias) host_alias
set oid2classname(host_console) host_console
set oid2classname(host_netgroup_member_object) host_netgroup_member_object
set oid2classname(host_or_region) host_or_region
set oid2classname(host_principal) host_principal
set oid2classname(hub) hub
set oid2classname(interface_or_host_or_region) interface_or_host_or_region
set oid2classname(ip_service) ip_service
set oid2classname(ipv4_abstract_interface) ipv4_abstract_interface
set oid2classname(ipv4_interface) ipv4_interface
set oid2classname(ipv4_network) ipv4_network
set oid2classname(ipv4_node) ipv4_node
set oid2classname(ipv4_secondary_address) ipv4_secondary_address
set oid2classname(login) login
set oid2classname(machine) machine
set oid2classname(machine_spec) machine_spec
set oid2classname(mail_route) mail_route
set oid2classname(mailbox) mailbox
set oid2classname(mailbox_alias) mailbox_alias
set oid2classname(mailing_list) mailing_list
set oid2classname(mailing_list_member) mailing_list_member
set oid2classname(mailing_list_member_object) mailing_list_member_object
set oid2classname(named_item) named_item
set oid2classname(netgroup) netgroup
set oid2classname(netgroup_member) netgroup_member
set oid2classname(nfs_volume) nfs_volume
set oid2classname(organization) organization
set oid2classname(os) os
set oid2classname(os_family) os_family
set oid2classname(os_group) os_group
set oid2classname(os_login) os_login
set oid2classname(os_spec) os_spec
set oid2classname(os_specific) os_specific
set oid2classname(pager) pager
set oid2classname(paging_provider) paging_provider
set oid2classname(person) person
set oid2classname(principal) principal
set oid2classname(printer) printer
set oid2classname(program_mailbox) program_mailbox
set oid2classname(region) region
set oid2classname(role) role
set oid2classname(router) router
set oid2classname(secondary_automount) secondary_automount
set oid2classname(server_alias) server_alias
set oid2classname(server_type) server_type
set oid2classname(shell_location) shell_location
set oid2classname(sybase_interface) sybase_interface
set oid2classname(system_group) system_group
set oid2classname(system_login) system_login
set oid2classname(tcp_port) tcp_port
set oid2classname(tcp_service) tcp_service
set oid2classname(tcp_service_alias) tcp_service_alias
set oid2classname(terminal_server) terminal_server
set oid2classname(udp_port) udp_port
set oid2classname(udp_service) udp_service
set oid2classname(udp_service_alias) udp_service_alias
set oid2classname(unix_pathname) unix_pathname
set oid2classname(user_group) user_group
set oid2classname(user_login) user_login
set oid2classname(user_netgroup_member_object) user_netgroup_member_object
set oid2classname(user_principal) user_principal
set root_oid(cell) oG.IIZ702R073kU.65b.VU
set root_oid(ipv4_network) oHvXD3702R073kU.65b.VU
set root_oid(role) o3btp3702R073kU.65b.VU
set subclasses(host_or_region) {region host terminal_server computer hub router cell}
set subclasses(program_mailbox) {}
set subclasses(terminal_server) {}
set subclasses(computer) {}
set subclasses(ipv4_network) {}
set subclasses(file_mailbox) {}
set subclasses(machine) {}
set subclasses(ipv4_interface) {}
set subclasses(os_login) {}
set subclasses(automount_map) {}
set subclasses(mailing_list_member) {}
set subclasses(hub) {}
set subclasses(udp_port) udp_service
set subclasses(group_member) {}
set subclasses(secondary_automount) {}
set subclasses(paging_provider) {}
set subclasses(system_group) {}
set subclasses(role) {}
set subclasses(generic_group) {group system_group user_group application_group os_group}
set subclasses(nfs_volume) {secondary_automount abstract_automount automount user_login}
set subclasses(os_spec) {os os_family}
set subclasses(udp_service) {}
set subclasses(bsd_printer) {}
set subclasses(user_group) {}
set subclasses(principal) {host_principal user_principal}
set subclasses(host_console) {}
set subclasses(server_alias) {}
set subclasses(abstract_mailing_list) {}
set subclasses(region) cell
set subclasses(mailbox_alias) {}
set subclasses(organization) {}
set subclasses(ipv4_dynamic_range) {}
set subclasses(host_netgroup_member_object) {region host terminal_server computer hub router cell abstract_host host_alias abstract_computer server_alias}
set subclasses(mailing_list) {}
set subclasses(machine_spec) {machine abi}
set subclasses(router) {}
set subclasses(user_netgroup_member_object) {region login system_login cell application_login user_login}
set subclasses(external_mail_address) {}
set subclasses(login) {system_login application_login user_login}
set subclasses(os) {}
set subclasses(mailing_list_member_object) {mailing_list external_mail_address login system_login mailbox program_mailbox file_mailbox aliasable_mailbox person application_login user_login}
set subclasses(application_group) {}
set subclasses(host_principal) {}
set subclasses(os_specific) {os_login os_group}
set subclasses(ipv4_range) {ipv4_dynamic_range ipv4_static_range}
set subclasses(person) {}
set subclasses(aliasable_mailbox) {person user_login}
set subclasses(udp_service_alias) {}
set subclasses(netgroup) {}
set subclasses(host) {terminal_server computer hub router}
set subclasses(system_login) {}
set subclasses(server_type) {}
set subclasses(interface_or_host_or_region) {host_or_region region host terminal_server computer hub router cell ipv4_abstract_interface ipv4_interface}
set subclasses(named_item) {ipv4_network automount_map paging_provider generic_group abstract_mailing_list mailbox_alias organization host_netgroup_member_object region user_netgroup_member_object login netgroup host terminal_server computer hub router system_login server_type interface_or_host_or_region host_or_region printer group system_group user_group application_group mail_route mailing_list_member_object mailing_list external_mail_address os_group automount cell ipv4_abstract_interface ipv4_interface mailbox program_mailbox file_mailbox aliasable_mailbox person application_login abstract_host host_alias abstract_computer server_alias bsd_printer_alias user_login bsd_printcap bsd_printer bsd_printer_type generic_login os_login}
set subclasses(printer) {bsd_printcap bsd_printer bsd_printer_type}
set subclasses(tcp_service) {}
set subclasses(ip_service) {udp_service udp_service_alias tcp_service tcp_service_alias}
set subclasses(authorization) {}
set subclasses(bsd_printer_type) {}
set subclasses(shell_location) {}
set subclasses(ipv4_node) {ipv4_secondary_address ipv4_abstract_interface ipv4_interface host terminal_server computer hub router}
set subclasses(sybase_interface) {}
set subclasses(abi) {}
set subclasses(group) {system_group user_group application_group}
set subclasses(tcp_service_alias) {}
set subclasses(pager) {}
set subclasses(unix_pathname) {program_mailbox file_mailbox nfs_volume secondary_automount abstract_automount automount user_login generic_login os_login login system_login application_login}
set subclasses(mail_route) {mailing_list_member_object mailing_list external_mail_address login system_login mailbox program_mailbox file_mailbox aliasable_mailbox person application_login abstract_host host_alias abstract_computer computer server_alias user_login}
set subclasses(os_group) {}
set subclasses(user_principal) {}
set subclasses(ipv4_secondary_address) {}
set subclasses(tcp_port) {tcp_service sybase_interface}
set subclasses(automount) {}
set subclasses(os_family) {}
set subclasses(cell) {}
set subclasses(netgroup_member) {}
set subclasses(ipv4_abstract_interface) {ipv4_interface host terminal_server computer hub router}
set subclasses(mailbox) {program_mailbox file_mailbox aliasable_mailbox person user_login}
set subclasses(application_login) {}
set subclasses(abstract_host) {host_alias abstract_computer computer server_alias}
set subclasses(ipv4_static_range) {}
set subclasses(host_alias) {}
set subclasses(abstract_computer) {computer server_alias}
set subclasses(bsd_printer_alias) {}
set subclasses(user_login) {}
set subclasses(abstract_automount) {automount user_login}
set subclasses(bsd_printcap) {bsd_printer bsd_printer_type}
set subclasses(generic_login) {os_login login system_login application_login user_login}
