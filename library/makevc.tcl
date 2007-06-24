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
    object_name pkgIndex.tcl
    object_type data
    directory_macro UNAMEIT_TCLLIB
}

target {
    object_name error.tcl
    object_type tcl_module
}

target {
    object_name esmlogo.gif
    object_type data
    directory_macro UNAMEIT_TOILIB
}

target {
    object_name config.dll
    object_type dll
    c_files {
        config.c
    }
    h_files {
        confproc.h
    }
    directory_macro UNAMEIT_TCLLIB
}

foreach t [list confproc] {
    target [list \
	object_name $t.h \
	object_type tcl_include \
	tcl_files $t.tcl \
    ]
}
