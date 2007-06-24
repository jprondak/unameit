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
set VLIST(ALNUM)\
    {{regexp E1STNOTLETTER {^[a-zA-Z]}}\
     {regexp ENOTALNUM {^[a-zA-Z0-9]*$}}}
#
set VLIST(ALPHA)\
    {{regexp ENOTALPHA {^[a-zA-Z]*$}}}
#
set VLIST(DASHGENALNUM)\
    {{regexp E1STNOTLETTER {^[a-zA-Z]}}\
     {regexp ENOTDASHGENALNUM {^([-_]?[0-9A-Za-z])*$}}}
#
set VLIST(ERRORCODE)\
    {{regexp E1STNOTE {^E}}\
     {regexp ENOTALNUM {^[A-Z0-9]*$}}}
#
set VLIST(GENALNUM)\
    {{regexp E1STNOTLETTER {^[a-zA-Z]}}\
     {regexp ENOTGENALNUM {^([_]?[0-9A-Za-z])*$}}}
#
set VLIST(GRAPH)\
    {{regexp ENOTGRAPH "^[^\001-\040\177-\377]*$"}}
#
set VLIST(NUMERIC)\
    {{regexp ENOTNUMERIC {^[0-9]*$}}}
#
set VLIST(PRINT)\
    {{regexp ENOTPRINT "^[^\001-\037\177-\377]*$"}}
#
set VLIST(WORDS)\
    {{regexp E1STNOTLETTER {^[a-zA-Z]}}\
     {regexp ENOTWORDS {^([ ]?[a-zA-Z]+)*$}}}

new_collision_table unameit_attribute_name
new_collision_table unameit_class_label
new_collision_table unameit_class_name
new_collision_table unameit_collision_name
new_collision_table unameit_collision_rule
new_collision_table unameit_error_code
new_collision_table unameit_eproc_name
new_collision_table unameit_family_name
new_collision_table unameit_inherited_attribute
new_collision_table unameit_net_class
new_collision_table unameit_range_class
new_collision_table unameit_role_name

#
# Data class: unameit_item
# Readonly?: Yes
# Group: 
# Label: Generic Item
# Name attributes: 
# Superclasses: 
#
#
new_data_class unameit_item eJmCVYyj2R0BWUU.65b.VU Yes {} {Generic Item} {}
    #
    raw_class_attribute unameit_item root_object unameit_item
    #
    raw_attribute unameit_item backp/block object
    #
    raw_attribute unameit_item backp/cascade object
    #
    raw_attribute unameit_item backp/nullify object
    #
    new_uuid_attribute Defining Scalar {Data eJmDy2yj2R0BWUU.65b.VU} uuid\
        unameit_item UUID Error No
    #
    new_string_attribute Defining Scalar {Data Wo1YKZ5j2R00DUU.65b.VU}\
        comment unameit_item Comment NULL Yes 1 128 Mixed PRINT
    #
    new_string_attribute Defining Scalar {} modby unameit_item\
        {Last Modified By} NULL Yes 0 63 Mixed {}
    #
    new_time_attribute Defining Scalar {} mtime unameit_item\
        {Modification Time} NULL Yes
    #
    new_string_attribute Defining Scalar {} mtran unameit_item\
        {Last Trans Id} NULL Yes 0 63 Mixed {}
    #
    new_enum_attribute Defining Scalar {} deleted unameit_item\
        {Item Deleted?} NULL Yes {No Yes}
    #
    display unameit_item comment

#
# Data class: unameit_data_item
# Readonly?: Yes
# Group: 
# Label: Data Item
# Name attributes: 
# Superclasses: 
#
#
new_data_class unameit_data_item eJmFTYyj2R0BWUU.65b.VU Yes {} {Data Item}\
    {}
    #
    new_pointer_attribute Defining Scalar {Data eJmGyYyj2R0BWUU.65b.VU}\
        owner unameit_data_item Owner Error Yes unameit_data_item Block\
        No Off
    #
    display unameit_data_item owner
    display unameit_data_item comment

#
# Data class: named_item
# Readonly?: Yes
# Group: 
# Label: Named Item
# Name attributes: name
# Superclasses: 
#
#
new_data_class named_item eJmIRYyj2R0BWUU.65b.VU Yes {} {Named Item} name
    #
    new_string_attribute Defining Scalar {Data eJmJwYyj2R0BWUU.65b.VU}\
        name named_item Name Error Yes 1 63 lower {}
    #
    display named_item name
    display named_item owner
    display named_item comment

#
# Data class: role
# Readonly?: No
# Group: Authorization
# Label: Role
# Name attributes: role_name
# Superclasses: 
#
#
new_data_class role eJmME2yj2R0BWUU.65b.VU No Authorization Role\
    role_name
    #
    new_string_attribute Defining Scalar {Data eJmNo2yj2R0BWUU.65b.VU}\
        role_name role Name Error No 2 16 lower ALPHA
    #
    new_pointer_attribute Inherited Scalar {Data eJmPxYyj2R0BWUU.65b.VU}\
        owner role {Parent Role} NULL Yes role Block No On
    #
    new_pointer_attribute Defining Set {} unameit_role_create_classes\
        role {Create Classes} NULL Yes unameit_data_class Nullify No Off
    #
    new_pointer_attribute Defining Set {} unameit_role_update_classes\
        role {Update Classes} NULL Yes unameit_data_class Nullify No Off
    #
    new_pointer_attribute Defining Set {} unameit_role_delete_classes\
        role {Delete Classes} NULL Yes unameit_data_class Nullify No Off
    #
    new_collision_rule unameit_role_name role role_name Strong None None\
        None
    #
    new_trigger role Yes After After After unameit_uncache_auth_role {}\
        {owner unameit_role_create_classes unameit_role_update_classes unameit_role_delete_classes}\
        {}
    #
    new_trigger role Yes Before Before No unameit_root_default_trigger {}\
        owner {}
    #
    display role role_name
    display role owner
    display role comment

#
# Schema class: unameit_protected_item
# Readonly?: Yes
# Label: Protected Item
# Name attributes: 
# Superclasses: 
#
new_schema_class unameit_protected_item Yes {Protected Item} {}
    #
    raw_attribute unameit_protected_item item unameit_item

#
# Schema class: unameit_transaction
# Readonly?: Yes
# Label: Transaction State
# Name attributes: 
# Superclasses: 
#
new_schema_class unameit_transaction Yes {Transaction State} {}
    #
    raw_class_attribute unameit_transaction data_major INTEGER
    #
    raw_class_attribute unameit_transaction data_minor INTEGER
    #
    raw_class_attribute unameit_transaction data_micro INTEGER
    #
    raw_class_attribute unameit_transaction schema_major INTEGER
    #
    raw_class_attribute unameit_transaction schema_minor INTEGER
    #
    raw_class_attribute unameit_transaction schema_micro INTEGER

#
# Schema class: unameit_schema_item
# Readonly?: Yes
# Label: Schema Item
# Name attributes: 
# Superclasses: unameit_item
#
new_schema_class unameit_schema_item Yes {Schema Item} {} unameit_item

#
# Schema class: unameit_class
# Readonly?: Yes
# Label: Schema Class
# Name attributes: unameit_class_name
# Superclasses: unameit_schema_item
#
new_schema_class unameit_class Yes {Schema Class} unameit_class_name\
    unameit_schema_item
    #
    new_string_attribute Defining Scalar {} unameit_class_name\
        unameit_class {Class Name} Error No 2 32 lower GENALNUM
    #
    new_enum_attribute Defining Scalar {} unameit_class_readonly\
        unameit_class {Class Readonly} Error Yes {No Yes}
    #
    new_pointer_attribute Defining Set {} unameit_class_supers\
        unameit_class SuperClasses Error Yes unameit_class Nullify No On
    #
    new_string_attribute Defining Scalar {} unameit_class_label\
        unameit_class {Class Label} Error Yes 2 32 Mixed PRINT
    #
    new_string_attribute Defining Scalar {} unameit_class_group\
        unameit_class {Class Group} Error Yes 0 255 Mixed WORDS
    #
    new_pointer_attribute Defining Sequence {}\
        unameit_class_name_attributes unameit_class {Name Fields} Error\
        Yes unameit_defining_scalar_attribute Block No Off
    #
    new_pointer_attribute Defining Sequence {}\
        unameit_class_display_attributes unameit_class {Displayed Fields}\
        Error Yes unameit_defining_attribute Block No Off
    #
    new_collision_rule unameit_class_label unameit_class\
        unameit_class_label Strong None None None
    #
    new_collision_rule unameit_class_name unameit_class\
        unameit_class_name Strong None None None

#
# Schema class: unameit_data_class
# Readonly?: No
# Label: Data Class
# Name attributes: unameit_class_name
# Superclasses: unameit_class
#
new_schema_class unameit_data_class No {Data Class} unameit_class_name\
    unameit_class
    #
    new_pointer_attribute Inherited Set {} unameit_class_supers\
        unameit_data_class Superclasses Error Yes unameit_data_class\
        Nullify No On
    #
    new_pointer_attribute Inherited Sequence {}\
        unameit_class_name_attributes unameit_data_class {Name Fields}\
        Error Yes unameit_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Inherited Sequence {}\
        unameit_class_display_attributes unameit_data_class\
        {Displayed Fields} Error Yes unameit_defining_data_attribute\
        Block No Off
    #
    new_collision_rule unameit_class_label unameit_data_class\
        unameit_class_label Strong None None None
    #
    new_collision_rule unameit_class_name unameit_data_class\
        unameit_class_name Strong None None None
    #
    display unameit_data_class unameit_class_name
    display unameit_data_class unameit_class_label
    display unameit_data_class unameit_class_group
    display unameit_data_class unameit_class_readonly
    display unameit_data_class unameit_class_supers
    display unameit_data_class unameit_class_name_attributes
    display unameit_data_class unameit_class_display_attributes

#
# Schema class: unameit_address_family
# Readonly?: No
# Label: Address Family
# Name attributes: unameit_family_name
# Superclasses: unameit_schema_item
#
new_schema_class unameit_address_family No {Address Family}\
    unameit_family_name unameit_schema_item
    #
    new_string_attribute Defining Scalar {} unameit_family_name\
        unameit_address_family {Address Family Name} Error No 2 32 Mixed\
        PRINT
    #
    new_integer_attribute Defining Scalar {} unameit_address_octets\
        unameit_address_family {Address Octets} Error No 1 32 Decimal
    #
    new_enum_attribute Defining Scalar {} unameit_node_zero\
        unameit_address_family {Node Zero} Error Yes {Available Reserved}
    #
    new_enum_attribute Defining Scalar {} unameit_last_node\
        unameit_address_family {Last Node} Error Yes {Available Reserved}
    #
    new_enum_attribute Defining Scalar {} unameit_net_zero\
        unameit_address_family {Net Zero} Error Yes {Available Reserved}
    #
    new_enum_attribute Defining Scalar {} unameit_last_net\
        unameit_address_family {Last Net} Error Yes {Available Reserved}
    #
    new_pointer_attribute Defining Scalar {} unameit_node_class\
        unameit_address_family {Node Class} Error No unameit_data_class\
        Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_node_netof_attribute\
        unameit_address_family {Node Netof Attribute} Error No\
        unameit_pointer_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {}\
        unameit_node_address_attribute unameit_address_family\
        {Node Address Attribute} Error No\
        unameit_address_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_class\
        unameit_address_family {Net Class} Error No unameit_data_class\
        Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_netof_attribute\
        unameit_address_family {Network Netof Attribute} Error No\
        unameit_pointer_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_start_attribute\
        unameit_address_family {Network Start Attribute} Error No\
        unameit_address_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_end_attribute\
        unameit_address_family {Network End Attribute} Error No\
        unameit_address_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_bits_attribute\
        unameit_address_family {Network Bits Attribute} Error No\
        unameit_integer_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_mask_attribute\
        unameit_address_family {Subnet Mask Attribute} Error No\
        unameit_address_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_net_type_attribute\
        unameit_address_family {Subnet Type Attribute} Error No\
        unameit_enum_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_range_class\
        unameit_address_family {Range Class} NULL No unameit_data_class\
        Block No Off
    #
    new_pointer_attribute Defining Scalar {}\
        unameit_range_netof_attribute unameit_address_family\
        {Range Netof Attribute} NULL No\
        unameit_pointer_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {}\
        unameit_range_start_attribute unameit_address_family\
        {Range Start Attribute} NULL No\
        unameit_address_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_range_end_attribute\
        unameit_address_family {Range End Attribute} NULL No\
        unameit_address_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_range_type_attribute\
        unameit_address_family {Range Type Attribute} NULL No\
        unameit_enum_defining_scalar_data_attribute Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_range_devices_attribute\
        unameit_address_family {Range Devices Attribute} NULL No\
        unameit_enum_defining_set_data_attribute Block No Off
    #
    new_collision_rule unameit_family_name unameit_address_family\
        unameit_family_name Strong None None None
    #
    new_collision_rule unameit_net_class unameit_address_family\
        unameit_net_class Strong None None None
    #
    new_collision_rule unameit_range_class unameit_address_family\
        unameit_range_class Strong None None None
    #
    display unameit_address_family unameit_family_name
    display unameit_address_family unameit_address_octets
    display unameit_address_family unameit_node_zero
    display unameit_address_family unameit_last_node
    display unameit_address_family unameit_net_zero
    display unameit_address_family unameit_last_net
    display unameit_address_family unameit_node_class
    display unameit_address_family unameit_node_netof_attribute
    display unameit_address_family unameit_node_address_attribute
    display unameit_address_family unameit_net_class
    display unameit_address_family unameit_net_netof_attribute
    display unameit_address_family unameit_net_start_attribute
    display unameit_address_family unameit_net_end_attribute
    display unameit_address_family unameit_net_bits_attribute
    display unameit_address_family unameit_net_mask_attribute
    display unameit_address_family unameit_net_type_attribute
    display unameit_address_family unameit_range_class
    display unameit_address_family unameit_range_netof_attribute
    display unameit_address_family unameit_range_start_attribute
    display unameit_address_family unameit_range_end_attribute

#
# Schema class: unameit_syntax_class
# Readonly?: Yes
# Label: Syntax Class
# Name attributes: unameit_class_name
# Superclasses: unameit_class
#
new_schema_class unameit_syntax_class Yes {Syntax Class}\
    unameit_class_name unameit_class
    #
    new_string_attribute Defining Scalar {} unameit_syntax_name\
        unameit_syntax_class {Syntax Name} Error Yes 2 32 lower ALPHA
    #
    new_enum_attribute Defining Scalar {} unameit_syntax_type\
        unameit_syntax_class Type NULL No {Generic Integer String Object}
    #
    new_enum_attribute Defining Scalar {} unameit_syntax_resolution\
        unameit_syntax_class Resolution NULL No\
        {Generic Inherited Defining}
    #
    new_enum_attribute Defining Scalar {} unameit_syntax_multiplicity\
        unameit_syntax_class Multiplicity NULL No\
        {Generic Scalar Set Sequence}
    #
    new_enum_attribute Defining Scalar {} unameit_syntax_domain\
        unameit_syntax_class {Name Space} NULL No {Generic Data}
    #
    new_collision_rule unameit_class_label unameit_syntax_class\
        unameit_class_label Strong None None None
    #
    new_collision_rule unameit_class_name unameit_syntax_class\
        unameit_class_name Strong None None None

#
# Schema class: unameit_collision_table
# Readonly?: Yes
# Label: Collision Table
# Name attributes: unameit_collision_name
# Superclasses: unameit_schema_item
#
new_schema_class unameit_collision_table Yes {Collision Table}\
    unameit_collision_name unameit_schema_item
    #
    new_string_attribute Defining Scalar {} unameit_collision_name\
        unameit_collision_table Name Error Yes 2 63 lower GENALNUM
    #
    new_collision_rule unameit_collision_name unameit_collision_table\
        unameit_collision_name Strong None None None

#
# Schema class: unameit_data_collision_table
# Readonly?: No
# Label: Data Collision Table
# Name attributes: unameit_collision_name
# Superclasses: unameit_collision_table
#
new_schema_class unameit_data_collision_table No {Data Collision Table}\
    unameit_collision_name unameit_collision_table
    #
    new_collision_rule unameit_collision_name\
        unameit_data_collision_table unameit_collision_name Strong None\
        None None
    #
    display unameit_data_collision_table unameit_collision_name

#
# Schema class: unameit_collision_rule
# Readonly?: Yes
# Label: Collision Rule
# Name attributes: unameit_collision_table unameit_colliding_class
# Superclasses: unameit_schema_item
#
new_schema_class unameit_collision_rule Yes {Collision Rule}\
    {unameit_collision_table unameit_colliding_class} unameit_schema_item
    #
    new_pointer_attribute Defining Scalar {} unameit_collision_table\
        unameit_collision_rule {Collision Table} Error No\
        unameit_collision_table Block No Off
    #
    new_pointer_attribute Defining Scalar {} unameit_colliding_class\
        unameit_collision_rule {Colliding Class} Error No unameit_class\
        Cascade No Off
    #
    new_pointer_attribute Defining Sequence {}\
        unameit_collision_attributes unameit_collision_rule {Field List}\
        Error No unameit_defining_scalar_attribute Cascade No Off
    #
    new_enum_attribute Defining Scalar {}\
        unameit_collision_local_strength unameit_collision_rule\
        {Local Collision Strength} Error No {None Weak Normal Strong}
    #
    new_enum_attribute Defining Scalar {} unameit_collision_cell_strength\
        unameit_collision_rule {Cell Collision Strength} Error No\
        {None Weak Normal Strong}
    #
    new_enum_attribute Defining Scalar {} unameit_collision_org_strength\
        unameit_collision_rule {Org Collision Strength} Error No\
        {None Weak Normal Strong}
    #
    new_enum_attribute Defining Scalar {}\
        unameit_collision_global_strength unameit_collision_rule\
        {Global Collision Strength} Error No {None Weak Normal Strong}
    #
    new_collision_rule unameit_collision_rule unameit_collision_rule\
        {unameit_collision_table unameit_colliding_class} Strong None\
        None None

#
# Schema class: unameit_data_collision_rule
# Readonly?: No
# Label: Data Collision Rule
# Name attributes: unameit_collision_table unameit_colliding_class
# Superclasses: unameit_collision_rule
#
new_schema_class unameit_data_collision_rule No {Data Collision Rule}\
    {unameit_collision_table unameit_colliding_class}\
    unameit_collision_rule
    #
    new_pointer_attribute Inherited Scalar {} unameit_collision_table\
        unameit_data_collision_rule {Collision Table} Error No\
        unameit_data_collision_table Block No Off
    #
    new_pointer_attribute Inherited Scalar {} unameit_colliding_class\
        unameit_data_collision_rule {Colliding Class} Error No\
        unameit_data_class Cascade No Off
    #
    new_pointer_attribute Inherited Sequence {}\
        unameit_collision_attributes unameit_data_collision_rule\
        {Field List} Error No unameit_defining_scalar_data_attribute\
        Cascade No Off
    #
    new_collision_rule unameit_collision_rule unameit_data_collision_rule\
        {unameit_collision_table unameit_colliding_class} Strong None\
        None None
    #
    display unameit_data_collision_rule unameit_collision_table
    display unameit_data_collision_rule unameit_colliding_class
    display unameit_data_collision_rule unameit_collision_attributes
    display unameit_data_collision_rule unameit_collision_local_strength
    display unameit_data_collision_rule unameit_collision_cell_strength
    display unameit_data_collision_rule unameit_collision_org_strength
    display unameit_data_collision_rule unameit_collision_global_strength

#
# Schema class: unameit_trigger
# Readonly?: Yes
# Label: Trigger
# Name attributes: unameit_trigger_class unameit_trigger_proc
# Superclasses: unameit_schema_item
#
new_schema_class unameit_trigger Yes Trigger\
    {unameit_trigger_class unameit_trigger_proc} unameit_schema_item
    #
    new_pointer_attribute Defining Scalar {} unameit_trigger_class\
        unameit_trigger {Item Class} Error Yes unameit_class Cascade No\
        Off
    #
    new_enum_attribute Defining Scalar {} unameit_trigger_inherited\
        unameit_trigger Inherited Error Yes {No Yes}
    #
    new_enum_attribute Defining Scalar {} unameit_trigger_oncreate\
        unameit_trigger {Run On Create} Error Yes {No Before After Around}
    #
    new_enum_attribute Defining Scalar {} unameit_trigger_onupdate\
        unameit_trigger {Run On Update} Error Yes {No Before After Around}
    #
    new_enum_attribute Defining Scalar {} unameit_trigger_ondelete\
        unameit_trigger {Run On Delete} Error Yes {No Before After Around}
    #
    new_string_attribute Defining Scalar {} unameit_trigger_proc\
        unameit_trigger {Trigger Proc} Error Yes 1 255 Mixed GENALNUM
    #
    new_list_attribute Defining Scalar {} unameit_trigger_args\
        unameit_trigger {Trigger Args} Error Yes 0 10
    #
    new_pointer_attribute Defining Sequence {} unameit_trigger_attributes\
        unameit_trigger {Trigger Fields} Error Yes\
        unameit_defining_attribute Block No Off
    #
    new_pointer_attribute Defining Sequence {} unameit_trigger_computes\
        unameit_trigger {Computed Fields} Error Yes\
        unameit_defining_attribute Block No Off

#
# Schema class: unameit_data_trigger
# Readonly?: No
# Label: Data Trigger
# Name attributes: unameit_trigger_class unameit_trigger_proc
# Superclasses: unameit_trigger
#
new_schema_class unameit_data_trigger No {Data Trigger}\
    {unameit_trigger_class unameit_trigger_proc} unameit_trigger
    #
    new_pointer_attribute Inherited Scalar {} unameit_trigger_class\
        unameit_data_trigger {Item Class} Error Yes unameit_data_class\
        Cascade No Off
    #
    new_pointer_attribute Inherited Sequence {}\
        unameit_trigger_attributes unameit_data_trigger {Trigger Fields}\
        Error Yes unameit_defining_data_attribute Block No Off
    #
    new_pointer_attribute Inherited Sequence {} unameit_trigger_computes\
        unameit_data_trigger {Computed Fields} Error Yes\
        unameit_defining_data_attribute Block No Off
    #
    display unameit_data_trigger unameit_trigger_class
    display unameit_data_trigger unameit_trigger_proc
    display unameit_data_trigger unameit_trigger_inherited
    display unameit_data_trigger unameit_trigger_oncreate
    display unameit_data_trigger unameit_trigger_onupdate
    display unameit_data_trigger unameit_trigger_ondelete
    display unameit_data_trigger unameit_trigger_args
    display unameit_data_trigger unameit_trigger_attributes
    display unameit_data_trigger unameit_trigger_computes

#
# Schema class: unameit_error_proc
# Readonly?: No
# Label: Error Procedure
# Name attributes: unameit_error_proc_name
# Superclasses: unameit_schema_item
#
new_schema_class unameit_error_proc No {Error Procedure}\
    unameit_error_proc_name unameit_schema_item
    #
    new_string_attribute Defining Scalar {} unameit_error_proc_name\
        unameit_error_proc {Procedure Name} Error Yes 1 255 Mixed\
        GENALNUM
    #
    new_list_attribute Defining Scalar {} unameit_error_proc_args\
        unameit_error_proc {Argument List} Error Yes 0 {}
    #
    new_code_attribute Defining Scalar {} unameit_error_proc_body\
        unameit_error_proc Body Error Yes
    #
    new_collision_rule unameit_eproc_name unameit_error_proc\
        unameit_error_proc_name Strong None None None
    #
    display unameit_error_proc unameit_error_proc_name
    display unameit_error_proc unameit_error_proc_args
    display unameit_error_proc unameit_error_proc_body

#
# Schema class: unameit_error
# Readonly?: No
# Label: Error Code
# Name attributes: unameit_error_code
# Superclasses: unameit_schema_item
#
new_schema_class unameit_error No {Error Code} unameit_error_code\
    unameit_schema_item
    #
    new_string_attribute Defining Scalar {} unameit_error_code\
        unameit_error {Error Code} Error Yes 1 {} UPPER ERRORCODE
    #
    new_string_attribute Defining Scalar {} unameit_error_message\
        unameit_error {Error Message} Error Yes 0 {} Mixed {}
    #
    new_pointer_attribute Defining Scalar {} unameit_error_proc\
        unameit_error {Error Procedure} Error Yes unameit_error_proc\
        Block No Off
    #
    new_enum_attribute Defining Scalar {} unameit_error_type\
        unameit_error {Error Type} Error Yes {Normal Internal}
    #
    new_collision_rule unameit_error_code unameit_error\
        unameit_error_code Strong None None None
    #
    display unameit_error unameit_error_code
    display unameit_error unameit_error_proc
    display unameit_error unameit_error_type
    display unameit_error unameit_error_message

#
# Schema class: unameit_range_block
# Readonly?: Yes
# Label: Range Block
# Name attributes: 
# Superclasses: 
#
new_schema_class unameit_range_block Yes {Range Block} {}
    #
    raw_class_attribute unameit_range_block nextfree object
    #
    raw_attribute unameit_range_block nextfree object
    #
    raw_attribute unameit_range_block range_start INTEGER
    #
    raw_attribute unameit_range_block range_end INTEGER
