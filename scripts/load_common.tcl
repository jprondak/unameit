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
# $Id: load_common.tcl,v 1.5.12.1 1997/08/28 18:29:04 viktor Exp $
#

#
# Routines used by most of the loadup scripts.

###########################################################################
#
# This proc is used to sort region names by
# 1. number of .'s in the name
# 2. lexically

# Use this to determine a sorted set of names using the number of .'s in
# the name. This ordering is implied by
# 	ml.com
# is the parent of (e.g.)
#	sales.ml.com
# NOTE: . comes first

proc dots {a b} {
     regsub -all {(^\.|[^.])} $a {} da
     regsub -all {(^\.|[^.])} $b {} db 
     string compare "$da $a" "$db $b"
}


###########################################################################
#
# Split user@host.place.org into user and host.place.org
#
proc split_member {member p_person p_where} {
    upvar 1 $p_person person \
	    $p_where where
    set pieces [split $member @] 
    if {[llength $pieces] == 2} {
	lassign $pieces person where
	return 1
    }
    return 0
}


###########################################################################
#
# Get the caller-supplied options and the standard logging options.
# The caller's environment is used, so he has access to the settings
# of the logging options.
#
proc get_options {v args} {
    global argc argv
    # We need to do "upvar $v $v" because the options passed in in
    # the variable $args contains references to the variable named in "v".
    upvar 1 $v options $v $v

    #
    # Set up a list of standard options
    #
    set cmd [list getopt $argc $argv \
	    {W	options(LogWarnings)	1 } \
	    {I	options(LogIgnore)	1 } \
	    {R	options(LogReject)	1 } \
	    {C	options(LogCreate)	1 } \
	    {T	options(LogTrace)	1 } \
	    {D	options(LogDebug)	1 }]

    #
    # Append the callers option specs
    #
    lvarcat cmd $args

    #
    # Get the options for the caller
    #
    eval $cmd

    #
    # enable stacktrace
    #
    if {[info exists options(LogTrace)]} {
	global TCLXENV
	catch {unset TCLXENV(noDump)}
    }

    # 
    # Define the logging procedures
    #
    set optlist {
	LogWarnings 	log_warn 	Warning:	
	LogIgnore	log_ignore	Ignore:
	LogCreate	log_create	Create:
	LogReject	log_reject	Rejected:
	LogDebug	log_debug	Debug:		
    }

    foreach {option procname prefix} $optlist {
	if [info exists options($option)] {
	    set the_body [format {
		puts "%s $message"
	    } $prefix]
	} else {
	    set the_body ""
	}
	proc $procname {message} $the_body
    }
}

###########################################################################
#
# Check to see that all given arguments are supplied in the variable.
#
proc check_options {v args} {
    upvar 1 $v options 
    foreach {flag option} $args {
	if {! [info exists options($option)]} {
	    error "missing argument -$flag"
	}
    }
}

###########################################################################
#
# Check to see that the files exist.
#
proc check_files {v args} {
    upvar 1 $v options 
    foreach {flag option} $args {
	if {! [info exists options($option)]} {
	    error "missing argument -$flag"
	}
	if {! [file exists $options($option)]} {
	    error "file '$options($option)' does not exist"
	}
	if {! [file readable $options($option)]} {
	    error "file '$options($option)' is not readable"
	}
    }
}

proc dump_canon_attr {class attr value} {
    unameit_check_syntax $class $attr "" $value db
}

###########################################################################
#
# Remove the first component of an internet name. The name of the owner domain
# x.y.z is y.z. This is a strictly lexical function.
#
proc split_domain {full_name domain_name host_name} {
    upvar 1 $domain_name domain $host_name host

    # Split full_name on .
    set pieces [split $full_name .]

    # The first part is the host
    set host [lindex $pieces 0]

    # If thats all, we are done
    if {[llength $pieces] < 2} {
	return 0
    }

    set domain [join [lrange $pieces 1 end] .]
    return 1
}

###########################################################################
#
# Make a directory. if one already exists, mv it to a backup.
#
proc make_directory {name} {
    
    if {! [file exists $name]} {
	file mkdir $name
	return
    }

    set dirs [glob -nocomplain $name.*] 
    set max 0
    foreach dir $dirs {
	if {1 == [scan $dir $name.%d num]} {
	    if {$num > $max} {
		set max $num
	    }
	}
    }
    incr max
    file rename $name $name.$max
    file mkdir $name
}
