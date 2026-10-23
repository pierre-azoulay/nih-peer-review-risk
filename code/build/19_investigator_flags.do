/* =============================================================================
   code/build/19_investigator_flags.do

   Purpose: the investigator attributes that the descriptive, heterogeneity
            and robustness exhibits use, one row per cycle:
              new_inv     new investigator: the cycle starts in the
                          investigator's first year of any R01-equivalent
                          award (activity codes DP1, DP2, DP5, R01, R37, R56,
                          RL1, U01, R35, RF1, R29 and R23); Figure 5 and
                          Appendix Tables D1 to D3 and I1, among others
              esi         early-stage investigator: at most 10 years since the
                          degree at evaluation, 15 for an MD or MD-PhD
              elite       the investigator belongs to the elite in the year
                          before the cycle starts (cycle_yr - 1): elected to
                          the NAS or the IOM (now the National Academy of
                          Medicine) by then, or holding an HHMI appointment
                          then (start by then, end not before). The election
                          year counts; the one-year lag covers the delay to
                          induction and to an appointment's start. Figure 5
                          and Appendix Table I1
              elite_ever  ever Nobel, Lasker, HHMI, IOM or NAS (Table 1a)
              name_freq_authority  the frequency of the investigator's last
                          name: the number of Author-ity identifiers, over all
                          of Author-ity (2018), that share the last name once
                          standardized by supermessoudar; merged by author_id
                          (namefreq_authority.dta; Appendix Table A3)
              frac_pubs_nih share of the investigator's English original
                          research in Author-ity, 1980 on, whose PubMed grant
                          list names an NIH grant (agency containing
                          "NIH HHS"); the split of Appendix Table A4 uses the
                          same share measured when the cycle starts
                          (frac_pubs_nih_pre, code/build/20_record_before_cycle.do)
            The honors come from the file of honors of the investigators,
            stars_all_new.dta (key newsetnb, which is setnb). The log records
            the file's date, since a later edit of that file changes this
            build. namefreq_authority.dta, an input file of name frequencies
            (one row per Author-ity identifier matched to an investigator), is
            read as it is.

   Input:
     - ${data}/build/cycles.dta           (code/build/01_cycles.do)
     - ${data}/build/cycle_controls.dta   (code/build/04_cycle_controls.do)
     - ${input}/cgaf_nih_risk.dta   grant-year records
     - ${stars}/stars_all_new.dta   honors of the investigators, by newsetnb
     - ${input}/namefreq_authority.dta   frequency of the investigators' last
       names in Author-ity, by author_id
     - ${pubmed_root}/authority/authority_pmids_clean.dta,
       ${pubmed_root}/pubmed/overall_typology_2025.dta, overall_language_2025.dta,
       overall_dates_2025.dta, overall_grants_2025.dta

   Output:
     - ${data}/build/cycle_investigator.dta, one row per cycle
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;

log using "logs/19_investigator_flags.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. First year of an R01-equivalent award, by investigator
   ----------------------------------------------------------------------------- */
use setnb year activity using "${input}/cgaf_nih_risk.dta", clear ;
keep if inlist(activity, "DP1", "DP2", "DP5", "R01", "R37", "R56", "RL1", "U01", "R35")
      | inlist(activity, "RF1", "R29", "R23") ;
drop if setnb == "" ;
gcollapse (min) first_r01eq = year, by(setnb) ;
tempfile first ;
save `first' ;

/* -----------------------------------------------------------------------------
   2. Cycles, with the flags
   ----------------------------------------------------------------------------- */
use setnb project_number cycle cycle_yr eval_year author_id using "${data}/build/cycles.dta", clear ;
merge 1:1 setnb project_number cycle using "${data}/build/cycle_controls.dta", keepusing(age deg_cat) ;
tab _merge ;
assert _merge == 3 ;
drop _merge ;

merge m:1 setnb using `first' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
gen byte new_inv = (cycle_yr == first_r01eq) if !missing(first_r01eq) ;

gen byte esi = (age <= cond(inlist(deg_cat, 1, 3), 15, 10)) if !missing(age, deg_cat) ;

tempfile cyc0 ;
save `cyc0' ;

/* the honors, from the file of honors of the investigators (its date in the log) */
dir "${stars}/stars_all_new.dta" ;
use newsetnb hhmi start_hhmi end_hhmi nobel laskerclinical laskerbasic iom_year nas_year
    using "${stars}/stars_all_new.dta", clear ;
rename newsetnb setnb ;
gisid setnb ;
count if hhmi == 0 & !missing(start_hhmi) ;
display as text "HHMI dates with hhmi == 0 (the dates are used): " r(N) ;
tempfile honors ;
save `honors' ;

use `cyc0', clear ;
merge m:1 setnb using `honors' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
gen int t_elite = cycle_yr - 1 ;
gen byte hhmi_t = !missing(start_hhmi) & start_hhmi <= t_elite
                  & (missing(end_hhmi) | end_hhmi >= t_elite) ;
gen byte acad_t = (!missing(nas_year) & nas_year <= t_elite)
                  | (!missing(iom_year) & iom_year <= t_elite) ;
gen byte elite = hhmi_t | acad_t ;
tab hhmi_t acad_t ;
gen byte elite_ever = (hhmi == 1) | !missing(start_hhmi) | !missing(nobel) | !missing(laskerclinical)
                     | !missing(laskerbasic) | !missing(iom_year) | !missing(nas_year) ;
drop hhmi start_hhmi end_hhmi nobel laskerclinical laskerbasic iom_year nas_year t_elite hhmi_t acad_t ;

merge m:1 author_id using "${input}/namefreq_authority.dta", keepusing(namefreq) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
rename namefreq name_freq_authority ;
tempfile cyc ;
save `cyc' ;

/* -----------------------------------------------------------------------------
   3. Share of the investigator's papers with an NIH grant
   ----------------------------------------------------------------------------- */
use pmid agency using "${pubmed_root}/pubmed/overall_grants_2025.dta", clear ;
gen byte nih = strpos(agency, "NIH HHS") > 0 ;
gcollapse (max) nih, by(pmid) ;
tempfile nihpm ;
save `nihpm' ;

use pmid orgnl using "${pubmed_root}/pubmed/overall_typology_2025.dta", clear ;
gcollapse (max) orgnl, by(pmid) ;
tempfile typ ;
save `typ' ;
use pmid eng using "${pubmed_root}/pubmed/overall_language_2025.dta", clear ;
gcollapse (max) eng, by(pmid) ;
merge 1:1 pmid using `typ' ;
keep if _merge == 3 ;
drop _merge ;
keep if orgnl == 1 & eng == 1 ;
merge 1:1 pmid using "${pubmed_root}/pubmed/overall_dates_2025.dta", keepusing(year) ;
keep if _merge == 3 ;
drop _merge ;
keep if year >= 1980 ;
keep pmid ;
tempfile pm ;
save `pm' ;

use author_id using `cyc', clear ;
drop if author_id == "" ;
bysort author_id: keep if _n == 1 ;
tempfile aid ;
save `aid' ;
use author_id pmid using "${pubmed_root}/authority/authority_pmids_clean.dta", clear ;
merge m:1 author_id using `aid' ;
keep if _merge == 3 ;
drop _merge ;
bysort author_id pmid: keep if _n == 1 ;
merge m:1 pmid using `pm' ;
keep if _merge == 3 ;
drop _merge ;
merge m:1 pmid using `nihpm' ;
drop if _merge == 2 ;
replace nih = 0 if _merge == 1 ;
drop _merge ;
gcollapse (mean) frac_pubs_nih = nih (count) n_career_pubs = nih, by(author_id) ;
summarize frac_pubs_nih n_career_pubs, detail ;
tempfile share ;
save `share' ;

use `cyc', clear ;
merge m:1 author_id using `share' ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;

keep setnb project_number cycle first_r01eq new_inv esi elite elite_ever
     name_freq_authority frac_pubs_nih n_career_pubs ;
label variable first_r01eq   "First year of an R01-equivalent award (investigator)" ;
label variable new_inv       "Cycle starts in the investigator's first R01-equivalent year" ;
label variable esi           "Early-stage investigator: <= 10 years since degree (15 for MD, MD-PhD)" ;
label variable elite         "Elite the year before the cycle: NAS or IOM member, or HHMI investigator" ;
label variable elite_ever    "Ever Nobel, Lasker, HHMI, IOM or NAS" ;
label variable name_freq_authority "Author-ity identifiers sharing the standardized last name (Author-ity 2018)" ;
label variable frac_pubs_nih "Share of career papers (1980 on) with an NIH grant" ;
label variable n_career_pubs "Career papers in Author-ity, 1980 on (English original research)" ;
summarize new_inv esi elite elite_ever name_freq_authority frac_pubs_nih ;

sort setnb project_number cycle ;
compress ;
save "${data}/build/cycle_investigator.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
