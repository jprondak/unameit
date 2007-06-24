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
# If a previous KDC exists, complain and quit. It is up to the
# installer to delete it.
#

files=""
for f in \
    $Krb5Setup(KDC_Admin_Directory) \
    $Krb5Setup(Client_Configuration_File) \
    $Krb5Setup(KDC_Configuration_File)
do
    if test -r \$f
    then
	if test \$mode = delete
	then
	    rm -rf \$f
	else
	    echo \$f already exists.
	    files="\$f \$files"
	fi
    fi
done
	
if test \$mode = delete
then
    exit 0
fi

if test -n "\$files"
then
    echo 'Please remove the file(s) and execute this procedure again.'
    echo "You can delete the file(s) using \$0 delete"
    exit 1
fi

#
# Specify the current KRB5 configuration file, in case it is in a 
# non-standard location.
#
KRB5_CONFIG=$Krb5Setup(Client_Configuration_File)
export KRB5_CONFIG

#
# Create needed directories
#
mkdir -p $Krb5Setup(KDC_Admin_Directory)

#
# Copy configuration files to their destination
#
cat > $Krb5Setup(Client_Configuration_File) <<EndOfFile
$KrbConfig
EndOfFile

cat > $Krb5Setup(KDC_Configuration_File) <<EndOfFile
$KdcConfig
EndOfFile

#
# Create an acl file
#

echo '$Krb5Setup(Administrator_Principal)@$Krb5Setup(Kerberos_Realm) *' > $Krb5Setup(KDC_Admin_Directory)/kadm5.acl

#
# Create the database.
#
kdb5_util -r $Krb5Setup(Kerberos_Realm) create -s

#
# Create the administrator principal
#
kadmin.local -q 'addprinc $Krb5Setup(Administrator_Principal)@$Krb5Setup(Kerberos_Realm)'

#
# Create a keytab for same
#
kadmin.local -q 'ktadd -k $Krb5Setup(KDC_Admin_Directory)/kadm5.keytab kadmin/admin kadmin/changepw'
