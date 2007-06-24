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
    name site_config
    object_name unameit.conf
    install_type client
    directory_macro UNAMEIT_INSTALL 
    object_type data
}

target {
    name host_config
    object_name unameit_root.conf
    install_type client
    object_type data
    directory_macro UNAMEIT_INSTALL 
}

target {
    object_name unameit_win.exe 
    object_type exe 
    install_type client 
    c_files {unameit_win.c winenv.c}
    rc_files {setup.rc}
    subsystem windows 
}

target {
    object_name configure_host.exe 
    object_type exe 
    install_type client 
    c_files {setup.c winenv.c}
    rc_files {setup.rc}
    subsystem windows 
}

#target {
#    object_name netuser.exe 
#    object_type exe 
#    c_files {netuser.c}
#    other_libraries {netapi32.lib}
#    subsystem console
#}

target {
    object_name uwish.exe 
    object_type exe 
    install_type client 
    c_files {uwish.c winenv.c}
    rc_files {setup.rc}
    subsystem windows 
    directory_macro ""
}

target {
    object_name unameit_setup.tcl
    object_type tcl_module
    install_type client
}

target {
    object_name textview.tcl
    object_type tcl_module
    install_type client 
}

target {
    object_name unameit_wm.exe 
    object_type exe 
    install_type client 
    c_files {unameit_wm.c winenv.c}
    rc_files {setup.rc}
    subsystem windows 
}

target {
    object_name unameit_con.exe 
    object_type exe 
    install_type client 
    c_files {unameit_con.c winenv.c}
    subsystem console 
}

target {
    object_name shortcut.dll
    object_type dll
    install_type client 
    c_files {shortcut.c}
    directory_macro UNAMEIT_TCLLIB
}

#target {
#    object_name user.dll
#    object_type dll
#    install_type client 
#    c_files {user.c}
#    other_libraries {netapi32.lib}
#    directory_macro UNAMEIT_TCLLIB
#}

target {
    object_name shortcuts.tcl
    install_type client
    object_type tcl_module
}

target {
    object_name wizard.tcl
    install_type client
    object_type tcl_module
}

