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
# Read a config file, ignoring comment lines.
# Put the values into the named variable.
# This routine is used by the mode editing commands as well as 
# unameit_getconfig.
#
proc read_config_file {vn priority filename} {
    upvar 1 $vn config

    set Applications All
    set Modules All
    for_file line $filename {
	set line [string trim $line]
	if {[cequal "" $line]} continue
	if {[cequal # [cindex $line 0]]} continue
	if {! [regexp -- "(\[^ \t\]*)(.*)" $line junk param value]} continue
	set value [string trim $value]

	switch -- $param {
	    Applications {
		set Applications $value
		set Modules All
	    }
	    Modules {
		set Modules $value
	    }

	    default {
		# Explode the matrix
		foreach app $Applications {
		    foreach module $Modules {
			set field $priority/$app/$module/$param
			set config($field) $value
		    }   
		}
	    }
	}
    }
}

#
# TBD - clear env of all but a few, needed variables.
#
# We return optind if processing commandline options. This is currently
# turned off, so we just return 0.
#
# This proc is given the name of a variable and the default application
# name. The data from the configuration files is stored in the named
# array. The app name will be stored as $vn(application), and will be
# used by unameit_config as a default. 
#
proc unameit_getconfig {vn app {class Unameit}} {
    global env argc argv tcl_platform TCLXENV

    upvar 1 $vn config

    #
    # Set up list of configuration files based on euid and UNAMEIT_MODE.
    #
    foreach envar [list UNAMEIT_ETC UNAMEIT_MODE UNAMEIT] {
	if {![info exists env($envar)]} {
	    error "$envar must be set in the environment" {} {UNAMEIT ENOMODE}
	}
	global $envar
	set $envar $env($envar)
    }

    # Sitewide file, in software tree
    set sitefile [unameit_filename UNAMEIT_CONFIG $UNAMEIT_MODE.conf]

    # Overrides for root users or for personal config items
    if {($tcl_platform(platform) == "unix") && (0 == [id userid])} {
	set userfile [file join $UNAMEIT_ETC $UNAMEIT_MODE.conf]
    } else {
	set userfile [file join ~ .unameit $UNAMEIT_MODE.conf]
    }

    #
    # Read sitewide configuration file, then the user-specific one.
    # The sitewide configuration file is mandatory.
    #
    if {[file readable $sitefile]} {
	read_config_file config site $sitefile 
    } else {
	error "site configuration file $sitefile could not be read"
    }
    if {[file readable $userfile]} {
	read_config_file config user $userfile 
    } 

    set config(application) $app
    set config(class) $class
    set config(unameit_mode) $UNAMEIT_MODE
    #
    # May not be set, but then presumably not needed. Must never default!
    #
    set data_dir [unameit_config_f config 1 data "" "" "" ""]
    if {[string compare $data_dir ""]} {
	global UNAMEIT_DATA
	set UNAMEIT_DATA $data_dir
    }

    if {[unameit_config_flag config stacktrace]} {
	if {[info exists TCLXENV(noDump)]} {
	    unset TCLXENV(noDump)
	}
    } else {
	set TCLXENV(noDump) 1
    }

    # We return optind if processing commandline options
    return 0
}

#
# Return the configured setting of the parameter. Module is optional.
# The default application (set during unameit_getconfig) will be used 
# unless overridden. This allows applications to query the settings for
# other applications.
#
# The highest priority setting is that of the parameter 
# (not app/module/param). Any setting made by the application itself
# will override the configuration. This should be done with care
# since it usually defeats the purpose of configuration ;-)
#
proc unameit_config {vn param {module ""} {app ""} {class ""}} {
    upvar 1 $vn config
    
    if {[info exists config($param)]} {
	return $config($param)
    }

    if {[cequal "" $app]} {
	set app $config(application)
    }

    if {[cequal "" $class]} {
	set class $config(class)
    }

    foreach priority [list user site] {
	foreach name [list \
		$priority/$app/$module/$param \
		$priority/$app/All/$param \
		$priority/$class/$module/$param \
		$priority/$class/All/$param \
		$priority/All/$module/$param \
		$priority/All/All/$param \
		] {
	    if {[info exists config($name)]} {
		return $config($name)
	    }
	}
    }

    error "parameter $param not set (app '$app', module '$module')"
}

#
# internal utility routine
#
proc unameit_config_f {vn level param default module app class} {
    upvar $level $vn config
    
    if {[info exists config($param)]} {
	return $config($param)
    }

    if {[cequal "" $app]} {
	set app $config(application)
    }

    if {[cequal "" $class]} {
	set class $config(class)
    }

    foreach priority [list user site] {
	foreach name [list \
		$priority/$app/$module/$param \
		$priority/$app/All/$param \
		$priority/$class/$module/$param \
		$priority/$class/All/$param \
		$priority/All/$module/$param \
		$priority/All/All/$param \
		] {
	    if {[info exists config($name)]} {
		return $config($name)
	    }
	}
    }
     
    return $default
}

#
# Return a label. If not defined, the parameter name is capitalized
# and returned.
#
proc unameit_config_label {vn param {module ""} {app ""} {class ""}} {
    set default [string toupper [string range $param 0 0]]
    append default [string range $param 1 end]
    unameit_config_f $vn 2 $param.label $default $module $app $class
}

#
# If the field is defined secret, return true. E.g. a password
# field may be configured to show *'s if it is secret.
#
proc unameit_config_secret {vn param {module ""} {app ""} {class ""}} {
    unameit_config_f $vn 2 $param.secret 0 $module $app $class
}

# 
# Should the field appear on the form or be hidden from the user?
#
proc unameit_config_hidden {vn param {module ""} {app ""} {class ""}} {
    unameit_config_f $vn 2 $param.hidden 0 $module $app $class
}

# 
# Should the field be readonly?
#
proc unameit_config_readonly {vn param {module ""} {app ""} {class ""}} {
    unameit_config_f $vn 2 $param.readonly 0 $module $app $class
}

#
# Is a flag set? The default is 0 if it is not present.
#
proc unameit_config_flag {vn param {module ""} {app ""} {class ""}} {
    unameit_config_f $vn 2 $param 0 $module $app $class
}

#
# Get a mandatory parameter. If it is not set, or if it is empty,
# generate an error.
#
proc unameit_config_ne {vn param {module ""} {app ""} {class ""}} {
    set p [unameit_config_f $vn 2 $param "" $module $app $class]
    if {[cequal "" $p]} {
	error "parameter $param is empty (app '$app', module '$module')"
    }
    return $p
}

#
# Copy all non-module dependent values from a configuration to
# an array.
#
proc unameit_configure_app {vn vout} {
    upvar 1 $vn config
    upvar 1 $vout priv

    set app $config(application)
    set class $config(class)

    foreach {getpat keypat} [list \
	    site/All/All/* 	"^site/All/All/(.*)" \
	    site/$class/All/* 	"^site/$class/All/(.*)" \
	    site/$app/All/* 	"^site/$app/All/(.*)" \
	    user/All/All/* 	"^user/All/All/(.*)" \
	    user/$class/All/* 	"^user/$class/All/(.*)" \
	    user/$app/All/* 	"^user/$app/All/(.*)" \
	    ] {
	foreach {name value} [array get config $getpat] {
	    if {[regexp -- $keypat $name junk key]} {
		set priv($key) $value
	    }
	}
    }
}	

#
# Returns the name using macros defined in pre.mk.in, used
# during the building of unameit, plus $env(UNAMEIT), the root of
# the installed software directory. These filenames are usable by tcl,
# not necessarily by native programs. Use unameit_nativename to get
# the platform version of the file.
#
# An error will occur if macro is not a unameit installation directory.
#
# Examples:
#
#	unameit_filename UNAMEIT_TCLLIB config.so
#
# returns on unix
#
# 	/opt/unameit/lib/unameit/config.so
#
# and on windows
#
#	//server/unameit/lib/unameit/config.so
#
# But on windows unameit_nativename will return
#
#	\\server\unameit\lib\unameit\config.so
#
proc unameit_file {file} {
    global unameit_config_files env
    if {! [array exists unameit_config_files]} {
	set fname [file join $env(UNAMEIT) install unameit_files.dat]
	array set unameit_config_files [read_file $fname]
	set unameit_config_files(UNAMEIT) $env(UNAMEIT)
	set unameit_config_files(UNAMEIT_ETC) $env(UNAMEIT_ETC)
    }
    if {! [info exists unameit_config_files($file)]} {
	error "$file is not a UName*It file"
    }
    list $unameit_config_files(UNAMEIT) $unameit_config_files($file)
}

proc unameit_filename {file args} {
    eval file join [unameit_file $file] $args
}

proc unameit_nativename {file args} {
    file nativename [eval file join [unameit_file $file] $args]
}


#
# Take any unisqlx/ module parameters and put them into environment
# variables. Define UNISQLX according to the build-time definition.
#
proc unameit_configure_unisqlx {vn} {
    upvar 1 $vn config
    global env

    set app $config(application)
    set class $config(class)
    foreach pattern [list user/All/unisqlx/* \
	    user/$class/unisqlx/* \
	    user/$app/unisqlx/*] {
	foreach {name value} [array get config $pattern] {
	    set key [string toupper [lindex [split $name /] end]]
	    set ename UNISQLX_$key
	    #
	    # Convert numeric values ending in KB to pages,
	    # and propagate new value back to config array.
	    #
	    if {[regexp {^([0-9]+)KB$} $value x value]} {
		set value [expr {$value / ([unameit_config_pagesize] / 1024)}]
		set config($name) $value
	    }
	    set env($ename) $value
	}
    }
    set env(UNISQLX) [unameit_filename UNAMEIT_UNISQLX]
    if {! [info exists env(HOME)]} {
	set env(HOME) /
    }
}	
