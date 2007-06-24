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
# See <unameit>/win/makevc.README
#
# Commands are:
#	clean
#	configure
#	make
#	install
#	runtime
#	trace

###########################################################################
#
# Delete an entire tree, leaving the empty directory.
#
proc deltree {dir} {
    foreach path [glob -nocomplain -- [file join $dir *]] {
	if [file isdirectory $path] {
	    deltree $path
	}
	file delete $path
    }
}

#
# return absolute native path to a build subdirectory
#
proc build_dir {{subdir ""}} {
    global Makevc
    file nativename [file join $Makevc(TmpShare) $Makevc(TmpTop) $subdir]
}

# 
# Write string out to the toplevel makefile.
#
proc make_out {s} {
    global Makevc
    if {! [info exists Makevc(Makefile)]} {
	set Makevc(Makefile) [open [file join $Makevc(TmpShare) \
		$Makevc(TmpTop) makefile] w]
    }
    puts $Makevc(Makefile) $s
}

#
# In a subdirectory, create a slave interpreter to process the local
# makevc.tcl file, producing a makefile. Save the names of any files
# to be installed.
#
proc makevc_subdir {subdir} {
    global MakevcProcs MakevcConfig ClientFiles ServerFiles UnameitFiles Makevc

    set maker [interp create]
    load {} Tclx $maker
    $maker eval $MakevcConfig
    $maker eval $MakevcProcs
    $maker eval set Targets 0
    $maker eval set Makevc(SubDir) $subdir
    $maker eval set Makevc(Trace) $Makevc(Trace)
    $maker eval {source [src_name makevc.tcl]}

    $maker eval process_targets

    foreach target [$maker eval array names UnameitFiles] {
	if {[info exists UnameitFiles($target)]} {
	    error "duplicate target name $target in directory $subdir"
	}
    }
    array set UnameitFiles [$maker eval array get UnameitFiles]
    array set ClientFiles [$maker eval array get ClientFiles]
    array set ServerFiles [$maker eval array get ServerFiles]
    interp delete $maker
}

#
# File mkdir is broken in tcl8.0b1; creating a UNC with a full path name
# fails. So we cd to the share and use a relative path.
#

proc makevc_copy_file {from to} {
    set dir [file dirname $to]
    file mkdir $dir
    file copy -force -- $from $to
}    

#
# Read the file containing a pattern list, then glob the patterns.
# Return the list of all files to be shipped. Directory names are
# not included.
#
proc ship_files {product source_dir dir} {
    global Makevc  
    set pattern_file [file join $Makevc(SourceShare) $Makevc(SourceTop) win ship-$product-$dir]
    pushd $source_dir
    set paths [source $pattern_file]
    popd
    return [lsort $paths]
}

proc copy_file {from to} {
    announce $from
    if {[file exists $to]} {
	error "$to already exists"
    }
    file mkdir [file dirname $to]
    file copy -- $from $to
}

proc makevc_runtime {} {
    global Makevc MakevcSourceDirs env
    cd $Makevc(DestShare)
    file mkdir $Makevc(DestTop)
    cd $Makevc(DestTop)
    
    # copy selected dlls and exes to bin directory
    file mkdir bin
    pushd bin
    foreach {name source_dir} [array get MakevcSourceDirs] {
	foreach path [ship_files $name $source_dir bin] {
	    copy_file [file join $source_dir $path] [file tail $path]
	}
    }
    set path [file join $env(SystemRoot) system32 msvcrt.dll]
    copy_file $path [file tail $path]
    popd

    # copy selected files from the trees
    file mkdir lib
    pushd lib
    foreach {name source_dir} [array get MakevcSourceDirs] {
	file mkdir $name
	deltree $name
	pushd $name
	foreach path [ship_files $name $source_dir lib] {
	    copy_file [file join $source_dir $path] $path
	}
	popd
    }
    popd

    return
}

###########################################################################

# default just reports configuration
set commands $argv

set UNAMEIT [file dirname $argv0]
set MakevcProcs [read_file $UNAMEIT/makevc_procs.tcl]
set MakevcConfig [read_file $UNAMEIT/makevc_config.tcl]

eval $MakevcConfig

cd $Makevc(TmpShare)
cd $Makevc(TmpTop)

set wsource [file nativename [file join $Makevc(SourceShare) $Makevc(SourceTop)]]
set wbuild [file nativename [pwd]]
set winstall [file nativename [file join $Makevc(DestShare) $Makevc(DestTop)]]
set version [string trim [read_file [file join $wsource version]]]

puts "UName*It version:  $version"
puts "Source directory:  $wsource"
puts "Build directory:   $wbuild"
puts "Install directory: $winstall"

#
# Actually, we could build in the source tree, but 'clean' would
# remove the source files. Also, frink targets have the same name
# as source files (no .frink is used in the rules).
#
if {[cequal $wsource $wbuild]} {
    error "Do not build in the source tree."
}

foreach command $commands {

    switch -- $command {
	clean {
	    cd $Makevc(TmpShare)
	    deltree $Makevc(TmpTop)
	    puts "cleaned"
	}

	configure {
	    cd $wbuild
	    # Write out the version header.
	    file mkdir include
	    pushd include
	    set template [read_file [file join $wsource include version.h.in]]
	    regsub -- {@UNAMEIT_VERSION@} $template $version header
	    write_file version.h $header
	    write_file arith_types.h "/* arith_types.h not used on Windows */\n"
	    popd

	    # Set array of unameit files. This gets copied to unameit_files.dat
	    array set UnameitFiles [array get MakevcInstallDirs]
	    set UnameitFiles(wishx) [file join bin wishx.exe]
	    set UnameitFiles(tcl) [file join bin tcl.exe]

	    # Process each subdirectory
	    foreach subdir $Makevc(Subdirs) {
		file mkdir $subdir
		pushd $subdir
		announce [pwd]
		makevc_subdir $subdir
		popd
	    }

	    # We go to the top, then the subdirectory. 
	    make_out "all : "
	    foreach subdir $Makevc(Subdirs) {
		make_out "\tcd [build_dir $subdir]"
		make_out "\tnmake/nologo"
	    }
	    make_out ""

	    close $Makevc(Makefile)

	    write_file unameit_files.dat [array get UnameitFiles]
	    write_file unameit_client_files.dat [array get ClientFiles]
	    write_file unameit_server_files.dat [array get ServerFiles]

	    puts "configured"
	}
	
	install -
	install_client {
	    cd $wbuild
	    catch {unset UnameitFiles}
	    array set UnameitFiles [read_file unameit_files.dat]
	    set ObjectFiles [read_file unameit_client_files.dat]

	    cd $Makevc(DestShare)
	    file mkdir $Makevc(DestTop)
	    cd $Makevc(DestTop)
	    announce "installing in [pwd]"
	    foreach {key dir} [array get MakevcInstallDirs] {
		file mkdir $dir
	    }

	    foreach {target from} $ObjectFiles {
		set to $UnameitFiles($target)
		file copy -force -- $from $to
		announce "$from -> $to"
	    }
	    set to [dest_relname UNAMEIT_INSTALL unameit_files.dat]
	    write_file $to [array get UnameitFiles]
	    puts "installed"
	}

	runtime -
	runtime_client {
	    makevc_runtime
	    puts "runtime made"
	}

	make {
	    set make [auto_execok nmake]
	    if {$make == ""} {
		error "nmake is not on your path"
	    }
	    if {$Makevc(Trace)}  {
		exec $make /nologo >@stdout 2>@stderr
	    } else {
		exec $make /nologo 
	    }
	    puts "made"
	}

	trace {
	    set Makevc(Trace) 1
	}

	notrace {
	    set Makevc(Trace) 0
	}

	default {
	    error "bogus command $command"
	}
    }
}
