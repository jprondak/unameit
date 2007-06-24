#
# Copyright (c) 1996 Enterprise Systems Management Corp.
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
# $Id: tests.tcl,v 1.36 1996/12/10 22:45:40 simpson Exp $
#

#
# Test script for server TCL procedures.
#

proc test_syscall {test_num result errcode args} {
    global PRINT_ERR_MSGS errorCode errorInfo CREATED_UUIDS ERRCODE_TO_MSG

    set cmdargs [lassign $args cmd]
    if {[cequal $cmd unameit_create]} {
	lassign $cmdargs class uuid
    } else {
	lassign $cmdargs uuid
    }

    puts -nonewline "$test_num..."
    flush stdout

    set catch_result [catch {unameit_send $args} msg]

    if {$catch_result != $result} {
	if {$catch_result} {
	    if {![cequal $errorCode NONE]} {
		set msg $ERRCODE_TO_MSG([lindex $errorCode 1])
	    }
	} else {
	    set errorInfo ""
	    set errorCode ""
	}
	error "failed: result $catch_result, $msg" $errorInfo \
		$errorCode
    }
    if {$catch_result == 0} {
	switch -- $cmd {
	    unameit_undelete -
	    unameit_create {
		lappend CREATED_UUIDS $uuid
	    }
	    unameit_delete {
		set i [lsearch $CREATED_UUIDS $uuid]
		set CREATED_UUIDS [lreplace $CREATED_UUIDS $i $i]
	    }
	}
    }
    puts OK
}

proc test_syscalls {{print_err_msgs 1} {leave_data 0}} {
    global CREATED_UUIDS PRINT_ERR_MSGS errorInfo errorCode ERRCODE_TO_MSG

    catch {unset CREATED_UUIDS}
    set CREATED_UUIDS ""
    if {$print_err_msgs} {
	set PRINT_ERR_MSGS 1
    } else {
	set PRINT_ERR_MSGS 0
    }

    catch {unset ERRCODE_TO_MSG}
    foreach uuid\
	[unameit_decode_items -result\
	    [unameit_qbe unameit_error\
		    unameit_error_code unameit_error_message]] {
	upvar 0 $uuid eu
	set ERRCODE_TO_MSG($eu(unameit_error_code)) $eu(unameit_error_message)
    }

    puts [unameit_license_terms]
    set catch_result [catch run_syscalls msg]
    if {$catch_result != 0} {
	puts "$errorInfo\n$errorCode\n$msg"
    }
    if {$catch_result != 0 || !$leave_data} {
	if {![lempty [info commands master_eval]]} {
	    #
	    # Revert to super user
	    #
	    master_eval unameit_transaction "UName*It"
	    master_eval unameit_principal ""
	}
	while {![lempty $CREATED_UUIDS]} {
	    unameit_delete [lvarpop CREATED_UUIDS end]
	}
	unameit_commit
    }
    puts [unameit_license_terms]
}

proc run_syscalls {} {
    #
    # Load root cell, and pick first non root cell as `top cell'
    #
    foreach cell\
	    [unameit_decode_items -result\
		[unameit_qbe cell name relname owner cellorg]] {
	upvar 0 $cell cell_item
	set name $cell_item(name)
	if {[cequal $name .]} {
	    set root_cell $cell
	} elseif {![info exists top_cell]} {
	    set top_cell $cell
	    set top_cell_name $name
	    set org $cell_item(cellorg)
	}
    }

    #
    # Cell tests
    #
    puts "\nTesting cell behaviour\n"

    #
    # Make sure root cell is protected
    #
    test_syscall 1000.0 1 EPERM unameit_update $root_cell name foo.com

    #
    # Create new cell named sales
    #
    set sales_cell [uuidgen]
    test_syscall 1000.1 0 "" unameit_create cell $sales_cell\
	name sales.$top_cell_name cellorg $org

    puts -nonewline 1000.2...
    set hosts_ng\
	[unameit_decode_items -result\
	    [unameit_qbe host_netgroup\
		{name = hosts} [list owner = $sales_cell]]]
    set count [llength $hosts_ng]

    if {$count == 1} {
	puts OK
    } else {
	puts "failed: Unexpected number of 'hosts' netgroups: $count"
    }

    #
    # Make sure cell relname is computed
    #
    test_syscall 1000.3 1 ECOMPUTED unameit_create cell [uuidgen]\
	name foo.$top_cell_name relname foo cellorg ""
    test_syscall 1000.4 1 ECOMPUTED unameit_update cell $sales_cell\
	relname foo

    #
    # Make sure cell owner is computed
    #
    test_syscall 1000.5 1 ECOMPUTED unameit_update cell $sales_cell\
	owner $root_cell

    test_syscall 1000.6 1 ECOMPUTED unameit_create cell [uuidgen]\
	name foo.$top_cell_name owner $top_cell cellorg ""

    #
    # Test org change
    #
    test_syscall 1000.7 0 "" unameit_update $sales_cell cellorg $org
    test_syscall 1000.8 1 EORGMOVE unameit_update $sales_cell cellorg ""


    #
    # Rename the top cell, and make sure sales cell is adjusted accordingly
    #
    test_syscall 1000.9 0 "" unameit_update $top_cell name "tla.org"

    unameit_decode_items [unameit_fetch $sales_cell name relname owner]
    upvar 0 $sales_cell cell_item
    set name $cell_item(name)
    set relname $cell_item(relname)
    set owner $cell_item(owner)

    puts -nonewline "1000.10..."
    if {![cequal $owner $root_cell]} {
	error "failed: New cell owner is not root_cell"
    }
    puts OK

    puts -nonewline "1000.11..."
    if {![cequal $name sales.$top_cell_name]} {
	error "failed: New cell name is not sales.<top_cell_name>"
    }
    puts OK

    puts -nonewline "1000.12..."
    if {![cequal $relname sales.$top_cell_name]} {
	error "failed: New cell relname is not sales.<top_cell_name>"
    }
    puts OK

    #
    # Restore top cell and make sure sales cell is reverts to initial state
    #
    test_syscall 1000.13 0 "" unameit_update $top_cell name $top_cell_name

    unameit_decode_items [unameit_fetch $sales_cell name relname owner]
    upvar 0 $sales_cell cell_item
    set name $cell_item(name)
    set relname $cell_item(relname)
    set owner $cell_item(owner)

    puts -nonewline "1000.14..."
    if {![cequal $name sales.$top_cell_name]} {
	error "failed: New cell name is not sales.<top_cell_name>"
    }
    puts OK

    puts -nonewline "1000.15..."
    if {![cequal $relname sales]} {
	error "failed: New cell relname is not sales"
    }
    puts OK

    puts -nonewline "1000.16..."
    if {![cequal $owner $top_cell]} {
	error "failed: New cell owner is not top cell"
    }
    puts OK

    #
    # Delete the sales cell,  and make sure  hosts netgroup goes with it.
    #
    test_syscall 1000.17 0 "" unameit_delete $sales_cell
    unameit_decode_items [unameit_fetch $sales_cell uuid]

    puts -nonewline "1000.18..."
    upvar 0 $sales_cell domain_item
    if {[cequal $domain_item(deleted) ""]} {
	error "Could not delete cell"
    }
    puts OK

    unameit_decode_items [unameit_fetch $hosts_ng uuid]
    puts -nonewline "1000.19..."
    upvar 0 $hosts_ng ng_item
    if {[cequal $ng_item(deleted) ""]} {
	error "Could not cascade automatic netgroup"
    }
    puts OK

    #
    # Undelete the sales cell
    #
    test_syscall 1000.20 0 "" unameit_undelete $sales_cell
    test_syscall 1000.21 0 "" unameit_fetch $sales_cell uuid
    test_syscall 1000.22 0 "" unameit_fetch $hosts_ng uuid

    #
    # Region tests
    #
    puts "\nTesting region behaviour\n"

    #
    # Create new region under sales cell,  and make sure it looks good
    #
    set domestic_region [uuidgen]
    test_syscall 1001.0 0 "" unameit_create region $domestic_region\
	    name domestic.sales.$top_cell_name

    unameit_decode_items [unameit_fetch $domestic_region name relname owner]
    upvar 0 $domestic_region region_item
    set name $region_item(name)
    set relname $region_item(relname)
    set owner $region_item(owner)

    puts -nonewline "1001.1..."
    if {![cequal $name domestic.sales.$top_cell_name]} {
	error "failed: region name is not domestic.sales.<top_cell_name>"
    }
    puts OK

    puts -nonewline "1001.2..."
    if {![cequal $relname domestic]} {
	error "failed: region relname is not domestic"
    }
    puts OK

    puts -nonewline "1001.3..."
    if {![cequal $owner $sales_cell]} {
	error "failed: region owner is not <sales_cell>"
    }
    puts OK

    set rhosts_ng\
	[unameit_decode_items -result\
	    [unameit_qbe host_netgroup {name = hosts}\
		[list owner = $domestic_region]]]
    set count [llength $rhosts_ng]

    puts -nonewline 1001.4...
    if {$count == 1} {
	puts OK
    } else {
	puts "failed: Unexpected number of 'hosts' netgroups: $count"
    }

    #
    # Delete the region,  make sure everything goes away
    #
    test_syscall 1001.5 0 "" unameit_delete $domestic_region

    unameit_decode_items [unameit_fetch $domestic_region uuid]
    puts -nonewline "1001.6..."
    upvar 0 $domestic_region domain_item
    if {[cequal $domain_item(deleted) ""]} {
	error "Could not delete region"
    }
    puts OK

    unameit_decode_items [unameit_fetch $rhosts_ng uuid]
    puts -nonewline "1001.7..."
    upvar 0 $rhosts_ng ng_item
    if {[cequal $ng_item(deleted) ""]} {
	error "Could not cascade automatic netgroup"
    }
    puts OK

    #
    # Undelete the region,  make sure everything comes back
    # and take a few detours while we are at it.
    #

    #
    # Oops can't move into root cell
    #
    test_syscall 1001.8 1 EDUPREGION unameit_undelete $domestic_region\
	name .
    test_syscall 1001.9 1 EROOTREGION unameit_undelete $domestic_region\
	name domestic.org
    #
    # Undelete into different cell!
    #
    test_syscall 1001.10 0 "" unameit_undelete $domestic_region\
	name domestic.$top_cell_name
    #
    # Can't update into different cell
    #
    test_syscall 1001.11 1 ECELLMOVE unameit_update $domestic_region\
	name domestic.sales.$top_cell_name
    #
    # Delete again
    #
    test_syscall 1001.12 0 "" unameit_delete $domestic_region
    #
    # Undelete into intended cell
    #
    test_syscall 1001.13 0 "" unameit_undelete $domestic_region\
	name domestic.sales.$top_cell_name
    test_syscall 1001.14 0 "" unameit_fetch $rhosts_ng uuid

    #
    # Create a subsubregion,  then a subcell of that,  then a subregion
    # and a subcell of that,
    #
    set subdomestic_region [uuidgen]
    test_syscall 1001.15 0 "" unameit_create region $subdomestic_region\
	name sub.domestic.sales.$top_cell_name
    #
    set subdomestic_cell [uuidgen]
    test_syscall 1001.16 0 "" unameit_create cell $subdomestic_cell\
	name cell.sub.domestic.sales.$top_cell_name
    #
    set sub_subdomestic_cell [uuidgen]
    test_syscall 1001.17 0 "" unameit_create region $sub_subdomestic_cell\
	name sub.cell.sub.domestic.sales.$top_cell_name
    #
    set subcell_subdomestic_cell [uuidgen]
    test_syscall 1001.18 0 "" unameit_create region $subcell_subdomestic_cell\
	name cell.cell.sub.domestic.sales.$top_cell_name

    #
    # Rename the sales cell,  and make sure all is well
    #
    test_syscall 1001.19 0 "" unameit_update $sales_cell\
	name tla.org

    #
    # Retrieve the whole mess
    #
    unameit_decode_items\
	[unameit_fetch\
	    [list\
		$domestic_region\
		$subdomestic_region\
		$subdomestic_cell\
		$sub_subdomestic_cell\
		$subcell_subdomestic_cell] name relname owner]

    puts -nonewline "1001.20..."

    upvar 0 $domestic_region region_item
    if {![cequal $region_item(name) domestic.tla.org]} {
	error "failed: domestic region name != domestic.tla.org"
    }
    if {![cequal $region_item(relname) domestic]} {
	error "failed: domestic region relname != domestic"
    }
    if {![cequal $region_item(owner) $sales_cell]} {
	error "failed: domestic region owner != <sales_cell>"
    }

    upvar 0 $subdomestic_region region_item
    if {![cequal $region_item(name) sub.domestic.tla.org]} {
	error "failed: subdomestic region name != sub.domestic.tla.org"
    }
    if {![cequal $region_item(relname) sub]} {
	error "failed: subdomestic region relname != sub"
    }
    if {![cequal $region_item(owner) $domestic_region]} {
	error "failed: subdomestic region owner != <domestic_region>"
    }

    upvar 0 $subdomestic_cell cell_item
    if {![cequal $cell_item(name) cell.sub.domestic.sales.$top_cell_name]} {
	error "failed: subdomestic cell name !=\
		cell.sub.domestic.sales.$top_cell_name"
    }
    if {![cequal $cell_item(relname) cell.sub.domestic.sales]} {
	error "failed: subdomestic cell relname != cell.sub.domestic.sales"
    }
    if {![cequal $cell_item(owner) $top_cell]} {
	error "failed: subdomestic cell owner != <top_cell>"
    }

    upvar 0 $sub_subdomestic_cell region_item
    if {![cequal $region_item(name)\
	    sub.cell.sub.domestic.sales.$top_cell_name]} {
	error "failed: sub_subdomestic_cell region name !=\
		sub.cell.sub.domestic.sales.$top_cell_name"
    }
    if {![cequal $region_item(relname) sub]} {
	error "failed: sub_subdomestic_cell region relname != sub"
    }
    if {![cequal $region_item(owner) $subdomestic_cell]} {
	error "failed: sub_subdomestic_cell region owner !=\
		<subdomestic_cell>"
    }

    upvar 0 $subcell_subdomestic_cell cell_item
    if {![cequal $cell_item(name)\
	    cell.cell.sub.domestic.sales.$top_cell_name]} {
	error "failed: subcell_subdomestic cell name !=\
		cell.cell.sub.domestic.sales.$top_cell_name"
    }
    if {![cequal $cell_item(relname) cell]} {
	error "failed: subcell_subdomestic cell relname != cell"
    }
    if {![cequal $cell_item(owner) $subdomestic_cell]} {
	error "failed: subcell_subdomestic cell owner != <subdomestic_cell>"
    }
    puts OK

    #
    # Restore the old name of the sales cell,  and make sure all is well
    #
    test_syscall 1001.21 0 "" unameit_update $sales_cell\
	name sales.$top_cell_name

    #
    # Retrieve the whole mess
    #
    unameit_decode_items\
	[unameit_fetch\
	    [list\
		$domestic_region\
		$subdomestic_region\
		$subdomestic_cell\
		$sub_subdomestic_cell\
		$subcell_subdomestic_cell] name relname owner]

    puts -nonewline "1001.22..."

    upvar 0 $domestic_region region_item
    if {![cequal $region_item(name) domestic.sales.$top_cell_name]} {
	error "failed: domestic region name !=\
		domestic.sales.<top_cell_name>"
    }
    if {![cequal $region_item(relname) domestic]} {
	error "failed: domestic region relname != domestic"
    }
    if {![cequal $region_item(owner) $sales_cell]} {
	error "failed: domestic region owner != <sales_cell>"
    }

    upvar 0 $subdomestic_region region_item
    if {![cequal $region_item(name) sub.domestic.sales.$top_cell_name]} {
	error "failed: subdomestic region name !=\
		sub.domestic.sales.<top_cell_name>"
    }
    if {![cequal $region_item(relname) sub]} {
	error "failed: subdomestic region relname != sub"
    }
    if {![cequal $region_item(owner) $domestic_region]} {
	error "failed: subdomestic region owner != <domestic_region>"
    }

    upvar 0 $subdomestic_cell cell_item
    if {![cequal $cell_item(name) cell.sub.domestic.sales.$top_cell_name]} {
	error "failed: subdomestic cell name !=\
		cell.sub.domestic.sales.$top_cell_name"
    }
    if {![cequal $cell_item(relname) cell]} {
	error "failed: subdomestic cell relname != cell"
    }
    if {![cequal $cell_item(owner) $subdomestic_region]} {
	error "failed: subdomestic cell owner != <subdomestic_region>"
    }

    upvar 0 $sub_subdomestic_cell region_item
    if {![cequal $region_item(name)\
	    sub.cell.sub.domestic.sales.$top_cell_name]} {
	error "failed: sub_subdomestic_cell region name !=\
		sub.cell.sub.domestic.sales.$top_cell_name"
    }
    if {![cequal $region_item(relname) sub]} {
	error "failed: sub_subdomestic_cell region relname != sub"
    }
    if {![cequal $region_item(owner) $subdomestic_cell]} {
	error "failed: sub_subdomestic_cell region owner !=\
		<subdomestic_cell>"
    }

    upvar 0 $subcell_subdomestic_cell cell_item
    if {![cequal $cell_item(name)\
	    cell.cell.sub.domestic.sales.$top_cell_name]} {
	error "failed: subcell_subdomestic cell name !=\
		cell.cell.sub.domestic.sales.$top_cell_name"
    }
    if {![cequal $cell_item(relname) cell]} {
	error "failed: subcell_subdomestic cell relname != cell"
    }
    if {![cequal $cell_item(owner) $subdomestic_cell]} {
	error "failed: subcell_subdomestic cell owner != <subdomestic_cell>"
    }
    puts OK

    puts "\nTesting EDUPREGION region hierarchy protection\n"
    #
    # Test EDUPREGION cases
    #
    #
    # Direct collision
    #
    test_syscall 1002.0 1 EDUPREGION unameit_create region [uuidgen]\
	name sales.$top_cell_name
    test_syscall 1002.1 1 EDUPREGION unameit_update $domestic_region\
	name sales.$top_cell_name
    #
    # Indirect collision of subregion of renamed cell
    #
    test_syscall 1002.2 0 "" unameit_create cell [set cell1 [uuidgen]]\
	name sub.sub.$top_cell_name
    test_syscall 1002.3 0 "" unameit_create cell [set cell2 [uuidgen]]\
	name cell.$top_cell_name
    test_syscall 1002.4 0 "" unameit_create region [set region [uuidgen]]\
	name sub.cell.$top_cell_name
    test_syscall 1002.5 1 EDUPREGION unameit_update $cell2\
	name sub.$top_cell_name
    test_syscall 1002.6 0 "" unameit_delete $region
    test_syscall 1002.7 0 "" unameit_update $cell2\
	name sub.$top_cell_name

    puts "\nTesting that cells with subregions may not be deleted\n"
    #
    # Test that cells with subregions may not be deleted, and
    # that subcells are not a problem.
    #
    #
    test_syscall 1002.8 0 "" unameit_undelete $region\
	name sub2.sub.$top_cell_name
    test_syscall 1002.9 1 EREFINTEGRITY unameit_delete $cell2
    test_syscall 1002.10 0 "" unameit_delete $region
    test_syscall 1002.11 0 "" unameit_delete $cell2
    test_syscall 1002.12 0 "" unameit_delete $cell1

    puts "\n Testing ipv4 network code \n"

    set sales_subnet [uuidgen]
    # The following is an illegal top level subnet (top level subnets must
    # be exactly class A, B or C).
    test_syscall 1003.0 1 EBADNETSIZE unameit_create ipv4_network\
	    $sales_subnet \
	    name sales owner $sales_cell ipv4_address 128.192.0.0 \
	    ipv4_last_address 128.255.255.255 ipv4_mask 255.192.0.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed

    # The following has a subnet ipv4_mask that is smaller than the number of
    # common bits
    test_syscall 1003.1 1 EBADMASK unameit_create ipv4_network\
	    $sales_subnet \
	    name sales owner $sales_cell ipv4_address 128.195.0.0 \
	    ipv4_last_address 128.195.255.255 ipv4_mask 255.254.0.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed

    # The following has an octet of 256
    test_syscall 1003.2 1 ENOTADDRESS unameit_create ipv4_network\
	    $sales_subnet \
	    name sales  owner $sales_cell ipv4_address 128.256.0.0 \
	    ipv4_last_address 128.256.255.255 ipv4_mask 255.255.0.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed

    # The following is completely legal. It is a class B net. Since the
    # subnet ipv4_mask is the same as the number of leading common bits,
    # only IP addresses can appear below this net.
    test_syscall 1003.3 0 "" unameit_create ipv4_network $sales_subnet \
	    name sales owner $sales_cell ipv4_address 128.195.0.0 \
	    ipv4_last_address 128.195.255.255 ipv4_mask 255.255.0.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed

    # The following IP range already exists. 
    # It was just created above. Otherwise, it would be legal.
    test_syscall 1003.4 1 EDUPNET unameit_create ipv4_network [uuidgen] \
	    name foobar owner $sales_cell ipv4_address 128.195.0.0 \
	    ipv4_last_address 128.195.255.255 ipv4_mask 255.255.0.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed

    # The following is not legal because you cannot create networks below
    # networks with common bits and subnet ipv4_masks equal.
    test_syscall 1003.5 1 ENOTSUBNETTED unameit_create ipv4_network\
	    [uuidgen] \
	    name subsales owner $sales_cell ipv4_address 128.195.3.0 \
	    ipv4_last_address 128.195.3.255 ipv4_mask 255.255.255.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed

    # The following is an illegal network. The subnet bits extend too far
    # to the right.
    test_syscall 1003.6 1 EBADMASK unameit_create ipv4_network\
	    [uuidgen] \
	    name dev owner $domestic_region ipv4_address 128.199.0.0 \
	    ipv4_last_address 128.199.255.255 ipv4_mask 255.255.255.254\
	    ipv4_mask_type Fixed

    # The following is a legal net. Since the subnet ipv4_mask is longer than
    # the number of common bits, only networks with a number of common bits and
    # subnet ipv4_mask equal to this subnet ipv4_mask can exist below this
    # network. Also, only IP ipv4_address nodes can exist below any child
    # subnets of this network.
    set dev_subnet [uuidgen]
    test_syscall 1003.7 0 "" unameit_create ipv4_network $dev_subnet name dev \
	    owner $domestic_region ipv4_address 128.199.0.0 \
	    ipv4_last_address 128.199.255.255 ipv4_mask 255.255.240.0\
	    ipv4_network ""\
	    ipv4_mask_type Fixed
    
    # The following is an illegal subnet because the subnet ipv4_mask does not
    # match the number of common bits and this subnet's ipv4_network has a
    # fixed ipv4_mask.
    test_syscall 1003.8 1 EFIXEDMASK unameit_create ipv4_network\
	    [uuidgen] \
	    owner $domestic_region ipv4_address 128.199.128.0 \
	    ipv4_last_address 128.199.143.255 ipv4_mask 255.255.255.0 name\
	    blah\
	    ipv4_mask_type Fixed

    # The following is an illegal subnet because the number of common
    # bits is not equal to the ipv4_network's subnet ipv4_mask.
    test_syscall 1003.9 1 EFIXEDMASK unameit_create ipv4_network\
	    [uuidgen] \
	    owner $domestic_region ipv4_address 128.199.128.0 \
	    ipv4_last_address 128.199.191.255 ipv4_mask 255.255.240.0 name\
	    blah\
	    ipv4_mask_type Fixed

    # The following network is illegal because its ipv4_mask is null and its
    # ipv4_network's ipv4_mask isn't.
    test_syscall 1003.10 1 EBADMASK unameit_create ipv4_network\
	    [uuidgen] \
	    owner $domestic_region ipv4_address 128.199.128.0 \
	    ipv4_last_address 128.199.143.255 ipv4_mask "" name blah\
	    ipv4_mask_type Fixed

    # The following is a legal subnet below the dev network.
    set subdev_subnet [uuidgen]
    test_syscall 1003.11 0 "" unameit_create ipv4_network $subdev_subnet \
	    owner $domestic_region ipv4_address 128.199.128.0 \
	    ipv4_last_address 128.199.143.255 ipv4_mask 255.255.240.0 name\
	    subdev\
	    ipv4_mask_type Fixed

    # The following subnet is legal. Networks with no subnet ipv4_mask are
    # free form. The top level network must be a proper class A, B or C
    # though.
    set test_subnet [uuidgen]
    test_syscall 1003.12 0 "" unameit_create ipv4_network $test_subnet \
	    owner $domestic_region ipv4_address 128.67.0.0 \
	    ipv4_last_address 128.67.255.255 ipv4_mask "" name test\
	    ipv4_mask_type Variable

    # The following is a legal subnet with a null ipv4_mask and not a proper
    # class A, B or C network.
    set subtest_subnet [uuidgen]
    test_syscall 1003.13 0 "" unameit_create ipv4_network $subtest_subnet \
	    owner $domestic_region ipv4_address 128.67.204.0 \
	    ipv4_last_address 128.67.207.255 ipv4_mask "" name subtest\
	    ipv4_mask_type Variable

    # The following is a legal sub-subnet 
    set subsubtest_subnet [uuidgen]
    test_syscall 1003.14 0 "" unameit_create ipv4_network $subsubtest_subnet \
	    owner $domestic_region ipv4_address 128.67.205.0 \
	    ipv4_last_address 128.67.205.255 ipv4_mask 255.255.255.0 \
	    name subsubtest\
	    ipv4_mask_type Fixed

    # The following is an illegal subnet with a "subnet" ipv4_address of all\
    # ones.
    test_syscall 1003.15 1 ELASTSUBNET unameit_create ipv4_network\
	    [uuidgen] \
	    owner $domestic_region ipv4_address 128.67.255.0 \
	    ipv4_last_address 128.67.255.255 ipv4_mask 255.255.255.0 \
	    name junk\
	    ipv4_mask_type Fixed

    # The is a network with a 2 bit subnet ipv4_mask and 2 bits of host
    # addresses.
    set smallnet [uuidgen]
    test_syscall 1003.16 0 "" unameit_create ipv4_network $smallnet \
	    owner $domestic_region ipv4_address 128.67.203.240 \
	    ipv4_last_address 128.67.203.255 ipv4_mask fffffffc name smallnet\
	    ipv4_mask_type Fixed

    # Now let's grab a couple of subnets automatically
    for {set i 0} {$i < 2} {incr i} {
	set small_subnet [uuidgen]
	set n [expr 17 + $i]
	test_syscall 1003.$n 0 "" unameit_create ipv4_network $small_subnet\
	    owner $domestic_region\
	    ipv4_address ""\
	    ipv4_last_address ""\
	    ipv4_mask ""\
	    ipv4_network $smallnet\
	    name smallsubnet$i\
	    ipv4_mask_type Fixed
    }

    test_syscall 1003.19 1 ENOADDRSLEFT unameit_create ipv4_network\
    	    [uuidgen] \
    	    owner $domestic_region ipv4_address "" ipv4_last_address ""\
    	    ipv4_mask "" ipv4_network $smallnet name smallsubnet2\
    	    ipv4_mask_type Fixed

    set allow_subnet_zero 0
    set allow_supernets 0
    #
    if {[cequal $allow_subnet_zero Yes]} {
    	test_syscall 1003.20 0 "" unameit_create ipv4_network [uuidgen] \
    		owner $domestic_region \
    		ipv4_address 128.67.203.240 ipv4_last_address 128.67.203.243 \
    		ipv4_mask fffffffc ipv4_network $smallnet name smallsubnet2\
    		ipv4_mask_type Fixed
    } else {
    	test_syscall 1003.20 1 EZEROTHSUBNET unameit_create ipv4_network \
    	    [uuidgen] \
    		owner $domestic_region \
    		ipv4_address 128.67.203.240 ipv4_last_address 128.67.203.243 \
    		ipv4_mask fffffffc ipv4_network $smallnet name smallsubnet2\
    		ipv4_mask_type Fixed
    }

    # We should be able to update the ipv4_mask of this network to a fixed
    # subnet ipv4_mask of Class C shape
    test_syscall 1003.21 0 "" unameit_update $subtest_subnet \
	    ipv4_mask 255.255.255.0\
	    ipv4_mask_type Fixed

    test_syscall 1003.22 1 ENOTPARENT unameit_create ipv4_network\
    	    [uuidgen] \
    	    owner $domestic_region ipv4_address 128.199.16.0 \
    	    ipv4_last_address 128.199.31.255 ipv4_mask 255.255.240.0 \
    	    name foonet ipv4_network $smallnet\
    	    ipv4_mask_type Fixed

    test_syscall 1003.23 1 ENULL unameit_create ipv4_network [uuidgen] \
	    owner $domestic_region ipv4_address 128.199.16.0 \
	    ipv4_last_address "" ipv4_mask "" name junk ipv4_network ""\
	    ipv4_mask_type Variable

    # To get the ENOTIPV4_NETWORK error, we need to create a three level
    # subnetted network. The first level has no subnet ipv4_mask, the next
    # level is a subnetted network and the last network is one that we create
    # with a bogus ipv4_network.
    set level1_net [uuidgen]
    test_syscall 1003.24 0 "" unameit_create ipv4_network $level1_net \
	    owner $top_cell ipv4_address 128.5.0.0 \
	    ipv4_last_address 128.5.255.255 ipv4_mask "" name level1\
	    ipv4_network ""\
	    ipv4_mask_type Variable
    set level2_net [uuidgen]
    test_syscall 1003.25 0 "" unameit_create ipv4_network $level2_net \
	    owner $top_cell ipv4_address 128.5.20.0 \
	    ipv4_last_address 128.5.20.255 ipv4_mask fffffff0 name level2\
	    ipv4_mask_type Fixed
    test_syscall 1003.26 1 ENOTPARENT unameit_create ipv4_network\
	    [uuidgen] \
	    owner $top_cell ipv4_address 128.5.20.16 \
	    ipv4_last_address 128.5.20.31 ipv4_mask fffffff0 name level3 \
	    ipv4_network $level1_net\
	    ipv4_mask_type Fixed

    test_syscall 1003.27 1 ENULL unameit_create ipv4_network [uuidgen] \
	    owner $top_cell ipv4_address 128.5.20.16 ipv4_last_address ""\
	    ipv4_mask fffffff0 name foobarnet\
	    ipv4_mask_type Fixed
	    
    test_syscall 1003.28 1 ENULL unameit_create ipv4_network [uuidgen] \
	    owner $top_cell ipv4_address "" ipv4_last_address 128.5.20.31 \
	    ipv4_mask fffffff0 name foobarnet\
	    ipv4_mask_type Fixed
	    
    test_syscall 1003.29 1 ENULL unameit_create ipv4_network [uuidgen] \
	    owner $top_cell ipv4_address "" ipv4_last_address ""\
	    ipv4_mask fffffff0 name foobarnet\
	    ipv4_mask_type Fixed

    #
    set cnet [uuidgen]
    test_syscall 1003.30 0 "" unameit_create ipv4_network $cnet name cnet201 \
	    owner $top_cell\
	    ipv4_address 192.9.201.0\
	    ipv4_last_address 192.9.201.255\
	    ipv4_mask FFFFFF00\
	    ipv4_mask_type Fixed

    puts "\n Testing host system calls\n"

    set salesdemo_host [uuidgen]
    test_syscall 1004.1 0 "" unameit_create computer $salesdemo_host \
	name salesdemo owner $sales_cell os "" machine ""\
	ifname "" ifaddress "" ipv4_address 192.9.201.1\
	receives_mail No

    unameit_decode_items [unameit_fetch $salesdemo_host ipv4_network]
    puts -nonewline 1004.2...
    if {![cequal [set ${salesdemo_host}(ipv4_network)] $cnet]} {
	error "failed: computed network != $cnet"
    }
    puts OK

    set autoip_host [uuidgen]
    test_syscall 1004.3 0 "" unameit_create computer $autoip_host \
	name autoip owner $top_cell os "" machine ""\
	ifname "" ifaddress "" ipv4_network $cnet ipv4_address ""\
	receives_mail No

    unameit_decode_items [unameit_fetch $autoip_host ipv4_address]
    puts -nonewline 1004.4...
    set addr [set ${autoip_host}(ipv4_address)]
    if {![cequal $addr c009c902]} {
	error "failed: autogenerated address $addr != c009c902"
    }
    puts OK

    #
    # Make sure NULL IP addresses are illegal
    #
    test_syscall 1004.5 1 ENULL unameit_create computer [uuidgen] \
	name foohost ipv4_address "" owner $domestic_region\
	os "" machine "" ifname le0 ifaddress 0:1:2:2:3:4\
	receives_mail No
    #
    # Aliases collide with hosts in same org!
    #
    test_syscall 1004.6 1 EDIRECTUNIQ unameit_create host_alias [uuidgen]\
	name autoip owner $salesdemo_host
    #
    # Different org should work!
    #
    set autoip_host2 [uuidgen]
    test_syscall 1004.7 0 "" unameit_create computer $autoip_host2 \
	name autoip owner $subdomestic_cell os "" machine ""\
	ifname "" ifaddress aa:aa:aa:aa:aa:aa\
	ipv4_network $cnet ipv4_address ""\
	receives_mail No

    unameit_decode_items [unameit_fetch $autoip_host2 ipv4_address]
    puts -nonewline 1004.8...
    if {![cequal [set ${autoip_host2}(ipv4_address)] c009c903]} {
	error "failed: autogenerated address != 192.9.201.3"
    }
    puts OK

    set autoip_alias [uuidgen]
    test_syscall 1004.9 0 "" unameit_create host_alias $autoip_alias\
	name autoip-alias owner $autoip_host2

    test_syscall 1004.10 1 EDIRECTUNIQ unameit_create host [uuidgen]\
	name junkhost\
	owner $top_cell os "" machine "" ifname le0 \
	ifaddress aa:aa:aa:aa:aa:aa ipv4_address 192.9.201.123\
	receives_mail No

    test_syscall 1004.11 0 "" unameit_delete $autoip_host2
    #
    # Make sure both go away
    #
    unameit_decode_items [unameit_fetch $autoip_host2]
    puts -nonewline "1004.12..."
    upvar 0 $autoip_host2 host_item
    if {[cequal $host_item(deleted) ""]} {
	error "Could not delete host"
    }
    puts OK

    unameit_decode_items [unameit_fetch $autoip_alias]
    puts -nonewline "1004.13..."
    upvar 0 $autoip_alias alias_item
    if {[cequal $alias_item(deleted) ""]} {
	error "Could not cascade alias"
    }
    puts OK

    puts "\n Host interface tests \n"

    set net_if [uuidgen]
    test_syscall 1005.0 1 ENOTADDRESS unameit_create ipv4_interface $net_if\
	ifname le1 \
	ifaddress Ga:aa:aa:aa:aa:aa owner $salesdemo_host \
	ipv4_address "" ipv4_network $cnet

    test_syscall 1005.1 0 "" unameit_create ipv4_interface $net_if \
	ifname le1\
	ifaddress aa:aa:aa:aa:aa:aa owner $salesdemo_host\
	ipv4_address "" ipv4_network $cnet

    unameit_decode_items [unameit_fetch [list $net_if $salesdemo_host] name]
    puts -nonewline 1005.2...
    set ifname [set ${net_if}(name)]
    set hostname [set ${salesdemo_host}(name)]
    if {![cequal $ifname $hostname]} {
	error "failed: computed name $name != $hostname"
    }
    puts OK

    test_syscall 1005.3 0 "" unameit_update $salesdemo_host\
	name tmpname

    unameit_decode_items [unameit_fetch $net_if name]
    puts -nonewline 1005.4...
    if {![cequal [set ${net_if}(name)] tmpname]} {
	error "failed: <hostname> change not propagated to interfaces"
    }
    puts OK

    for {set i 5} {$i < 7} {incr i} {
	set if$i [uuidgen]
	test_syscall 1005.$i 0 "" unameit_create ipv4_interface [set if$i]\
	    ifname if$i ifaddress ""\
	    ipv4_address "" ipv4_network $small_subnet\
	    owner $salesdemo_host
    }

    test_syscall 1005.7 0 "" unameit_update $salesdemo_host\
	name salesdemo

    unameit_decode_items [unameit_fetch $if5 name]
    puts -nonewline 1005.8...
    if {![cequal [set ${if5}(name)] salesdemo]} {
	error "failed: <hostname> change not propagated to interfaces"
    }
    puts OK

    test_syscall 1005.9 1 ENOADDRSLEFT unameit_create ipv4_interface \
	[uuidgen] \
	    ifname le4 ifaddress a:b:c:d:e:4 ipv4_address "" \
	    ipv4_network $small_subnet owner $salesdemo_host

    set net_if2 [uuidgen]
    test_syscall 1005.10 0 "" unameit_create ipv4_interface $net_if2 \
	ifname le5 \
	ifaddress 1:4:4:3:2:1 owner $salesdemo_host \
	ipv4_address 192.9.201.69

    test_syscall 1005.11 0 "" unameit_update $net_if2 ipv4_address 192.9.201.70

    puts "\n Testing secondary addresses \n"

    #
    # This addr is illegal because it doesn't reside in any of the
    # subnets created above. It resides below the root node.
    # The universe network looks like a subnetted network so we get the
    # error ESUBNETTED.
    #
    test_syscall 1006.0 1 ESUBNETTED unameit_create ipv4_secondary_address\
	[uuidgen] ipv4_address 129.195.0.1 owner $net_if

    #
    # This addr is illegal. It resides on the 128.67.205 network left boundary
    #
    test_syscall 1006.1 1 EADDRRESERVED unameit_create ipv4_secondary_address\
	[uuidgen] ipv4_address 128.67.205.0 owner $net_if

    #
    # This addr is illegal. It resides on the 128.67.205 network right boundary
    #
    test_syscall 1006.2 1 EADDRRESERVED unameit_create ipv4_secondary_address\
	[uuidgen] ipv4_address 128.67.205.255 owner $net_if

    #
    # This addr is legal and it lies under the 128.195 network
    #
    set sales_ip_addr [uuidgen]
    test_syscall 1006.3 0 "" unameit_create ipv4_secondary_address\
	$sales_ip_addr ipv4_address 128.195.0.1 owner $net_if

    #
    # Make sure duplicate IP addresses are detected
    #
    test_syscall 1006.4 1 EDUPADDR unameit_create ipv4_secondary_address\
	[uuidgen] ipv4_address 128.195.0.1 owner $if5

    #
    # Now try to delete the ipv4_address from the host interface we created
    # This change is illegal because secondary addresses require a primary
    # Normally empty interface addresses are legal.
    #
    test_syscall 1006.5 1 ENULLPRIMARYIP unameit_update $net_if\
	ipv4_network "" ipv4_address ""

    test_syscall 1006.6 0 "" unameit_delete $sales_ip_addr

    #
    # Make sure deleted IP addresses are do not preclude duplicates
    #
    test_syscall 1006.7 0 "" unameit_create ipv4_secondary_address\
	[uuidgen] ipv4_address 128.195.0.1 owner $if5

    #
    # Now try to zero the address of the host interface
    # Should work if no secondary addresses.
    #
    test_syscall 1006.8 0 "" unameit_update $net_if\
	ipv4_network "" ipv4_address ""

    #
    test_syscall 1006.9 0 "" unameit_update $net_if\
	ipv4_network $cnet ipv4_address ""

    # This addr is illegal because networks where the subnet ipv4_mask is
    # not equal to the number of common bits can only have networks below
    # them.
    test_syscall 1006.10 1 ESUBNETTED unameit_create ipv4_secondary_address \
	[uuidgen] ipv4_address 128.199.0.1 owner $net_if

    # This addr is legal. It resides in the lower level of a two
    # level subnetted network.
    set subdev_ip_addr1 [uuidgen]
    test_syscall 1006.11 0 "" unameit_create ipv4_secondary_address \
	$subdev_ip_addr1 ipv4_address 128.199.143.254 owner $net_if

    # This addr is also legal. It goes in the same subnet as the above
    # addr. I wanted to put two inet addresses below a node.
    set subdev_ip_addr2 [uuidgen]
    test_syscall 1006.12 0 "" unameit_create ipv4_secondary_address \
	$subdev_ip_addr2 \
	    ipv4_address 128.199.143.253 owner $net_if

    puts -nonewline 1006.13...
    unameit_decode_items\
	[unameit_fetch [list $subdev_ip_addr1 $subdev_ip_addr2] ipv4_network]
    if {![cequal [set ${subdev_ip_addr1}(ipv4_network)] $subdev_subnet]} {
	error "Address placed in wrong subnet"
    }
    if {![cequal [set ${subdev_ip_addr2}(ipv4_network)] $subdev_subnet]} {
	error "Address placed in wrong subnet"
    }
    puts OK

    # This ipv4_address is illegal. You can't create addresses below subnets
    # with a null subnet ipv4_mask.
    test_syscall 1006.14 1 ESUBNETTED unameit_create\
	    ipv4_secondary_address \
	    [uuidgen] \
	    ipv4_address 128.67.206.1 owner $net_if

    test_syscall 1006.15 1 ENOTPARENT unameit_create ipv4_secondary_address\
	    [uuidgen] ipv4_address 128.195.0.50 owner $net_if \
    	    ipv4_network $smallnet

    # This ipv4_address is legal. It falls into the subsubnet with fixed
    # ipv4_mask and correct length
    set subsubtest_ip_addr [uuidgen]
    test_syscall 1006.16 0 "" unameit_create ipv4_secondary_address \
	$subsubtest_ip_addr \
	    ipv4_address 128.67.205.1 owner $net_if

    # We can't nullify the ipv4_address portion of the interface because there
    # are secondary IP addresses pointing to it. We must nullify both
    # ipv4_network and ipv4_address or the system call will pick a new
    # ipv4_address.
    test_syscall 1006.17 1 ENULLPRIMARYIP unameit_update $net_if \
	ipv4_address "" ipv4_network ""

    # Now zap an interface IP ipv4_address and try to add a secondary IP addr.
    test_syscall 1006.18 0 "" unameit_update $net_if2 ipv4_address ""\
	    ipv4_network ""
    test_syscall 1006.19 1 ENOPRIMARYIP unameit_create ipv4_secondary_address \
	[uuidgen] \
	    ipv4_address 128.67.206.2 owner $net_if2

    test_syscall 1006.20 1 ENULL unameit_update $subsubtest_ip_addr \
	ipv4_network "" ipv4_address ""

    puts "\n Testing automount maps \n"

    set top_auto_map [uuidgen]
    test_syscall 1007.0 0 "" unameit_create automount_map $top_auto_map \
	name auto_apps mount_point /apps\
	mount_opts -rw,hard,intr owner $top_cell

    set sales_auto_map [uuidgen]
    test_syscall 1007.1 0 "" unameit_create automount_map $sales_auto_map\
	name auto_home mount_point /home\
	mount_opts -rw,intr,hard,rsize=1024 owner $sales_cell

    test_syscall 1007.2 1 EDIRECTUNIQ unameit_create automount_map [uuidgen]\
	name auto_home mount_point /tmp mount_opts\
	-rw,intr,hard owner $sales_cell

    test_syscall 1007.3 1 EDIRECTUNIQ unameit_create automount_map [uuidgen]\
	name auto_foo mount_point /home mount_opts\
	-rw,intr,hard owner $sales_cell

    test_syscall 1007.4 1 EMOUNTOPTUNKNOWN unameit_create automount_map\
	[uuidgen]\
	name auto_foo mount_point /foo mount_opts\
	-rw,intr,hard,foo owner $sales_cell

    test_syscall 1007.4 1 EMOUNTISBOOLEAN unameit_create automount_map\
	[uuidgen]\
	name auto_foo mount_point /foo mount_opts\
	-rw=5,intr,hard owner $sales_cell

    test_syscall 1007.5 1 EMOUNTISINTEGER unameit_create automount_map\
	[uuidgen]\
	name auto_foo mount_point /foo mount_opts\
	-rw,intr,hard,actimeo owner $sales_cell

    puts "\n Testing user_groups \n"

    set gid_attr\
	[unameit_decode_items -result\
	    [unameit_qbe unameit_autoint_defining_scalar_data_attribute\
		{unameit_attribute_name = gid}\
		unameit_integer_attribute_min\
		unameit_integer_attribute_max\
		unameit_autoint_attribute_level\
		unameit_autoint_attribute_min\
		unameit_autoint_attribute_max
		]]

    #
    # XXX: assume that user_group does not override default attribute
    # definition of gid.  If this changes # need to fetch level from
    # defining record as above, and all else from inherited record.
    #
    upvar 0 $gid_attr gid_attr_item
    set imin $gid_attr_item(unameit_integer_attribute_min)
    set imax $gid_attr_item(unameit_integer_attribute_max)
    set amin $gid_attr_item(unameit_autoint_attribute_min)
    set amax $gid_attr_item(unameit_autoint_attribute_max)

    set rnum 0

    test_syscall 1008.0.[incr rnum] 1 ETOOSMALL\
	unameit_create user_group [uuidgen]\
	owner $top_cell gid [expr $imin - 1] name faculty

    test_syscall 1008.0.[incr rnum] 1 ETOOBIG\
	unameit_create user_group [uuidgen]\
	owner $top_cell gid [expr $imax + 1] name faculty

    test_syscall 1008.0.[incr rnum] 0 ""\
	unameit_create user_group [set tmpuuid [uuidgen]]\
	owner $top_cell gid $imin name faculty
    test_syscall 1008.0.[incr rnum] 0 "" unameit_delete $tmpuuid

    test_syscall 1008.0.[incr rnum] 0 ""\
	unameit_create user_group [set tmpuuid [uuidgen]]\
	owner $top_cell gid $imax name faculty
    test_syscall 1008.0.[incr rnum] 0 "" unameit_delete $tmpuuid

    set faculty_user_group [uuidgen]

    test_syscall 1008.1 0 "" unameit_create user_group $faculty_user_group \
	    owner $top_cell gid "" name faculty
    unameit_decode_items [unameit_fetch $faculty_user_group gid]

    puts -nonewline "1008.2..."
    upvar 0 $faculty_user_group fug_item
    if {![cequal $fug_item(gid) $amin]} {
	error "Gid autogeneration: expected $amin, got $fug_item(gid)"
    }
    puts OK

    puts "\n Testing user_logins \n"

    set joe_user [uuidgen]
    test_syscall 1009.0 0 "" unameit_create person $joe_user \
	fullname "Joe H. User" owner $top_cell

#check cell of primary group to owner

    set guest_login [uuidgen]
    test_syscall 1010.0 1 EXCELL unameit_create user_login $guest_login \
	    name guest password gH2FTrSqCynk2 uid 20400 auto_map ""\
	    unix_pathname /usr/guest shell csh\
	    owner $domestic_region person $joe_user \
	    primary_group $faculty_user_group nfs_server "" login_enabled Yes\
	    mailhost ""

    test_syscall 1010.1 1 EXCELL unameit_create user_login $guest_login \
	    name guest password gH2FTrSqCynk2 uid 20400 \
	    auto_map $sales_auto_map \
	    unix_pathname /usr/guest shell csh \
	    owner $top_cell person $joe_user \
	    primary_group $faculty_user_group \
	    nfs_server $salesdemo_host login_enabled Yes mailhost ""

    test_syscall 1010.2 0 "" unameit_create user_login $guest_login\
	    name guest password gH2FTrSqCynk2 uid 20400 \
	    unix_pathname /usr/guest shell csh\
	    owner $top_cell person $joe_user\
	    primary_group $faculty_user_group login_enabled Yes

    test_syscall 1010.3 0 "" unameit_create user_login [uuidgen] \
	    name test password gH2FTrSqCynk2 uid 2400 auto_map ""\
	    unix_pathname /usr/guest shell /foo/bar \
	    owner $top_cell person $joe_user \
	    primary_group $faculty_user_group nfs_server "" login_enabled Yes\
	    mailhost ""

    set auto_gen_login [uuidgen]
    test_syscall 1010.4 0 "" unameit_create user_login $auto_gen_login \
	    name automan password * \
	    unix_pathname /usr/automan shell csh\
	    owner $top_cell person $joe_user uid ""\
	    primary_group $faculty_user_group login_enabled Yes

    set joe_login [uuidgen]
    test_syscall 1010.5 0 "" unameit_create user_login $joe_login\
	    name joe \
	    password * uid 443 auto_map ""\
	    unix_pathname /usr/joe shell /bin/sh\
	    owner $top_cell person $joe_user \
	    primary_group $faculty_user_group nfs_server "" login_enabled Yes

    puts "\n Testing automounts \n"
    
    set domestic_automount [uuidgen]
    test_syscall 1011.0 1 EXCELL unameit_create automount \
	    $domestic_automount owner $domestic_region name demo \
	    auto_map $top_auto_map nfs_server $salesdemo_host \
	    unix_pathname /usr/demo

    test_syscall 1011.1 0 "" unameit_create automount $domestic_automount \
	    owner $domestic_region name unameit \
	    auto_map $sales_auto_map nfs_server $salesdemo_host \
	    unix_pathname /opt/unameit

    test_syscall 1011.2 0 "" unameit_create secondary_automount [uuidgen]\
	owner $domestic_automount nfs_server $autoip_host\
	    unix_pathname /opt/unameit

    test_syscall 1011.3 1 EDIRECTUNIQ unameit_create secondary_automount\
	[uuidgen] owner $domestic_automount\
	    nfs_server $autoip_host unix_pathname /opt/unameit2

    test_syscall 1011.4 1 EDIRECTUNIQ unameit_update $domestic_automount\
	nfs_server $autoip_host

    test_syscall 1011.5 0 "" unameit_create automount [uuidgen]\
	    owner $top_cell name guest\
	    auto_map $top_auto_map nfs_server $salesdemo_host \
	    unix_pathname /usr/guest

    puts "\n Testing OS & Machine classes\n"

    set sunos41x [uuidgen]
    test_syscall 1012.0 0 "" unameit_create os_family $sunos41x\
	os_name SunOS os_release_name 4.1.X

    set sunos414 [uuidgen]
    test_syscall 1012.1 1 ENULL unameit_create os $sunos414\
	os_name SunOS os_release_name 4.1.4

    test_syscall 1012.2 0 "" unameit_create os $sunos414\
	os_name SunOS os_release_name 4.1.4 os_family $sunos41x

    set sparc [uuidgen]
    test_syscall 1012.3 0 "" unameit_create abi $sparc\
	machine_name sparc

    set sun4m [uuidgen]
    test_syscall 1012.4 1 ENULL unameit_create machine $sun4m\
	machine_name sun4m

    test_syscall 1012.5 0 "" unameit_create machine $sun4m\
	machine_name sun4m abi $sparc

    test_syscall 1012.6 1 EDIRECTUNIQ unameit_create os_family [uuidgen]\
	os_name SunOS os_release_name 4.1.X

    test_syscall 1012.7 1 EDIRECTUNIQ unameit_create os [uuidgen]\
	os_name SunOS os_release_name 4.1.4 os_family $sunos41x

    test_syscall 1012.8 1 EDIRECTUNIQ unameit_create abi [uuidgen]\
	machine_name SunOS os_release_name 4.1.X

    set parisc [uuidgen]
    test_syscall 1012.9 0 "" unameit_create abi $parisc\
	machine_name PARISC

    test_syscall 1012.10 1 EDIRECTUNIQ unameit_create machine [uuidgen]\
	machine_name sun4m abi $parisc

    test_syscall 1012.11 1 EWORM unameit_update $sunos41x\
	os_release_name 5.X

    test_syscall 1012.12 1 EWORM unameit_update $sunos414\
	os_release_name 4.1.3

    test_syscall 1012.13 1 EWORM unameit_update $sparc\
	machine_name ppc

    test_syscall 1012.14 1 EWORM unameit_update $sun4m\
	machine_name sun4c

    puts "\n Testing system groups\n"

    set kmem_system_group [uuidgen]
    test_syscall 1013.0 0 "" unameit_create system_group $kmem_system_group\
    	    owner $domestic_region name kmem gid 2 template_group Yes

    test_syscall 1013.1 0 "" unameit_create os_group [uuidgen]\
	base_group $kmem_system_group gid "" os_spec $sunos41x

    if {[lempty [info commands master_eval]]} {
	puts "\nBest to compile test server with -DINTERACTIVE"
	puts "Authorization tests skipped\n"
    } else {
	puts "\nAuthorization\n"

	#
	# Get all role UUIDs
	#
	foreach role\
		[unameit_decode_items -result\
		    [unameit_qbe role role_name]] {
	    upvar 0 $role role_item
	    set ruuid($role_item(role_name)) $role
	}

	set foreign_region [uuidgen]
	test_syscall 1014.0 0 "" unameit_create region $foreign_region\
		name foreign.sales.$top_cell_name

	set tp [uuidgen]
	test_syscall 1014.1 0 "" unameit_create principal $tp\
	    pname test pinst auth owner $domestic_region

	test_syscall 1014.2 0 "" unameit_create authorization [uuidgen]\
	    principal $tp owner $domestic_region role $ruuid(sysadmin)

	test_syscall 1014.3 0 "" unameit_create authorization [uuidgen]\
	    principal $tp owner $foreign_region role $ruuid(netadmin)

	#
	# Create a network that foreign netadmin can manage,  and
	# sysadmin of domestic cannot.
	#
	test_syscall 1014.4 0 "" unameit_create ipv4_network [uuidgen] \
		name authnet owner $foreign_region ipv4_address 128.67.208.0 \
		ipv4_last_address 128.67.211.255 ipv4_mask 255.255.255.0\
		ipv4_network ""\
		ipv4_mask_type Fixed

	#
	# Create as superuser a computer in domestic region
	# on a top level owned net.
	#
	set unauth_host [uuidgen]
	test_syscall 1014.5 0 "" unameit_create computer $unauth_host \
	    name unauth-host owner $domestic_region os "" machine ""\
	    ifname "" ifaddress "" ipv4_address 192.9.201.4\
	    receives_mail No

	#
	# Switch identities
	#
	master_eval unameit_transaction "test.auth@YOUR.COM"
	master_eval unameit_principal $tp

	#
	# Create a computer in domestic region on a domestic net.
	#
	set auth_host_d [uuidgen]
	test_syscall 1014.6 0 "" unameit_create computer $auth_host_d \
	    name auth-cd owner $domestic_region os "" machine ""\
	    ifname "" ifaddress "" ipv4_address 128.67.205.2\
	    receives_mail No

	#
	# Illegal router in domestic region on same domestic net.
	#
	test_syscall 1014.7 1 EPERM unameit_create router [uuidgen] \
	    name auth-rd owner $domestic_region \
	    ifname "" ifaddress "" ipv4_address 128.67.205.3

	#
	# Create a subnet of above network
	#
	test_syscall 1014.8 0 "" unameit_create ipv4_network [uuidgen] \
		name authsubnet owner $foreign_region\
		ipv4_address 128.67.209.0 \
		ipv4_last_address 128.67.209.255 ipv4_mask 255.255.255.0\
		ipv4_network ""\
		ipv4_mask_type Fixed

	#
	# Create router in foreign region on foreign subnet.
	#
	test_syscall 1014.9 0 "" unameit_create router [uuidgen] \
	    name auth-rf owner $foreign_region \
	    ifname "" ifaddress "" ipv4_address 128.67.209.1

	#
	# Illegal router in foreign region on domestic subnet.
	#
	test_syscall 1014.10 1 EREFPERM unameit_create router [uuidgen] \
	    name auth-rf2 owner $foreign_region \
	    ifname "" ifaddress "" ipv4_address 128.67.205.3

	#
	# Illegal move of computer to foreign subnet
	#
	test_syscall 1014.11 1 EREFPERM unameit_update $auth_host_d \
	    ipv4_network "" ipv4_address 128.67.209.2

	#
	# Ok move of computer to another domestic net
	#
	test_syscall 1014.12 0 "" unameit_update $auth_host_d \
	    ipv4_network "" ipv4_address 128.199.128.1

	#
	# Illegal move of computer to domestic net from top owned net
	#
	test_syscall 1014.13 1 EREFPERM unameit_update $unauth_host\
	    ipv4_network "" ipv4_address 128.67.205.2

    }
    return

    set domestic_ingres [uuidgen]
    test_syscall 1014.0 1 ETOOBIG unameit_create application_login\
	    $domestic_ingres name ingres owner $domestic_region\
	    password gH2FTrSqCynk2 uid 250000\
	    primary_group $kmem_system_group unix_pathname /usr/ingres\
	    shell /bin/csh

    test_syscall 1014.1 0 "" unameit_create application_login $domestic_ingres\
	name ingres\
	owner $domestic_region password gH2FTrSqCynk2 uid 3\
	primary_group $kmem_system_group unix_pathname /usr/ingres\
	shell /bin/csh auto_map "" nfs_server ""

    set domestic_sybase [uuidgen]
    test_syscall 1014.2 0 "" unameit_create system_login $domestic_sybase \
	name sybase owner $domestic_region password gH2FTrSqCynk2 uid 4\
	primary_group $kmem_system_group unix_pathname /usr/sybase \
	shell /bin/csh auto_map $sales_auto_map \
	nfs_server $salesdemo_host

#check to see if auto_map is in same cell

    set domestic_sybase10 [uuidgen]
    test_syscall 1010.5 1 EXCELL unameit_create system_login \
	    $domestic_sybase10 name sybase10 owner $top_cell \
	    password gH2FTrSqCynk2 uid 4 \
	    primary_group $kmem_system_group unix_pathname /usr/sybase10 \
	    shell /bin/csh auto_map $sales_auto_map \
	    nfs_server $salesdemo_host\
	    nfs_secondary_servers $slogin_host

#check is_tcp/is_udp null for services

    set unameit_service [uuidgen]
    test_syscall 1018.0 1 ENOSVCPROTO unameit_create service $unameit_service \
	    name unameit owner $top_cell port 28737 \
	    is_tcp "" is_udp ""

#check validation for is_tcp

    test_syscall 1018.1 1 EBADENUM unameit_create service $unameit_service \
	    name unameit owner $top_cell port 28737 \
	    is_tcp m is_udp ""

#check validation for udp


    test_syscall 1018.2 1 EBADENUM unameit_create service $unameit_service \
	    name unameit owner $top_cell port 28737 \
	    is_tcp "" is_udp m

#check for port number out of range

    test_syscall 1018.3 1 ETOOBIG  unameit_create service $unameit_service \
	    name unameit owner $top_cell port 65536 \
	    is_tcp Yes is_udp No

    test_syscall 1018.4 1 ETOOSMALL unameit_create service $unameit_service \
	    name unameit owner $top_cell port 0 \
	    is_tcp Yes is_udp No

    test_syscall 1018.5 0 "" unameit_create service $unameit_service \
	    name unameit owner $top_cell port 28737 \
	    is_tcp Yes is_udp Yes


    test_syscall 1018.6 1 ENOSVCPROTO unameit_create service [uuidgen] \
	    name foo owner $top_cell port 15 is_tcp "" is_udp ""

    set unameit_service_alias [uuidgen]
    test_syscall 1018.7 0 "" unameit_create service_alias \
	$unameit_service_alias \
	    name unameit_alias owner $marketing_cell \
	    service $unameit_service

    set foo_uuid [uuidgen]
    test_syscall 1019.0 0 "" unameit_create server_type $foo_uuid \
	    name foohost server_type_name foohost one_per_host Yes\
	    owner $top_cell

    set bar_uuid [uuidgen]
    test_syscall 1019.1 0 "" unameit_create server_type $bar_uuid \
	name bar server_type_name barserver one_per_host No\
	owner $top_cell

    test_syscall 1019.2 1 EDIRECTUNIQ unameit_create server_type [uuidgen] \
	name foohost server_type_name fooserver

    test_syscall 1019.3 1 EDIRECTUNIQ unameit_create server_type [uuidgen] \
	name barlias server_type_name barserver

    set paging_provider [uuidgen]
    test_syscall 1020.0 0 "" unameit_create paging_provider $paging_provider \
	    name MobileMedia\
	    provider_data_number {(714) 505-7686}\
	    owner $top_cell

    test_syscall 1021.0 1 ENOTREFUUID unameit_create pager [uuidgen] \
	    owner $top_cell\
	    pager_pin 12345678\
	    pager_phone {(714) 505-7690} \
	    pager_person foobar\
	    provider $paging_provider

    test_syscall 1021.1 0 "" unameit_create pager [uuidgen] \
	    owner $top_cell\
	    pager_pin 12345678\
	    pager_phone {(714) 505-7690} \
	    pager_person $joe_user\
	    provider $paging_provider

    set qbe_netgroup [uuidgen]
    test_syscall 1022.0 0 "" unameit_create qbe_user_netgroup $qbe_netgroup \
    	    owner $top_cell qbe_user_spec {user_login {name ~ s*}} name autoqbe

    set serval [uuidgen]
    test_syscall 1023.0 0 "" unameit_create server_alias $serval \
	server_type $bar_uuid primary_server $slogin_host owner $top_cell

    test_syscall 1023.1 1 EPRIMARYSERVER unameit_update $serval\
	secondary_servers $slogin_host

    #
    # Tickle the EWORM code.
    #
    test_syscall 1023.2 0 "" unameit_update $serval server_type $bar_uuid
    set xyzzy_uuid [uuidgen]
    test_syscall 1023.3 0 "" unameit_create server_type $xyzzy_uuid \
	name xyzzy server_type_name xyzzyserver owner $top_cell
    test_syscall 1023.4 1 EWORM unameit_update $serval server_type $xyzzy_uuid
    
    set foo_server_alias [uuidgen]
    test_syscall 1023.5 0 "" unameit_create server_alias $foo_server_alias \
          server_type $foo_uuid primary_server $slogin_host \
          owner $marketingMGR_cell

    test_syscall 1023.6 1 ESAMEHOST4SERVERALIAS unameit_create server_alias\
	[uuidgen] server_type $foo_uuid primary_server $slogin_host\
        owner $top_cell

    set mdropuu [uuidgen]
    test_syscall 1024.0 0 "" unameit_create mail_drop $mdropuu \
	    owner $joe_login
    test_syscall 1024.1 0 "" unameit_update $joe_login name newjoe

    array set foo [unameit_send {unameit_qbe -all auth_principal}] 
    array set bar $foo(result)
    set principal [lindex $bar(qbe) 0]
	
    array set foo [unameit_send {
	unameit_qbe unameit_role {role_name = mailadmin}
    }] 
    array set bar $foo(result)
    set role $bar(qbe)

    set authrec [uuidgen]
    test_syscall 1025.0 0 "" unameit_create auth_record $authrec \
	    principal $principal role $role owner $top_cell

    test_syscall 1025.1 0 "" unameit_update $authrec owner $top_cell
    
    set printer_type [uuidgen]
    test_syscall 1028.0 0 "" unameit_create printer_type $printer_type \
	    owner $top_cell name foo

    test_syscall 1029.0 1 EXCELL unameit_create printer [uuidgen] \
	    owner $sales_cell rm $salesdemo_host rp $printer_type \
	    name bar

    test_syscall 1029.1 1 ENOTREFUUID unameit_create printer [uuidgen] \
	    owner $sales_cell rm foobar rp $printer_type \
	    name bar

    test_syscall 1029.2 1 EPERM unameit_update $top_cell name foo

    test_syscall 1029.3 1 ENOTREFUUID unameit_create printer [uuidgen] \
	    name p owner $sales_cell rm foobar rp $printer_type

    # Do some updates and deletes to make sure those syscalls work too.
    test_syscall 1030.0 0 "" unameit_update $marketingMGR_host name manager

    test_syscall 1030.1 0 "" unameit_update $mr2_mailing_list\
	    addrs [list f@b.com g@c.com]

    test_syscall 1030.2 0 "" unameit_delete $printer_type
    global CREATED_UUIDS
    set CREATED_UUIDS \
	    [lrange $CREATED_UUIDS 0 [expr [llength $CREATED_UUIDS] - 2]]
    return ""
}

### Define a `unameit_send' workalike

if {[cequal [info commands unameit_send] ""]} {
    proc unameit_send {code} {
	set ok [catch $code result]
	if {$ok == 0} {
	    set ok [catch unameit_commit err]
	    if {$ok != 0} {set result $err}
	} else {
	    if {[catch unameit_abort err]} {
		set result $err
	    }
	}
	if {$ok == 0} {
	    return $result
	}
	global errorCode errorInfo
	return -code $ok -errorinfo $errorInfo -errorcode $errorCode $result
    }
}
