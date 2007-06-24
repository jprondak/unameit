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
# $Id: heap_to_html.tcl,v 1.6.10.1 1997/08/28 18:29:01 viktor Exp $
#

#
# Dump a heap into an html file for browsing.
# The OIDs used are currently the class and instance number, but
# this can easily be changed by setting OidName(oid).
#
source [unameit_filename UNAMEIT_LOADLIB load_common.tcl]
source [unameit_filename UNAMEIT_LOADLIB heap.tcl]

proc html_open {filename title} {
    set fh [open $filename w]
    puts $fh "<HTML><HEAD><TITLE>$title</TITLE></HEAD>"
    puts $fh "<BODY>"
    return $fh
}

proc html_close {fh} {
    puts $fh "</BODY></HTML>"
    close $fh
}

proc html_table_start {fh options caption} {
    puts $fh "<TABLE $options>"
    puts $fh "<CAPTION>$caption</CAPTION>"
}

proc html_table_finish {fh} {
    puts $fh "</TABLE>"
}

proc html_table_col {fh options} {
    foreach option $options {
	puts $fh "<COL $option>"
    }
}

proc html_table_thead {fh options} {
    puts -nonewline $fh "<THEAD><TR>"
    foreach option $options {
	puts -nonewline $fh "<TH>$option"
    }
    puts $fh "</TR></THEAD>"
}


proc html_dump_item {heap_dir fh p_item p_AttributeType p_OidName} {
    upvar 1 $p_item item \
	    $p_AttributeType AttributeType \
	    $p_OidName OidName

    set oid $item(Oid)
    set name $OidName($oid)
    html_table_start $fh "WIDTH=90% BORDER" "<A NAME=\"$name\">$name</A>"

    html_table_col $fh [list WIDTH=\"1*\" WIDTH=\"3*\"]

    html_table_thead $fh [list Attribute Value]

    puts $fh "<TBODY>"
    foreach field [lsort [array names item]] {

	switch -- $AttributeType($field) {
	    ObjectList {
		foreach oid $item($field) {
		    set name $OidName($oid)
		    if {[oid_get_class $heap_dir class $oid]} {
			puts $fh "<TR> <TD>$field <TD><A HREF=\"$class.html\#$name\">$name</A></TR>"
		    } else {
			puts $fh "<TR> <TD>$field <TD>$name</TR>"
		    }
		}
	    }

	    Object {
		set oid $item($field)
		if {! [cequal "" $oid]} {
		    set name $OidName($oid)
		    if {[oid_get_class $heap_dir class $oid]} {
			puts $fh "<TR> <TD>$field <TD><A HREF=\"$class.html\#$name\">$name</A></TR>"
		    } else {
			puts $fh "<TR> <TD>$field <TD>$name</TR>"
		    } 
		}
	    }

	    default {
		puts $fh "<TR> <TD>$field <TD>$item($field)</TR>"
	    }
	}
    }
    puts $fh "</TBODY>"
    puts $fh "<HR>"

    html_table_finish $fh
}

proc dump_items {heap_dir html_dir p_ClassOids p_AttributeType p_OidName} {
    upvar 1 $p_ClassOids ClassOids \
	    $p_AttributeType AttributeType \
	    $p_OidName OidName

    foreach class [lsort [array names ClassOids]] {

	catch {unset nameoid}
	foreach oid $ClassOids($class) {
	    set name $OidName($oid)
	    set nameoid($name) $oid
	}

	set fh [html_open [file join $html_dir $class.html] \
		"$class objects in UName*It"]
	puts $fh "<H3>$class objects in UName*It</H3>"

	foreach oidname [lsort [array names nameoid]] {
	    set oid $nameoid($oidname)
	    oid_heap_get_data_a $heap_dir item $oid
	    html_dump_item $heap_dir $fh item AttributeType OidName
	}

	html_close $fh
    }
}

proc dump_list {heap_dir html_dir p_ClassOids p_OidName} {
    upvar 1 $p_ClassOids ClassOids \
	    $p_OidName OidName

    set dump_index [file join $html_dir Index.html]
    set fh [html_open $dump_index "objects in UName*It"]

    foreach class [lsort [array names ClassOids]] {
	set oidnames {} 
	foreach oid $ClassOids($class) {
	    lappend oidnames $OidName($oid)
	}

	puts $fh "<H3>$class objects</H3>"
	puts $fh "<DIR>"
	foreach oidname [lsort $oidnames] {
	    puts $fh "<LI><A HREF=\"$class.html\#$oidname\">$oidname</A>"
	}
	puts $fh "</DIR>"
	puts $fh "<HR>"
    }
    html_close $fh
}

#
# See which fields are object, object list, or vanilla
#
proc get_attribute_types {p_ClassOids p_AttributeType} {
    upvar 1 $p_ClassOids ClassOids \
	    $p_AttributeType AttributeType

    catch {unset AttributeType}
    array set AttributeType [list \
	    Oid Plain \
	    uuid Plain \
	    Class Plain]

    foreach class [array names ClassOids] {
	foreach field [unameit_get_settable_attributes $class] {
	    if {[info exists AttributeType($field)]} {
		continue
	    }
	    set AttributeType($field) Plain
	    if {![cequal Object [unameit_attribute_type $field]]} continue
	    if {[cequal Scalar [unameit_get_attribute_multiplicity $field]]} {
		set AttributeType($field) Object
	    } else {
		set AttributeType($field) ObjectList
	    }
	}
    }
}

proc heap_to_html {option} {
    global HeapIndex OidHeap
    upvar 1 $option options

    set heap_dir $options(DataDir)
    set html_dir $options(HtmlDirectory)

    if {! [oid_heap_open $heap_dir]} {
	error "oid_heap_open failed"
    }

    set dbmcmd $HeapIndex($OidHeap($heap_dir))
    for {set more [$dbmcmd first oid]} {$more} {set more [$dbmcmd next oid]} {
	if {! [oid_get_class $heap_dir class $oid]} {
	    error "no class for $oid"
	}
	if {[info exists ClassOids($class)]} {
	    lappend ClassOids($class) $oid
	    incr classcount($class)
	} else {
	    set classcount($class) 1
	    set ClassOids($class) [list $oid]
	}

	#save class and instance number
	set OidNumber($oid) $classcount($class)
	set OidClass($oid) $class
	set OidName($oid) [format "%s %6d" $OidClass($oid) $OidNumber($oid)]
    }

    get_attribute_types ClassOids AttributeType

    # TBD set user friendly names in OidName
    #foreach oid $oids {
    #}

    oid_heap_get_classnames $heap_dir o2c
    array set OidName $o2c

    dump_list $heap_dir $html_dir ClassOids OidName

    dump_items $heap_dir $html_dir ClassOids AttributeType OidName

    oid_heap_close $heap_dir
}

if {[catch {
    get_options LoadOptions \
	    {d	LoadOptions(DataDir)		$optarg} \
	    {h  LoadOptions(HtmlDirectory)	$optarg}
    check_options LoadOptions \
	    d DataDir \
	    h HtmlDirectory
    check_files LoadOptions \
	    d DataDir 
} problem ]} {
    puts $problem
    puts "Usage: unameit_load dump_html \n\
	    -d data 	name of directory made by unameit_load copy_checkpoint \n\
	    -h directory	name of html directory"
    exit 1
}

make_directory $LoadOptions(HtmlDirectory)

heap_to_html LoadOptions
