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
# $Id: unameit_setup_kerberos5.tcl,v 1.5.8.1 1997/08/28 18:29:53 viktor Exp $
#

#
# This TCL script will set up a minimal default kerberos5 server.
# It should be run using $UNAMEIT/install/unameit_setup_kerberos5,
# on the host which is to be the Kerberos Domain Controller.
#

package require Config

proc krb5_setup_conf {} {
    global Krb5Setup env

    foreach {field value} [array get Krb5Setup] {
	set Krb5Setup($field) [string trim $value]
	if {[cequal "" $Krb5Setup($field)]} {
	    regsub -all -- "_" $field " " label
	    error "$label must be specified"
	}
    }
    set kdc_conf [unameit_filename UNAMEIT_INSTALL kdc.conf.$Krb5Setup(Kerberos_Realm)]
    set krb5_conf [unameit_filename UNAMEIT_INSTALL krb5.conf.$Krb5Setup(Kerberos_Realm)]

    #
    # Copy each config file, substituting variables.
    #
    set KdcConfig [read_file [unameit_filename UNAMEIT_INSTALL kdc.conf]]
    set KdcConfig [subst -nocommands -nobackslash $KdcConfig]
    write_file $kdc_conf $KdcConfig

    set KrbConfig [read_file [unameit_filename UNAMEIT_INSTALL krb5.conf]]
    set KrbConfig [subst -nocommands -nobackslash $KrbConfig]
    write_file $krb5_conf $KrbConfig

    set unameit $env(UNAMEIT)
    set Krb5Paths(PATH)\
	[join\
	    [list\
		$unameit/lbin/exe\
		$unameit/lsbin/exe\
		/opt/krb5/bin\
		/opt/krb5/sbin\
		/bin\
		/usr/bin\
		/sbin\
		/usr/sbin\
		/usr/ucb\
		/usr/etc\
		]\
	    :]
    set Krb5Paths(LD_LIBRARY_PATH) $unameit/lib/krb5/lib:/opt/krb5/lib

    set conf [read_file [unameit_filename UNAMEIT_INSTALL krb5_server.sh]]
    set conf [subst -nocommands $conf]
    set cfile [unameit_filename UNAMEIT_INSTALL krb5_server.$Krb5Setup(Kerberos_Realm)]
    write_file $cfile $conf
    chmod 0755 $cfile
    puts "On the kerberos server, execute \n$cfile\n"

    set conf [read_file [unameit_filename UNAMEIT_INSTALL krb5_client.sh]]
    set conf [subst -nocommands $conf]
    set cfile [unameit_filename UNAMEIT_INSTALL krb5_client.$Krb5Setup(Kerberos_Realm)]
    write_file $cfile $conf
    chmod 0755 $cfile
    puts "On all kerberos client machines, execute \n$cfile\n"

    exit 0
}



#
# Assign variables to be substituted in the configuration files.
# The default kerberos server will be 'kerberos' if an alias exists for it.
#
proc krb5_setup_defaults {} {
    global Krb5Setup env

    set khost ""
    catch {set khost [host_info official_name [info hostname]]}

    set Krb5Setup(Kerberos_Realm) ""
    set Krb5Setup(Default_Domain) ""
    set Krb5Setup(KDC_Configuration_File) /etc/kdc.conf
    set Krb5Setup(Client_Configuration_File) /etc/krb5.conf
    set Krb5Setup(KDC_Admin_Host) $khost
    set Krb5Setup(KDC_Admin_Port) 749
    set Krb5Setup(KDC_Server_Host) $khost
    set Krb5Setup(KDC_Server_Port) 88
    set Krb5Setup(KDC_Admin_Directory) /var/krb5/lib/krb5kdc
    set Krb5Setup(Administrator_Principal) "joeuser/admin"
}



proc krb5_setup_dialog {} {

    global Krb5Setup 

    toplevel .d
    pack [frame .d.sep -bg black -height 2] -fill x

    pack [frame .d.file_entries] -fill x    
    
    pack [frame .d.buttons] -fill x
    pack [button .d.buttons.read -text "Okay" -command "krb5_setup_conf"] \
	    -side left
    pack [button .d.buttons.defaults -text "Restore Defaults" \
	    -command krb5_setup_defaults] \
	    -side left
    pack [button .d.buttons.save -text "Abort" -command "exit 1"] \
	    -side left

    set fnum 0
    foreach f [lsort [array names Krb5Setup]] {
	incr fnum
	set fe .d.file_entries.f$fnum
	pack [frame $fe] -fill x
	regsub -all -- "_" $f " " label
	pack [label $fe.label -text $label -width 30 -anchor w] -side left
	pack [entry $fe.entry -textvariable Krb5Setup($f)] \
		-side right -fill x -expand 1 
    }
    wm title .d "Kerberos 5 Domain Controller Setup"
    wm group .d .
    wm withdraw .
}

krb5_setup_defaults
krb5_setup_dialog
