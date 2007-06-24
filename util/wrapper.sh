#
# Wrapper template.
#
# $Id: $
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

unameit_lib=$UNAMEIT/lib
TCLLIBPATH="$unameit_lib/tcl/lib $unameit_lib/unameit"; export TCLLIBPATH
TCL_LIBRARY="$unameit_lib/tcl/lib/tcl"; export TCL_LIBRARY
TK_LIBRARY="$unameit_lib/tcl/lib/tk"; export TK_LIBRARY
TCLX_LIBRARY="$unameit_lib/tcl/lib/tclX"; export TCLX_LIBRARY
TKX_LIBRARY="$unameit_lib/tcl/lib/tkX"; export TKX_LIBRARY

###########################################################################
#
# Handle loadable library paths and executable paths
#
libpath="$unameit_lib/tcl/lib:$unameit_lib/unameit"

for subdir in unisqlx krb5 
do
    libpath=$libpath:$unameit_lib/$subdir/lib
done

# For most Unix systems with shared libraries
LD_LIBRARY_PATH=$libpath${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export LD_LIBRARY_PATH

# For HP
SHLIB_PATH=$libpath${SHLIB_PATH:+:$SHLIB_PATH}
export SHLIB_PATH

# Most OS's use PATH
path=$UNAMEIT/bin/exe:$UNAMEIT/sbin/exe:$UNAMEIT/lbin/exe:$UNAMEIT/lsbin/exe:/bin:/usr/bin:/sbin:/usr/sbin:/usr/etc
PATH=$path${PATH:+:$PATH}
export PATH
