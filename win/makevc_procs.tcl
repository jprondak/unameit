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
# Procedures available to the makevc interpreter.
# Only 'target' should be in makevc.tcl, the rest of these procedures will
# be run in the interpreter's namespace by the master interpreter.
# Then the interpreter will be deleted to clean up variables.
#
proc util_script {name} {
    global Makevc
    file join $Makevc(SourceShare) $Makevc(SourceTop) util $name
}

#
# This procedure saves the name of the target in either ClientTargets or
# ServerTargets depending on the install_type of the target. If a target
# is installed, the full path of source will be saved in
# either ClientFiles or ServerFiles. The path relative to the top will
# be saved in UnameitFiles.
#
# This procedure is called after the target has been processed, since
# processing the target may determine whether there is a manufactured
# object to be processed (i.e. target(copy_from_source) is true).
#
# NOTES: 
# 1. to keep a target from being installed, specify a directory_macro
#    of "". 
# 2. to install a target with a different name, specify a new_name.
#


proc check_type {target_name} {
    global ClientTargets ServerTargets Makevc ClientFiles ServerFiles UnameitFiles

    upvar #0 $target_name target

    switch -- $target(install_type) {
	client {
	    upvar #0 ClientFiles from
	    lappend ClientTargets $target(name)
	}
	server {
	    upvar #0 ServerFiles from
	    lappend ServerTargets $target(name)
	}
	default {
	    error "target $target(name) must be client or server install_type"
	}
    }

    #
    # Installed exe's and dll's have standard locations.
    # libs and tcl_includes are not installed.
    #
    if {! [info exists target(directory_macro)]} {
	switch -- $target(object_type) {
	    dll -
	    exe {
		set target(directory_macro) UNAMEIT_BIN
	    }

	    tcl_module -
	    wish_script -
	    tcl_script {
		set target(directory_macro) UNAMEIT_TCLLIB
	    }
	    
	    tcl_include -
	    lib {
		set target(directory_macro) ""
	    }
	}
    }

    #
    # Targets with empty directory_macro are not installed.
    #
    if {[cequal "" $target(directory_macro)]} {
	announce "$target(name) is not installed"
	return
    }

    set uname $target(name)

    set oname $target(object_name)
    if {[info exists target(new_name)]} {
	set oname $target(new_name)
    }

    if {$target(copy_from_source)} {
	set from($uname) [src_name $target(object_name)]
    } else {
	set from($uname) [obj_name $target(object_name)]
    }

    set UnameitFiles($uname) [dest_relname $target(directory_macro) $oname]
    announce "$from($uname) -> $UnameitFiles($uname)"
}
  
proc make_out {string} {
    global Makevc
    puts $Makevc(Makefile) $string
}

#
# Create a target from the given parameters.
# Some defaults are filled in.
#
proc target {lparams} {
    global Targets 

    incr Targets
    upvar #0 Target$Targets target

    set target(install_type) client 
    set target(copy_from_source) 0
    set target(frink) 0

    array set target $lparams

    if {! [info exists target(name)]} {
	set target(name) [file root $target(object_name)]
    }
}

proc c2obj {files} {
    set objs {}
    foreach c $files {
	regsub -nocase -- {.c$} $c .obj obj
	lappend objs $obj
    }
    return $objs
}

proc rc2res {files} {
    set ress {}
    foreach rc $files {
	regsub -nocase -- {.rc$} $rc .res res
	lappend ress $res
    }
    return $ress
}

#
# Process a data object. Set the flag indicating a copy from 
# source.
#
proc process_data {target_name} {
    global Makevc ObjectsDone
    upvar #0 $target_name target

    set target(copy_from_source) 1
}

#
# Process a tcl script. 
#
proc process_tcl_script {target_name} {
    upvar #0 $target_name target
    if {$target(frink)} {
	process_frinked_module $target_name 
    } else {
	process_data $target_name  
    }
}

#
# Process a wish script.
#
proc process_wish_script {target_name} {
    upvar #0 $target_name target
    if {$target(frink)} {
	process_frinked_module $target_name 
    } else {
	process_data $target_name 
    }
}

#
# Process a tcl module. 
#
proc process_tcl_module {target_name} {
    upvar #0 $target_name target
    if {$target(frink)} {
	process_frinked_module $target_name 
    } else {
	process_data $target_name
    }
}

#
# A frinked file is a tcl module with some obfuscatory processing
# applied.
#
proc process_frinked_module {target_name} {
    global Makevc ObjectsDone MakevcCommands
    upvar #0 $target_name target

    set frink $MakevcCommands(frink)
    set dumpprocs "$MakevcCommands(tcl) [util_script dumpprocs]"
    set tcl2c "$MakevcCommands(tcl) [util_script tcl2c]"

    foreach f $target(tcl_files) {
	append tcl_files [src_name $f] " "
    }
    set name $target(name)
    set obj_file $target(object_name)

    if {[info exists ObjectsDone($obj_file)]} {
	continue
    } else {
	set ObjectsDone($obj_file) 1
    }
    make_out "$obj_file : $tcl_files"
    make_out "\t$dumpprocs $tcl_files | $frink > $obj_file"
    make_out ""
}

#
# Process TCL files to make a header. 
#
proc process_tcl_include {target_name} {
    global Makevc ObjectsDone MakevcCommands
    upvar #0 $target_name target

    set frink $MakevcCommands(frink)
    set dumpprocs "$MakevcCommands(tcl) [util_script dumpprocs]"
    set tcl2c "$MakevcCommands(tcl) [util_script tcl2c]"

    foreach f $target(tcl_files) {
	append tcl_files [src_name $f] " "
    }
    set name $target(name)
    set obj_file $target(object_name)

    if {[info exists ObjectsDone($obj_file)]} {
	continue
    } else {
	set ObjectsDone($obj_file) 1
    }
    make_out "$obj_file : $tcl_files"
    make_out "\t$dumpprocs $tcl_files |$frink > $obj_file.1"
    make_out "\t$tcl2c $name $obj_file.1 > $obj_file"
    make_out ""
}

#
# Process c_files in a target.
# Use precompiled header file with name based on target.
# Each object in an exe or lib uses the precompilation; there may be
# multiple targets in a directory. For this reason, all object files
# depend on the h_files.
#
proc process_c_files {target_name c_flags} {
    global Makevc ObjectsDone MakevcCommands
    upvar #0 $target_name target

    set name $target(name)
    set c $MakevcCommands(c)
    append c_flags " /I. /I[src_name .] /I [obj_dir include] " {$(INCLUDES)}
    catch {append c_flags " $target(other_includes)"}
    append c_flags "  /Fp$name /Fd$name /c"

    if {[info exists target(h_files)]} {
	foreach h $target(h_files) {
	    append h_files $h " "
	}
    } else {
	set h_files ""
    }
    foreach cf $target(c_files) {
	set c_file [src_name $cf]
	set obj_file [c2obj $cf]
	if {[info exists ObjectsDone($obj_file)]} {
	    continue
	} else {
	    set ObjectsDone($obj_file) 1
	}
	make_out "$obj_file : $c_file $h_files"
	make_out "\t$c $c_flags /Fo$obj_file $c_file"
	make_out ""
    }
}

#
# Process rc_files in a target.
# There may be none listed; if so we just return.
#
proc process_rc_files {target_name} {
    global Makevc ObjectsDone
    upvar #0 $target_name target

    if {! [info exists target(rc_files)]} return

    set name $target(name)
    set rc "rc.exe"
    foreach cf $target(rc_files) {
	set rc_file [src_name $cf]
	set res_file [rc2res $cf]
	if {[info exists ObjectsDone($res_file)]} {
	    continue
	} else {
	    set ObjectsDone($res_file) 1
	}
	make_out "$res_file : $rc_file"
	make_out "\t$rc /Fo$res_file $rc_file"
	make_out ""
    }
}

proc process_exe {target_name} {
    global Makevc ObjectsDone
    upvar #0 $target_name target
    set subdir $Makevc(SubDir)
    set exe $target(object_name)
    set objs [c2obj $target(c_files)]
    catch {append objs " " [rc2res $target(rc_files)]}
    set name $target(name)
    set libs {$(TCLLIBS) $(WINLIBS) }
    catch {append libs " " $target(other_libraries)}
    set deplibs {}
    catch {append deplibs " " [lib_name $target(dependent_libraries)]}
    set link "link.exe/nologo"
    set link_flags {$(EXE_LINKFLAGS)}
    switch -- $target(subsystem) {
	windows -
	console {
	    append link_flags " /subsystem:$target(subsystem)"
	}
	default {
	    error "invalid subsystem $target(subsystem)"
	}
    }
	
    make_out "$exe : $objs $deplibs"
    make_out "\t$link /out:$exe @<<"
    make_out "\t\t$link_flags $objs $deplibs $libs"
    make_out "<<\n"

    set c_flags {$(EXE_CPP_FLAGS)}
    process_c_files $target_name $c_flags
    process_rc_files $target_name
}

#
# Process a DLL.
#
proc process_dll {target_name} {
    global Makevc ObjectsDone
    upvar #0 $target_name target

    set lib $target(object_name)
    set objs [c2obj $target(c_files)]
    catch {append objs " " [rc2res $target(rc_files)]}
    set name $target(name)
    set link link.exe/nologo
    set libs {$(TCLLIBS) $(WINLIBS)}
    catch {append libs " " $target(other_libraries)}
    set deplibs {}
    catch {append deplibs " " [lib_name $target(dependent_libraries)]}
    set link_flags {$(DLL_LINK_FLAGS)}
    make_out "$lib : $objs $deplibs"
    make_out "\t$link  /out:$lib @<<"
    make_out "\t\t$link_flags $objs $deplibs $libs"
    make_out "<<\n"

    set c_flags {$(DLL_CPP_FLAGS)}
    process_c_files $target_name $c_flags
    process_rc_files $target_name
}

#
# Process a lib.
#
proc process_lib {target_name} {
    global Makevc ObjectsDone
    upvar #0 $target_name target

    set lib $target(object_name)
    set objs [c2obj $target(c_files)]
    catch {append objs " " [rc2res $target(rc_files)]}
    set link "link.exe -lib /nologo"
    set link_flags {$(LIB_LINK_FLAGS)}

    make_out "$lib : $objs"
    make_out "\t$link @<<"
    make_out "\t\t$link_flags $objs /out:$lib"
    make_out "<<"

    set c_flags {$(LIB_CPP_FLAGS)}
    process_c_files $target_name $c_flags
    process_rc_files $target_name
}

proc fix_filenames {s} {
    regsub -all -- / $s \\ x
    return $x
}

proc process_targets {} {
    global Targets Makevc MakevcMacros \
	    ClientTargets ServerTargets \
	    ClientFiles ServerFiles
    
    set Makevc(Makefile) [open makefile w]

    foreach line [split $MakevcMacros "\n"] {
	make_out [string trim $line]
    }

    make_out "all : client server"
    make_out ""
    # Compile and link
    for {set x 1} {$x <= $Targets} {incr x} {
	set t Target$x
	upvar #0 $t target
	make_out "# Target $x, $target(name)"

	set type $target(object_type)
	if {[cequal process_$type [info procs process_$type]]} {
	    process_$type $t
	} else {
	    error "invalid target type $type"
	}

	if {! [cequal $target(name) $target(object_name)]} {
	    if {$target(copy_from_source)} {
		make_out "$target(name) : [src_name $target(object_name)]"
	    } else {
		make_out "$target(name) : $target(object_name)"
	    }
	    make_out ""
	}
    }

    # classify targets for 'make client' and 'make server'
    set ClientTargets {}
    set ServerTargets {}
    for {set x 1} {$x <= $Targets} {incr x} {
	check_type Target$x
    }
	
    make_out "client : $ClientTargets"
    make_out ""
    make_out "server : $ServerTargets"
    make_out ""

    close $Makevc(Makefile)
}    
   
package require MakevcConfig
