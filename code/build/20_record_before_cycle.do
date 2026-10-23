/* =============================================================================
   code/build/20_record_before_cycle.do

   Purpose: the rows of Table 1b that describe the investigator when the cycle
            starts, the NIH-funded share of the cycle's other papers, and the
            NIH-funded share of the investigator's earlier papers:
              pi_pubs_precycle   the investigator's English original research
                                 in Author-ity published before cycle_yr
              pi_cites_precycle  OpenAlex citations from PubMed papers to those
                                 papers through cycle_yr - 1, the stock of
                                 code/build/04_cycle_controls.do, section 4
                                 (career citations), taken at the cycle's start
                                 rather than the year before evaluation, so
                                 that both rows describe the same moment (the
                                 regression control of Table 2 stays at the
                                 evaluation year). Its log is the career-
                                 citation control of Appendix Tables A2, G4
                                 and G5
              frac_noackn_nih    share of the cycle's other papers
                                 (cycle_papers.dta, ackn == 0) whose PubMed
                                 grant list names an NIH grant, as in
                                 code/build/19_investigator_flags.do; these
                                 papers do not acknowledge the focal grant, so
                                 the share counts the investigator's other NIH
                                 grants, collaborators' grants, and links
                                 RePORTER misses
              frac_pubs_nih_pre  share of the investigator's English original
                                 research published from 1980 to cycle_yr - 1
                                 whose PubMed grant list names an NIH grant:
                                 frac_pubs_nih of 19_investigator_flags.do,
                                 measured when the cycle starts, so that the
                                 split of Appendix Table A4 cannot reflect the
                                 cycle's outcome (the career share counts
                                 papers published after the renewal decision);
                                 n_pubs_nih_pre, the papers behind it
            Missing for investigators without an Author-ity ID (first two),
            for cycles without another paper (the third), and for cycles whose
            investigator has no paper from 1980 to cycle_yr - 1 (the fourth).

   Input:
     - ${data}/build/cycles.dta         (code/build/01_cycles.do)
     - ${data}/build/cycle_papers.dta   (code/build/03_cycle_papers.do)
     - ${pubmed_root}/authority/authority_pmids_clean.dta
     - ${pubmed_root}/pubmed/pubmed_universe_2025.dta, overall_typology_2025.dta,
       overall_language_2025.dta, overall_grants_2025.dta
     - ${pubmed_root}/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta

   Output:
     - ${data}/build/cycle_record.dta, one row per cycle
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/20_record_before_cycle.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use setnb project_number cycle cycle_yr author_id using "${data}/build/cycles.dta", clear ;
gisid setnb project_number cycle ;
tempfile cyc ;
save `cyc' ;

/* -----------------------------------------------------------------------------
   1. The investigators' English original research in Author-ity
   (the filters of code/build/04_cycle_controls.do, section 4)
   ----------------------------------------------------------------------------- */
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
keep aid pmid pubyear ;
tempfile authpm ;
save `authpm' ;

/* papers whose PubMed grant list names an NIH grant (sections 3b and 4) */
use pmid agency using "${pubmed_root}/pubmed/overall_grants_2025.dta", clear ;
gen byte nih = strpos(agency, "NIH HHS") > 0 ;
gcollapse (max) nih, by(pmid) ;
tempfile nihpm ;
save `nihpm' ;
use `authpm', clear ;

/* publications by year, cumulated: the count before each year */
gen byte one = 1 ;
gcollapse (sum) npubs = one, by(aid pubyear) ;
rename pubyear year ;
fillin aid year ;
replace npubs = 0 if _fillin ;
drop _fillin ;
sort aid year ;
by aid: gen double stk_pubs = sum(npubs) ;
keep aid year stk_pubs ;
summarize year ;
local pub_lo = r(min) ;
local pub_hi = r(max) ;
tempfile pstock ;
save `pstock' ;

/* -----------------------------------------------------------------------------
   2. Citations to those papers by citing year, cumulated (as in
      code/build/04_cycle_controls.do)
   ----------------------------------------------------------------------------- */
use `authpm', clear ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
tempfile invpm ;
save `invpm' ;
use pmid year nbcites if nbcites > 0
    using "${pubmed_root}/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta", clear ;
merge m:1 pmid using `invpm' ;
keep if _merge == 3 ;
drop _merge ;
joinby pmid using `authpm' ;
drop pubyear ;
gcollapse (sum) cites = nbcites, by(aid year) ;
fillin aid year ;
replace cites = 0 if _fillin ;
drop _fillin ;
sort aid year ;
by aid: gen double stk_cites = sum(cites) ;
summarize year ;
local cite_lo = r(min) ;
local cite_hi = r(max) ;
keep aid year stk_cites ;
tempfile cstock ;
save `cstock' ;

/* -----------------------------------------------------------------------------
   3. Each cycle at its start: the stocks through cycle_yr - 1
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr author_id using `cyc', clear ;
merge m:1 author_id using `aid', keepusing(aid) ;
assert _merge != 2 ;
drop _merge ;
gen int year = cycle_yr - 1 ;
assert inrange(year, `cite_lo', `cite_hi') ;
merge m:1 aid year using `cstock' ;
display as result "=== cycles matched to a citation stock (1 = no cited paper: stock 0, or no Author-ity ID: missing)" ;
tab _merge ;
drop if _merge == 2 ;
gen double pi_cites_precycle = cond(_merge == 3, stk_cites, 0) if aid < . ;
drop _merge stk_cites ;
/* fillin gave every investigator a row for every year of the panel, so an
   investigator with an English original paper always matches; one without
   any has a count of 0 */
assert inrange(year, `pub_lo', `pub_hi') ;
merge m:1 aid year using `pstock' ;
display as result "=== cycles matched to a publication stock (1 = no paper: 0, or no Author-ity ID: missing)" ;
tab _merge ;
drop if _merge == 2 ;
gen double pi_pubs_precycle = cond(_merge == 3, stk_pubs, 0) if aid < . ;
drop _merge stk_pubs year ;
keep setnb project_number cycle pi_pubs_precycle pi_cites_precycle ;
tempfile rec ;
save `rec' ;

/* -----------------------------------------------------------------------------
   3b. NIH-funded share of the investigator's papers before the cycle, 1980 on
   (frac_pubs_nih of code/build/19_investigator_flags.do, taken at cycle_yr - 1)
   ----------------------------------------------------------------------------- */
use aid pmid pubyear using `authpm' if pubyear >= 1980, clear ;
merge m:1 pmid using `nihpm' ;
drop if _merge == 2 ;
replace nih = 0 if _merge == 1 ;
drop _merge ;
gen byte one = 1 ;
gcollapse (sum) npubs = one nnih = nih, by(aid pubyear) ;
rename pubyear year ;
fillin aid year ;
replace npubs = 0 if _fillin ;
replace nnih  = 0 if _fillin ;
drop _fillin ;
sort aid year ;
by aid: gen double stk_n   = sum(npubs) ;
by aid: gen double stk_nih = sum(nnih) ;
keep aid year stk_n stk_nih ;
tempfile nstock ;
save `nstock' ;

/* a cycle starting in 1980 looks at 1979, before the window: no paper */
use setnb project_number cycle cycle_yr author_id using `cyc', clear ;
merge m:1 author_id using `aid', keepusing(aid) ;
assert _merge != 2 ;
drop _merge ;
gen int year = cycle_yr - 1 ;
merge m:1 aid year using `nstock' ;
display as result "=== cycles matched to a 1980-on publication stock (1 = no paper since 1980, or no Author-ity ID)" ;
tab _merge ;
drop if _merge == 2 ;
gen double n_pubs_nih_pre    = cond(_merge == 3, stk_n, 0) if aid < . ;
gen double frac_pubs_nih_pre = stk_nih / stk_n if _merge == 3 & stk_n > 0 ;
drop _merge stk_n stk_nih year ;
keep setnb project_number cycle n_pubs_nih_pre frac_pubs_nih_pre ;
merge 1:1 setnb project_number cycle using `rec' ;
assert _merge == 3 ;
drop _merge ;
save `rec', replace ;

/* -----------------------------------------------------------------------------
   4. NIH-funded share of the cycle's other papers
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 0 ;
drop ackn ;
merge m:1 pmid using `nihpm' ;
tab _merge ;
drop if _merge == 2 ;
replace nih = 0 if _merge == 1 ;
drop _merge ;
gcollapse (mean) frac_noackn_nih = nih, by(setnb project_number cycle) ;
tempfile share ;
save `share' ;

use `rec', clear ;
merge 1:1 setnb project_number cycle using `share' ;
tab _merge ;
assert _merge != 2 ;
drop _merge ;
label variable pi_pubs_precycle  "Investigator's English original research before cycle_yr (Author-ity)" ;
label variable pi_cites_precycle "Citations to the investigator's papers through cycle_yr-1 (OpenAlex)" ;
label variable frac_noackn_nih   "Share of the cycle's other papers listing an NIH grant (PubMed)" ;
label variable frac_pubs_nih_pre "Share of the investigator's papers, 1980 to cycle_yr-1, listing an NIH grant" ;
label variable n_pubs_nih_pre    "Investigator's papers, 1980 to cycle_yr-1, behind frac_pubs_nih_pre" ;
summarize pi_pubs_precycle pi_cites_precycle frac_noackn_nih frac_pubs_nih_pre n_pubs_nih_pre, detail ;

sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_record.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
