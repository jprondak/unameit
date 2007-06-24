#### $Id: fancylb.tcl,v 1.7.12.1 1997/08/28 18:29:22 viktor Exp $

# $ Header: /u/ra/raines/cvs/tk/fancylb/fancylb.tk,v 1.3 1996/01/30 03:49:32 raines Exp $
####################################################################
#
# FANCYLB.TK v2.0	- by Paul Raines
#
# This file contains code for a "listbox" using the text widget that
# supports all features of the normal tk4.0 listbox along with some
# additional features such as text tags and embedded windows. For the
# most part, you can replace your normal 'listbox' command with
# 'fancylistbox'. See the include README file for details.
#
#
# COPYRIGHT:
#     Copyright 1993-1996 by Paul Raines (raines@slac.stanford.edu)
#
#     Permission to use, copy, modify, and distribute this
#     software and its documentation for any purpose and without
#     fee is hereby granted, provided that the above copyright
#     notice appear in all copies.  The University of Pennsylvania
#     makes no representations about the suitability of this
#     software for any purpose.  It is provided "as is" without
#     express or implied warranty.
#
# DISCLAIMER:
#     UNDER NO CIRCUMSTANCES WILL THE AUTHOR OF THIS SOFTWARE OR THE
#     UNIVERSITY OF PENNSYLVANIA BE RESPONSIBLE FOR ANY DIRECT OR
#     INCIDENTAL DAMAGE ARISING FROM THE USE OF THIS SOFTWARE AND ITS
#     DOCUMENTATION. THE SOFTWARE HEREIN IS PROVIDED "AS IS" WITH NO
#     IMPLIED OBLIGATION TO PROVIDE SUPPORT, UPDATES, OR MODIFICATIONS.
#
# HISTORY:
#  v1.0 
#     93-08-25    released original version
#
#  v1.1
#     93-08-26	  fixed configure bug
#		  added offset option to curselection
#
#  v1.2
#     93-09-28    added flb_convndx to handle "end" index and errors
#		    (thanks to Norm (N.L.) MacNeil)
#		  created 'destroy' procedure to safely destroy widget
#		    and added catches to all 'renames'
#		  added configure option -selectrelief to specify
#		    relief for selection tag
#		  fixed problem with deleting last element when
#		    it was the single selection
#     93-12-08    changed so configure will return results
#
#  v1.3
#     94-05-17    added "item configure" and "item clear" commands
#
#  v1.4
#     94-06-18    fixed bug with delete removing selline tag
#
#  v1.5
#     94-11-15    fixed insert bug with curtndx
#
#  v2.0 (Renamed to fancylistbox)
#     96-01-14    updated to tk4.0 listbox interface
#		  moved several commands out of case statement to
#		    speed up processing of Listbox bindings
#
#     96-01-15    added support for embedded windows and searches
#
#  v2.1
#     96-01-27    fixed item configure bug with tags
#		  fixed "end" index bug
#		  update get command to tk4.0
#		  added "selection at"
#
###############################################################

proc flb_init {} {
    global flb
    set flb(debug) 0
    set flb(version) 2.0
    bind Flb_Bind <FocusIn> {
      %W_text tag configure activetag -underline 1
    }
    bind Flb_Bind <FocusOut> {
      %W_text tag configure activetag -underline 0
    }
    bind Flb_Bind <KeyPress> {
      set flb(presscur) $flb(%W,curtndx)
      set flb(worry) 0
    }
    bind Flb_Bind <ButtonPress> {
      set flb(presscur) $flb(%W,curtndx)
    }
    bind Flb_Bind <B1-Motion> {
      set flb(worry) 0
    }
    bind Flb_Bind <ButtonRelease-1> {
      flb_selection %W 3 selection worry
    }
    bind Flb_Bind <KeyRelease> {
      flb_selection %W 3 selection worry
    }
    bind Flb_Label <ButtonPress> {
      set flb(presscur) $flb($flb(%W,list),curtndx)
    }
    bind Flb_Label <B1-Motion> {
      set flb(worry) 0
      set tkPriv(x,y) [flb_convcoord_lbl %W @%x,%y]
      scan $tkPriv(x,y) "@%%d,%%d" tkPriv(x) tkPriv(y)
      tkListboxMotion $flb(%W,list) [$flb(%W,list) index $tkPriv(x,y)]
      break
    }
    bind Flb_Label <B1-Leave> {
      scan [flb_convcoord_lbl %W @%x,%y] "@%%d,%%d" tkPriv(x) tkPriv(y)
      tkListboxAutoScanLBL $flb(%W,list)
      break
    }
    bind Flb_Label <ButtonRelease-1> {
      flb_selection $flb(%W,list) 3 selection worry
    }
}

proc flb_configure { flbname args } {
  global flb

  if {[set ndx [lsearch $args -selectrelief]] != -1} {
    set flb($flbname,selectrelief) [lindex $args [expr $ndx+1]]
    set args [lreplace $args $ndx [expr $ndx+1]]
  }
  if {[set ndx [lsearch $args -selectmode]] != -1} {
    set flb($flbname,selectmode) [lindex $args [expr $ndx+1]]
    set args [lreplace $args $ndx [expr $ndx+1]]
  }

  set ret [eval "${flbname}_text configure $args"]

  ${flbname}_text configure -insertbackground \
      [${flbname}_text cget -background]

  ${flbname}_text tag configure selline \
      -background  [${flbname}_text cget -selectbackground] \
      -foreground  [${flbname}_text cget -selectforeground] \
      -borderwidth [${flbname}_text cget -selectborderwidth] \
      -relief $flb($flbname,selectrelief)

  return $ret
}

proc flb_confget { flbname args } {
  global flb

  if [llength $args] {set all 0} else {set all 1}
  set ret {}

  if {[set ndx [lsearch $args -selectrelief]] != -1 || $all} {
    lappend ret [list -selectrelief selectRelief Relief \
		     flat $flb($flbname,selectrelief)]
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }
  if {[set ndx [lsearch $args -selectmode]] != -1 || $all} {
    lappend ret [list -selectmode selectMode SelectMode browse \
		     $flb($flbname,selectmode)]
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }

  if {[llength $args] || $all} {
    set ret [concat $ret [eval "${flbname}_text configure $args"]]
  }

  return $ret
}

proc flb_cget { flbname args } {
  global flb

  if [llength $args] {set all 0} else {set all 1}
  set ret {}

  if {[set ndx [lsearch $args -selectrelief]] != -1 || $all} {
    lappend ret $flb($flbname,selectrelief)
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }
  if {[set ndx [lsearch $args -selectmode]] != -1 || $all} {
    lappend ret $flb($flbname,selectmode)
    if {!$all} { set args [lreplace $args $ndx [expr $ndx+1]] }
  }

  if {[llength $args] || $all} {
    set ret [concat $ret [eval "${flbname}_text cget $args"]]
  }

  return $ret
}

# the actual creation of fancy listbox procedure
proc fancylistbox { flbname args } {
  global flb

  text $flbname
  $flbname mark set active 1.0
  $flbname mark set anchor 1.0
  $flbname mark gravity anchor left
  $flbname configure -wrap none -cursor left_ptr
  $flbname tag configure activetag -underline 0

  if {[catch "rename $flbname ${flbname}_text" errmsg]} {
    rename ${flbname}_text {}
    rename $flbname ${flbname}_text
  }

  set flb($flbname,curtndx) 0.0
  set flb($flbname,selectrelief) raised
  set flb($flbname,tags) 0
  set flb($flbname,selectmode) browse
  
  eval "flb_configure $flbname $args"

  # Set up default bindings    
  bindtags ${flbname} \
      "${flbname} Flb_Bind Listbox [winfo toplevel $flbname] all"
  bind $flbname <Destroy> "flb_destroy $flbname"

  # setup the procedure
  proc $flbname {args} "eval \"flb_process $flbname \$args\""

  if {![info exist flb(worry)]} { 
    set flb(worry) 1 
    set flb(presscur) 0.0
  }
  return $flbname
}

# convert a listbox index to text index
proc flb_convndx {flbname lndx} {
  if {$lndx == "end"} {
    return [${flbname}_text index "end-2l linestart"]
  } elseif {$lndx == "active"} {
    return [${flbname}_text index active]
  } elseif {$lndx == "anchor"} {
    return [${flbname}_text index anchor]
  } elseif {[string first . $lndx] == 0} {
    return [${flbname}_text index $lndx]
  } elseif {[string first @ $lndx] > -1} {
    if {[catch "${flbname}_text index $lndx" res]} {
      error "bad listbox index in $flbname: $lndx"
    } else {
      return $res
    }    
  } else {
    if {[catch "expr $lndx+1" res]} {
      error "bad listbox index in $flbname: $lndx"
    } else {
      return $res.0
    }
  }
}

proc flb_selection {flbname cnt args} {
  global flb

  if {$cnt == 1} {
    error "too few args: should be \"$flbname selection option ?index?\""
  }

  set lastcur $flb($flbname,curtndx)
  case [lindex $args 1] {
    {anchor} {
      if {$cnt == 3} {
	set ndx [flb_convndx $flbname [lindex $args 2]]
	${flbname}_text mark set anchor "$ndx linestart"
      } else {
	error "wrong # args: should be $flbname selection anchor index"
      }
    }
    {clear} {
      if {$cnt > 1 && $cnt < 5} {
	if {[llength $args] == 2} {
	  ${flbname}_text tag remove selline 0.0 end
	  set flb($flbname,curtndx) 0.0
	} else {
	  set fndx [flb_convndx $flbname [lindex $args 2]]
	  if {$cnt == 4} {
	    set lndx [flb_convndx $flbname [lindex $args 3]]
	  } else { set lndx $fndx }
	  if {[${flbname}_text compare $fndx >= $lndx]} {
	    set ndx $fndx; set fndx $lndx; set lndx $ndx
	  }
	  ${flbname}_text tag remove selline $fndx \
	      [${flbname}_text index "$lndx lineend + 1 chars"]
	  if {[${flbname}_text compare $lastcur >= $fndx] &&
	      [${flbname}_text compare $lastcur <= $lndx]} {
	    set flb($flbname,curtndx) 0.0
	  }
	}
      } else {
	error "wrong # args: should be $flbname selection clear ?first? ?last?"
      }
    }
    {includes} {
      if {$cnt == 3} {
	set ndx [flb_convndx $flbname [lindex $args 2]]
	if {[lsearch [${flbname}_text tag names $ndx] selline] > -1} {
	  return 1
	} else {return 0}
      } else {
	error "wrong # args: should be $flbname selection includes index"
      }
    }
    {set at} {
      if {$cnt == 3 || $cnt == 4} {
	set start [lindex $args 2]
	if {$cnt == 4} {
	  set stop [lindex $args 3]
	} else { set stop $start }

	set fndx [flb_convndx $flbname $start]
	set lndx [flb_convndx $flbname $stop]
	if {[${flbname}_text compare $fndx >= $lndx]} {
	    set ndx $fndx; set fndx $lndx; set lndx $ndx
	}
	set fndx [${flbname}_text index "$fndx linestart"]
	if {[${flbname}_text compare $fndx >= "end -1l linestart"]} {
	  set fndx [${flbname}_text index "$fndx -1l linestart"]
	}

	if {[lsearch {single browse} $flb($flbname,selectmode)] > -1} {
	  ${flbname}_text tag remove selline 0.0 end
	  set flb($flbname,curtndx) 0.0
	}

	${flbname}_text tag add selline $fndx \
	    [${flbname}_text index "$lndx lineend + 1 chars"]
	${flbname}_text tag remove selline "end -1l linestart" end

	if {[lindex $args 1] == "at" || \
		($flb($flbname,curtndx) == 0.0 && $flb(worry))} {
	  set flb($flbname,curtndx) $fndx
	  set flb(presscur) $fndx
	}
      } else {
	error "wrong # args: should be $flbname selection set first ?last?"
      }
    }
    {worry} { set flb(worry) 1 }
    default {
      error "bad select option: must be anchor, clear, includes or set"
    }
  }

  set worry [expr "$flb($flbname,curtndx) == 0.0 && $flb(worry)"]
  if {$flb($flbname,curtndx) != $lastcur || $worry} {
    if {$lastcur != 0.0} {
      ${flbname}_text insert $lastcur+1c " "
      ${flbname}_text delete $lastcur
    }
    if {$worry} {
      if {[lsearch [${flbname}_text tag names $flb(presscur)] selline] > -1} {
	set flb($flbname,curtndx) $flb(presscur)
      }	else {
	set rngs [${flbname}_text tag ranges selline]
	if {[string length $rngs]} {
	  foreach tndx $rngs {
	    if {$flb(presscur) < $tndx} {
	      set flb($flbname,curtndx) $tndx
	      set flb(presscur) $tndx
	      break
	    }
	  }
	  if {$flb($flbname,curtndx) == 0.0} {
	    set tndx [lindex $rngs [expr [llength $rngs]-1]]
	    set flb($flbname,curtndx) [${flbname}_text index $tndx-1l]
	    set flb(presscur) $flb($flbname,curtndx)
	  }
	}
      }
    }
    if {$flb($flbname,curtndx) != 0.0} {
      ${flbname}_text insert $flb($flbname,curtndx)+1c ">"
      ${flbname}_text delete $flb($flbname,curtndx)
    }
  }

  # ${flbname}_text delete "end -1l linestart" "end -1c"
  return {}
}

proc flb_delete {flbname cnt args} {
  global flb
  if {$cnt > 1 && $cnt < 4} {
    set lndx ""
    set ndx [flb_convndx $flbname [lindex $args 1]]
    if {[llength $args] == 3} {
      if {[lindex $args 1] == "end"} {return ""}
      set lndx [flb_convndx $flbname [lindex $args 2]]
    } else {
      set lndx $ndx
    }

    # Remove useless item tags, but not the selline tag
    set tndx $ndx
    while {[${flbname}_text compare $tndx <= $lndx] && \
	       [${flbname}_text compare $tndx < end]} {
      set tagname [flb_itemtag $flbname $tndx 1]
      if [string length $tagname] {
	${flbname}_text tag delete $tagname
      }
      set tndx [${flbname}_text index "$tndx +1l"]
    }

    ${flbname}_text delete $ndx "$lndx lineend +1c"

    # see if we still have "first" selection and adjust
    if {$flb($flbname,curtndx) >= $ndx && $flb($flbname,curtndx) <= $lndx} {
      set flb($flbname,curtndx) 0.0
      set rngs [${flbname}_text tag ranges selline]
      if {[string length $rngs]} {
	for {set i 0} {$i < [llength $rngs]} {incr i 2} {
	  set tndx [lindex $rngs $i]
	  if {$ndx <= $tndx} {
	    set flb($flbname,curtndx) $tndx
	    break
	  }
	}
	if {$flb($flbname,curtndx) == 0.0} {
	  set tndx [lindex $rngs [expr [llength $rngs]-1]]
	  set flb($flbname,curtndx) [${flbname}_text index $tndx-1l]
	}
	${flbname}_text insert $flb($flbname,curtndx)+1c ">"
	${flbname}_text delete $flb($flbname,curtndx)
      }
    } elseif {$flb($flbname,curtndx) > $lndx} {
      set tmp [expr [lindex [split $lndx .] 0]-[lindex $args 1]]
      set flb($flbname,curtndx) [${flbname}_text index $flb($flbname,curtndx)-${tmp}l]
    }
    return ""
  } else {
    error "wrong # args: should be $flbname delete first ?last?"
  } 
}

proc flb_itemtag {flbname ndx {query 0}} {
  global flb

  set tagname [${flbname}_text tag names $ndx]
  set gndx [lsearch -glob $tagname flbtag*]
  if {$gndx < 0} {
    if $query {
      set tagname {}
    } else {
      set tagname flbtag[incr flb($flbname,tags)]
      ${flbname}_text tag add $tagname $ndx "$ndx lineend"
    }
  } else {
    set tagname [lindex $tagname $gndx]
  }
  return $tagname
}

proc flb_item {flbname cnt args} {
  global flb

  if {$cnt == 1} {
    error "too few args: should be $flbname item option ?arg arg ...?"
  }
  set cmd [lindex $args 1]

  if {$cmd == "configure"} {
    if {$cnt > 2} {
      set ndx [flb_convndx $flbname [lindex $args 2]]
      set tagname [flb_itemtag $flbname $ndx 0]
      eval "${flbname}_text tag configure $tagname [lrange $args 3 end]"
    } else {
      error "wrong # args: should be $flbname item configure index ?option value ...?"
    }
    return ""
  }
  if {$cmd == "clear"} {
    if {$cnt > 2} {
      foreach item [lrange $args 2 end] {
	set ndx [flb_convndx $flbname $item]
	set tagname [flb_itemtag $flbname $ndx 1]
	if {[string length $tagname]} {
	  ${flbname}_text tag delete $tagname
	}
      }
    } else {
      error "wrong # args: should be $flbname item clear index ?index ...?"
    }
    return ""
  }

  error "bad item option: must be configure or clear"
}

proc flb_window {flbname cnt args} {
  global flb

  set opt [lindex $args 1]
  if {$opt == "names"} {
    return [${flbname}_text window names]
  }
  if {[lsearch {cget configure create} $opt] < 0} {
    error "bad window option: must be cget, configure, create or names"
  }
  set ndx [lindex $args 2]
  set char 0
  if {[string first . $ndx] > 0} {
    set ndx [split $ndx .]
    set char [lindex $ndx 1]
    set ndx [lindex $ndx 0]
  }
  incr char ;# get past '>' column
  set ndx [flb_convndx $flbname $ndx]
  set max [${flbname}_text index "$ndx lineend"]
  set ndx [${flbname}_text index "$ndx linestart +${char}c"]
  if [${flbname}_text compare $ndx > $max] { set ndx $max }
  set fargs [lrange $args 3 end]
  set ret [eval "${flbname}_text window $opt $ndx $fargs"]
  set w [${flbname}_text window cget $ndx -window]
  if [info exists flb($w,list)] {
    set flb($w,list) $flbname
  }
  return $ret
}

proc flb_search {flbname cnt args} {
  global flb

  foreach opt {-forw -back -count} {
    if {[string first $opt $args] > -1} {
      error "invalid search switch: should be -exact, -regexp, or -nocase"
    }
  }

  for {set i 1} {[string first - [lindex $args $i]] == 0} {incr i} { }
  incr i
  if {$i != $cnt} {
    error "wrong # args: should be $flbname search ?switches? pattern"
  }
  set fargs [lrange $args 1 end]

  set flist {}
  set start 1.0
  set tw ${flbname}_text
  while {[string length [set ndx [eval "$tw search $fargs $start end"]]]} {
    set start [$tw index "$ndx lineend +1c"]
    set y [lindex [split $ndx .] 0]
    incr y -1
    lappend flist $y
  }

  return $flist
}

proc flb_destroy {flbname} {
  if {[winfo exists $flbname]} {
    destroy $flbname
  }
  catch "rename ${flbname}_text {}"
  catch "rename $flbname {}"
}

# setup the procedure
proc flb_process {flbname args} {
  global flb

  # puts stderr "FAKE: $args"

  set cnt [llength $args]
  set cmd [lindex $args 0]

  if {[lsearch {scan xview yview compare tag} $cmd] > -1} {
    return [eval "${flbname}_text $args"]
  }

  if {$cmd == "index"} {
    if {$cnt == 2} {
      set ndx [flb_convndx $flbname [lindex $args 1]]
      return [expr [lindex [split $ndx .] 0]-1]
    } else {
      error "wrong # args: should be $flbname index index"
    }
  }

  if {$cmd == "selection"} {
    return [eval "flb_selection $flbname $cnt $args"]
  }

  if {$cmd == "cget"} {
      return [flb_cget $flbname [lindex $args 1]]
  }

  if {$cmd == "activate"} {
    set ndx [flb_convndx $flbname [lindex $args 1]]
    if {[${flbname}_text compare $ndx >= "end -1l linestart"]} {
      set ndx [${flbname}_text index "$ndx -1l linestart"]
    }
    ${flbname}_text tag remove activetag 0.0 end
    ${flbname}_text mark set active $ndx
    ${flbname}_text tag add activetag "$ndx linestart" "$ndx lineend"
    return ""
  }

  case $cmd {
    {delete item window search} {
      return [eval "flb_$cmd $flbname $cnt $args"]
    }
    {bbox} {
      set ndx [flb_convndx $flbname [lindex $args 1]]
      return [lrange [${flbname}_text dlineinfo $ndx] 0 3]
    }
    {configure} {
      if {$cnt < 2} {
	return [eval "flb_confget $flbname [lrange $args 1 end]"]
      } else {
	return [eval "flb_configure $flbname [lrange $args 1 end]"]
      }
    }
    {cursingle} {
      if {$cnt == 1} {
	# return empty if no "first" selection
	if {$flb($flbname,curtndx) == 0.0} {return ""}
	set ndx [lindex [split $flb($flbname,curtndx) .] 0]
	return [expr $ndx-1]
      } else {
	error "wrong # args: should be $flbname cursingle"
      } 
    }
    {curselection} {
      if {$cnt > 0 && $cnt < 3} {
	# return list of selected item indices
	if {$cnt == 2} {
	  set offset [lindex $args 1]
        } else {
	  set offset 0
	}
	set lsel ""
	set ranges [${flbname}_text tag ranges selline]
	for {set line 0} {$line < [llength $ranges]} {incr line} {
	  set ndx [lindex [split [lindex $ranges $line] .] 0]
	  incr line
	  set last [lindex [split [lindex $ranges $line] .] 0]
	  for {set i $ndx} {$i < $last} {incr i} {
	    lappend lsel [expr $i-1+$offset] 
	  }    
	}
	return $lsel
      } else {
	error "wrong # args: should be $flbname cursingle"
      } 
    }
    {debug} { set flb(debug) [lindex $args 1]}
    {destroy} {
      if {$cnt == 1} {
        if {[winfo exists $flbname]} {
	  destroy $flbname
	}
        catch "rename ${flbname}_text {}"
	catch "rename $flbname {}"
      } else {
	error "wrong # args: should be $flbname destroy"
      } 
    }
    {get} {
      if {$cnt == 2 || $cnt == 3} {
	set ndx [flb_convndx $flbname [lindex $args 1]]
	if {$cnt == 3} {
	  set lndx [flb_convndx $flbname [lindex $args 2]]
	} else { set lndx $ndx }
	set result {}
	set tndx $ndx
	while {[${flbname}_text compare $tndx <= $lndx] && \
		   [${flbname}_text compare $tndx < end]} {
	  lappend result [${flbname}_text get $tndx+1c "$tndx lineend"]
	  set tndx [${flbname}_text index "$tndx +1l"]
	}
	return $result
      } else {
	error "wrong # args: should be $flbname get first ?last?"
      } 
    }
    {insert} {
      if {$cnt > 2} {
        set ndx [lindex $args 1]
        if {$ndx == "end"} {
	  set ndx [${flbname}_text index end]
        } else {
	  set ndx [flb_convndx $flbname $ndx]
        }
	if {$ndx <= $flb($flbname,curtndx)} { 
	  set flb($flbname,curtndx) \
	      [expr $flb($flbname,curtndx)+[llength $args]-2]
	}
	set start $ndx
	foreach line [lrange $args 2 end] {
	  ${flbname}_text insert $ndx " $line\n"
	  set ndx [${flbname}_text index $ndx+1l]
	}
	${flbname}_text tag remove selline $start $ndx
	return ""
      } else {
        if {$cnt == 1} {
	  error "wrong # args: should be $flbname insert index ?element ...?"
	}
      } 
    }
    {isselected} {
      if {$cnt != 2} {
	error "wrong number of args: should be $flbname isselected ndx"
      }
      set ndx [flb_convndx $flbname [lindex $args 1]]
      if {[lsearch [${flbname}_text tag names $ndx] selline] > -1} {
	return 1
      } else {return 0}
    }
    {nearest} {
      if {$cnt == 2} {
	set y [lindex $args 1]
	set ndx [${flbname}_text index @0,$y]
	set ndx [expr [lindex [split $ndx .] 0]-1]
	set sz [${flbname}_text index end]
	set sz [expr [lindex [split $sz .] 0]-1]
	if {$ndx >= $sz} {set ndx [expr $sz-1]}
	return $ndx
      } else {
	error "wrong # args: should be $flbname nearest y"
      } 
    }
    {see} {
      if {$cnt == 2} {
	set ndx [flb_convndx $flbname [lindex $args 1]]
	${flbname}_text see $ndx
      } else {
	error "wrong # args: should be $flbname see y"
      }
    }
    {size} {
      if {$cnt == 1} {
	set ndx [flb_convndx $flbname end]
	return [lindex [split $ndx .] 0]
      } else {
	error "wrong # args: should be $flbname size"
      } 
    }
    default {
      error "bad option \"[lindex $args 0]\": should be [list activate, \
	  bbox, cget, configure, cursingle, curselection, delete, get, index, \
          insert, nearest, scan, selection, size, or yview]"
    }
  }
}

proc fancylabel { flblname args } {
  global flb

  label $flblname
  $flblname configure -cursor left_ptr 
  eval "$flblname configure $args"

  if {[catch "rename $flblname ${flblname}_label" errmsg]} {
    rename ${flblname}_label {}
    rename $flblname ${flblname}_label
  }

  set flb($flblname,list) {}
  
  # Set up default bindings    
  bindtags ${flblname} \
      "${flblname} Flb_Label Listbox [winfo toplevel $flblname] all"
  bind $flblname <Destroy> "flb_destroy_lbl $flblname"

  # setup the procedure
  proc $flblname {args} "eval \"flb_process_lbl $flblname \$args\""

}

proc flb_convcoord_lbl {flblname ndx} {
  global flb
  if {[string first @ $ndx] != 0} {return $ndx}
  scan $ndx "@%d,%d" x y
  set lb $flb($flblname,list)
  set adj [${lb}_text bbox $flblname]
  if ![llength $adj] { set adj {0 0} }
  set ndx @[expr $x+[lindex $adj 0]],[expr $y+[lindex $adj 1]]
  return $ndx
}

proc tkListboxAutoScanLBL {w} {
  global tkPriv
  set x $tkPriv(x)
  set y $tkPriv(y)

  if {$y >= [winfo height $w]} {
    ${w}_text yview scroll 1 units
  } elseif {$y < 0} {
    ${w}_text yview scroll -1 units
  } elseif {$x >= [winfo width $w]} {
    ${w}_text xview scroll 2 units
  } elseif {$x < 0} {
    ${w}_text xview scroll -2 units
  }
  tkListboxMotion $w [$w index @$x,$y]
  set tkPriv(afterId) [after 50 tkListboxAutoScanLBL $w]
}

proc flb_destroy_lbl {flblname} {
  global flb
  catch "unset flb($flblname,list)"
  if [winfo exists $flblname] {
    destroy $flblname
  }
  catch "rename ${flblname}_label {}"
  catch "rename $flblname {}"
}

proc flb_process_lbl {flblname args} {
  global flb

  set cmd [lindex $args 0]

  set haslist 0
  set lb $flb($flblname,list)
  if [winfo exists $lb] {
    if [catch {${lb}_text index $flblname}] {
      set flb($flblname,list) {}
    } else {
      set haslist 1
    }
  }

  if {$cmd == "configure"} {
    set islabel 1
    foreach opt {-select -setgrid -takefocus -xscroll -yscroll} {
      if {[string first $opt $args] > -1} {
	set islabel 0
	break
      }
    }

    if $islabel {
      return [eval "${flblname}_label $args"]
    } else {
      if $haslist {
	return [eval "$lb $args"]
      } else {
	error "$flblname has not associated fancylistbox"
      }
    }
  }

  if {$cmd == "cget"} {
    if [catch {eval "${flblname}_label $args"} ret] {
      if $haslist {
	return [eval "$lb $args"]
      } else {
	error "$flblname has not associated fancylistbox"
      }      
    } else {
      return $ret
    }
  } 

  if $haslist {
    set ndx [lindex $args 1]
    if {[string first @ $ndx] == 0} {
      scan $ndx "@%d,%d" x y
      set adj [${lb}_text bbox $flblname]
      if ![llength $adj] { set adj {0 0} }
      set ndx @[expr $x+[lindex $adj 0]],[expr $y+[lindex $adj 1]]
    }
    if {[llength $args] > 2} {
      set fargs [lrange $args 2 end]
    } else { set fargs {} }
    return [eval "$lb $cmd $ndx $fargs"]
  } else {
    error "$flblname has not associated fancylistbox"
  }      
}

package provide Fancylistbox 2.0
