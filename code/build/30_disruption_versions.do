/* =============================================================================
   code/build/30_disruption_versions.do

   Purpose: The versions of the disruption index that Appendix Tables C1 and
            C2 compare, at the publication level
            (code/build/31_disruption_versions_cycle.do takes them to the
            cycle). Ranks every version of the index within publication
            year, over all PubMed publications for which that version is
            defined (midrank percentile, 0 to 100, ties averaged), as the
            shipped percentile di1_nok_byyear_midrank is ranked (function
            midrank_pctl of s12_stage7_percentiles.py, in
            ${pubmed_root}/disruption_index/code), then keeps the
            publications that acknowledge a grant of the cycle file.
            Versions, by tag:
            - base   di1_nok, the paper's index (one shared reference, no N_k)
            - di1    di1, with N_k: the index as first defined
            - d5n    di5_nok, five shared references
            - di5    di5, five shared references, with N_k
            - w5     di1_nok_w5, citers within five years
            - w10    di1_nok_w10, citers within ten years
            - nslf   di1_nok_nslf, citers sharing an author with the paper dropped
            - orgnl  di1_nok_orgnl, citers that are original research
            - ge5    di1_nok_ge5, citers with at least 5 PubMed references
            - ge10   di1_nok_ge10, at least 10
            - ge20   di1_nok_ge20, at least 20
            - cit    di1_nok ranked within (year x citation bin), as shipped:
                     a (year x bin) cell with fewer than 500 publications
                     with an index is pooled with the other small cells of
                     its year (s12, line 336)
            - ref    di1_nok ranked within (year x reference-count bin), the
                     bins 1, 2, 3-4, 5-6, 7-9, 10-14, 15-19, 20-24, 25-29,
                     30-39, 40-49, 50-74, 75-99, 100+, small cells pooled as
                     for cit
            Checks (asserted): the computed percentiles of di1_nok and
            di5_nok within year, and of di1_nok within (year x citation
            bin), equal the shipped ones on every publication.

   Input:
     - ${pubmed_root}/disruption_index/di_index_pubmed2025.dta   the disruption
       index over PubMed 2025, with its shipped percentiles (read only)
     - ${data}/build/cycle_papers.dta   (code/build/03_cycle_papers.do)

   Output:
     - ${data}/build/paper_disruption_versions.dta   one row per acknowledging
                                                     pmid: pubyear nrefs_f
                                                     n_citers cites_bin
                                                     di1_nok di5_nok p_<tag>
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/30_disruption_versions.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* midrank percentile within a group, ties averaged, over the publications
   where the variable is defined: 100 * (midrank - 0.5) / n, as s12 */
capture program drop dv_midrank ;
program define dv_midrank ;
    syntax varname(numeric), Group(varname) Generate(name) ;
    tempvar pos mid ng ;
    sort `group' `varlist' ;
    quietly by `group': gen long `pos' = _n if !missing(`varlist') ;
    gegen double `mid' = mean(`pos'), by(`group' `varlist') ;
    gegen long `ng' = count(`varlist'), by(`group') ;
    gen double `generate' = 100 * (`mid' - 0.5) / `ng' if !missing(`varlist') ;
end ;

/* -----------------------------------------------------------------------------
   1. The acknowledging publications of the cycle file
   ----------------------------------------------------------------------------- */
use pmid ackn using "${data}/build/cycle_papers.dta" if ackn == 1, clear ;
keep pmid ;
bysort pmid: keep if _n == 1 ;
display as result "=== acknowledging publications of the cycle file" ;
count ;
tempfile ackn ;
save `ackn' ;

/* -----------------------------------------------------------------------------
   2. The index, all of PubMed
   ----------------------------------------------------------------------------- */
use pmid pubyear nrefs_f n_citers cites_bin small_cell_l1
    di1_nok di1_nok_byyear_midrank di1_nok_byyear_cites_pctl
    di1 di5_nok di5_nok_byyear_midrank di5
    di1_nok_w5 di1_nok_w10 di1_nok_nslf di1_nok_orgnl
    di1_nok_ge5 di1_nok_ge10 di1_nok_ge20
    using "${pubmed_root}/disruption_index/di_index_pubmed2025.dta", clear ;
gisid pmid ;
assert !missing(pubyear) ;
display as result "=== the index: publications, and those with each version" ;
count ;
summarize di1_nok di1 di5_nok di5 di1_nok_w5 di1_nok_w10 di1_nok_nslf di1_nok_orgnl
          di1_nok_ge5 di1_nok_ge10 di1_nok_ge20, separator(0) ;

/* -----------------------------------------------------------------------------
   3. Within-year percentiles of every version
   ----------------------------------------------------------------------------- */
local v1 "di1_nok" ;      local g1 "base" ;
local v2 "di1" ;          local g2 "di1" ;
local v3 "di5_nok" ;      local g3 "d5n" ;
local v4 "di5" ;          local g4 "di5" ;
local v5 "di1_nok_w5" ;   local g5 "w5" ;
local v6 "di1_nok_w10" ;  local g6 "w10" ;
local v7 "di1_nok_nslf" ; local g7 "nslf" ;
local v8 "di1_nok_orgnl" ; local g8 "orgnl" ;
local v9 "di1_nok_ge5" ;  local g9 "ge5" ;
local v10 "di1_nok_ge10" ; local g10 "ge10" ;
local v11 "di1_nok_ge20" ; local g11 "ge20" ;
local nv 11 ;

forvalues k = 1/`nv' {;
    display as text "ranking `v`k'' within year" ;
    dv_midrank `v`k'', group(pubyear) generate(p_`g`k'') ;
    label variable p_`g`k'' "Within-year midrank percentile of `v`k'', 0-100" ;
} ;

/* -----------------------------------------------------------------------------
   4. Within (year x citation bin) and (year x reference-count bin)
   ----------------------------------------------------------------------------- */
gen long yb = pubyear * 100 + cites_bin ;
gegen long ncell = count(di1_nok), by(yb) ;
gen long gcit = cond(ncell < 500, pubyear * 100, yb) ;
display as result "=== the small-cell rule reproduces the shipped flag (publications with an index)" ;
count if !missing(di1_nok) & (ncell < 500) != (small_cell_l1 == 1) ;
assert r(N) == 0 ;
dv_midrank di1_nok, group(gcit) generate(p_cit) ;
label variable p_cit "di1_nok midrank percentile within (year x citation bin), 0-100" ;
drop yb ncell gcit ;

gen byte rbin = irecode(nrefs_f, 1, 2, 4, 6, 9, 14, 19, 24, 29, 39, 49, 74, 99) if nrefs_f >= 1 & !missing(nrefs_f) ;
display as result "=== reference-count bins, publications with an index" ;
tab rbin if !missing(di1_nok), missing ;
gen long yr = pubyear * 100 + rbin ;
gegen long ncell = count(di1_nok), by(yr) ;
gen long gref = cond(ncell < 500, pubyear * 100 + 99, yr) ;
gen byte small_ref = ncell < 500 if !missing(di1_nok) ;
dv_midrank di1_nok, group(gref) generate(p_ref) ;
label variable p_ref "di1_nok midrank percentile within (year x reference-count bin), 0-100" ;
drop yr ncell gref ;

/* -----------------------------------------------------------------------------
   5. Checks against the shipped percentiles
   ----------------------------------------------------------------------------- */
display as result "=== checks: computed against shipped percentiles (missingness and largest gap)" ;
local c1 "p_base di1_nok_byyear_midrank" ;
local c2 "p_d5n di5_nok_byyear_midrank" ;
local c3 "p_cit di1_nok_byyear_cites_pctl" ;
forvalues k = 1/3 {;
    local a : word 1 of `c`k'' ;
    local b : word 2 of `c`k'' ;
    count if missing(`a') != missing(`b') ;
    assert r(N) == 0 ;
    gen double gap = abs(`a' - `b') ;
    summarize gap, meanonly ;
    display as text "`a' against `b': largest gap " %12.3e r(max) ;
    assert r(max) < 1e-6 ;
    drop gap ;
} ;
drop di1_nok_byyear_midrank di5_nok_byyear_midrank di1_nok_byyear_cites_pctl small_cell_l1 ;

/* -----------------------------------------------------------------------------
   6. Keep the acknowledging publications, describe, save
   ----------------------------------------------------------------------------- */
drop di1 di5 di1_nok_w5 di1_nok_w10 di1_nok_nslf di1_nok_orgnl di1_nok_ge5 di1_nok_ge10 di1_nok_ge20 ;
merge 1:1 pmid using `ackn' ;
tab _merge ;
display as result "=== acknowledging publications missing from the index file (_merge == 2)" ;
count if _merge == 2 ;
keep if _merge == 3 ;
drop _merge ;

display as result "=== acknowledging publications: those with each version, and its distribution" ;
summarize p_base p_di1 p_d5n p_di5 p_w5 p_w10 p_nslf p_orgnl p_ge5 p_ge10 p_ge20 p_cit p_ref, separator(0) ;
tabstat p_base p_di1 p_d5n p_di5 p_w5 p_w10 p_nslf p_orgnl p_ge5 p_ge10 p_ge20 p_cit p_ref,
        stat(n mean p10 p50 p90 max) columns(statistics) ;
display as result "=== acknowledging publications with an index in a pooled small cell (cit, ref)" ;
count if !missing(p_base) & small_ref == 1 ;
display as result "=== rank correlations with the paper's percentile, acknowledging publications" ;
foreach t in di1 d5n di5 w5 w10 nslf orgnl ge5 ge10 ge20 cit ref {;
    quietly spearman p_base p_`t' ;
    display as text "p_`t': " %6.3f r(rho) "  (N " %9.0fc r(N) ")" ;
} ;
display as result "=== at +1: publications with an index, one and five shared references" ;
count if di1_nok == 1 ;
count if !missing(di1_nok) ;
count if di5_nok == 1 ;
count if !missing(di5_nok) ;
drop small_ref rbin ;

label variable di1_nok "Disruption index DI_1^nok (raw)" ;
label variable di5_nok "Disruption index DI_5^nok (raw)" ;
label data "Versions of the disruption index, acknowledging papers, nih_risk" ;
notes: Built `c(current_date)' by code/build/30_disruption_versions.do. ;
order pmid pubyear nrefs_f n_citers cites_bin di1_nok di5_nok p_base p_di1 p_d5n p_di5
      p_w5 p_w10 p_nslf p_orgnl p_ge5 p_ge10 p_ge20 p_cit p_ref ;
sort pmid ;
compress ;
save "${data}/build/paper_disruption_versions.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/build/30_disruption_versions.do */
