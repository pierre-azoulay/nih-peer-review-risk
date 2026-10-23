/* =============================================================================
   code/analysis/32_table_G2.do

   Purpose: Appendix Table G2, renewal, the cycle's risk, and risk measured
            before the cycle. The lagged risk of code/build/25_lagged_risk.do
            is, for first cycles, the measure computed on the investigator's
            record before the grant and, for later cycles, the measure of the
            grant's previous cycle.
            Step 1 regresses the cycle's risk on its lag, with two slopes
            (first and later cycles); its slopes and partial R2 go to the log.
            Step 2 regresses renewal, for all cycles, on (i) the cycle's risk
            alone, (iii) the lagged risk in place of the cycle's risk, and
            the cycle's risk and its lag together.
            Table G2: for each measure, the three regressions of Step 2, with
            the one-SD effects. In the third column, the coefficient on the
            lag equals (iii)'s minus the coefficient on the cycle's risk times
            the Step 1 slope, an identity the log checks.
            Every regression has the controls of Table 2 (control set 3 of
            code/programs/_spec.do, with the grant output controls), an
            indicator for later cycles and bins of the lag's paper count (1, 2,
            3-4, 5-9, 10-19, 20-49, 50+), separate for first and later cycles.
            Tails and disruption in units of 10 percentile points, pivoting and
            standing out as fractions; the lag in the same units. Sample:
            cycles with the measure, its lag and a mean impact factor; the
            first-step sample serves every column.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of risk_lagged.dta (code/build/25_lagged_risk.do)
   Output:
     - output/tables/table_G2.tex   Appendix Table G2 (written row by row)
     - estimates/table_G2_s1_<t>.ster, estimates/table_G2_s2_<t>_A1.ster,
       _A3.ster and _A4.ster
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
set processors 4 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/32_table_G2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;
gen byte later = cycle_nb >= 2 if cycle_nb < . ;

local vn1 "tails" ; local vn2 "disr" ; local vn3 "pivot" ; local vn4 "so" ;
forvalues j = 1/`nmeas' {;
    local sc = cond(`j' <= 2, 10, 1) ;
    local v "`vn`j''" ;
    gen double R`j' = `m`j'' * `sc' ;
    gen double L`j' = lag_`v' * `sc' ;
    gen double L`j'a = L`j' * (1 - later) ;
    gen double L`j'b = L`j' * later ;
    gen byte bl`j' = cond(n_lag_`v' <= 2, n_lag_`v', cond(n_lag_`v' <= 4, 3, cond(n_lag_`v' <= 9, 5,
                     cond(n_lag_`v' <= 19, 10, cond(n_lag_`v' <= 49, 20, 50))))) ;
    egen int lc`j' = group(bl`j' later) ;
    label variable R`j'  "Current-cycle risk" ;
    label variable L`j'a "Lagged risk \(\times\) first cycle" ;
    label variable L`j'b "Lagged risk \(\times\) later cycle" ;
} ;

/* -------------------------------------------------------------------------
   Sample losses: the cycles with each measure, and those with its lag too
   ------------------------------------------------------------------------- */
display as result "=== cycles with each measure, and with its lag too (all; new investigators)" ;
forvalues j = 1/`nmeas' {;
    quietly count if !missing(R`j') & !missing(log_meanjif_all) ;
    local a = r(N) ;
    quietly count if !missing(R`j') & !missing(log_meanjif_all) & !missing(L`j') ;
    local b = r(N) ;
    quietly count if !missing(R`j') & !missing(log_meanjif_all) & new_inv == 1 ;
    local c = r(N) ;
    quietly count if !missing(R`j') & !missing(log_meanjif_all) & !missing(L`j') & new_inv == 1 ;
    local d = r(N) ;
    display as result "`l`j'': " %7.0fc `a' " -> " %7.0fc `b' " (lost " %5.1f 100*(1-`b'/`a') "%); new investigators " %7.0fc `c' " -> " %7.0fc `d' ;
    tab later if !missing(R`j') & !missing(log_meanjif_all) & !missing(L`j') ;
} ;

/* -------------------------------------------------------------------------
   Steps 1 and 2, by measure
   ------------------------------------------------------------------------- */
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    display _newline as result "==================== `l`j'' ====================" ;

    /* Step 1: current risk on the two lagged slopes */
    reghdfe R`j' L`j'a L`j'b `x3' if !missing(L`j'), absorb(`fe3' lc`j') vce(cluster `clus') ;
    estimates save "estimates/table_G2_s1_`t'", replace ;
    gen byte s`j' = e(sample) ;
    local s1b1_`j' = _b[L`j'a] ;
    local s1s1_`j' = _se[L`j'a] ;
    local s1b2_`j' = _b[L`j'b] ;
    local s1s2_`j' = _se[L`j'b] ;
    local s1r2w_`j' = e(r2_within) ;
    local rssf = e(rss) ;
    local s1ninv_`j' = e(N_clust1) ;
    quietly count if s`j' & later == 0 ;
    local s1nf_`j' = r(N) ;
    quietly count if s`j' & later == 1 ;
    local s1nl_`j' = r(N) ;
    quietly reghdfe R`j' `x3' if s`j', absorb(`fe3' lc`j') ;
    local s1pr2_`j' = (e(rss) - `rssf') / e(rss) ;
    display as result "Step 1: first " %7.4f `s1b1_`j'' " (" %6.4f `s1s1_`j'' "), later " %7.4f `s1b2_`j'' " (" %6.4f `s1s2_`j'' "), partial R2 " %6.4f `s1pr2_`j'' ", within R2 " %6.4f `s1r2w_`j'' ;
    display as result "        cycles first " %7.0fc `s1nf_`j'' ", later " %7.0fc `s1nl_`j'' ;

    /* Step 2, all cycles: (i) the cycle's risk alone, (iii) the lagged risk
       in its place, and the two together */
    local cond "s`j'" ;
    reghdfe `dv' R`j' `x3' if `cond', absorb(`fe3' lc`j') vce(cluster `clus') ;
    nr_post ;
    estimates save "estimates/table_G2_s2_`t'_A1", replace ;
    local b1_`j'_A = _b[R`j'] ;
    local se1_`j'_A = _se[R`j'] ;
    local N_`j'_A = e(N) ;
    local md_`j'_A = e(meandv) ;
    local ni_`j'_A = e(ninv) ;
    reghdfe `dv' L`j'a L`j'b `x3' if `cond', absorb(`fe3' lc`j') vce(cluster `clus') ;
    nr_post ;
    estimates save "estimates/table_G2_s2_`t'_A3", replace ;
    local bl1_`j'_A = _b[L`j'a] ;
    local sl1_`j'_A = _se[L`j'a] ;
    local bl2_`j'_A = _b[L`j'b] ;
    local sl2_`j'_A = _se[L`j'b] ;
    /* the third column of each measure in Table G2: the cycle's risk and its
       lag together. The coefficient on the cycle's risk is its association
       net of the lag and the controls; the lag's is (iii)'s minus that
       coefficient times the Step 1 slope */
    reghdfe `dv' R`j' L`j'a L`j'b `x3' if `cond', absorb(`fe3' lc`j') vce(cluster `clus') ;
    nr_post ;
    estimates save "estimates/table_G2_s2_`t'_A4", replace ;
    local bj_`j'  = _b[R`j'] ;
    local sj_`j'  = _se[R`j'] ;
    local bja_`j' = _b[L`j'a] ;
    local sja_`j' = _se[L`j'a] ;
    local bjb_`j' = _b[L`j'b] ;
    local sjb_`j' = _se[L`j'b] ;
    display as result "Table G2, `l`j'': cycle's risk " %8.5f `bj_`j'' "; lag, first "
        %8.5f `bja_`j'' " (by the identity " %8.5f `bl1_`j'_A' - `bj_`j'' * `s1b1_`j'' "), later "
        %8.5f `bjb_`j'' " (by the identity " %8.5f `bl2_`j'_A' - `bj_`j'' * `s1b2_`j'' "); N " %7.0fc e(N) ;
    display as result "Step 2: current " %7.4f `b1_`j'_A' " (" %6.4f `se1_`j'_A' "); N " %7.0fc `N_`j'_A' ;
} ;

tempname fh ;

/* -------------------------------------------------------------------------
   Appendix Table G2 (all cycles), in Table 2's layout: one column per
   regression, rows the regressors. For each measure, the cycle's risk alone
   (Step 2, (i)), risk before the cycle alone ((iii)), and both. In brackets,
   the one-SD effect: the coefficient times the regressor's s.d. on these
   cycles (risk before the cycle: among first cycles and among later cycles,
   since each has its own coefficient)
   ------------------------------------------------------------------------- */
file open `fh' using "output/tables/table_G2.tex", write replace text ;
file write `fh' " & \multicolumn{3}{c}{`l1'} & & \multicolumn{3}{c}{`l2'} & & \multicolumn{3}{c}{`l3'} & & \multicolumn{3}{c}{`l4'} \\" _n ;
file write `fh' "\cmidrule(lr){2-4}\cmidrule(lr){6-8}\cmidrule(lr){10-12}\cmidrule(lr){14-16}" _n ;
file write `fh' " & (1) & (2) & (3) & & (4) & (5) & (6) & & (7) & (8) & (9) & & (10) & (11) & (12) \\" _n ;
file write `fh' "\midrule" _n ;
local Rrow "Risk in the cycle" ;                           local Rse "" ; local Rsd "" ;
local Frow "Risk before the grant (first cycles)" ;        local Fse "" ; local Fsd "" ;
local Lrow "Risk in the previous cycle (later cycles)" ;   local Lse "" ; local Lsd "" ;
local mrow "Mean of dependent variable" ;
local irow "Nb. of investigators" ;
local nrow "Nb. of grant cycles" ;
forvalues j = 1/`nmeas' {;
    quietly summarize R`j' if s`j' ;
    local sdR = r(sd) ;
    quietly summarize L`j' if s`j' & later == 0 ;
    local sdF = r(sd) ;
    quietly summarize L`j' if s`j' & later == 1 ;
    local sdL = r(sd) ;
    display as result "Table G2, `l`j'': s.d. of the cycle's risk " %7.4f `sdR' ", of the risk before the grant " %7.4f `sdF' ", of the previous cycle's " %7.4f `sdL' ;
    /* the cells: regressor (R, F, L) by column (1, 2, 3); the empty cells
       are the locals never defined */
    local Rb1 = `b1_`j'_A' ;  local Re1 = `se1_`j'_A' ;
    local Rb3 = `bj_`j'' ;    local Re3 = `sj_`j'' ;
    local Fb2 = `bl1_`j'_A' ; local Fe2 = `sl1_`j'_A' ;
    local Fb3 = `bja_`j'' ;   local Fe3 = `sja_`j'' ;
    local Lb2 = `bl2_`j'_A' ; local Le2 = `sl2_`j'_A' ;
    local Lb3 = `bjb_`j'' ;   local Le3 = `sjb_`j'' ;
    if `j' > 1 {;
        foreach r in R F L {;
            local `r'row "``r'row' &" ;
            local `r'se "``r'se' &" ;
            local `r'sd "``r'sd' &" ;
        } ;
        local mrow "`mrow' &" ;
        local irow "`irow' &" ;
        local nrow "`nrow' &" ;
    } ;
    foreach r in R F L {;
        local sdv = `sd`r'' ;
        forvalues c = 1/3 {;
            if "``r'b`c''" == "" {;
                local `r'row "``r'row' & " ;
                local `r'se "``r'se' & " ;
                local `r'sd "``r'sd' & " ;
            } ;
            else {;
                nr_star ``r'b`c'' ``r'e`c'' ;
                local vb  = strtrim(string(``r'b`c'', "%7.4f")) ;
                local ve  = strtrim(string(``r'e`c'', "%6.4f")) ;
                local vsd = strtrim(string(``r'b`c'' * `sdv', "%7.4f")) ;
                local `r'row "``r'row' & `vb'`r(star)'" ;
                local `r'se "``r'se' & (`ve')" ;
                local `r'sd "``r'sd' & {\footnotesize [`vsd']}" ;
            } ;
        } ;
    } ;
    local vm = strtrim(string(`md_`j'_A', "%5.3f")) ;
    local vi = strtrim(string(`ni_`j'_A', "%9.0fc")) ;
    local vn = strtrim(string(`N_`j'_A', "%9.0fc")) ;
    local mrow "`mrow' & `vm' & `vm' & `vm'" ;
    local irow "`irow' & `vi' & `vi' & `vi'" ;
    local nrow "`nrow' & `vn' & `vn' & `vn'" ;
} ;
file write `fh' "`Rrow' \\" _n "`Rse' \\" _n "`Rsd' \\" _n "\addlinespace" _n ;
file write `fh' "`Frow' \\" _n "`Fse' \\" _n "`Fsd' \\" _n "\addlinespace" _n ;
file write `fh' "`Lrow' \\" _n "`Lse' \\" _n "`Lsd' \\" _n "\midrule" _n ;
file write `fh' "`mrow' \\" _n "`irow' \\" _n "`nrow' \\" _n ;
file close `fh' ;
type "output/tables/table_G2.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
