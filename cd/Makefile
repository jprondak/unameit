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

install:
	rm -f /opt/cd/cluster/* /opt/cd/copyright/* /opt/cd/depend/* \
	    /opt/cd/icons/* /opt/cd/pkginfo/* /opt/cd/scripts/*
	for f in common.sh install-sh make_release make_image;\
	 do \
	    ./install-sh -c -m 755 -o root -g bin $$f /opt/cd; \
	done
	./install-sh -c -m 644 -o root -g bin psf /opt/cd
	./install-sh -c -m 644 -o root -g bin psf_demo /opt/cd
	for f in cluster/*; do \
	    if [ -f $$f ]; then ./install-sh -c -m 644 -o root -g bin $$f \
		/opt/cd/cluster; \
	    fi; \
	done
	for f in copyright/*; do \
	    if [ -f $$f ]; then ./install-sh -c -m 644 -o root -g bin $$f \
		/opt/cd/copyright; \
	    fi; \
	done
	for f in depend/*; do \
	    if [ -f $$f ]; then ./install-sh -c -m 644 -o root -g bin $$f \
		/opt/cd/depend; \
	    fi; \
	done
	for f in icons/*; do \
	    if [ -f $$f ]; then ./install-sh -c -m 644 -o root -g bin $$f \
		/opt/cd/icons; \
	    fi; \
	done
	for f in pkginfo/*; do \
	    if [ -f $$f ]; then ./install-sh -c -m 644 -o root -g bin $$f \
		/opt/cd/pkginfo; \
	    fi; \
	done
	for f in scripts/*; do \
	    if [ -f $$f ]; then ./install-sh -c -m 755 -o root -g bin $$f \
		/opt/cd/scripts; \
	    fi; \
	done
	./install-sh -c -m 644 -o root -g bin mkisofsrc /opt/cd/.mkisofsrc
