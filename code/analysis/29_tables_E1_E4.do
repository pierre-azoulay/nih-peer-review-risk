/* =============================================================================
   code/analysis/29_tables_E1_E4.do

   Purpose: the dissection of standing out (Appendix E), from the pieces built
            by code/build/32_standout_extras.do.
              Table E1: standing out and its parts, the placebo, the measure
                        without check tags and the pool's size (Panel A),
                        and their correlations with standing out, pivoting,
                        new MeSH pairs, new noun phrases and the pool's size
                        (Panel B), on Table E2's cycles.
              Table E2: renewal on standing out (1) and on its three parts
                        by where the unique pairs are found (2), on Table 2's
                        standing-out cycles with a baseline paper, with the
                        bins of baseline papers of Appendix D in every
                        column. A third regression on the same cycles, on
                        the near and far parts, gives the numbers the text
                        reports.
              Table E3: renewal on pivoting computed on the pairs of the
                        common vocabulary, split by the study section's
                        portfolio, on Table E2's cycles.
              Table E4: renewal on standing out, on the placebo, and on
                        both, on Table 2's standing-out cycles.
            The text of Appendix E also reports standing out with bins of
            the pool's size, in pools of at least 50 and 100 other tagged
            applications, and without check tags: estimated here, shown in
            the log's screen.
            Every regression is a linear probability model of renewal with
            Table 2's grant output controls, standard errors clustered by
            investigator and by grant; the measures enter as fractions; in
            brackets, the coefficient times one s.d. of the regressor on the
            column's cycles. The log adds the part new to PubMed at one and
            ten years, the groups of new and other investigators, Tables E2
            and E3 without the baseline bins, and the placebo's first draw
            alone.

   Input:
     - ${public}/nih_risk_public.dta             (code/build/34_public_file.do)
       with the variables of risk_standout_extras.dta (code/build/32_standout_extras.do)
   Output:
     - output/tables/table_E1.tex, table_E2.tex, table_E3.tex, table_E4.tex
       (rows only, written row by row)
     - estimates/tables_E_t<2|3|4|5>_c<k>.ster: t2_c1, t2_c2 for Table E2
       (t2_c3, near and far, for the text); t3_c1 to t3_c3 for Table E4;
       t4_c2 to t4_c5 (the pool's size and the check tags) for the text;
       t5_c1 to t5_c3 for Table E3

   Note: a first argument of 0 (do code/analysis/29_tables_E1_E4.do 0) reuses
         the saved estimates.
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

log using "logs/29_tables_E1_E4.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate; 0 = reuse the saved estimates. A first argument overrides it
   (do code/analysis/29_tables_E1_E4.do 0) */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

local so "frac_icirg_pair" ;

/* -----------------------------------------------------------------------------
   1. The analysis file, with the pieces of code/build/32_standout_extras.do
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;
assert abs(so_own + so_est + so_new - `so') < 1e-9 if has_base == 1 ;
assert abs(so_near + so_far - `so') < 1e-9 if !missing(`so') ;
assert !missing(so_plac) if !missing(`so') ;

/* pivoting on the pairs of the common vocabulary, the sum of its two parts
   (Table E3) */
gen double piv_v = piv_sh + piv_un ;
assert abs(piv_un - so_est - so_new) < 1e-9 if has_base == 1 ;

/* the part established in PubMed when new to PubMed means first used within
   one year, or within ten, rather than three (for the log) */
gen double so_est1  = `so' - so_own - so_new1  if has_base == 1 ;
gen double so_est10 = `so' - so_own - so_new10 if has_base == 1 ;

/* bins of the number of baseline papers with MeSH
   (code/analysis/26_tables_D1_D3_figure_D1.do) */
gen byte nprior_bin = 1 if n_base_mesh == 1 ;
replace nprior_bin = 2 if n_base_mesh == 2 ;
replace nprior_bin = 3 if inrange(n_base_mesh, 3, 4) ;
replace nprior_bin = 4 if inrange(n_base_mesh, 5, 9) ;
replace nprior_bin = 5 if inrange(n_base_mesh, 10, 19) ;
replace nprior_bin = 6 if inrange(n_base_mesh, 20, 49) ;
replace nprior_bin = 7 if n_base_mesh >= 50 & !missing(n_base_mesh) ;
assert !missing(nprior_bin) if has_base == 1 ;

/* bins of the pool's size: other tagged applications */
gen byte pool_bin = 1 if inrange(nb_abs, 20, 49) ;
replace pool_bin = 2 if inrange(nb_abs, 50, 99) ;
replace pool_bin = 3 if inrange(nb_abs, 100, 149) ;
replace pool_bin = 4 if inrange(nb_abs, 150, 199) ;
replace pool_bin = 5 if inrange(nb_abs, 200, 299) ;
replace pool_bin = 6 if nb_abs >= 300 & !missing(nb_abs) ;
assert !missing(pool_bin) if !missing(`so') ;

/* Table 2's standing-out sample: its regression on all cycles
   (code/analysis/12_table_2.do) */
gquantiles dec = `so' if !missing(`so'), xtile nquantiles(10) by(`pctby') ;
gen byte lo = (dec == 1)  if !missing(dec) ;
gen byte hi = (dec == 10) if !missing(dec) ;
quietly reghdfe `dv' lo hi `x3', absorb(`fe3') vce(cluster `clus') ;
gen byte t2smp = e(sample) ;
local n_t2 = e(N) ;
display as result "=== Table 2 standing-out sample: " %9.0fc `n_t2' " cycles" ;
drop dec lo hi ;
display as result "=== with a baseline paper with MeSH" ;
tab has_base if t2smp, missing ;
display as result "=== the bins of the pool's size on Table 2's cycles" ;
tab pool_bin if t2smp ;

/* -----------------------------------------------------------------------------
   2. The regressions
   ----------------------------------------------------------------------------- */
/* so_reg <name> : <regression>, then the summary rows and the s.d. of each
   regressor on the estimation sample, saved with the estimates */
capture program drop so_reg ;
program define so_reg ;
    gettoken nm 0 : 0 ;
    gettoken colon 0 : 0 ;
    `0' ;
    nr_post ;
    local rhs : colnames e(b) ;
    local mvars "frac_icirg_pair so_own so_est so_new so_near so_far so_plac so_plac1 so_noct piv_v piv_sh piv_un" ;
    foreach v of local rhs {;
        if !`: list v in mvars' continue ;
        quietly summarize `v' if e(sample) ;
        estadd scalar sd_`v' = r(sd) ;
    } ;
    estimates save "estimates/`nm'", replace ;
end ;

local c2fe "`fe3' nprior_bin" ;
if `run_regs' {;
    /* Table E2 (columns 1 and 2) and the near and far parts (for the
       text): Table 2's cycles with a baseline paper */
    so_reg tables_E_t2_c1 : reghdfe `dv' `so' `x3' if t2smp & has_base == 1, absorb(`c2fe') vce(cluster `clus') ;
    gen byte s2 = e(sample) ;
    local n2 = e(N) ;
    so_reg tables_E_t2_c2 : reghdfe `dv' so_own so_est so_new `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
    assert e(N) == `n2' ;
    so_reg tables_E_t2_c3 : reghdfe `dv' so_near so_far `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
    assert e(N) == `n2' ;
    /* Table E4: Table 2's cycles. Its column 1 is also the benchmark of the
       pool's size and the check tags below */
    so_reg tables_E_t3_c1 : reghdfe `dv' `so' `x3' if t2smp, absorb(`fe3') vce(cluster `clus') ;
    gen byte s3 = e(sample) ;
    local n3 = e(N) ;
    assert `n3' == `n_t2' ;
    so_reg tables_E_t3_c2 : reghdfe `dv' so_plac `x3' if s3, absorb(`fe3') vce(cluster `clus') ;
    assert e(N) == `n3' ;
    so_reg tables_E_t3_c3 : reghdfe `dv' `so' so_plac `x3' if s3, absorb(`fe3') vce(cluster `clus') ;
    assert e(N) == `n3' ;
    /* for the text: bins of the pool's size, pools of at least 50 and 100
       other tagged applications, and the measure without check tags */
    so_reg tables_E_t4_c2 : reghdfe `dv' `so' `x3' if s3, absorb(`fe3' pool_bin) vce(cluster `clus') ;
    so_reg tables_E_t4_c3 : reghdfe `dv' `so' `x3' if s3 & nb_abs >= 50, absorb(`fe3') vce(cluster `clus') ;
    so_reg tables_E_t4_c4 : reghdfe `dv' `so' `x3' if s3 & nb_abs >= 100, absorb(`fe3') vce(cluster `clus') ;
    so_reg tables_E_t4_c5 : reghdfe `dv' so_noct `x3' if t2smp & !missing(so_noct), absorb(`fe3') vce(cluster `clus') ;
    /* Table E3: pivoting split by the study section's portfolio, on Table
       E2's cycles */
    so_reg tables_E_t5_c1 : reghdfe `dv' piv_v `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
    assert e(N) == `n2' ;
    so_reg tables_E_t5_c2 : reghdfe `dv' piv_sh piv_un `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
    assert e(N) == `n2' ;
    so_reg tables_E_t5_c3 : reghdfe `dv' so_own piv_sh piv_un `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
    assert e(N) == `n2' ;
} ;
else {;
    quietly reghdfe `dv' `so' `x3' if t2smp & has_base == 1, absorb(`c2fe') vce(cluster `clus') ;
    gen byte s2 = e(sample) ;
    local n2 = e(N) ;
    gen byte s3 = t2smp ;
    local n3 = `n_t2' ;
} ;
estimates use "estimates/tables_E_t2_c2" ;
test so_own = so_est = so_new ;
local p_t2c2 = r(p) ;
test so_own = so_est ;
local p_oe = r(p) ;
test so_est = so_new ;
local p_en = r(p) ;
test so_own = so_new ;
local p_on = r(p) ;
estimates use "estimates/tables_E_t2_c3" ;
test so_near = so_far ;
local p_t2c3 = r(p) ;
display as result "=== Table E2 and the near and far parts, p-values" ;
display as result "own = est = new " %8.6f `p_t2c2' ;
display as result "own = est       " %8.6f `p_oe' ;
display as result "est = new       " %8.6f `p_en' ;
display as result "own = new       " %8.6f `p_on' ;
display as result "near = far      " %8.6f `p_t2c3' ;
estimates use "estimates/tables_E_t5_c2" ;
test piv_sh = piv_un ;
local p_t5c2 = r(p) ;
lincom piv_un - piv_sh ;
estimates use "estimates/tables_E_t5_c3" ;
test piv_sh = piv_un ;
local p_t5c3 = r(p) ;
test so_own = piv_sh ;
local p_t5os = r(p) ;
display as result "=== Table E3, p-values" ;
display as result "shared = absent, col 2  " %8.6f `p_t5c2' ;
display as result "shared = absent, col 3  " %8.6f `p_t5c3' ;
display as result "own = shared, col 3     " %8.6f `p_t5os' ;

/* screen, for the log */
eststo clear ;
foreach s in t2_c1 t2_c2 t2_c3 t3_c1 t3_c2 t3_c3 t4_c2 t4_c3 t4_c4 t4_c5 t5_c1 t5_c2 t5_c3 {;
    estimates use "estimates/tables_E_`s'" ;
    eststo `s' ;
} ;
esttab t2_c1 t2_c2 t2_c3, keep(`so' so_own so_est so_new so_near so_far) b(%7.4f) se(%7.4f)
    star(+ 0.10 * 0.05 ** 0.01) nomtitles noobs stats(meandv ninv N r2_a, fmt(%6.3f %9.0fc %9.0fc %6.4f))
    title("Table E2 (column 3: near and far, for the text)") ;
esttab t3_c1 t3_c2 t3_c3, keep(`so' so_plac) b(%7.4f) se(%7.4f)
    star(+ 0.10 * 0.05 ** 0.01) nomtitles noobs stats(meandv ninv N r2_a, fmt(%6.3f %9.0fc %9.0fc %6.4f))
    title("Table E4") ;
esttab t3_c1 t4_c2 t4_c3 t4_c4 t4_c5, keep(`so' so_noct) b(%7.4f) se(%7.4f)
    star(+ 0.10 * 0.05 ** 0.01) nomtitles noobs stats(meandv ninv N r2_a, fmt(%6.3f %9.0fc %9.0fc %6.4f))
    title("Standing out: the pool's size and the check tags, for the text") ;
esttab t5_c1 t5_c2 t5_c3, keep(piv_v piv_sh piv_un so_own) b(%7.4f) se(%7.4f)
    star(+ 0.10 * 0.05 ** 0.01) nomtitles noobs stats(meandv ninv N r2_a, fmt(%6.3f %9.0fc %9.0fc %6.4f))
    title("Table E3") ;

/* -----------------------------------------------------------------------------
   3. Log only
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    display as result "=== LOG: Table E2, column 2, with the part new to PubMed at 1 and at 10 years" ;
    foreach k in 1 10 {;
        quietly reghdfe `dv' so_own so_est`k' so_new`k' `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
        display as result "cutoff `k': own " %7.4f _b[so_own] " (" %6.4f _se[so_own] "), est " %7.4f _b[so_est`k']
            " (" %6.4f _se[so_est`k'] "), new " %7.4f _b[so_new`k'] " (" %6.4f _se[so_new`k'] ")" ;
        summarize so_own so_est`k' so_new`k' if s2 ;
    } ;
    display as result "=== LOG: Table E2 and the near and far parts without the baseline bins" ;
    quietly reghdfe `dv' so_own so_est so_new `x3' if s2, absorb(`fe3') vce(cluster `clus') ;
    display as result "own " %7.4f _b[so_own] " (" %6.4f _se[so_own] "), est " %7.4f _b[so_est] " (" %6.4f _se[so_est]
        "), new " %7.4f _b[so_new] " (" %6.4f _se[so_new] ")" ;
    quietly reghdfe `dv' so_near so_far `x3' if s2, absorb(`fe3') vce(cluster `clus') ;
    display as result "near " %7.4f _b[so_near] " (" %6.4f _se[so_near] "), far " %7.4f _b[so_far] " (" %6.4f _se[so_far] ")" ;
    display as result "=== LOG: Table E2 for new investigators (1) and other investigators (0)" ;
    foreach g in 1 0 {;
        quietly reghdfe `dv' `so' `x3' if s2 & new_inv == `g', absorb(`c2fe') vce(cluster `clus') ;
        display as result "new_inv `g' (" %7.0fc e(N) " cycles): standing out " %7.4f _b[`so'] " (" %6.4f _se[`so'] ")" ;
        quietly reghdfe `dv' so_own so_est so_new `x3' if s2 & new_inv == `g', absorb(`c2fe') vce(cluster `clus') ;
        display as result "   own " %7.4f _b[so_own] " (" %6.4f _se[so_own] "), est " %7.4f _b[so_est] " (" %6.4f _se[so_est]
            "), new " %7.4f _b[so_new] " (" %6.4f _se[so_new] ")" ;
        quietly reghdfe `dv' so_near so_far `x3' if s2 & new_inv == `g', absorb(`c2fe') vce(cluster `clus') ;
        display as result "   near " %7.4f _b[so_near] " (" %6.4f _se[so_near] "), far " %7.4f _b[so_far] " (" %6.4f _se[so_far] ")" ;
    } ;
    display as result "=== LOG: the placebo's first draw alone, and with standing out" ;
    quietly reghdfe `dv' so_plac1 `x3' if s3, absorb(`fe3') vce(cluster `clus') ;
    display as result "first draw alone " %7.4f _b[so_plac1] " (" %6.4f _se[so_plac1] ")" ;
    quietly reghdfe `dv' `so' so_plac1 `x3' if s3, absorb(`fe3') vce(cluster `clus') ;
    display as result "with standing out: standing out " %7.4f _b[`so'] " (" %6.4f _se[`so'] "), first draw " %7.4f _b[so_plac1] " (" %6.4f _se[so_plac1] ")" ;
    display as result "=== LOG: standing out with and without check tags, on the same cycles" ;
    quietly reghdfe `dv' `so' `x3' if t2smp & !missing(so_noct), absorb(`fe3') vce(cluster `clus') ;
    display as result "with check tags, cycles of the measure without them: " %7.4f _b[`so'] " (" %6.4f _se[`so'] "), N " %9.0fc e(N) ;
    display as result "=== LOG: Table E3, the paper's pivoting (all descriptors) on the same cycles" ;
    quietly reghdfe `dv' frac_setnb_pair `x3' if s2, absorb(`c2fe') vce(cluster `clus') ;
    display as result "pivoting, all descriptors: " %7.4f _b[frac_setnb_pair] " (" %6.4f _se[frac_setnb_pair] ")" ;
    correlate piv_v frac_setnb_pair if s2 ;
    display as result "=== LOG: Table E3 for new investigators (1) and other investigators (0)" ;
    foreach g in 1 0 {;
        quietly reghdfe `dv' piv_sh piv_un `x3' if s2 & new_inv == `g', absorb(`c2fe') vce(cluster `clus') ;
        display as result "new_inv `g' (" %7.0fc e(N) " cycles): shared " %7.4f _b[piv_sh] " (" %6.4f _se[piv_sh]
            "), absent " %7.4f _b[piv_un] " (" %6.4f _se[piv_un] ")" ;
    } ;
    display as result "=== LOG: Table E3, column 2, without the baseline bins" ;
    quietly reghdfe `dv' piv_sh piv_un `x3' if s2, absorb(`fe3') vce(cluster `clus') ;
    display as result "shared " %7.4f _b[piv_sh] " (" %6.4f _se[piv_sh] "), absent " %7.4f _b[piv_un] " (" %6.4f _se[piv_un] ")" ;
} ;
display as result "=== Table E3: the cells of the two-way split, by renewal" ;
gen double old_sh = 1 - so_own - piv_sh - piv_un if s2 ;
tabstat old_sh so_own piv_sh piv_un piv_v frac_setnb_pair if s2, by(`dv') stat(mean sd n) ;
display as result "=== LOG: correlations of the placebo and of the measure without check tags" ;
correlate `so' so_plac so_plac1 so_noct ct_share if s3 ;
summarize so_plac so_plac1 so_noct ct_share ct_share_sh if s3 ;
tab plac_small if s3 ;

/* -----------------------------------------------------------------------------
   4. Table E1: the parts, on Table E2's cycles
   ----------------------------------------------------------------------------- */
local v1 "`so'" ;    local q1 "Standing out" ;
local v2 "so_own" ;  local q2 "\quad Unique, on her earlier publications" ;
local v3 "so_est" ;  local q3 "\quad Unique, new to her, established in \emph{PubMed}" ;
local v4 "so_new" ;  local q4 "\quad Unique, new to \emph{PubMed}" ;
local v5 "so_near" ; local q5 "\quad Unique and near" ;
local v6 "so_far" ;  local q6 "\quad Unique and far" ;
local v7 "so_plac" ; local q7 "Standing out (placebo study section)" ;
local v8 "so_noct" ; local q8 "Standing out without check tags" ;
local v9 "nb_abs" ;  local q9 "Other tagged applications in the pool" ;

tempname fh ;
file open `fh' using "output/tables/table_E1.tex", write replace ;
file write `fh' " & & & & \multicolumn{2}{c}{Mean} & \\" _n ;
file write `fh' "\cmidrule(lr){5-6}" _n ;
file write `fh' " & Mean & Std. dev. & Median & Not renewed & Renewed & Cycles \\" _n ;
file write `fh' "\midrule" _n ;
file write `fh' "\multicolumn{7}{l}{\textit{A. Standing out and its parts}} \\" _n ;
forvalues i = 1/9 {;
    local f = cond(`i' == 9, "%5.1f", "%5.3f") ;
    quietly summarize `v`i'' if s2, detail ;
    local mu : display `f' r(mean) ;
    local sd : display `f' r(sd) ;
    local md : display `f' r(p50) ;
    local nc : display %9.0fc r(N) ;
    local nc = strtrim("`nc'") ;
    quietly summarize `v`i'' if s2 & `dv' == 0 ;
    local m0 : display `f' r(mean) ;
    quietly summarize `v`i'' if s2 & `dv' == 1 ;
    local m1 : display `f' r(mean) ;
    file write `fh' "`q`i'' & `mu' & `sd' & `md' & `m0' & `m1' & `nc' \\" _n ;
    display as text "`q`i'': mean `mu' sd `sd' median `md' not renewed `m0' renewed `m1' N `nc'" ;
} ;
file write `fh' "\addlinespace" _n ;
file write `fh' "\multicolumn{7}{l}{\textit{B. Correlations}} \\" _n ;
file write `fh' " & Standing out & Pivoting & New MeSH pairs & New noun phrases & Pool size & \\" _n ;
quietly correlate `so' frac_setnb_pair agepair_cyclefrac `nov' nb_abs
    so_own so_est so_new so_near so_far so_plac so_noct if s2 ;
matrix C = r(C) ;
local ncc : display %9.0fc r(N) ;
local ncc = strtrim("`ncc'") ;
matrix list C, format(%6.3f) ;
/* rows of C: 1 standing out, 2 pivoting, 3 new MeSH pairs, 4 new noun
   phrases, 5 pool size, 6 to 12 the parts, placebo and no check tags */
forvalues i = 1/8 {;
    local r = cond(`i' == 1, 1, `i' + 4) ;
    local line "`q`i''" ;
    forvalues c = 1/5 {;
        if `r' == `c' local line "`line' & " ;
        else {;
            local cc : display %5.3f C[`r', `c'] ;
            local line "`line' & `cc'" ;
        } ;
    } ;
    file write `fh' "`line' & \\" _n ;
} ;
file write `fh' "\quad\quad{\footnotesize\textit{Cycles}} & \multicolumn{5}{c}{\footnotesize `ncc'} & \\" _n ;
file close `fh' ;
type "output/tables/table_E1.tex" ;

/* -----------------------------------------------------------------------------
   5. The three parts of standing out by renewal status, on Table E2's cycles
      (log)
   ----------------------------------------------------------------------------- */
display as result "=== the three parts by renewal status, Table E2's cycles" ;
tabstat so_own so_est so_new if s2, by(`dv') stat(mean sd p99 n) ;

/* -----------------------------------------------------------------------------
   6. Tables E4, E3 and E2, written row by row
   ----------------------------------------------------------------------------- */
/* so_rows <handle> <ster names> <variable> <label> [<second line>]: one
   coefficient row, its standard error and its one-s.d. effect, across the
   columns; an optional second line of the label goes on the standard
   error's row ("Standing out" over "(actual study section)" and "(placebo
   study section)" in Table E4) */
capture program drop so_rows ;
program define so_rows ;
    args fh cols v lab lab2 ;
    local r1 "`lab'" ;
    local r2 "`lab2'" ;
    local r3 "" ;
    foreach c of local cols {;
        quietly estimates use "estimates/`c'" ;
        local b = . ;
        capture local b = _b[`v'] ;
        if `b' < . {;
            local se = _se[`v'] ;
            local sdv = e(sd_`v') ;
            local bsd = strtrim(string(`b' * `sdv', "%7.4f")) ;
            nr_star `b' `se' ;
            local r1 "`r1' & `: display %6.3f `b''`r(star)'" ;
            local r2 "`r2' & (`: display %5.3f `se'')" ;
            local r3 "`r3' & {\footnotesize [`bsd']}" ;
        } ;
        else {;
            local r1 "`r1' & " ;
            local r2 "`r2' & " ;
            local r3 "`r3' & " ;
        } ;
    } ;
    file write `fh' "`r1' \\" _n "`r2' \\" _n "`r3' \\" _n ;
end ;

/* so_foot <handle> <ster names>: the summary rows, the adjusted R2 last */
capture program drop so_foot ;
program define so_foot ;
    args fh cols ;
    local rm "Mean of dependent variable" ;
    local rn "Nb. of grant cycles" ;
    local ri "Nb. of investigators" ;
    local ra "Adjusted \(R^2\)" ;
    foreach c of local cols {;
        quietly estimates use "estimates/`c'" ;
        local rm "`rm' & `: display %5.3f e(meandv)'" ;
        local nv : display %12.0fc e(N) ;
        local iv : display %12.0fc e(ninv) ;
        local nv = strtrim("`nv'") ;
        local iv = strtrim("`iv'") ;
        local rn "`rn' & `nv'" ;
        local ri "`ri' & `iv'" ;
        local ra "`ra' & `: display %6.4f e(r2_a)'" ;
    } ;
    file write `fh' "\midrule" _n "`rm' \\" _n "`rn' \\" _n "`ri' \\" _n "`ra' \\" _n ;
end ;

/* Table E4: standing out against the actual and the placebo study sections */
local cols "tables_E_t3_c1 tables_E_t3_c2 tables_E_t3_c3" ;
file open `fh' using "output/tables/table_E4.tex", write replace ;
file write `fh' " & (1) & (2) & (3) \\" _n "\midrule" _n ;
so_rows `fh' "`cols'" `so' "Standing out" "(actual study section)" ;
so_rows `fh' "`cols'" so_plac "Standing out" "(placebo study section)" ;
so_foot `fh' "`cols'" ;
file close `fh' ;
type "output/tables/table_E4.tex" ;

/* Table E3: pivoting split by the study section's portfolio */
local cols "tables_E_t5_c1 tables_E_t5_c2 tables_E_t5_c3" ;
file open `fh' using "output/tables/table_E3.tex", write replace ;
file write `fh' " & (1) & (2) & (3) \\" _n "\midrule" _n ;
so_rows `fh' "`cols'" piv_v "Pivoting" ;
so_rows `fh' "`cols'" piv_sh "\quad New to her, shared with the section" ;
so_rows `fh' "`cols'" piv_un "\quad New to her, absent from the section" ;
so_rows `fh' "`cols'" so_own "Not new to her, absent from the section" ;
local p2 : display %5.3f `p_t5c2' ;
if `p_t5c2' < 0.001 local p2 "\(<\)0.001" ;
local p3 : display %5.3f `p_t5c3' ;
if `p_t5c3' < 0.001 local p3 "\(<\)0.001" ;
file write `fh' "\addlinespace" _n "\textit{p}-value, shared \(=\) absent & & `p2' & `p3' \\" _n ;
so_foot `fh' "`cols'" ;
file close `fh' ;
type "output/tables/table_E3.tex" ;

/* Table E2: standing out and its three parts, the first two regressions on
   Table E2's cycles (the near and far parts, the third, are reported in the
   text) */
local cols "tables_E_t2_c1 tables_E_t2_c2" ;
file open `fh' using "output/tables/table_E2.tex", write replace ;
file write `fh' " & (1) & (2) \\" _n "\midrule" _n ;
so_rows `fh' "`cols'" `so' "Standing out" ;
so_rows `fh' "`cols'" so_own "\quad Unique, on her earlier publications" ;
so_rows `fh' "`cols'" so_est "\quad Unique, new to her, established in \emph{PubMed}" ;
so_rows `fh' "`cols'" so_new "\quad Unique, new to \emph{PubMed}" ;
local p2a : display %5.3f `p_t2c2' ;
if `p_t2c2' < 0.001 local p2a "\(<\)0.001" ;
file write `fh' "\addlinespace" _n "\textit{p}-value, equal coefficients & & `p2a' \\" _n ;
so_foot `fh' "`cols'" ;
file close `fh' ;
type "output/tables/table_E2.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/analysis/29_tables_E1_E4.do */
