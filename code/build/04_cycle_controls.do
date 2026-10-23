/* =============================================================================
   code/build/04_cycle_controls.do

   Purpose: The investigator and institution controls of Table 2 and its fixed-effect
            groups, one row per cycle:
            - amount_allgrants: NIH funding of the cycle's institution in the year
              before the evaluation year (centered five-year moving average, 2024
              dollars), 0 when missing; the institution is the one holding the grant
              in the cycle's last year of payments (ipf_eval), which after a transfer
              is the one that submits the renewal.
            - pi_careercites_evalyr: the stock of OpenAlex citations from PubMed
              papers to the investigator's Author-ity papers (English original
              research) through the year before the evaluation year; 0 when none.
            - pi_priorgrants_all: the investigator's NIH funding (2024 dollars) in all
              years before the cycle starts, summed by cycle.
            - age and its bins, the degree groups, and the fixed-effect groups.

   Input:
     - ${data}/build/cycles.dta                     (code/build/01_cycles.do)
     - ${cgaf}/data/CGAF_by_ipfcode.dta             institution x year funding
     - ${cgaf}/data/CGAF_all_2025_it.dta            investigator x year funding
     - ${pubmed_root}/authority/authority_pmids_clean.dta   Author-ity, author_id x pmid
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta
     - ${pubmed_root}/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta  citation panel

   Output:
     - ${data}/build/cycle_controls.dta   one row per setnb x project_number x cycle
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/04_cycle_controls.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. Cycles
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr eval_year cycle_length ipf_eval author_id
    deg deg_year ic irg_code first_is_renewal using "${data}/build/cycles.dta", clear ;
gisid setnb project_number cycle ;
tempfile cyc ;
save `cyc' ;

/* -----------------------------------------------------------------------------
   2. Institution funding in the year before the evaluation year
   ----------------------------------------------------------------------------- */
use new_ipfcode year amount_smth_jt using "${cgaf}/data/CGAF_by_ipfcode.dta", clear ;
rename (new_ipfcode amount_smth_jt) (ipf_eval amount_allgrants) ;
gisid ipf_eval year ;
tempfile inst ;
save `inst' ;

use setnb project_number cycle eval_year ipf_eval using `cyc', clear ;
gen int year = eval_year - 1 ;
merge m:1 ipf_eval year using `inst' ;
display as result "=== cycles matched to their institution's funding (1 = no row: funding 0)" ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
replace amount_allgrants = 0 if amount_allgrants == . ;
keep setnb project_number cycle amount_allgrants ;
tempfile c_inst ;
save `c_inst' ;

/* -----------------------------------------------------------------------------
   3. Prior NIH funding of the investigator, summed by cycle
   ----------------------------------------------------------------------------- */
use setnb using `cyc', clear ;
bysort setnb: keep if _n == 1 ;
tempfile setnbs ;
save `setnbs' ;
use setnb year amount_it using "${cgaf}/data/CGAF_all_2025_it.dta", clear ;
merge m:1 setnb using `setnbs' ;
display as result "=== investigator-years of funding: the cycle file's investigators (3)" ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
tempfile it ;
save `it' ;

use setnb project_number cycle cycle_yr using `cyc', clear ;
joinby setnb using `it' ;
keep if year < cycle_yr ;
gcollapse (sum) pi_priorgrants_all = amount_it, by(setnb project_number cycle) ;
tempfile c_prior ;
save `c_prior' ;

/* -----------------------------------------------------------------------------
   4. Career citations through the year before the evaluation year
   ----------------------------------------------------------------------------- */
/* paper filters, one row per PMID: English original research */
use pmid orgnl using "${pubmed_root}/pubmed/overall_typology_2025.dta", clear ;
gcollapse (max) orgnl, by(pmid) ;
tempfile typ ;
save `typ' ;
use pmid eng using "${pubmed_root}/pubmed/overall_language_2025.dta", clear ;
gcollapse (max) eng, by(pmid) ;
tempfile lng ;
save `lng' ;
use pmid year using "${pubmed_root}/pubmed/pubmed_universe_2025.dta", clear ;
bysort pmid: keep if _n == 1 ;
rename year pubyear ;
merge 1:1 pmid using `typ' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
merge 1:1 pmid using `lng' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
keep if orgnl == 1 & eng == 1 ;
keep pmid pubyear ;
tempfile pm ;
save `pm' ;

/* the investigators' Author-ity papers, with a numeric investigator key */
use author_id using `cyc', clear ;
drop if author_id == "" ;
bysort author_id: keep if _n == 1 ;
gen long aid = _n ;
tempfile aid ;
save `aid' ;
use author_id pmid using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `aid' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
bysort aid pmid: keep if _n == 1 ;  /* an author listed twice on a paper counts it once */
merge m:1 pmid using `pm' ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
display as result "=== Author-ity papers of the investigators: English original research (investigator x paper)" ;
count ;
keep aid pmid ;
tempfile authpm ;
save `authpm' ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile invpm ;
save `invpm' ;

/* citations to those papers, by citing year (the panel holds papers ever cited) */
use pmid year nbcites if nbcites > 0
    using "${pubmed_root}/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta", clear ;
merge m:1 pmid using `invpm' ;
keep if _merge == 3 ;
drop _merge ;
preserve ;
    keep pmid ;
    bysort pmid: keep if _n == 1 ;
    gen byte cited = 1 ;
    tempfile cited ;
    save `cited' ;
restore ;
joinby pmid using `authpm' ;
gcollapse (sum) cites = nbcites, by(aid year) ;

/* the stock through each year: a full investigator x year panel, cumulated */
fillin aid year ;
replace cites = 0 if _fillin ;
drop _fillin ;
sort aid year ;
by aid: gen double stk_cites = sum(cites) ;
summarize year ;
local cite_lo = r(min) ;
local cite_hi = r(max) ;
keep aid year stk_cites ;
tempfile stock ;
save `stock' ;

/* the papers' coverage: cited at least once in OpenAlex, by publication decade */
use `invpm', clear ;
merge 1:1 pmid using `pm', keepusing(pubyear) ;
keep if _merge == 3 ;
drop _merge ;
merge 1:1 pmid using `cited' ;
assert _merge != 2 ;
gen byte ever_cited = _merge == 3 ;
drop _merge ;
gen int decade = 10 * floor(pubyear / 10) ;
display as result "=== investigators' papers ever cited by a PubMed paper (OpenAlex), by decade" ;
tabstat ever_cited, by(decade) stat(n mean) ;

use setnb project_number cycle eval_year author_id using `cyc', clear ;
merge m:1 author_id using `aid', keepusing(aid) ;
assert _merge != 2 ;
drop _merge ;
gen int year = eval_year - 1 ;
assert inrange(year, `cite_lo', `cite_hi') ;
merge m:1 aid year using `stock' ;
display as result "=== cycles matched to a citation stock (1 = no cited paper: stock 0, or no Author-ity ID: missing)" ;
tab _merge ;
drop if _merge == 2 ;
gen double pi_careercites_evalyr = cond(_merge == 3, stk_cites, 0) if aid < . ;
keep setnb project_number cycle pi_careercites_evalyr ;
tempfile c_cites ;
save `c_cites' ;

/* -----------------------------------------------------------------------------
   5. Assemble: logs, age, degree, fixed-effect groups
   ----------------------------------------------------------------------------- */
use `cyc', clear ;
merge 1:1 setnb project_number cycle using `c_inst' ;
assert _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using `c_cites' ;
assert _merge == 3 ;
drop _merge ;
merge 1:1 setnb project_number cycle using `c_prior' ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
replace pi_priorgrants_all = 0 if pi_priorgrants_all == . ;

gen double log_amount_allgrants      = ln(amount_allgrants + 1) ;
gen double log_pi_careercites_evalyr = ln(pi_careercites_evalyr + 1) ;
gen byte   no_pi_priorgrants         = pi_priorgrants_all == 0 ;
gen double log_pi_priorgrants_all    = cond(no_pi_priorgrants, 0, ln(pi_priorgrants_all)) ;

/* age at the evaluation year (years since the latest degree), in five-year bins */
gen int age = eval_year - deg_year ;
gen byte agepi_under5 = age <= 5             if age < . ;
gen byte agepi_5t10   = age >  5 & age <= 10 if age < . ;
gen byte agepi_10t15  = age > 10 & age <= 15 if age < . ;
gen byte agepi_15t20  = age > 15 & age <= 20 if age < . ;
gen byte agepi_20t25  = age > 20 & age <= 25 if age < . ;
gen byte agepi_25t30  = age > 25 & age <= 30 if age < . ;
gen byte agepi_30t35  = age > 30 & age <= 35 if age < . ;
gen byte agepi_35t40  = age > 35 & age <= 40 if age < . ;
gen byte agepi_40plus = age > 40             if age < . ;

/* degree: MD, PhD, MD-PhD, other */
gen byte deg_cat = deg ;
replace deg_cat = 4 if inlist(deg, 5, 6, 7) ;

/* fixed-effect groups. The first evaluation years are thin (4 sample cycles in 1980,
   66 in 1981) and join 1982. */
gen int new_eval_year = max(eval_year, 1982) ;
gen byte new_cycle_length = min(cycle_length, 10) ;
egen long ic_irg = group(ic irg_code), label ;
/* the cycle's number within the grant, unknown when the grant's first record is a renewal */
gegen byte fir = max(first_is_renewal), by(setnb project_number) ;
gen byte cycle_nb = cycle if fir == 0 ;
drop fir ;

capture label drop degcat ;
label define degcat 1 "MD" 2 "PhD" 3 "MD-PhD" 4 "Other" ;
label values deg_cat degcat ;
label var amount_allgrants          "NIH funding of the institution (ipf_eval), eval_year-1, 2024 dollars, 5-yr MA" ;
label var log_amount_allgrants      "ln(amount_allgrants + 1)" ;
label var pi_careercites_evalyr     "Citations to the investigator's papers through eval_year-1 (OpenAlex)" ;
label var log_pi_careercites_evalyr "ln(pi_careercites_evalyr + 1)" ;
label var pi_priorgrants_all        "Investigator's NIH funding before cycle_yr, 2024 dollars" ;
label var log_pi_priorgrants_all    "ln(pi_priorgrants_all), 0 when none" ;
label var no_pi_priorgrants         "No NIH funding before the cycle" ;
label var age                       "eval_year - deg_year" ;
label var deg_cat                   "Degree: MD, PhD, MD-PhD, other" ;
label var new_eval_year             "Evaluation year, 1980 and 1981 pooled with 1982" ;
label var new_cycle_length          "Cycle length, top-coded at 10" ;
label var ic_irg                    "Institute x study section" ;
label var cycle_nb                  "Cycle number within the grant, missing if first_is_renewal" ;
keep setnb project_number cycle amount_allgrants log_amount_allgrants pi_careercites_evalyr
     log_pi_careercites_evalyr pi_priorgrants_all log_pi_priorgrants_all no_pi_priorgrants
     age agepi_* deg_cat new_eval_year new_cycle_length ic_irg cycle_nb ;
order setnb project_number cycle amount_allgrants log_amount_allgrants pi_careercites_evalyr
      log_pi_careercites_evalyr pi_priorgrants_all log_pi_priorgrants_all no_pi_priorgrants
      age agepi_* deg_cat new_eval_year new_cycle_length ic_irg cycle_nb ;
label data "Cycle-level investigator and institution controls, nih_risk" ;
notes: Built `c(current_date)' by code/build/04_cycle_controls.do. ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_controls.dta", replace ;

/* -----------------------------------------------------------------------------
   6. First look: sample cycles
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta",
    keepusing(in_sample sep renewed cycle_yr new_ipfcode ipf_eval) ;
assert _merge == 3 ;
drop _merge ;
keep if in_sample & sep != 1 ;
display as result "=== sample cycles: controls by renewal" ;
tabstat log_amount_allgrants log_pi_careercites_evalyr log_pi_priorgrants_all
    no_pi_priorgrants age, by(renewed) stat(mean sd) ;
display as result "=== sample cycles: institution at the last payment differs from the first year's" ;
count if ipf_eval != new_ipfcode ;
display as result "=== sample cycles with zero institution funding, zero career citations" ;
count if amount_allgrants == 0 ;
count if pi_careercites_evalyr == 0 ;
tab deg_cat ;
tab new_cycle_length ;
tab cycle_nb, missing ;
count if ic_irg == . ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/04_cycle_controls.do */
