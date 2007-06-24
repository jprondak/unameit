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

package ifneeded Ndbmtcl 1.0 [list load [file join $dir "ndbmtcl[info sharedlibextension]"]]

package ifneeded ukrbiv 2.0 [list load [file join $dir "ukrbiv[info sharedlibextension]"]]
package ifneeded ukrbv 2.0 [list load [file join $dir "ukrbv[info sharedlibextension]"]]
package ifneeded trivial 2.0 [list load [file join $dir "trivial[info sharedlibextension]"]]

package ifneeded Config 1.3 [list load [file join $dir "config[info sharedlibextension]"]]

package ifneeded Shortcut 1.0 [list load [file join $dir "shortcut[info sharedlibextension]"]]

package ifneeded Error 1.0 [list source [file join $dir error.tcl]]

package ifneeded Fancylistbox 2.0 [list source [file join $dir fancylb.tcl]]

package ifneeded Shortcuts 1.0 [list source [file join $dir shortcuts.tcl]]

package ifneeded Wizard 1.0 [list source [file join $dir wizard.tcl]]

package ifneeded Textview 1.0 [list source [file join $dir textview.tcl]]

package ifneeded Services.Tcl 1.0 [list source [file join $dir services.tcl.tcl]]
