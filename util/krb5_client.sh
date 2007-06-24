#! /bin/sh
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

# On a client machine, just install the configuration file.
#
set -e
set -u

mode=\${1-create}

path=$Krb5Paths(PATH)
PATH=\$path\${PATH:+:\$PATH}
libpath=$Krb5Paths(LD_LIBRARY_PATH)
LD_LIBRARY_PATH=\$libpath\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
SHLIB_PATH=\$libpath\${SHLIB_PATH:+:\$SHLIB_PATH}
export PATH LD_LIBRARY_PATH SHLIB_PATH

#
# If a previous installation exists, complain and quit. It is up to the
# installer to delete it.
#
if test -r $Krb5Setup(Client_Configuration_File)
then
	if test \$mode = delete
	then
	    rm \$f
	    exit 0
	else
	    echo $Krb5Setup(Client_Configuration_File) already exists.
	    echo Please remove it and execute this procedure again.
	exit 1
    fi
fi

#
# Copy configuration files to their destination
#

cat > $Krb5Setup(Client_Configuration_File) <<EndOfFile
$KrbConfig
EndOfFile

