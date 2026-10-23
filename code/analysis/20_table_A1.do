/* =============================================================================
   code/analysis/20_table_A1.do

   Purpose: Appendix Table A1, the cycles without an acknowledging publication
            (n_ackn == 0) and with exactly one (n_ackn == 1): their numbers,
            their shares and their renewal rates, for all cycles, first
            cycles (cycle_nb == 1) and later ones (cycle_nb >= 2). Cycles of
            grants first observed at a renewal, whose cycle number is unknown
            (cycle_nb missing), count in "all cycles" only. Cycles without an
            acknowledging publication have none of the four measures; cycles
            with exactly one have no measure of extreme tail outcomes. The
            log also gives the counts that Appendix A's text and Table A1's
            notes quote: the cycles whose cycle number is unknown, and the
            share without an acknowledging publication by decade of the
            cycle's start.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/tables/table_A1.tex   Table A1, rows only (file write)
     - estimates/table_A1.dta       the numbers of Table A1
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 3 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/20_table_A1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;

/* -----------------------------------------------------------------------------
   Table A1: cycles without acknowledging publications
   ----------------------------------------------------------------------------- */
gen byte paperless = n_ackn == 0 ;
gen byte onepaper  = n_ackn == 1 ;
gen byte grp_first = cycle_nb == 1 ;
gen byte grp_later = cycle_nb >= 2 & !missing(cycle_nb) ;
gen byte grp_all   = 1 ;

tab paperless renewed, row ;
tab paperless grp_first if !missing(cycle_nb), col ;
count if missing(cycle_nb) ;
tab paperless if missing(cycle_nb) ;

/* the share by decade of the cycle's start (Appendix A quotes it, from the
   1980s to the years after 2010) */
gen int decade = 10 * floor(cycle_yr / 10) ;
tab decade paperless, row ;
drop decade ;

/* paperless first cycles without an Author-ity identifier: for them, the
   lagged risk of Table A2 (the investigator's record before the grant)
   cannot be computed */
count if paperless & grp_first & !has_author_id ;
display as result "paperless first cycles without an author identifier: " r(N) ;
count if paperless & grp_first ;

tempname pf ;
postfile `pf' str5 grp long(n n0 n1) double(sh0 sh1 rr0 rr_oth rr1) using "estimates/table_A1.dta", replace ;
foreach g in all first later {;
    quietly count if grp_`g' ;
    local n = r(N) ;
    quietly count if grp_`g' & paperless ;
    local n0 = r(N) ;
    quietly count if grp_`g' & onepaper ;
    local n1 = r(N) ;
    quietly summarize renewed if grp_`g' & paperless ;
    local rr0 = r(mean) ;
    quietly summarize renewed if grp_`g' & !paperless ;
    local rr_oth = r(mean) ;
    quietly summarize renewed if grp_`g' & onepaper ;
    local rr1 = r(mean) ;
    post `pf' ("`g'") (`n') (`n0') (`n1') (`n0'/`n') (`n1'/`n') (`rr0') (`rr_oth') (`rr1') ;
} ;
postclose `pf' ;

preserve ;
    use "estimates/table_A1.dta", clear ;
    list, noobs ;
    forvalues i = 1/3 {;
        local c_n`i'  = string(n[`i'], "%12.0fc") ;
        local c_0`i'  = string(n0[`i'], "%12.0fc") + " (" + string(100*sh0[`i'], "%4.1f") + "\%)" ;
        local c_1`i'  = string(n1[`i'], "%12.0fc") + " (" + string(100*sh1[`i'], "%4.1f") + "\%)" ;
        local c_r0`i' = string(rr0[`i'], "%5.3f") ;
        local c_ro`i' = string(rr_oth[`i'], "%5.3f") ;
        local c_r1`i' = string(rr1[`i'], "%5.3f") ;
    } ;
restore ;

tempname fh ;
file open `fh' using "output/tables/table_A1.tex", write replace ;
file write `fh' " & All cycles & First cycles & Later cycles \\" _n ;
file write `fh' "\midrule" _n ;
file write `fh' "Nb. of cycles facing renewal & `c_n1' & `c_n2' & `c_n3' \\" _n ;
file write `fh' "Nb. (share) with no acknowledging paper & `c_01' & `c_02' & `c_03' \\" _n ;
file write `fh' "Nb. (share) with exactly one acknowledging paper & `c_11' & `c_12' & `c_13' \\" _n ;
file write `fh' "\addlinespace" _n ;
file write `fh' "Renewal rate, cycles with no acknowledging paper & `c_r01' & `c_r02' & `c_r03' \\" _n ;
file write `fh' "Renewal rate, all other cycles & `c_ro1' & `c_ro2' & `c_ro3' \\" _n ;
file write `fh' "Renewal rate, cycles with exactly one acknowledging paper & `c_r11' & `c_r12' & `c_r13' \\" _n ;
file close `fh' ;
type "output/tables/table_A1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
