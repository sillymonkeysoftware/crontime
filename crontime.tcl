package provide crontime 0.1
package require Tcl 8.5


namespace eval ::crontime {

    namespace export valid now next last

    variable cronsz 5
    variable ranges [list \
                            {0 59} \
                            {0 23} \
                            {1 31} \
                            {1 12} \
                            {0 6} ]
                        
    variable conversion [list \
                            [dict create 60 0] \
                            [dict create 24 0] \
                            {} \
                            [dict create 0 1] \ \
                            [dict create 7 0] ]
    
    variable alphamap [list \
                            {} \
                            {} \
                            {} \
                            [dict create jan 1 feb 2 mar 3 apr 4 may 5 jun 6 \
                                          jul 7 aug 8 sep 9 oct 10 nov 11 \
                                          dec 12] \
                            [dict create sun 0 mon 1 tue 2 wed 3 thu 4 \
                                          fri 5 sat 6] ]
                                          
    variable formatmap [dict create \
                            0 "%M" \
                            1 "%H" \
                            2 "%d" \
                            3 "%m" \
                            4 "%w" ]
}



# valid()
#   Check a crontab string for validity
#
#   PARAMETERS
#       a crontab time string
#
#   RETURNS 
#       1 = TRUE
#       0 = FALSE
#
#**************************************
proc ::crontime::valid {cron} {
    variable cronsz
    
    set atoms [::crontime::expand $cron]    
    if {[llength $atoms] != $cronsz} {
        return 0
    }
    
    return 1
}


# expand()
#   Expand a cron time entry into lists of possible numbers
#
#   This function is mostly used internally by this package, but
#   may prove useful for debugging other things too.
#
#   PARAMETERS
#       a crontab time string
#
#   RETURNS 
#       Success: a list of 5 number-lists { {} {} {} {} {} }
#       Failure: an empty list {}
#
#**************************************
proc ::crontime::expand {cron} {
    
    set atoms {}
    set segments [regexp -inline -all -- {\S+} $cron]
    
    # iterate over each segment, and expand into lists of numbers.
    for {set index 0} {$index < [llength $segments]} {incr index} {
        set tmp [::crontime::_expand_cron_index [lindex $segments $index] $index]
        lappend atoms $tmp
    }
    
    return $atoms    
}


# now()
#   Check if a crontab string is valid for the current time
#
#   PARAMETERS
#       a crontab time string
#       (optional) a reference timestamp
#
#   RETURNS 
#       1 = TRUE
#       0 = FALSE
#
#**************************************
proc ::crontime::now {cron args} {
    variable formatmap
    
    if {$args != ""} {
        set stamp [lindex $args 0]
    } else {
        set stamp [clock seconds]    
    }
    
    set atoms [::crontime::expand $cron]
    set mday 0
    
    foreach key [lsort -integer [dict keys $formatmap]] {
        set found 0
        
        # extract our value from clock format, and convert to INT number
        set fmt [dict get $formatmap $key]
        set val [expr [clock format $stamp -format $fmt]]
        
        if {[regexp "\\y$val\\y" [lindex $atoms $key]]} {
            set found 1
            if {$key == 2} { set mday 1 }    
        }
        
        # For some complex cases(like, "30 08 1 10 Tue"), a cron is valid
        # in TWO situations:
        #  - 08:30am on October 1st.
        #  - 08:30am on EVERY Tuesday in October.
        # So, do not be too hasty to abort if the MDAY field doesn't match,
        # because WDAY needs to be given opportunity to match in some cases 
        if {$key == 2 && ! $found && [llength [lindex $atoms 4]] < 7} { 
            continue       
        }
        
        if {$key == 4} {
            if {$found} { return 1 }
            if {! $found && $mday} { return 1 }
        }
         
        if {! $found} { return 0 } 
    }
    
    return 0
}


# next()
#   return the next timestamp when cron will be valid
#
#   PARAMETERS
#       a crontab time string
#       (optional) a reference start timestamp
#
#   RETURNS 
#       a timestamp (clock seconds)
#
#**************************************
proc ::crontime::next {cron args} {
    variable ranges
    
    if {$args != ""} {
        set start [lindex $args 0]
    } else {
        set start [clock seconds]    
    }
    
    set stamp $start
    set atoms [::crontime::expand $cron]
    set mode [::crontime::_timesearch_mode {*}$atoms]
    set finished 0
    set results {}
    
    if {$mode == 3} { set pass 2 } else { set pass 1 }
    
    while {! $finished} {
        set ymd_lock 0
        
        # have we gone too far incrementing years?
        if {[clock format $stamp -format "%Y"] > [expr \
                                    [clock format $start -format "%Y"] + 1] } {
            return {}                                
        }
        
        # iterate over cron sections in a specific order
        foreach index {3 4 2 1 0} {
            set possibles [lindex $atoms $index]
            set max [expr ([lindex [lindex $ranges $index] end] + 1) - \
                                           [lindex [lindex $ranges $index] 0] ]
            
            # skip indexes depending on allowed range, or mode/pass values
            if {[llength $possibles] >= $max} { continue }
            if {$index == 4 && $mode == 0} { continue }
            if {$index == 4 && $pass == 2} { continue }
            if {$index == 2 && $mode == 3 && $pass == 1} { continue }
            
            # calculating new timestamps per segment
            if {$index == 3} {
                set rval [::crontime::_month_parsing 1 $stamp $possibles]
                set stamp [lindex $rval 0]
                if {[lindex $rval 1]} { break }
                
            } elseif {$index == 2} {
                set rval [::crontime::_mday_parsing 1 $stamp $possibles]
                set stamp [lindex $rval 0]
                if {[lindex $rval 1]} { break }
                
            } elseif {$index == 1} {
                set rval [::crontime::_hour_parsing 1 $stamp $possibles]
                set stamp [lindex $rval 0]
                if {[lindex $rval 1]} { break }
                
            } elseif {$index == 0} {
                set rval [::crontime::_min_parsing 1 $stamp $possibles]
                set stamp [lindex $rval 0]
                if {[lindex $rval 1]} { break }
                
                set finished 1
                
            } else {
                if {$ymd_lock} {
                    set stamp [clock add $stamp 1 days]    
                }
                set rval [::crontime::_wday_parsing 1 $stamp $possibles]
                set stamp [lindex $rval 0]
                if {[lindex $rval]} { break }
                set ymd_lock 1
            }
        }
        
        if {$finished} {
            lappend results $stamp
            incr pass -1
            
            # must re-do this whole procedure again?
            if {$pass} {
                set finished 0
                set stamp $start   
            }
        }
    }    

    # sort the results, and pick the soonest value
    return [lindex [lsort -integer $results] 0]
}



###  PRIVATE FUNCTIONS BELOW  #################################################



# _month_parsing()
#   Find next possible month for
#
#   PARAMETERS
#       1. a seek mode (forward (1) or reverse (0))
#       2. a starting timestamp
#       3. list of possible values
#
#   RETURNS
#       A list containing two numbers, like; {1234553454 0}
#           1. a new timestamp
#           2. bool indicating if entire parse block should be restarted.
#               
#**************************************
proc ::crontime::_month_parsing {direction stamp args} {
    variable formatmap
    variable ranges
    
    set index 3
    set fmt [dict get $formatmap $index]
    set current [clock format $stamp -format $fmt]
    set max [expr ([lindex [lindex $ranges $index] end] + 1) - \
                                           [lindex [lindex $ranges $index] 0] ]

                                                                 
    if {$direction eq "forward" || $direction == 1} {
        set seeking [::crontime::_next_possible $current $args]
        
        if {$current == $seeking} { 
            return "$stamp 0"
        } else {
            if {$seeking > $current} {
                set diff [expr $seeking - $current]
            } else {
                set diff [expr ($max - $current) + $seeking] 
            }
        
            # increment to desired month, and then reset day info
            set stamp [clock add $stamp $diff months]
            set stamp [clock scan [format "%d-%d-%d 00:00:00" \
    		                           [clock format $stamp -format "%Y"] \
    		                           [clock format $stamp -format "%m"] \
    		                           1 ] -format {%Y-%m-%d %H:%M:%S} ]
    		                           
    		if {$seeking > $current} {
                return "$stamp 0"        
            } else {
                return "$stamp 1"        
            }
        }
    }
}


# _mday_parsing()
#   Find next possible day of month for
#
#   PARAMETERS
#       1. a seek mode (forward (1) or reverse (0))
#       2. a starting timestamp
#       3. list of possible values
#
#   RETURNS
#       A list containing two numbers, like; {1234553454 0}
#           1. a new timestamp
#           2. bool indicating if entire parse block should be restarted.
#               
#**************************************
proc ::crontime::_mday_parsing {direction stamp args} {
    variable formatmap
    variable ranges
    
    set index 2
    set fmt [dict get $formatmap $index]
    set current [clock format $stamp -format $fmt]
    set max [::crontime::_last_month_day [clock format $stamp -format "%m"] \
                                           [clock format $stamp -format "%Y"] ]

                                                                 
    if {$direction eq "forward" || $direction == 1} {
        set seeking [::crontime::_next_possible $current $args]
        
        if {$current == $seeking} { 
            return "$stamp 0"
        } else {
            # is seeking mday too high for current month?
            if {$seeking > $max} {
                set stamp [clock add $stamp 1 months]
                set stamp [clock scan [format "%d-%d-%d 00:00:00" \
		                           [clock format $stamp -format "%Y"] \
		                           [clock format $stamp -format "%m"] \
		                           1 ] -format {%Y-%m-%d %H:%M:%S} ]
                return "$stamp 1"
            }
            
            if {$seeking > $current} {
                set diff [expr $seeking - $current]
            } else {
                set diff [expr ($max - $current) + $seeking]    
            }        
            
            set stamp [clock add $stamp $diff days]
            set stamp [clock scan [format "%d-%d-%d 00:00:00" \
		                           [clock format $stamp -format "%Y"] \
		                           [clock format $stamp -format "%m"] \
		                           [clock format $stamp -format "%m"] \
		                          ] -format {%Y-%m-%d %H:%M:%S} ]
		                          
		    if {$seeking > $current} {
                return "$stamp 0"
            } else {
                return "$stamp 1"
            }                       
        }
    }
}


# _hour_parsing()
#   Find next possible hour for
#
#   PARAMETERS
#       1. a seek mode (forward (1) or reverse (0))
#       2. a starting timestamp
#       3. list of possible values
#
#   RETURNS
#       A list containing two numbers, like; {1234553454 0}
#           1. a new timestamp
#           2. bool indicating if entire parse block should be restarted.
#               
#**************************************
proc ::crontime::_hour_parsing {direction stamp args} {
    variable formatmap
    variable ranges
    
    set index 1
    set fmt [dict get $formatmap $index]
    set current [clock format $stamp -format $fmt]
    set max [expr ([lindex [lindex $ranges $index] end] + 1) - \
                                           [lindex [lindex $ranges $index] 0] ]

                                                                 
    if {$direction eq "forward" || $direction == 1} {
        set seeking [::crontime::_next_possible $current $args]
        
        if {$current == $seeking} {
            return "$stamp 0"
        } else {
            if {$seeking > $current} {
                set diff [expr $seeking - $current]
            } else {
                set diff [expr ($max - $current) + $seeking]     
            }
               
            set stamp [clock add $stamp $diff hours]
            set stamp [clock scan [format "%d-%d-%d %d:00:00" \
		                           [clock format $stamp -format "%Y"] \
		                           [clock format $stamp -format "%m"] \
		                           [clock format $stamp -format "%m"] \
		                           [clock format $stamp -format "%H"] \
		                          ] -format {%Y-%m-%d %H:%M:%S} ]
		                          
		    if {$seeking > $current} {
    		    return "$stamp 0"
		    } else {
    		    return "$stamp 1"    
		    }
        } 
    }
}


# _min_parsing()
#   Find next possible minute for
#
#   PARAMETERS
#       1. a seek mode (forward (1) or reverse (0))
#       2. a starting timestamp
#       3. list of possible values
#
#   RETURNS
#       A list containing two numbers, like; {1234553454 0}
#           1. a new timestamp
#           2. bool indicating if entire parse block should be restarted.
#               
#**************************************
proc ::crontime::_min_parsing {direction stamp args} {
    variable formatmap
    variable ranges
    
    set index 0
    set fmt [dict get $formatmap $index]
    set current [clock format $stamp -format $fmt]
    set max [expr ([lindex [lindex $ranges $index] end] + 1) - \
                                           [lindex [lindex $ranges $index] 0] ]

                                                                
    if {$direction eq "forward" || $direction == 1} {
        set seeking [::crontime::_next_possible $current $args]
        
        if {$current == $seeking} {
            return "$stamp 0"
        } else {
            if {$seeking > $current} {
                set diff [expr $seeking - $current]
            } else {
                set diff [expr ($max - $current) + $seeking]     
            }
               
            set stamp [clock add $stamp $diff minutes]
            set stamp [clock scan [format "%d-%d-%d %d:%d:00" \
		                           [clock format $stamp -format "%Y"] \
		                           [clock format $stamp -format "%m"] \
		                           [clock format $stamp -format "%m"] \
		                           [clock format $stamp -format "%H"] \
		                           [clock format $stamp -format "%M"] \
		                          ] -format {%Y-%m-%d %H:%M:%S} ]
		                          
		    if {$seeking > $current} {
    		    return "$stamp 0"
		    } else {
    		    return "$stamp 1"    
		    }
        } 
    }
}


# _wday_parsing()
#   Find next possible week day for
#
#   PARAMETERS
#       1. a seek mode (forward (1) or reverse (0))
#       2. a starting timestamp
#       3. list of possible values
#
#   RETURNS
#       A list containing two numbers, like; {1234553454 0}
#           1. a new timestamp
#           2. bool indicating if entire parse block should be restarted.
#               
#**************************************
proc ::crontime::_wday_parsing {direction stamp args} {
    variable formatmap
    variable ranges
    
    set index 4
    set fmt [dict get $formatmap $index]
    set current [clock format $stamp -format $fmt]
    set max [expr ([lindex [lindex $ranges $index] end] + 1) - \
                                           [lindex [lindex $ranges $index] 0] ]
    
                  
    if {$direction eq "forward" || $direction == 1} {
        set seeking [::crontime::_next_possible $current $args]
        
        set temp [::crontime::_next_dow_time $seeking $stamp]
        if {[clock format $temp -format "%m"] == \
                                          [clock format $stamp -format "%m"]} {
            return "$temp 0"
        } else {
            # next found day-of-week is beyond the range of the desired month. 
            # that won't do, return the stamp and request a restart.
            set stamp [clock add $stamp 1 months]
            set stamp [clock scan [format "%d-%d-%d 00:00:00" \
		                           [clock format $stamp -format "%Y"] \
		                           [clock format $stamp -format "%m"] \
		                           1 ] -format {%Y-%m-%d %H:%M:%S} ]    
            
            return "$stamp 1"
        }
    }
}


# _expand_cron_index()
#   Expand a piece of a cron time entry into list of all possible values
#
#   PARAMETERS
#       1. a crontab time string segment
#       2. the index number of the cron segment entry
#
#   RETURNS 
#       Success: a list of numbers
#       Failure: an empty list {}
#
#**************************************
proc ::crontime::_expand_cron_index {str index} {
    
    variable conversion
    variable alphamap
    variable ranges
    
    set results {}
    
    foreach piece [split $str ","] {
        set step 0
        set atoms {}
        
        # grab a step-value from end of string, then delete it
        if {[regexp {\/(\d+)$} $piece junk step]} {
            regsub {\/\d+$} $piece {} piece
        }
        
        # replace any text values with corresponding numbers.
        if {[lindex $alphamap $index] != ""} {
            dict for {key replace} [lindex $alphamap $index] {
                regsub -nocase -all $key $piece $replace piece
            }
        }
        
        # fix common out-of-range numbers
        if {[lindex $conversion $index] != ""} {
            dict for {key replace} [lindex $conversion $index] {
                regsub -nocase -all "\\y$key\\y" $piece $replace piece
            }
        }
        
        
        # a simple, singular number?
        if {[regexp {^\d+$} $piece]} {
            lappend results $piece
            continue
        }
        
        # expand asterisks into a range of numbers (like; 0-11)
        if {[regexp {\*} $piece]} {
            regsub -all {\*} $piece [join [lindex $ranges $index] "-"] piece
        }
        
        # expand ranges and place into atoms
        if {[regexp {(\d+)-(\d+)} $piece junk val1 val2]} {
            while {$val1 <= $val2} {
                lappend atoms $val1
                incr val1
            }
        }
        
        # filter steps, or push all numbers into results.
        # the first value in an step range always gets added, and so do 
        # numbers that divide evenly by the step.
        for {set i 0} {$i < [llength $atoms]} {incr i} {
            if {$step} {
                if {$i == 0 || ! [expr [lindex $atoms $i] % $step]} {
                    lappend results [lindex $atoms $i]
                }
            } else {
                lappend results [lindex $atoms $i]
            }
        }
    }
    
    # all results are expanded.
    # now, clean the list. remove duplicates, convert to INT, sort numeric asc
    set max [lindex [lindex $ranges $index] end]
    set temp [dict create]
    foreach val $results {
       dict set temp [scan $val %d] 1
    }
    
    return [lsort -integer [dict keys $temp]]
}


# _next_possible()
#   Choose next possible value from list of numbers.
#   either the same, or higher value. or, the lowest possible in the list.
#
#   PARAMETERS
#       1. a starting number
#       2. a list of numbers
#
#   RETURNS 
#       A number
#
#**************************************
proc ::crontime::_next_possible {num args} {
    foreach val $args {
        if {$val >= $num} { return $val }    
    }
    
    return [lindex $args 0]
}


# _timesearch_mode()
#
# Based on an expanded cron list, determine what mode of operation is needed.
#
#   mode 0: WDAY field is wide open, so only focus on MDAY and MON fields.
#   mode 1: WDAY field is limited, but MON and MDAY fields are wide open.
#   mode 2: WDAY and MON fields are both limited, but MDAY is wide open.
#   mode 3: WDAY, MON, and MDAY fields are all limited. This is the worst case.
#
# PARAMS:
#  1. An expanded crontab list
#
# RETURNS:
#  a number (0-3)
#
#**************************************
proc ::crontime::_timesearch_mode {args} {  
    variable ranges

    set dmax [expr ([lindex [lindex $ranges 2] end] + 1) - \
                                                [lindex [lindex $ranges 2] 0] ]
    
    set mmax [expr ([lindex [lindex $ranges 3] end] + 1) - \
                                                [lindex [lindex $ranges 3] 0] ]
                                                 
    set wmax [expr ([lindex [lindex $ranges 4] end] + 1) - \
                                                [lindex [lindex $ranges 4] 0] ]
    
                                                
    if {$wmax == [llength [lindex $args 4]]} {
        
        return 0
        
    } elseif { $wmax != [llength [lindex $args 4]] && \ 
               $mmax != [llength [lindex $args 3]] && \
               $dmax != [llength [lindex $args 3]] } {
                   
        return 3
        
    } elseif { $wmax != [llength [lindex $args 4]] && \
               $mmax != [llength [lindex $args 3]] } {
                   
        return 2
        
    } else {
        
        return 1
        
    }

    return 0
}


# _next_dow_time()
#
# Return timestamp for the next occurence of the desired WDAY.
#
# PARAMS:
#  1. a DOW number.
#  2. (optional) a reference start time
#
# RETURNS:
#  A timestamp
#
#**************************************
proc ::crontime::_next_dow_time {num args} {
    if {$args != ""} {
	set stamp [lindex $args 0]
    } else {
	set stamp [clock seconds]
    }
    
    set tries 7
    
    while {$tries} {
	
	# reset H:M:S to zeros
	set stamp [clock scan [format "%d-%d-%d 00:00:00" \
				[clock format $stamp -format "%Y"] \
				[clock format $stamp -format "%m"] \
				[clock format $stamp -format "%d"] ] -format {%Y-%m-%d %H:%M:%S}]
	
	if {$num == [clock format $stamp -format "%w"]} {
	    return $stamp;
	}
	
	set stamp [clock add $stamp 1 day]
	incr tries -1
    }
    
    return {}
}


# _last_month_day()
#
# Return the last day of a month in a given year. either 28,29,30, or 31
#
# PARAMS:
#  1. a MON number
#  2. a YEAR number
#
# RETURNS:
#  A number
#
#**************************************
proc ::crontime::_last_month_day {mon year} {
    set day 28
    set stamp [clock scan [format "%d-%d-%d 00:00:00" $year $mon $day ] -format {%Y-%m-%d %H:%M:%S} ]
    
    while {$mon == [clock format $stamp -format "%m"]} {
	    set day [clock format $stamp -format "%d"]
	    set stamp [clock add $stamp 1 days]
    }
    
    return $day
}


