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
# $Id: load_aliases.tcl,v 1.23.12.1 1997/08/28 18:29:03 viktor Exp $
#

#
# This script parses mail aliases files and produces mailing_list entries
# and mailing_list members. The mailing lists are owned by the default
# region. Members are dereferenced as much as possible (e.g. user_logins
# and hosts are looked up). If dereferencing fails, the entire string
# is used to generate an external address
#
# TBD - should error lines be discarded and/or logged?
# Currently we just give up, since error recovery from multiline formats
# is dubious.

source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB read_aliases.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

###########################################################################
#
# Make a mailing list in the given domain, if it is not already here.
# NOTE: User_logins are a form of mailing list.
# Return the oid of the mailing list if it is created.
# Return "" if this list is not needed.

proc make_mailing_list {datadir name} {
    global RegionOid OrgOid OidsInOrg forwardList

    # Look for a user login in the organization
    if {[lookup_mbox_oid $datadir mbox_oid $name OidsInOrg($OrgOid)]} {
	oid_heap_get_data_a $datadir F $mbox_oid
	if {[get_mailing_list_oid $datadir oid "$name-forward" $F(owner)]} {
	    if {[cequal $F(mailbox_route) $oid]} {
		set forwardList($oid) $mbox_oid
		return $oid
	    }
	}
	log_ignore "mailing list $name, found login or person"
	return ""
    }

    # See if it is already here
    if {[get_mailing_list_oid $datadir oid $name $RegionOid]} {
	log_ignore "mailing list $name, found list"
	return ""
    }
    
    set oid [oid_heap_create_l $datadir \
	    Class mailing_list \
	    owner $RegionOid \
	    name $name]
    return $oid
}



###########################################################################
#
# Make a mailing list member in the given mailing list
# member_and_comment is a list consisting of name and comment
#
proc make_member {datadir ml_oid member_and_comment ml_name} {
    global forwardList\
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    DomainNames CellNames RegionNames Orgnames \
	    OidsUpTree \
	    RegionOid OrgOid CellOid

    set F(Class) mailing_list_member
    set F(owner) $ml_oid
    lassign $member_and_comment member F(comment)
    #
    # See if this is thing@xyz.com
    # Reset org_oid if the location is found.
    #
    set known [lookup_location $datadir $member user l h domain_oid]

    #
    # Mailing lists and user logins must be in known domains.
    #
    if {$known && [cequal $h ""]} {
	#
	# Check for various objects,  or fall through to string code.
	#
	set org_oid $OrgOf($domain_oid)
	if {[lookup_mbox_oid $datadir oid $user OidsInOrg($org_oid)]} {
	    if {[info exists forwardList($ml_oid)]} {
		if {![cequal $oid $forwardList($ml_oid)]} {
		    if {[get_mailing_list_member_oid $datadir x $ml_oid $oid]} {
			return
		    }
		    set F(ml_member) $oid
		    oid_heap_create_a $datadir F
		    return
		}
	    } else {
		set F(ml_member) $oid
		oid_heap_create_a $datadir F
		return
	    }
	} elseif {[cequal $user $member] && \
		  [lookup_appsys_login_oid_by_name $datadir oid \
		      $user OidsUpTree($RegionOid)]} {
	    if {[info exists forwardList($ml_oid)]} {
		if {[get_mailing_list_member_oid $datadir junk $ml_oid $oid]} {
		    return
		}
	    }
	    set F(ml_member) $oid
	    #
	    oid_heap_create_a $datadir F
	    return
	} else {
	    if {![catch {dump_canon_attr mailing_list name $user} name] &&
		[get_mailing_list_oid $datadir oid $name $domain_oid]} {
	    # Avoid trivial loops
	    if {[cequal $ml_oid $oid]} return
	    if {[info exists forwardList($ml_oid)]} {
		if {[get_mailing_list_member_oid $datadir junk $ml_oid $oid]} {
		    return
		}
	    }
	    set F(ml_member) $oid
	    #
	    oid_heap_create_a $datadir F
	    return
	}}
    }

    # No need to explicitly include /dev/null on mailing lists.
    if {[cequal /dev/null $member]} {
	return
    }

    #
    # default is an external mail address! 
    #
    if {[catch {dump_canon_attr external_mail_address name $member} addr]} {
	log_ignore "mailing list $ml_name, unsupported external mail address"
	return
    }
    if {![get_address_oid $datadir oid $addr $RegionOid]} {
	set G(Class) external_mail_address
	set G(name) $addr
	set G(owner) $RegionOid
	set oid [oid_heap_create_a $datadir G]
    }
    if {[info exists forwardList($ml_oid)]} {
	if {[get_mailing_list_member_oid $datadir junk $ml_oid $oid]} return
    }
    set F(ml_member) $oid
    oid_heap_create_a $datadir F
    return
}

###########################################################################
#
# 

proc load_aliases {option} {

    upvar 1 $option options
    global \
	    CellOf OrgOf \
	    OidsInCell OidsInOrg \
	    DomainNames CellNames RegionNames Orgnames \
	    OidsUpTree \
	    RegionOid OrgOid CellOid

    set datadir 	$options(DataDir)
    set default_region	$options(Region)
    set aliases_file 	$options(AliasesFile)

    oid_heap_open $datadir

    get_domain_oids $datadir $default_region
    get_domain_oid $datadir rootoid .
    
    set fh [open $aliases_file r]

    while {[mgets $fh alias members]} {
	if {[catch {
	    set alias [dump_canon_attr mailing_list name $alias]
	}]} {
	    global errorCode
	    log_reject "$alias: $errorCode"
	    continue
	}
	log_debug "make alias $alias: $members"
	set ml_oid [make_mailing_list $datadir $alias]
	if {! [cequal "" $ml_oid]} {
	    # save it for later
	    set ml_members($ml_oid) $members
	    set ml_name($ml_oid) $alias
	}
    }
    close $fh

    foreach ml_oid [array names ml_members] {
	foreach member $ml_members($ml_oid) {
	    make_member $datadir $ml_oid $member $ml_name($ml_oid)
	}
    }
    oid_heap_close $datadir
}


if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {f	LoadOptions(AliasesFile)	$optarg} \
	    {r	LoadOptions(Region)  		$optarg} 
    check_options LoadOptions \
	    d DataDir \
	    f AliasesFile \
	    r Region
    check_files LoadOptions \
	    d DataDir \
	    f AliasesFile
} problem]} {
    puts $problem
    puts "Usage: unameit_load aliases \n\
	    \[ -W -R -C -I \] logging options \n\
	    -d data 	name of directory made by unameit_load copy_checkpoint \n\
	    -r region_name	name of this domain (e.g. mktng.xyz.com) \n\
	    -f aliases 	aliases file "
    exit 1
}

catch {unset TCLXENV(noDump)}
load_aliases LoadOptions
exit 0
