#
# Copyright (c) 1996 Enterprise Systems Management Corp.
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
# $Id: packages.tcl,v 1.5 1996/07/31 00:25:27 viktor Exp $
#

#
# This file isn't currently used. We use "load {} pkg" instead of "require".
# We can change to "require" later. We could use "require" now, but that would
# require us to read in this file in each application (and any interpreter
# in that application that wanted to load packages) and we don't currently do
# that.

# The following comes from linking with tcl and tclx
package ifneeded Tclx 7.5.0 {load {} Tclx}
package ifneeded Tk 4.1 {load {} Tk}

# The following comes from libconn
package ifneeded Uclient 2.0 {load {} Uclient}
package ifneeded Upasswd 1.0 {load {} Upasswd}
package ifneeded Uqbe 2.0 {load {} Uqbe}
package ifneeded Uaddress 1.0 {load {} Uaddress}
package ifneeded Userver 2.0 {load {} Userver}
package ifneeded Uk4 1.0 {load {} Uk4}

# The following comes from libudb
package ifneeded Uuid 1.0 {load {} Uuid}
package ifneeded Umeta 2.0 {load {} Umeta}

# The following comes from libcache_mgr
package ifneeded Ucache_mgr 1.0 {load {} Ucache_mgr}

# The following comes from libschema_mgr
package ifneeded Uschema_mgr 1.0 {load {} Uschema_mgr}

# The following comes from libcanon
package ifneeded Ucanon 1.0 {load {} Ucanon}
