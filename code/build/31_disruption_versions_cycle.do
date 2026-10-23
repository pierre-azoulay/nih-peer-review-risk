/* =============================================================================
   code/build/31_disruption_versions_cycle.do

   Purpose: The versions of the disruption measure that Appendix Tables C1 and
            C2 compare, at the cycle level (code/analysis/25_tables_C1_C2.do).
            From the percentiles of code/build/30_disruption_versions.do, for
            each cycle's acknowledging publications:
            - dmax_<tag>, dn_<tag>: the highest percentile of each version
              of the index (0-1) and the publications behind it, for the
              tags of 30_disruption_versions.do (base di1 d5n di5 w5 w10 nslf
              orgnl ge5 ge10 ge20 cit ref) and fl, the paper's percentile on
              the publications on which the investigator is first, last or
              single author;
            - dmean, dmed: the mean and the median of the paper's percentile;
            - dshq, dshd: the share of the publications with an index whose
              percentile is 75 or more (top quartile of their year), 90 or
              more (top decile);
            - drawmax, drawmean: the highest and the mean raw index DI_1^nok;
            - c_p50, c_mean, n_cp: the median and the mean five-year citation
              percentile (0-1) of the publications with an index and a
              citation percentile, and their number; c_atmax: the citation
              percentile of the publication that sets dmax_base (the mean
              over ties);
            - any1, any5: at least one publication at +1 on the index with
              one shared reference (among those with an index), with five
              (among those with the five-reference version).
            Check (asserted): dmax_base, dn_base and dmean equal the stored
            measure of code/build/08_disruption.do on every cycle. The last
            section describes the versions on the analysis cycles, in the
            log.

   Input:
     - ${data}/build/cycle_papers.dta              (code/build/03_cycle_papers.do)
     - ${data}/build/paper_attributes.dta          (code/build/05_paper_attributes.do),
                                                   cite5_pctl
     - ${data}/build/paper_disruption_versions.dta (code/build/30_disruption_versions.do)
     - ${data}/build/risk_disruption.dta           (code/build/08_disruption.do),
                                                   for the check
     - ${data}/build/cycles.dta                    (code/build/01_cycles.do),
                                                   for the last section

   Output:
     - ${data}/build/risk_disruption_versions.dta   setnb project_number cycle
                                                    and the variables above,
                                                    cycles with an index
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/31_disruption_versions_cycle.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* -----------------------------------------------------------------------------
   1. The acknowledging publications and their versions of the index
   ----------------------------------------------------------------------------- */
use setnb project_number cycle pmid ackn author_seq nb_authrs using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
merge m:1 pmid using "${data}/build/paper_disruption_versions.dta" ;
tab _merge ;
drop if _merge == 2 ;
display as result "=== cycle x publication pairs whose publication is absent from the index file (_merge == 1)" ;
count if _merge == 1 ;
drop _merge ;
merge m:1 pmid using "${data}/build/paper_attributes.dta", keepusing(cite5_pctl) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 ;
drop _merge ;

/* publication-level ingredients */
gen double p_fl = p_base if !missing(author_seq) & (author_seq == 1 | author_seq == nb_authrs) ;
gen byte q75 = p_base >= 75 if !missing(p_base) ;
gen byte q90 = p_base >= 90 if !missing(p_base) ;
gen double cpd = cite5_pctl if !missing(p_base) ;
gegen double mx = max(p_base), by(setnb project_number cycle) ;
gen double cmx = cite5_pctl if !missing(p_base) & p_base == mx ;
gen byte top1 = di1_nok == 1 if !missing(di1_nok) ;
gen byte top5 = di5_nok == 1 if !missing(p_d5n) ;

/* -----------------------------------------------------------------------------
   2. The cycle's measures
   ----------------------------------------------------------------------------- */
local tags "base di1 d5n di5 w5 w10 nslf orgnl ge5 ge10 ge20 cit ref fl" ;
local mxl "" ;
local cnl "" ;
foreach t of local tags {;
    local mxl "`mxl' dmax_`t' = p_`t'" ;
    local cnl "`cnl' dn_`t' = p_`t'" ;
} ;
gcollapse (max) `mxl' drawmax = di1_nok any1 = top1 any5 = top5
          (count) `cnl' n_cp = cpd
          (mean) dmean = p_base dshq = q75 dshd = q90 drawmean = di1_nok c_mean = cpd c_atmax = cmx
          (p50) dmed = p_base c_p50 = cpd,
          by(setnb project_number cycle) ;
foreach t of local tags {;
    replace dmax_`t' = dmax_`t' / 100 ;
} ;
foreach v in dmean dmed c_mean c_atmax c_p50 {;
    replace `v' = `v' / 100 ;
} ;
egen int dn_any = rowmax(dn_*) ;
keep if dn_any > 0 ;
drop dn_any ;

/* -----------------------------------------------------------------------------
   3. Check against the stored measure
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/risk_disruption.dta" ;
tab _merge ;
assert _merge != 2 ;
display as result "=== check: the paper's measure, its count and its mean equal the stored ones" ;
count if _merge == 3 & (abs(dmax_base - di1nok_ackn_maxpctl) > 1e-9 | dn_base != n_disr | abs(dmean - di1nok_ackn_meanpctl) > 1e-9) ;
assert r(N) == 0 ;
count if _merge == 1 ;
assert r(N) == 0 ;
drop _merge di1nok_ackn_maxpctl di1nok_ackn_meanpctl n_disr ;

/* -----------------------------------------------------------------------------
   4. Labels and save
   ----------------------------------------------------------------------------- */
label variable dmax_base "Disruption, the paper's measure: max within-year pctl of DI_1^nok (0-1)" ;
label variable dmax_di1  "Max within-year pctl of DI_1, with N_k (0-1)" ;
label variable dmax_d5n  "Max within-year pctl of DI_5^nok, five shared references (0-1)" ;
label variable dmax_di5  "Max within-year pctl of DI_5, with N_k (0-1)" ;
label variable dmax_w5   "Max within-year pctl of DI_1^nok, citers within 5 years (0-1)" ;
label variable dmax_w10  "Max within-year pctl of DI_1^nok, citers within 10 years (0-1)" ;
label variable dmax_nslf "Max within-year pctl of DI_1^nok, no self-citations (0-1)" ;
label variable dmax_orgnl "Max within-year pctl of DI_1^nok, original-research citers (0-1)" ;
label variable dmax_ge5  "Max within-year pctl of DI_1^nok, citers with 5+ references (0-1)" ;
label variable dmax_ge10 "Max within-year pctl of DI_1^nok, citers with 10+ references (0-1)" ;
label variable dmax_ge20 "Max within-year pctl of DI_1^nok, citers with 20+ references (0-1)" ;
label variable dmax_cit  "Max pctl of DI_1^nok within year x citation bin (0-1)" ;
label variable dmax_ref  "Max pctl of DI_1^nok within year x reference-count bin (0-1)" ;
label variable dmax_fl   "Max within-year pctl of DI_1^nok, first- or last-author papers (0-1)" ;
foreach t of local tags {;
    label variable dn_`t' "Acknowledging papers behind dmax_`t'" ;
} ;
label variable dmean    "Mean within-year pctl of DI_1^nok, acknowledging papers (0-1)" ;
label variable dmed     "Median within-year pctl of DI_1^nok, acknowledging papers (0-1)" ;
label variable dshq     "Share of papers with an index in the top quartile of their year" ;
label variable dshd     "Share of papers with an index in the top decile of their year" ;
label variable drawmax  "Highest raw DI_1^nok among acknowledging papers" ;
label variable drawmean "Mean raw DI_1^nok among acknowledging papers" ;
label variable c_p50    "Median 5-year citation pctl of the papers with an index (0-1)" ;
label variable c_mean   "Mean 5-year citation pctl of the papers with an index (0-1)" ;
label variable c_atmax  "5-year citation pctl of the paper setting dmax_base, mean over ties (0-1)" ;
label variable n_cp     "Papers with an index and a citation percentile" ;
label variable any1     "At least one paper at +1 on DI_1^nok" ;
label variable any5     "At least one paper at +1 on DI_5^nok" ;
label data "Versions of the disruption measure by cycle, nih_risk" ;
notes: Built `c(current_date)' by code/build/31_disruption_versions_cycle.do. ;
order setnb project_number cycle dmax_* dn_* dmean dmed dshq dshd drawmax drawmean c_p50 c_mean c_atmax n_cp any1 any5 ;
sort setnb project_number cycle ;
compress ;
save "${data}/build/risk_disruption_versions.dta", replace ;

/* -----------------------------------------------------------------------------
   5. A first look, in the log: the versions on the analysis cycles
   ----------------------------------------------------------------------------- */
merge 1:1 setnb project_number cycle using "${data}/build/cycles.dta", keepusing(in_sample sep renewed eval_year) ;
tab _merge ;
keep if _merge == 3 ;
drop _merge ;
keep if in_sample & sep != 1 ;
display as result "=== analysis cycles with the paper's measure" ;
count if !missing(dmax_base) ;
local nb = r(N) ;

display as result "=== coverage: share of the analysis cycles with the paper's measure on which each version is defined, and the publications behind it" ;
foreach t in base di1 d5n di5 w5 w10 nslf orgnl ge5 ge10 ge20 cit ref fl {;
    quietly count if !missing(dmax_`t') & !missing(dmax_base) ;
    local sh = r(N) / `nb' ;
    quietly summarize dn_`t' if !missing(dmax_`t') & !missing(dmax_base) ;
    display as text "`t': " %6.3f `sh' " of cycles, " %9.0fc r(N) " cycles, mean publications " %5.2f r(mean) ;
} ;
quietly count if !missing(c_p50) & !missing(dmax_base) ;
display as text "median citation percentile: " %6.3f r(N) / `nb' " of cycles" ;

display as result "=== distributions on the analysis cycles" ;
tabstat dmax_base dmax_di1 dmax_d5n dmax_di5 dmax_w5 dmax_w10 dmax_nslf dmax_orgnl dmax_ge5 dmax_ge10 dmax_ge20
        dmax_cit dmax_ref dmax_fl dmean dmed dshq dshd drawmax drawmean c_p50 c_atmax,
        stat(n mean sd p10 p50 p90) columns(statistics) ;

display as result "=== rank correlations with the paper's measure, analysis cycles" ;
foreach v in dmax_di1 dmax_d5n dmax_di5 dmax_w5 dmax_w10 dmax_nslf dmax_orgnl dmax_ge5 dmax_ge10 dmax_ge20
             dmax_cit dmax_ref dmax_fl dmean dmed dshq dshd drawmax drawmean c_p50 c_atmax dn_base {;
    quietly spearman dmax_base `v' ;
    display as text "`v': " %6.3f r(rho) "  (N " %9.0fc r(N) ")" ;
} ;

display as result "=== ties at the top: share of cycles with a publication at +1, one shared reference and five" ;
summarize any1 any5 ;

display as result "=== common samples: share of the cycles with the paper's measure" ;
gen byte com1 = !missing(dmax_base) ;
foreach t in di1 d5n di5 w5 w10 nslf orgnl ge5 ge10 ge20 {;
    replace com1 = 0 if missing(dmax_`t') ;
} ;
gen byte com2 = !missing(dmax_base) & !missing(dmax_cit) & !missing(dmax_ref) & !missing(c_p50) ;
gen byte com2fl = com2 & !missing(dmax_fl) ;
summarize com1 com2 com2fl if !missing(dmax_base) ;

display as result "=== the measures by renewal, analysis cycles with the paper's measure" ;
tabstat dmax_base dmean dshq dshd drawmax dmax_cit dmax_ref c_p50 dn_base if !missing(dmax_base),
        by(renewed) stat(mean sd n) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/31_disruption_versions_cycle.do */
