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
# $Id: canon.tcl,v 1.61.10.3 1997/10/09 20:41:48 viktor Exp $
#

#
# The following are procedures that generate the canonicalization and
# validation functions. The generator functions also generate any syntax
# specific meta data, such as display procs for the integer syntax, etc.
#
proc unameit_create_syntax_proc\
    {pname aname amul partial_body null gen_interp} {
    #
    set lbrace "{"; set rbrace "}";
    #
    # Each body gets the variable attr set which is the attribute the
    # procedure is being generated for
    #
    append body "set attr [list $aname]\n"
    #
    switch -- $amul {
	Scalar {
	    append body "upvar 0 input value\n"
	}
	Set -
	Sequence {
	    #
	    # Check to see if input is a valid Tcl list
	    #
	    append body {
    		if {[catch {llength $input}]} {
		    unameit_error ENOTLIST $uuid $attr $input
		}
	        set canon_list {}
	    }
    	    # Use double quotes in the following appends because of the
    	    # unmatched Tcl braces.
	    append body {foreach value $input}
	    append body " $lbrace\n"
	    append body {switch -- [catch}
	    append body " $lbrace\n"
	}
    }
    if {[cequal $null Error]} {
	#
	append body {
	    switch -- $value "" {
		if {[cequal $style db]} {
		    unameit_error ENULL $uuid $attr
		} else {
		    return
		}
	    }
        }
	#
    }
    #
    append body $partial_body
    #
    switch -- $amul {
	Set -
	Sequence {
	    append body "$rbrace "
	    append body {output]}
	    append body " $lbrace\n"
	    append body {
		0 -
		2 {
		    lappend canon_list $output
		}
		1 {
		    global errorCode errorInfo
		    error $output $errorInfo $errorCode
		}
	    }
	    append body "$rbrace\n$rbrace\n"
	    append body {
		return $canon_list
	    }
	}
    }
    # 
    # The different conversion types can be "db", "query" or "display"
    #
    interp eval $gen_interp\
	    [list proc $pname {class uuid input style} $body]
}

proc unameit_integer_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set base $attribute_item(unameit_integer_attribute_base)
    set min $attribute_item(unameit_integer_attribute_min)
    set max $attribute_item(unameit_integer_attribute_max)
    set null $attribute_item(unameit_attribute_null)

    if {[cequal $null NULL]} {
	append body {switch -- $value "" return
	}
    }
    switch -- $base {
	Decimal {
	    #
	    append body {
		if {[scan $value %d%s ival rest] != 1} {
		    unameit_error ENOTINT $uuid $attr $value
		}
	    }
	    #
	}
	Octal -
	Hexadecimal -
	Any {
	    #
	    append body {
		# $ival != $value checks for floating point numbers
		if {[catch {expr int([list $value])} ival] || 
			$ival != $value} {
		    unameit_error ENOTINT $uuid $attr $value
   	      	}
	    }
	    #
	}
    }
    if {![cequal $min ""]} {
	#
	append body [format {
	    if {$ival < %d && [cequal $style db]} {
		unameit_error ETOOSMALL $uuid $attr $value %d
	    }
        } $min $min]
	#
    }

    if {![cequal $max ""]} {
	#
	append body [format {
	    if {$ival > %d && [cequal $style db]} {
		unameit_error ETOOBIG $uuid $attr $value %d
	    }

        } $max $max]
	#
    }
    switch -- $base {
        Octal {
    	    append body {
		if {[cequal $style display]} {
		    set ival [format "0%o" $ival]
		}
	    }
	}
        Hexadecimal {
    	    append body {
		if {[cequal $style display]} {
		    set ival [format "0x%x" $ival]
		}
	    }
	}
    }
    append body "return \$ival\n"
    unameit_create_syntax_proc $pname $aname $amul $body $null $gen_interp
}

proc unameit_vlist_syntax_gen_proc {pname attribute aname amul gen_interp} {
    #
    append body {
	if {[cequal $style db]} {
	    if {[catch {llength $value}]} {
		unameit_error ENOTLIST $uuid $attr $value
	    }
	    foreach entry $value {
		if {[catch {llength $entry} entry_len]} {
		    unameit_error EBADVLIST $uuid $attr $value
		}
		if {$entry_len < 1} {
		    unameit_error EBADVLIST $uuid $attr $value
		}
		switch -- [lindex $entry 0] {
		    !regexp -
		    regexp {
			if {$entry_len != 3} {
			    unameit_error EBADVLIST $uuid $attr $value
			}
			if {[catch [list regexp [lindex $entry 2] ""]]} {
			    unameit_error EBADVLISTREGEXP $uuid $attr $value
			}
		    }
		    regsub -
		    regsuball {
			if {$entry_len != 3} {
			    unameit_error EBADVLIST $uuid $attr $value
			}
			if {[catch [list regsub [lindex $entry 1] ""\
				[lindex $entry 2] junk]]} {
			    unameit_error EBADVLISTREGEXP $uuid $attr $value
			}
		    }
		    code {
			if {$entry_len != 2} {
			    unameit_error EBADVLIST $uuid $attr $value
			}
		    }
		    default {
			unameit_error EBADVLIST $uuid $attr $value
		    }
		}
	    }
	}
	return $value
    }
    #
    unameit_create_syntax_proc $pname $aname $amul $body NULL $gen_interp
}

proc unameit_string_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set minlen $attribute_item(unameit_string_attribute_minlen)
    set maxlen $attribute_item(unameit_string_attribute_maxlen)
    set case $attribute_item(unameit_string_attribute_case)
    set vlist $attribute_item(unameit_string_attribute_vlist)
    set null $attribute_item(unameit_attribute_null)

    set lbrace "{"; set rbrace "}"
    #
    switch -- $case {
	lower {
	    #
	    append body {
		set value [string tolower $value]
	    }
	    #
	}
	UPPER {
	    #
	    append body {
		set value [string toupper $value]
	    }
	    #
	}
    }
    #
    # XXX:  Older schema may have NULL minlen values,  map to zero.
    #
    switch -- $minlen "" {set minlen 0}
    append body "set minlen $minlen\n"
    #
    # XXX:  Older schema may have NULL maxlen values,  adjust
    # to match bound in metaschema.
    #
    switch -- $maxlen "" {set maxlen 255}
    append body "set maxlen $maxlen\n"
    #
    # If empty value is legal,  return here,  since regexp tests
    # may fail below.  We do not test compliance with non-zero "minlen"
    # until the string has passed through the validation list.
    #
    if {[cequal $null NULL] || $minlen == 0} {
	#
	append body {switch -- $value "" return
	}
	#
    }
    append body "
        if {\[cequal \$style db\]} $lbrace
    "
    foreach validation $vlist {
	set rest [lassign $validation type arg1 arg2]
	switch -- $type {
	    !regexp {
		append body "set errcode [list $arg1]\n"
		append body "set pattern [list $arg2]\n"
		append body {
		    if {[regexp -- $pattern $value]} {
			unameit_error $errcode $uuid $attr $value
		    }
		}
	    }
	    regexp {
		append body "set errcode [list $arg1]\n"
		append body "set pattern [list $arg2]\n"
		append body {
		    if {![regexp -- $pattern $value]} {
			unameit_error $errcode $uuid $attr $value
		    }
		}
	    }
	    regsub {
		append body "set pattern [list $arg1]\n"
		append body "set sub [list $arg2]\n"
		append body {
		    regsub -- $pattern $value $sub value
		}
	    }
	    regsuball {
		append body "set pattern [list $arg1]\n"
		append body "set sub [list $arg2]\n"
		append body {
		    regsub -all -- $pattern $value $sub value
		}
	    }
	    code {
		append body "$arg1\n"
	    }
	}
    }
    append body "
        $rbrace
    "
    #
    if {[cequal $null NULL] || $minlen == 0} {
	#
	append body {switch -- $value "" return
	}
	#
    }
    #
    if {$minlen > 0} {
	append body {
	    if {[cequal $style db]} {
		if {[string length $value] < $minlen} {
		    unameit_error ETOOSHORT $uuid $attr $value $minlen
		}
	    }
	}
    }
    #
    # Restrict query strings to twice the official limit.
    #
    append body {
	switch -- $style db {
	    if {[string length $value] > $maxlen} {
		unameit_error ETOOLONG $uuid $attr $value $maxlen
	    }
	} query {
	    if {[string length $value] > 511} {
		unameit_error ETOOLONG $uuid $attr $value 511
	    }
	}
    }
    #
    append body {
	return $value
    }
    if {[cequal $null NULL] || [cequal $minlen ""] || $minlen == 0} {
	unameit_create_syntax_proc $pname $aname $amul $body NULL $gen_interp
    } else {
	unameit_create_syntax_proc $pname $aname $amul $body Error $gen_interp
    }
}

proc unameit_address_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set octets $attribute_item(unameit_address_attribute_octets)
    set format $attribute_item(unameit_address_attribute_format)
    set null $attribute_item(unameit_attribute_null)

    #
    # Load dotted quad parsing routine into target interpreter.
    #
    interp eval $gen_interp\
	[list proc unameit_parse_dotted_quads {uuid attr value style len} {
	    set result ""
	    switch -- $style query {
		set wild 0
		foreach octet [split $value .] {
		    switch -- $octet * {
			incr wild
			continue
		    }
		    loop wild $wild 0 -1 {append result ??}
		    if {[scan $octet %d%s octet x] != 1 ||
			    $octet < 0 || $octet > 0xff} {
			unameit_error EINETNOTADDR $uuid $attr $value
		    }
		    append result [format "%02x" $octet]
		}
		if $wild {
		    append result\
			[replicate ? [expr $len - [clength $result]]]
		}
	    } default {
		foreach octet [split $value .] {
		    if {[scan $octet %d%s octet x] != 1 ||
			    $octet < 0 || $octet > 0xff} {
			unameit_error EINETNOTADDR $uuid $attr $value
		    }
		    append result [format "%02x" $octet]
		}
	    }
	    if {[clength $result] != $len} {
		unameit_error EINETNOTADDR $uuid $attr $value
	    }
	    return $result
	}]

    #
    # Load hex pattern parsing routine into target interpreter.
    #
    interp eval $gen_interp\
	[list proc unameit_parse_hex_query {uuid attr value clen} {
	    set result ""
	    foreach chunk [split $value :] {
		switch -- $chunk "" {
		    unameit_error EINETNOTADDR $uuid $attr $value
		}
		regsub -all {[*?]+\*} $chunk * chunk
		set stars [regsub -all {\*} $chunk {} digits]
		if {[set len [clength $digits]] > $clen} {
		    unameit_error EINETNOTADDR $uuid $attr $value
		}
		switch -- $stars {
		    0 {
			append result\
			    "[replicate 0 [expr $clen - $len]]$chunk"
		    }
		    1 {
			regsub {\*} $chunk\
			    [replicate ? [expr $clen - $len]] chunk
			append result $chunk
		    }
		    default {
			unameit_error EINETNOTADDR\
			    $uuid $attr $value
		    }
		}
	    }
	    switch -regexp -- $value {\*$} {
		regsub {\?+$} $result * result
	    }
	    return $result
	}]
    #
    if {[cequal $null NULL]} {
	#
	append body {switch -- $value "" return
	}
	#
    }
    append body "[list set octets $octets]\n"
    append body "[list set hexsize [expr 2 * $octets]]\n"
    #
    switch -- $format {
	MAC {
	    append body {
		if {[regexp : $value]} {
		    switch -- $style query {
			set value\
			    [unameit_parse_hex_query $uuid $attr $value 2]
		    } default {
			set newvalue {}
			foreach octet [split $value :] {
			    if {[scan $octet %x%s octet x] != 1 ||
				    $octet < 0 || $octet > 0xff} {
				unameit_error EINETNOTADDR\
				    $uuid $attr $value
			    }
			    append newvalue [format "%02x" $octet]
			}
			set value $newvalue
		    }
		}
	    }
	}
	IP {
	    append body {
		if {[regexp {\.} $value]} {
		    set value\
			[unameit_parse_dotted_quads\
			    $uuid $attr $value $style $hexsize]
		}
	    }
	}
	IPv6 {
	    #
	    # IPv6 with :: kruft and embedded IPv4
	    #
	    append body {
		if {[regexp : $value]} {
		    if {![regexp {(.*)::(.*)} $value junk head tail]} {
			set shorts [split $value :]
		    } else {
			set hcount [llength [set head [split $head :]]]
			set tcount [llength [set tail [split $tail :]]]
			if {$hcount == 0 && $tcount == 1} {
			    if {[regexp {\.} $tail]} {
				set tail\
				    [unameit_parse_dotted_quads\
					$uuid $attr $tail $style 8]
				regexp {^(....)(....)$} $tail x s1 s2
				set tcount 2
				set tail [list $s1 $s2]
			    }
			}
			set fill [replicate "0 "\
				    [expr $octets/2 - $hcount - $tcount]]
			set shorts [concat $head $fill $tail]
		    }
		    switch -- $style query {
			set value\
			    [unameit_parse_hex_query\
				$uuid $attr [join $shorts :] 4]
		    } default {
			set newvalue {}
			foreach short $shorts {
			    if {[scan $short %x%s short x] != 1 ||
				    $short < 0 || $short > 0xffff} {
				unameit_error EINETNOTADDR $uuid $attr $value
			    }
			    append newvalue [format "%04x" $short]
			}
			set value $newvalue
		    }
		}
	    }
	}
    }
    #
    # Should now be an octet string (hex digits)
    #
    append body {
	set value [string tolower $value]
	switch -- $style query {
	    set regexp {^[0-9a-f*?]*$}
	} default {
	    set regexp {^[0-9a-f]*$}
	}
	if {![regexp $regexp $value]} {
	    unameit_error EINETNOTADDR $uuid $attr $value
	}	
    }
    #
    append body {
	regsub -all {\*} $value {} digits
	switch -- $value $digits {
	    if {[clength $value] != $hexsize} {
		unameit_error EINETNOTADDR $uuid $attr $value
	    }
	} default {
	    regsub -all {[*?]+\*} $value * value
	    if {[clength $digits] > $hexsize} {
		unameit_error EINETNOTADDR $uuid $attr $value
	    }
	}
    }
    switch -- $format {
	Octet {
	    append body {
		return $value
	    }
	}
	MAC {
	    append body {
		if {![cequal $style display]} {return $value}
		set newvalue {}
		while {[regexp {(..)(.*)} $value junk byte value]} {
		    lappend newvalue [format "%x" 0x$byte]
		}
		return [join $newvalue :]
	    }
	}
	IP {
	    append body {
		if {![cequal $style display]} {return $value}
		set newvalue {}
		while {[regexp {(..)(.*)} $value junk byte value]} {
		    lappend newvalue [format %d 0x$byte]
		}
		return [join $newvalue .]
	    }
	}
	IPv6 {
	    append body {
		if {![cequal $style display]} {return $value}
		set newvalue {}
		set filling 0
		while {[regexp {(....)(.*)} $value junk short value]} {
		    if {[cequal $short 0000]} {
			switch -- $filling {
			    0 {
				set filling 1
				if {[cequal $newvalue {}]} {
				    lappend newvalue ""
				}
				lappend newvalue ""
				continue
			    }
			    1 continue
			}
		    } elseif {$filling == 1} {
			set filling 2
		    }
		    lappend newvalue [format "%x" 0x$short]
		}
		set result [join $newvalue :]
		if {[regexp {^::([0-9a-f]+):([0-9a-f]+)$} $result x s1 s2]} {
		    set result [format "::%d.%d.%d.%d"\
			[expr 0x$s1 >> 8] [expr 0x$s1 & 0xff]\
			[expr 0x$s2 >> 8] [expr 0x$s2 & 0xff]]
		}
		return $result
	    }
	}
    }
    unameit_create_syntax_proc $pname $aname $amul $body $null $gen_interp
}

proc uuidok {value} {
    expr {[regexp {^[0-9A-Za-z./]+$} $value] && [clength $value] == 22}
}

proc unameit_pointer_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set domain $attribute_item(unameit_pointer_attribute_domain)
    set null $attribute_item(unameit_attribute_null)
    #
    if {[cequal $null NULL]} {
	#
	append body {switch -- $value "" return
	}
	#
    }
    #
    append body {
	if {![uuidok $value]} {
	    unameit_error ENOTREFUUID $uuid $attr $value
	}
    }
    #
    append body {
	return $value
    }
    unameit_create_syntax_proc $pname $aname $amul $body $null $gen_interp
}

proc unameit_list_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set min_elems $attribute_item(unameit_list_attribute_min_elems)
    set max_elems $attribute_item(unameit_list_attribute_max_elems)
    set null $attribute_item(unameit_attribute_null)
    #
    append body {
	if {[catch {llength $value} listlen]} {
	    unameit_error ENOTLIST $uuid $attr $value
	}
    }
    #
    if {![cequal $min_elems ""]} {
	if {[cequal $null NULL]} {
	    #
	    append body {
		if {$listlen == 0} return
	    }
	    #
	}
	#
	append body [format {
	    if {[cequal $style db]} {
		if {$listlen < %d} {
		    unameit_error ELISTTOOSHORT $uuid $attr $value %d
		}
	    }
	} $min_elems $min_elems]
	#
    }
    if {![cequal $max_elems ""]} {
	#
	append body [format {
	    if {[cequal $style db]} {
		if {$listlen > %d} {
		    unameit_error ELISTTOOLONG $uuid $attr $value %d
		}
	    }
	} $max_elems $max_elems]
	#
    }
    append body {
	return $value
    }
    if {[cequal $null NULL] || [cequal $min_elems ""] || $min_elems == 0} {
	unameit_create_syntax_proc $pname $aname $amul $body NULL $gen_interp
    } else {
	unameit_create_syntax_proc $pname $aname $amul $body Error $gen_interp
    }
}

proc unameit_enum_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set enum_values $attribute_item(unameit_enum_attribute_values)
    set null $attribute_item(unameit_attribute_null)
    #
    append body "set enum_values [list $enum_values]\n"
    #
    if {[cequal $amul Scalar] && [cequal $null NULL]} {
	#
	# Map empty value to 0th list element for display,
	# empty string otherwise
	#
	append body {
	    switch -- $value "" {
		if {[cequal $style display]} {
		    return [lindex $enum_values 0]
		} else {
		    return
		}
	    }
	}
    }
    #
    append body {
	set i [lsearch -exact $enum_values $value]
	if {$i == -1 && [cequal $style db]} {
	    unameit_error EBADENUM $uuid $attr $value $enum_values
	}
    }
    if {[cequal $amul Scalar] && [cequal $null NULL]} {
	#
	# Map 0th element to empty string for nullable enums on server.
	#
	append body {
	    if {$i == 0 && ![cequal $style display]} {
		return ""
	    }
	}
    }
    append body {
	return $value
    }
    unameit_create_syntax_proc $pname $aname $amul $body $null $gen_interp
}

proc unameit_choice_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set null $attribute_item(unameit_attribute_null)
    set enum_values $attribute_item(unameit_enum_attribute_values)
    set minlen $attribute_item(unameit_string_attribute_minlen)
    set maxlen $attribute_item(unameit_string_attribute_maxlen)
    set case $attribute_item(unameit_string_attribute_case)
    set vlist $attribute_item(unameit_string_attribute_vlist)
    #
    append body "set enum_values [list $enum_values]\n"
    append body {
	set i [lsearch -exact $enum_values $value]
	if {$i >= 0} {
	    return $value
	}
    }
    #
    if {![cequal $minlen ""]} {
	if {[cequal $null NULL] || $minlen == 0} {
	    #
	    append body {switch -- $value "" return
	    }
	    #
	}
	#
	append body "set minlen $minlen\n"
	append body {
	    if {[cequal $style db]} {
		if {[string length $value] < $minlen} {
		    unameit_error ETOOSHORT $uuid $attr $value $minlen
		}
	    }
	}
	#
    }
    if {![cequal $maxlen ""]} {
	#
	append body "set maxlen $maxlen\n"
	append body {
	    if {[cequal $style db]} {
		if {[string length $value] > $maxlen} {
		    unameit_error ETOOLONG $uuid $attr $value $maxlen
		}
	    }
	}
	#
    }
    switch -- $case {
	lower {
	    #
	    append body {
		set value [string tolower $value]
	    }
	    #
	}
	UPPER {
	    #
	    append body {
		set value [string toupper $value]
	    }
	    #
	}
    }
    append body "
        if {\[cequal \$style db\]} \{
    "
    foreach validation $vlist {
	set rest [lassign $validation type arg1 arg2]
	switch -- $type {
	    !regexp {
		append body "set errcode [list $arg1]\n"
		append body "set pattern [list $arg2]\n"
		append body {
		    if {[regexp -- $pattern $value]} {
			unameit_error $errcode $uuid $attr $value
		    }
		}
	    }
	    regexp {
		append body "set errcode [list $arg1]\n"
		append body "set pattern [list $arg2]\n"
		append body {
		    if {![regexp -- $pattern $value]} {
			unameit_error $errcode $uuid $attr $value
		    }
		}
	    }
	    regsub {
		append body "set pattern [list $arg1]\n"
		append body "set sub [list $arg2]\n"
		append body {
		    regsub -- $pattern $value $sub value
		}
	    }
	    regsuball {
		append body "set pattern [list $arg1]\n"
		append body "set sub [list $arg2]\n"
		append body {
		    regsub -all -- $pattern $value $sub value
		}
	    }
	    code {
		append body "$arg1\n"
	    }
	}
    }
    append body "
        \}
    "
    append body {
	return $value
    }
    if {[cequal $null NULL] || [cequal $minlen ""] || $minlen == 0} {
	unameit_create_syntax_proc $pname $aname $amul $body NULL $gen_interp
    } else {
	unameit_create_syntax_proc $pname $aname $amul $body Error $gen_interp
    }
}

proc unameit_uuid_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set null $attribute_item(unameit_attribute_null)
    #
    append body {
	if {![uuidok $value]} {
	    unameit_error ENOTREFUUID $uuid $attr $value
	}
	return $value
    }
    #
    unameit_create_syntax_proc $pname $aname $amul $body $null $gen_interp
}

proc unameit_qbe_syntax_gen_proc {pname attribute aname amul gen_interp} {
    # XXX: How do you query for a stored query!?
    append body {
	if {[catch {llength $value}]} {
	    unameit_error ENOTLIST $uuid $attr $value
	}
	#
	# Stored queries only support the "-all" option
	#
	foreach elem $value {
	    switch -glob -- $elem {
		-all continue
		-* {
		    unameit_error EBADQBESYNTAX $uuid $attr $value
		}
		default {
		    break
		}
	    }
	}
	return $value
    }
    unameit_create_syntax_proc $pname $aname $amul $body Error $gen_interp
}

proc unameit_time_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set null $attribute_item(unameit_attribute_null)

    if {[cequal $null NULL]} {
	append body {switch -- $value "" return
	}
    }
    #
    append body {
	if {[scan $value %d%s ival rest] != 1} {
	    if {[catch {clock scan $value} ival]} {
		unameit_error ENOTTIME $uuid $attr $value
	    }
	}
	if {[cequal $style display]} {
	    set ival [clock format $ival]
	}
	return $ival
    }
    #
    unameit_create_syntax_proc $pname $aname $amul $body $null $gen_interp
}

proc unameit_text_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    #
    unameit_create_syntax_proc $pname $aname $amul {set value}\
	NULL $gen_interp
}

proc unameit_code_syntax_gen_proc {pname attribute aname amul gen_interp} {
    upvar #0 $attribute attribute_item
    set null $attribute_item(unameit_attribute_null)
    #
    append body {
	if {[catch {llength $value} listlen]} {
	    unameit_error ENOTLIST $uuid $attr $value
	}
	return $value
    }
    unameit_create_syntax_proc $pname $aname $amul $body NULL $gen_interp
}

proc unameit_autoint_syntax_gen_proc {args} {
    #
    # For validation autoints are just ints,  and their NULL
    # interpretation is always "NULL" (trigger enforced),  so just
    # run the integer gen proc.
    #
    eval unameit_integer_syntax_gen_proc $args
}
