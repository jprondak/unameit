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
# $Id: wizard.tcl,v 1.2.12.1 1997/08/28 18:30:18 viktor Exp $
#

# This package contains the routines necessary to run through a chain
# of little dialgs. This is known in Windows as a 'wizard', since it 
# knows more magic about the system than ordinary people.

# To use this procedure, define a set of procs, each of which constructs
# a dialog inside a frame. Then call wizard_run with the list of proc
# names, in the order you wish to run them. The procs are alternating
# dialog and action procs; an action proc (if non-empty) must return
# a string. 

# Return string is one of:
#
# 	cancel - user wishes to abort
#	okay - everything is okay
#	something else - program abort

proc wizard_sep {w {side top}} {
    pack [frame $w -height 3 -bg blue] -side $side -fill x -pady 10
}


proc wizard_run {top title procs} {

    global WizardNext 

    set WizardTop $top
    catch {destroy $top}

    set bbox $top.bbox
    set title_label $top.title

    if {! [winfo exists $top]} {
	toplevel $top
	wm title $top $title
	wm geometry $top 500x500
	pack [label $title_label] -fill x
	wizard_sep $top.lsep


	pack [frame $bbox] -side bottom -fill x
	pack [button $bbox.cancel -text "Cancel" \
		-command "set WizardNext cancel"] -side right -padx 5
	pack [button $bbox.next -text "Next >" \
		-command "set WizardNext okay"] -side right -padx 5
	pack [button $bbox.back -text "< Back" \
		-command "set WizardNext back"] -side right -padx 5

	wizard_sep $top.bsep bottom
    } 

    # Save the dialog procs and action procs by number

    set WizardProcs 0
    foreach {dialog_proc title action_proc} $procs {
	set WizardDialogs($WizardProcs) $dialog_proc
	set WizardActions($WizardProcs) $action_proc
	set WizardTitle($WizardProcs) $title
	incr WizardProcs
    }

    # WizardProc is the index of the current dialog
    set WizardProc 0

    while {$WizardProc < $WizardProcs} {

	if {$WizardProc < 0} {
	    set WizardProc 0
	}
	
	if {$WizardProc == 0} {
	    $bbox.back configure -state disabled
	} else {
	    $bbox.back configure -state normal
	}
	catch {destroy $top.stuff}
	pack [frame $top.stuff] -fill both 
	$top.title configure -text $WizardTitle($WizardProc)

	if {$WizardProc + 1 == $WizardProcs} {
	    destroy $WizardTop.bbox.cancel
	    destroy $WizardTop.bbox.back
	    $WizardTop.bbox.next configure -text Done
	}

	$WizardDialogs($WizardProc) $top.stuff
	vwait WizardNext

	switch -- $WizardNext {
	    okay {
		if {[string length $WizardActions($WizardProc)]} {
		    if {[catch {set WizardNext [$WizardActions($WizardProc)]} msg]} {
			bgerror $msg
			set WizardNext stay
		    }
		} else {
		    set WizardNext okay
		}

		switch -- $WizardNext {
		    okay {
			incr WizardProc 
		    }
		    stay {
			# do nothing, stay on this dialog
		    }
		    default {
			# break out
			set WizardProc $WizardProcs
		    }
		}
	    }

	    back {
		incr WizardProc -1
	    }

	    cancel {
		# break out
		set WizardProc $WizardProcs
	    }

	    default {
		error "woops"
	    }
	}
    }
    destroy $top
    return $WizardNext
}

package provide Wizard 1.0

