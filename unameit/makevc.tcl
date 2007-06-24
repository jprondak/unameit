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

target {
    object_name fancylb.tcl
    install_type client
    object_type tcl_script
}

# 
# We run the toi through frink.
#
target {
    object_name toi.tcl
    install_type client
    object_type tcl_module
    tcl_files toi.tcl
    directory_macro UNAMEIT_TOILIB
    frink 1
}

target {
    dependent_libraries {
	libcache_mgr libcanon libconn 
	libordered_list libschema_mgr
    }
    object_name unameit.exe 
    object_type exe 
    install_type client 
    c_files winMain.c
    h_files bootstrap.h
    subsystem windows 
}

target {
    object_name bootstrap.h
    install_type client 
    object_type tcl_include
    tcl_files {bootstrap.tcl menubar8.tcl}
}
