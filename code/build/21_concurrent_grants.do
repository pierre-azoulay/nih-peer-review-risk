/* =============================================================================
   code/build/21_concurrent_grants.do

   Purpose: the investigator's other R01-equivalent grants, one row per cycle:
              n_other_r01  the number of distinct R01-equivalent grants other
                           than the cycle's own on which the investigator
                           (setnb) has a record in the cycle's evaluation year
              multi_r01    n_other_r01 >= 1
              n_other_r01_start, multi_r01_start  the same in the cycle's
                           first year (cycle_yr), fixed before the cycle's
                           work: a grant won during the cycle does not count,
                           where the evaluation-year count may partly mark the
                           cycle's success. multi_r01_start is the trait
                           "another R01-equivalent grant" of Figure 5 and
                           Appendix Table I1
            R01 equivalents here: R01, R37, R29, R23 (not R56, not U01). A
            grant is ic + grantno, as project_number is built
            (code/build/01_cycles.do), so "other" means a different
            ic + grantno; an AM grant takes its successor's number across the
            1986 split (am_successor.dta). Every grant of the records counts,
            not only the grants first funded 1980 to 2015 that make the cycle
            file, and every record counts as a payment (260 of the 1.6 million
            R01-equivalent records carry no dollars).

   Input:
     - ${input}/cgaf_nih_risk.dta   grant-year records, FY1938 to 2025
     - ${data}/build/cycles.dta         (code/build/01_cycles.do)
     - ${data}/build/am_successor.dta   (code/build/01_cycles.do)

   Output:
     - ${data}/build/cycle_concurrent.dta, one row per setnb project_number cycle
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

log using "logs/21_concurrent_grants.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. The investigators' R01-equivalent grants, by year: one row per
      investigator x year x grant
   ----------------------------------------------------------------------------- */
use setnb year activity ic grantno apptype using "${input}/cgaf_nih_risk.dta", clear ;
keep if inlist(activity, "R01", "R37", "R29", "R23") ;
drop if setnb == "" ;
display as result "R01-equivalent grant-year records: " _N ;
gen str8 pn_am = ic + grantno ;
/* AM grants carry the project number of their DK or AR successor, as in the cycle file */
merge m:1 pn_am using "${data}/build/am_successor.dta", keepusing(pn_succ) ;
tab _merge ;
drop if _merge == 2 ;
replace pn_am = pn_succ if _merge == 3 ;
drop _merge pn_succ ;
rename pn_am project_number ;
keep setnb year project_number grantno ;
gduplicates drop setnb year project_number, force ;
display as result "investigator x year x grant: " _N ;

/* the same grant number under two institutes in one year: counted as two
   grants under the rule ic + grantno; how often it touches a cycle is logged
   in section 2 */
gegen byte n_ic_same_no = count(year), by(setnb year grantno) ;
drop grantno ;
tempfile syg ;
save `syg' ;

gcollapse (count) n_r01_yr = n_ic_same_no, by(setnb year) ;
label variable n_r01_yr "R01-equivalent grants with a record, investigator x year" ;
tabulate n_r01_yr ;
tempfile sy ;
save `sy' ;

/* -----------------------------------------------------------------------------
   2. Cycles: the investigator's grants in the evaluation year, less the
      cycle's own
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr eval_year using "${data}/build/cycles.dta", clear ;
gisid setnb project_number cycle ;
display as result "cycles: " _N ;
gen int year = eval_year ;

/* is the cycle's own grant among the evaluation year's records? (it should
   be: the evaluation year is the cycle's last payment year) */
merge m:1 setnb year project_number using `syg', keepusing(n_ic_same_no) ;
tab _merge ;
drop if _merge == 2 ;
gen byte own_paid = _merge == 3 ;
drop _merge ;
tab own_paid ;

merge m:1 setnb year using `sy' ;
tab _merge ;
drop if _merge == 2 ;
replace n_r01_yr = 0 if _merge == 1 ;
drop _merge ;

gen int n_other_r01 = n_r01_yr - own_paid ;
assert n_other_r01 >= 0 & !missing(n_other_r01) ;
gen byte multi_r01 = n_other_r01 >= 1 ;

/* cycles where an "other" grant is the cycle's own grant number under
   another institute (the rule ic + grantno counts it as another grant) */
count if n_ic_same_no >= 2 & !missing(n_ic_same_no) ;
display as result "cycles with the own grant number under a second institute: " r(N) ;

label variable n_other_r01 "Other R01-equivalent grants (ic+grantno) with a record in eval_year" ;
label variable multi_r01   "Holds another R01-equivalent grant in eval_year" ;

gen byte n_other_cat = min(n_other_r01, 3) ;
tabulate n_other_cat ;
summarize n_other_r01 multi_r01, detail ;

/* -----------------------------------------------------------------------------
   3. The same count in the cycle's first year (cycle_yr), fixed before the
      cycle's work
   ----------------------------------------------------------------------------- */
drop year n_ic_same_no n_r01_yr ;
gen int year = cycle_yr ;
merge m:1 setnb year project_number using `syg', keepusing(n_ic_same_no) ;
tab _merge ;
drop if _merge == 2 ;
gen byte own_paid_s = _merge == 3 ;
drop _merge n_ic_same_no ;
display as text "the cycle's own grant has a record in its first year:" ;
tab own_paid_s ;
merge m:1 setnb year using `sy' ;
tab _merge ;
drop if _merge == 2 ;
replace n_r01_yr = 0 if _merge == 1 ;
drop _merge ;
gen int n_other_r01_start = n_r01_yr - own_paid_s ;
assert n_other_r01_start >= 0 & !missing(n_other_r01_start) ;
gen byte multi_r01_start = n_other_r01_start >= 1 ;
label variable n_other_r01_start "Other R01-equivalent grants (ic+grantno) with a record in cycle_yr" ;
label variable multi_r01_start   "Holds another R01-equivalent grant in cycle_yr" ;
display as text "another R01 at the start of the cycle against another R01 at the evaluation" ;
tab multi_r01_start multi_r01, cell ;

keep setnb project_number cycle n_other_r01 multi_r01 n_other_r01_start multi_r01_start ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_concurrent.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
