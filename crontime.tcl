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
                            {} \
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
        set tstamp [lindex $args 0]
    } else {
        set tstamp [clock seconds]    
    }
    
    set atoms [::crontime::expand $cron]
    set mday 0
    
    foreach key [lsort -integer [dict keys $formatmap]] {
        set found 0
        
        # extract our value from clock format, and convert to INT number
        set val [expr [clock format $tstamp -format [dict get $formatmap $key]]]
        
        if {[regexp "\\y$val\\y" [lindex $atoms $key]]} {
            set found 1
            if {$key == 2} {
                set mday 1
            }    
        }
        
        if {$key == 2 && ! $found && [llength [lindex $atoms 4]] < 7} {
            # For some complex cases(like, "30 08 1 10 Tue"), a cron is valid
            # in TWO situations:
            #  - 08:30am on October 1st.
            #  - 08:30am on EVERY Tuesday in October.
            # So, do not be too hasty to abort if the MDAY field doesn't match,
            # because WDAY needs to be given opportunity to match in some cases  
            continue       
        }
        
        if {$key == 4} {
            if {$found} {
                return 1
            }
            if {! $found && $mday} {
                return 1
            }
        }
         
        if {! $found} {
            return 0
        } 
    }
    
    return 0
}


# expand()
#   Expand a cron time entry into lists of possible numbers
#
#   This function is mostly used internally by this package, but
#   may prove useful for other things too.
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
    
    # iterate over each segment, and expand all possibilities into 
    # a list of numbers.
    for {set index 0} {$index < [llength $segments]} {incr index} {
        set tmp [::crontime::_expand_cron_index [lindex $segments $index] $index]
        lappend atoms $tmp
    }
    
    return $atoms    
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
       dict set temp [expr $val] 1
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
        if {$val >= $num} {
            return $val
        }    
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


