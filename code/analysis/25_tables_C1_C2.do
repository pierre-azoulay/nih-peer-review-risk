/* =============================================================================
   code/analysis/25_tables_C1_C2.do

   Purpose: Appendix Tables C1 and C2, the disruption measure taken apart, in
            versions of Table 2's disruption regression (all renewals, with
            Table 2's controls, the grant output controls; standard errors
            clustered by investigator and by grant). Each column enters
            another version in place of the paper's measure, standardized on
            the column's cycles and linearly, so that its coefficient is
            the change in the probability of renewal for one standard
            deviation. Each column is also estimated with indicators for the
            bottom and the top decile of its version, computed within
            evaluation year on every analysis cycle where that version is
            defined: these estimates give the tables' rank correlations, and
            the log reports their coefficients, which the notes to Appendix
            C's results quote.
            - Table C1, versions of the index (eleven columns): the paper's
              measure; with N_k; five shared references; five, with N_k;
              citers within 5 and 10 years; no self-citations;
              original-research citers; citers with 5, 10, 20 or more
              references. On the cycles where every version is defined.
            - Table C2, what the measure picks up and how it is aggregated
              (nine columns): the paper's measure; ranked within citation
              bin; ranked within reference-count bin; the paper's measure
              with the median citation percentile of the same publications;
              with indicators for the publications with an index; first- or
              last-author publications; mean percentile; share in the top
              quartile; highest raw index. On the cycles where columns 1 to
              5 and 7 to 9 are defined; column 6 on those of them with a
              first- or last-author publication with an index.
            The log also describes what the bottom and top deciles hold
            (section 3b), for the same notes.

   Input:
     - ${public}/nih_risk_public.dta               (code/build/34_public_file.do)
       with the variables of risk_disruption_versions.dta (code/build/31_disruption_versions_cycle.do)
   Output:
     - output/tables/table_C1.tex, output/tables/table_C2.tex   rows only
     - estimates/table_C1_<version>_d.ster, _z.ster (deciles, linear)
     - estimates/table_C2_<column>_d.ster, _z.ster

   Note: do code/analysis/25_tables_C1_C2.do [0]; the argument 0 redraws the
         tables from the saved estimates.
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 8 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/25_tables_C1_C2.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate and save; 0 = reuse the saved estimates. A first argument
   overrides it (do code/analysis/25_tables_C1_C2.do 0) */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

/* -----------------------------------------------------------------------------
   1. Data
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;
/* the paper's measure is the stored one */
assert missing(`m2') == missing(dmax_base) ;
assert abs(`m2' - dmax_base) < 1e-9 if !missing(`m2') ;

/* bins of a count of publications, Table 2's (code/build/06_cycle_output.do) */
capture program drop dv_bin ;
program define dv_bin ;
    args n b ;
    gen byte `b' = cond(`n' <= 5, `n', cond(`n' <= 7, 6, cond(`n' <= 10, 8,
                   cond(`n' <= 15, 11, cond(`n' <= 20, 16, 21))))) if !missing(`n') ;
end ;

/* the median citation percentile of the same publications, per 10 points
   (Table C2, column 4) */
gen double cp50x = c_p50 * 10 ;
label variable cp50x "Median citation percentile, same publications (per 10 points)" ;

/* Table C1: the versions of the index */
local a1 "dmax_base" ;  local n1 "base" ;  local h1 "Paper's measure" ;
local a2 "dmax_di1" ;   local n2 "di1" ;   local h2 "With \(N_k\)" ;
local a3 "dmax_d5n" ;   local n3 "d5n" ;   local h3 "Five shared references" ;
local a4 "dmax_di5" ;   local n4 "di5" ;   local h4 "Five shared, with \(N_k\)" ;
local a5 "dmax_w5" ;    local n5 "w5" ;    local h5 "Citers within 5 years" ;
local a6 "dmax_w10" ;   local n6 "w10" ;   local h6 "Citers within 10 years" ;
local a7 "dmax_nslf" ;  local n7 "nslf" ;  local h7 "No self-citations" ;
local a8 "dmax_orgnl" ; local n8 "orgnl" ; local h8 "Original-research citers" ;
local a9 "dmax_ge5" ;   local n9 "ge5" ;   local h9 "Citers with 5+ references" ;
local a10 "dmax_ge10" ; local n10 "ge10" ; local h10 "Citers with 10+ references" ;
local a11 "dmax_ge20" ; local n11 "ge20" ; local h11 "Citers with 20+ references" ;
local k1 11 ;

/* Table C2: what it picks up, and how it is aggregated. The variable
   whose deciles enter, and the extra control (absorbed or continuous) */
local b1 "dmax_base" ;  local q1 "b1" ; local e1 "" ;         local c1 "" ;
local b2 "dmax_cit" ;   local q2 "b2" ; local e2 "" ;         local c2 "" ;
local b3 "dmax_ref" ;   local q3 "b3" ; local e3 "" ;         local c3 "" ;
local b4 "dmax_base" ;  local q4 "b4" ; local e4 "" ;         local c4 "cp50x" ;
local b5 "dmax_base" ;  local q5 "b5" ; local e5 "bin_disr" ; local c5 "" ;
local b6 "dmax_fl" ;    local q6 "b6" ; local e6 "" ;         local c6 "" ;
local b7 "dmean" ;      local q7 "b7" ; local e7 "" ;         local c7 "" ;
local b8 "dshq" ;       local q8 "b8" ; local e8 "" ;         local c8 "" ;
local b9 "drawmax" ;    local q9 "b9" ; local e9 "" ;         local c9 "" ;
local k2 9 ;

dv_bin dn_base bin_disr ;

/* deciles within evaluation year, on every analysis cycle where the
   measure is defined (Table 2's rule, code/analysis/12_table_2.do) */
local dlist "dmax_base dmax_di1 dmax_d5n dmax_di5 dmax_w5 dmax_w10 dmax_nslf dmax_orgnl dmax_ge5 dmax_ge10 dmax_ge20 dmax_cit dmax_ref dmax_fl dmean dshq dshd drawmax" ;
local i = 0 ;
foreach v of local dlist {;
    local ++i ;
    gquantiles D`i' = `v' if !missing(`v'), xtile nquantiles(10) by(`pctby') ;
    gen byte lo_`v' = (D`i' == 1)  if !missing(D`i') ;
    gen byte hi_`v' = (D`i' == 10) if !missing(D`i') ;
    quietly summarize lo_`v' ;
    local slo = r(mean) ;
    local nv = r(N) ;
    quietly summarize hi_`v' ;
    display as text "`v': " %9.0fc `nv' " analysis cycles, share in the bottom group " %5.3f `slo' ", in the top group " %5.3f r(mean) ;
    drop D`i' ;
} ;

/* the common samples */
gen byte com1 = 1 ;
forvalues j = 1/`k1' {;
    replace com1 = 0 if missing(`a`j'') ;
} ;
gen byte com2 = !missing(dmax_base) & !missing(dmax_cit) & !missing(dmax_ref) & !missing(cp50x) & !missing(bin_disr)
                & !missing(dmean) & !missing(dshq) & !missing(drawmax) ;
gen byte com2fl = com2 & !missing(dmax_fl) ;
display as result "=== the common samples, among the analysis cycles with the paper's measure" ;
summarize com1 com2 com2fl if !missing(dmax_base) ;

/* -----------------------------------------------------------------------------
   2. The regressions
   Each column: deciles (d) and the measure standardized on the column's
   cycles (z). The scalars rho (rank correlation with the paper's measure on
   the column's cycles), shlo, shhi (shares of the cycles in the bottom and
   top groups) travel with the deciles' estimates.
   ----------------------------------------------------------------------------- */
if `run_regs' {;

    /* ---- Table C1 ---- */
    forvalues j = 1/`k1' {;
        local v "`a`j''" ;
        capture drop lo hi z smp ;
        gen byte lo = lo_`v' ;
        gen byte hi = hi_`v' ;
        reghdfe `dv' lo hi `x3' if com1, absorb(`fe3') vce(cluster `clus') ;
        gen byte smp = e(sample) ;
        nr_post, coefs(lo hi) ;
        quietly spearman `v' dmax_base if smp ;
        estadd scalar rho = r(rho) ;
        quietly summarize lo if smp ;
        estadd scalar shlo = r(mean) ;
        quietly summarize hi if smp ;
        estadd scalar shhi = r(mean) ;
        estimates save "estimates/table_C1_`n`j''_d.ster", replace ;
        quietly summarize `v' if smp ;
        gen double z = (`v' - r(mean)) / r(sd) ;
        reghdfe `dv' z `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
        nr_post, coefs(z) ;
        estimates save "estimates/table_C1_`n`j''_z.ster", replace ;
        drop lo hi z smp ;
    } ;

    /* ---- Table C2 ---- */
    forvalues j = 1/`k2' {;
        local v "`b`j''" ;
        local smpl = cond(`j' == 6, "com2fl", "com2") ;
        capture drop lo hi z smp ;
        gen byte lo = lo_`v' ;
        gen byte hi = hi_`v' ;
        reghdfe `dv' lo hi `c`j'' `x3' if `smpl', absorb(`fe3' `e`j'') vce(cluster `clus') ;
        gen byte smp = e(sample) ;
        nr_post, coefs(lo hi) ;
        quietly spearman `v' dmax_base if smp ;
        estadd scalar rho = r(rho) ;
        quietly summarize lo if smp ;
        estadd scalar shlo = r(mean) ;
        quietly summarize hi if smp ;
        estadd scalar shhi = r(mean) ;
        estimates save "estimates/table_C2_`q`j''_d.ster", replace ;
        quietly summarize `v' if smp ;
        gen double z = (`v' - r(mean)) / r(sd) ;
        reghdfe `dv' z `c`j'' `x3' if smp, absorb(`fe3' `e`j'') vce(cluster `clus') ;
        nr_post, coefs(z) ;
        estimates save "estimates/table_C2_`q`j''_z.ster", replace ;
        drop lo hi z smp ;
    } ;
} ;

/* -----------------------------------------------------------------------------
   3. The log: the decile and the linear estimates of every column
   ----------------------------------------------------------------------------- */
display as result _newline "=== Table C1: deciles on the common cycles (d) and one s.d. linear (z)" ;
forvalues j = 1/`k1' {;
    local line "`n`j'':" ;
    foreach s in d z {;
        estimates use "estimates/table_C1_`n`j''_`s'.ster" ;
        if "`s'" == "z" {;
            local line = "`line'  z " + strtrim(string(_b[z], "%7.4f")) + " (" + strtrim(string(_se[z], "%6.4f")) + ")" ;
        } ;
        else {;
            local line = "`line'  `s': lo " + strtrim(string(_b[lo], "%6.3f")) + " (" + strtrim(string(_se[lo], "%5.3f")) + ") hi " + strtrim(string(_b[hi], "%6.3f")) + " (" + strtrim(string(_se[hi], "%5.3f")) + ") N " + strtrim(string(e(N), "%9.0fc")) ;
        } ;
    } ;
    display as text "`line'" ;
} ;

display as result _newline "=== Table C2: deciles (d) and one s.d. linear (z)" ;
forvalues j = 1/`k2' {;
    estimates use "estimates/table_C2_`q`j''_d.ster" ;
    local line = "(`j') `b`j'' `c`j'' `e`j'': lo " + strtrim(string(_b[lo], "%6.3f")) + " (" + strtrim(string(_se[lo], "%5.3f")) + ") hi " + strtrim(string(_b[hi], "%6.3f")) + " (" + strtrim(string(_se[hi], "%5.3f")) + ") N " + strtrim(string(e(N), "%9.0fc")) + " rho " + strtrim(string(e(rho), "%5.3f")) + " shares " + strtrim(string(e(shlo), "%5.3f")) + " " + strtrim(string(e(shhi), "%5.3f")) ;
    if "`c`j''" != "" local line = "`line' `c`j'' " + strtrim(string(_b[`c`j''], "%7.4f")) + " (" + strtrim(string(_se[`c`j''], "%6.4f")) + ")" ;
    estimates use "estimates/table_C2_`q`j''_z.ster" ;
    local line = "`line'  z " + strtrim(string(_b[z], "%7.4f")) + " (" + strtrim(string(_se[z], "%6.4f")) + ")" ;
    display as text "`line'" ;
} ;

/* -----------------------------------------------------------------------------
   3b. Log only, descriptive (runs with or without re-estimation): what the
       bottom and top deciles hold under the paper's index and the two
       versions with N_k, on the cycles of Table C1 (com1): the citation
       percentile of the publication that sets the paper's measure, the
       median citation percentile of the publications with an index, their
       number, and the renewal rate. The notes to Appendix C's results, on
       the decile form, quote these numbers.
   ----------------------------------------------------------------------------- */
display as result _newline "=== what the deciles hold, cycles of Table C1" ;
foreach v in dmax_base dmax_di1 dmax_di5 {;
    foreach g in lo hi {;
        quietly summarize c_atmax if com1 & `g'_`v' == 1 ;
        local a = r(mean) ;
        quietly summarize c_p50 if com1 & `g'_`v' == 1 ;
        local b = r(mean) ;
        quietly summarize dn_base if com1 & `g'_`v' == 1 ;
        local c = r(mean) ;
        quietly summarize `dv' if com1 & `g'_`v' == 1 ;
        display as text "`v' `g': citation pctl at the maximum " %5.3f `a' ", median citation pctl " %5.3f `b'
            ", publications with an index " %5.2f `c' ", renewal rate " %5.3f r(mean) ", cycles " %7.0fc r(N) ;
    } ;
} ;
quietly summarize c_atmax if com1 ;
local a = r(mean) ;
quietly summarize c_p50 if com1 ;
display as text "all cycles of Table C1: citation pctl at the maximum " %5.3f `a' ", median citation pctl " %5.3f r(mean) ;
quietly count if hi_dmax_base == 1 & hi_dmax_di1 == 1 & com1 ;
local both = r(N) ;
quietly count if hi_dmax_base == 1 & com1 ;
display as text "top decile under both the paper's index and the index with N_k: " %7.0fc `both' " of " %7.0fc r(N) ;

/* -----------------------------------------------------------------------------
   4. The tables, written row by row, in the linear form: each version
      enters standardized on the column's cycles, and the coefficient is the
      change in the probability of renewal for one standard deviation. The
      decile estimates are in the log (section 3) and in
      estimates/table_C1_<version>_d.ster and table_C2_<column>_d.ster. The
      rank correlation is computed on the deciles' cycles, which are the
      linear column's.
   ----------------------------------------------------------------------------- */
tempname fh ;

/* Table C1: eleven columns, a gutter after column 4 */
local h1 "As in Table~2" ;
file open `fh' using "output/tables/table_C1.tex", write replace text ;
file write `fh' " & \multicolumn{4}{c}{The index} & & \multicolumn{7}{c}{The citers} \\" _n ;
file write `fh' "\cmidrule(lr){2-5}\cmidrule(lr){7-13}" _n ;
local hrow "" ;
local nrow0 "" ;
forvalues j = 1/`k1' {;
    if `j' == 5 {;
        local hrow "`hrow' &" ;
        local nrow0 "`nrow0' &" ;
    } ;
    local hrow "`hrow' & `h`j''" ;
    local nrow0 "`nrow0' & (`j')" ;
} ;
file write `fh' "`hrow' \\" _n "`nrow0' \\" _n "\midrule" _n ;
local Zrow "One s.d. of the measure" ; local Zse "" ;
local rrow "Rank correlation with column 1" ;
local mrow "Mean of dependent variable" ;
local irow "Nb.\ of investigators" ;
local nrow "Nb.\ of grant cycles" ;
local arow "Adjusted \(R^2\)" ;
forvalues j = 1/`k1' {;
    if `j' == 5 {;
        foreach r in Zrow Zse rrow mrow irow nrow arow {;
            local `r' "``r'' &" ;
        } ;
    } ;
    estimates use "estimates/table_C1_`n`j''_d.ster" ;
    local rrow "`rrow' & `=strtrim(string(e(rho), "%5.2f"))'" ;
    estimates use "estimates/table_C1_`n`j''_z.ster" ;
    nr_star `=_b[z]' `=_se[z]' ;
    local Zrow "`Zrow' & `=strtrim(string(_b[z], "%6.3f"))'`r(star)'" ;
    local Zse  "`Zse' & (`=strtrim(string(_se[z], "%5.3f"))')" ;
    local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
    local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
    local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
    local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
} ;
file write `fh' "`Zrow' \\" _n "`Zse' \\" _n "\midrule" _n ;
file write `fh' "`rrow' \\" _n "`mrow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
file close `fh' ;
type "output/tables/table_C1.tex" ;

/* Table C2: nine columns, a gutter after column 6 */
local g1 "As in Table~2" ;
local g2 "Ranked within citation bin" ;
local g3 "Ranked within reference bin" ;
local g4 "With median citation percentile" ;
local g5 "With publications with an index" ;
local g6 "First- or last-author publications" ;
local g7 "Mean percentile" ;
local g8 "Share in the top quartile" ;
local g9 "Highest raw index" ;
file open `fh' using "output/tables/table_C2.tex", write replace text ;
file write `fh' " & \multicolumn{6}{c}{The highest percentile} & & \multicolumn{3}{c}{Other summaries} \\" _n ;
file write `fh' "\cmidrule(lr){2-7}\cmidrule(lr){9-11}" _n ;
local hrow "" ;
local nrow0 "" ;
forvalues j = 1/`k2' {;
    if `j' == 7 {;
        local hrow "`hrow' &" ;
        local nrow0 "`nrow0' &" ;
    } ;
    local hrow "`hrow' & `g`j''" ;
    local nrow0 "`nrow0' & (`j')" ;
} ;
file write `fh' "`hrow' \\" _n "`nrow0' \\" _n "\midrule" _n ;
local Zrow "One s.d. of the measure" ; local Zse "" ;
local Crow "Median citation percentile, per 10 points" ; local Cse "" ;
local rrow "Rank correlation with column 1" ;
local mrow "Mean of dependent variable" ;
local irow "Nb.\ of investigators" ;
local nrow "Nb.\ of grant cycles" ;
local arow "Adjusted \(R^2\)" ;
forvalues j = 1/`k2' {;
    if `j' == 7 {;
        foreach r in Zrow Zse Crow Cse rrow mrow irow nrow arow {;
            local `r' "``r'' &" ;
        } ;
    } ;
    estimates use "estimates/table_C2_`q`j''_d.ster" ;
    local rrow "`rrow' & `=strtrim(string(e(rho), "%5.2f"))'" ;
    estimates use "estimates/table_C2_`q`j''_z.ster" ;
    nr_star `=_b[z]' `=_se[z]' ;
    local Zrow "`Zrow' & `=strtrim(string(_b[z], "%6.3f"))'`r(star)'" ;
    local Zse  "`Zse' & (`=strtrim(string(_se[z], "%5.3f"))')" ;
    if "`c`j''" != "" {;
        nr_star `=_b[`c`j'']' `=_se[`c`j'']' ;
        local Crow "`Crow' & `=strtrim(string(_b[`c`j''], "%6.3f"))'`r(star)'" ;
        local Cse  "`Cse' & (`=strtrim(string(_se[`c`j''], "%5.3f"))')" ;
    } ;
    else {;
        local Crow "`Crow' & " ;
        local Cse  "`Cse' & " ;
    } ;
    local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
    local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
    local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
    local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
} ;
file write `fh' "`Zrow' \\" _n "`Zse' \\" _n "\addlinespace" _n "`Crow' \\" _n "`Cse' \\" _n "\midrule" _n ;
file write `fh' "`rrow' \\" _n "`mrow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
file close `fh' ;
type "output/tables/table_C2.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
