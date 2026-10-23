/* =============================================================================
   code/analysis/27_table_D4_figure_D3.do

   Purpose: is the penalty on pivoting smaller when the investigator leaves a
            fading field (Appendix D, which dissects pivoting)? vib_pre
            (code/build/26_fading_fields.do) is the mean, over the
            investigator's baseline papers, of the share of each paper's PMRA
            neighbors published in s - 5 to s - 1 rather than s - 10 to
            s - 6, the neighbors she authored (in any position) removed.
            fading = 1 when vib_pre is below
            its median among the cycles of the regression sample with the
            same cycle_yr. Pivoting (frac_setnb_pair) enters as a fraction.
            Every column of Table D4 has the grant output controls of Table 2
            and the bins of baseline papers with MeSH of
            code/analysis/26_tables_D1_D3_figure_D1.do, clustered by
            investigator and grant:
              (1) pivoting, on Table 2's pivoting sample;
              (2) the same, on the cycles with vib_pre defined;
              (3) adds fading;
              (4) adds pivoting x fading, with pivoting centered at its
                  mean on the cycles of columns 2 to 4, so that the
                  coefficient on fading is the gap at average pivoting
                  (the coefficient on pivoting and the interaction are
                  unchanged by the centering).
            Every column ends with the adjusted R2. The penalty in a fading
            field, the sum of two coefficients, goes to the log for the
            text, never to a table row.
            Figure D3: the penalty on pivoting in each decile of vib_pre
            within cycle_yr, from one regression with a slope per decile.
            The share of the column 1 sample with vib_pre defined, the test
            that the ten slopes are equal and the penalty in a fading field
            go to the log.

   Input:
     - ${public}/nih_risk_public.dta             (code/build/34_public_file.do)
       with the variables of risk_fading.dta (code/build/26_fading_fields.do)
   Output:
     - output/tables/table_D4.tex (rows only, written row by row)
     - output/figures/figure_D3.pdf; graphs/gph, graphs/svg: the same graph
     - estimates/table_D4_c1.ster to table_D4_c4.ster, and
       estimates/table_D4_samples.dta (the samples of columns 1 and 4)

   Note: a first argument of 0 (do code/analysis/27_table_D4_figure_D3.do 0)
         reuses the saved estimates and samples, to redraw the table and the
         figure without re-estimating.
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

log using "logs/27_table_D4_figure_D3.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* Figure D3 is drawn in Stata's default scheme, stcolor (7.5 by 4.5 inches).
   The other figure do-files set grstyle's scheme, which stays in force for
   the rest of a Stata session, so the scheme is set here explicitly: run
   from master.do, after them, the figure is the same as run alone. */
set scheme stcolor ;

/* 1 = estimate and save; 0 = reuse the saved estimates. A first argument
   overrides it */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;
local pv "`m3'" ;

/* -----------------------------------------------------------------------------
   1. The analysis file, with vib_pre
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

/* the bins of baseline papers with MeSH of
   code/analysis/26_tables_D1_D3_figure_D1.do, absorbed in every regression: a
   thin baseline raises pivoting mechanically and pushes vibrancy to the
   extremes */
gen byte nprior_bin = 1 if n_base_mesh == 1 ;
replace nprior_bin = 2 if n_base_mesh == 2 ;
replace nprior_bin = 3 if inrange(n_base_mesh, 3, 4) ;
replace nprior_bin = 4 if inrange(n_base_mesh, 5, 9) ;
replace nprior_bin = 5 if inrange(n_base_mesh, 10, 19) ;
replace nprior_bin = 6 if inrange(n_base_mesh, 20, 49) ;
replace nprior_bin = 7 if n_base_mesh >= 50 & !missing(n_base_mesh) ;
assert !missing(nprior_bin) if !missing(`pv') ;

/* -----------------------------------------------------------------------------
   2. Regressions
   ----------------------------------------------------------------------------- */
if `run_regs' {;
    /* (1) Table 2's pivoting sample */
    reghdfe `dv' `pv' `x3' if !missing(`pv'), absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    gen byte s1 = e(sample) ;
    nr_post ;
    estimates save "estimates/table_D4_c1", replace ;

    /* fading: below the median of vib_pre within cycle_yr, regression sample */
    gen byte vs = s1 & !missing(vib_pre) ;
    /* the two samples, saved with the estimates: estimates use does not restore
       e(sample) on the data, and the figure and the deciles need them */
    preserve ;
        keep inv_id grant_id cycle s1 vs ;
        sort inv_id grant_id cycle ;
        compress ;
        save "estimates/table_D4_samples.dta", replace ;
    restore ;
    gegen double med = median(vib_pre) if vs, by(cycle_yr) ;
    gen byte fading = vib_pre < med if vs ;
    quietly summarize `pv' if vs ;
    gen double pvc = `pv' - r(mean) if vs ;
    gen double pv_x_fad = pvc * fading ;

    /* (2) the same on the cycles with vib_pre */
    reghdfe `dv' `pv' `x3' if vs, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    nr_post ;
    estimates save "estimates/table_D4_c2", replace ;
    local n2 = e(N) ;

    /* (3) fading, without the interaction */
    reghdfe `dv' `pv' fading `x3' if vs, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    assert e(N) == `n2' ;
    nr_post ;
    estimates save "estimates/table_D4_c3", replace ;

    /* (4) the interaction. The penalty in a fading field, the sum of two
       coefficients, is for the text and the log only, not a table row */
    reghdfe `dv' pvc fading pv_x_fad `x3' if vs, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
    assert e(N) == `n2' ;
    nr_post ;
    lincom pvc + pv_x_fad ;
    estadd scalar bfad    = r(estimate) ;
    estadd scalar bfad_se = r(se) ;
    estimates save "estimates/table_D4_c4", replace ;
} ;
else {;
    merge 1:1 inv_id grant_id cycle using "estimates/table_D4_samples.dta", keepusing(s1 vs) ;
    tab _merge ;
    assert _merge == 3 ;
    drop _merge ;
    gegen double med = median(vib_pre) if vs, by(cycle_yr) ;
    gen byte fading = vib_pre < med if vs ;
    quietly summarize `pv' if vs ;
    gen double pvc = `pv' - r(mean) if vs ;
    gen double pv_x_fad = pvc * fading ;
} ;
/* deciles of vib_pre within cycle_yr, on the regression sample */
gquantiles dec = vib_pre if vs, xtile nquantiles(10) by(cycle_yr) ;

/* -----------------------------------------------------------------------------
   3. The share of the column 1 sample with vib_pre defined (log)
   ----------------------------------------------------------------------------- */
display as result "=== Table 2 pivoting sample (column 1), and with vib_pre defined" ;
count if s1 ;
local a = r(N) ;
count if vs ;
local b = r(N) ;
display as result "share with vib_pre: " %6.4f `b' / `a' ;

/* -----------------------------------------------------------------------------
   4. Figure D3: the penalty on pivoting in each decile of vib_pre within
      cycle_yr. One regression: a separate pivoting slope for each decile,
      with decile indicators, the controls of column 4 and the baseline
      bins. Each point is the penalty in that decile itself, so no decile is
      omitted; the dashed line is the pooled slope of column 2.
   ----------------------------------------------------------------------------- */
estimates use "estimates/table_D4_c2" ;
local bpool = _b[`pv'] ;
reghdfe `dv' ibn.dec#c.`pv' `x3' if vs, absorb(`fe3' nprior_bin dec) vce(cluster `clus') ;
if `run_regs' assert e(N) == `n2' ;
local eq "1.dec#c.`pv'" ;
forvalues d = 2/10 {;
    local eq "`eq' = `d'.dec#c.`pv'" ;
} ;
test `eq' ;
local peq = r(p) ;
display as result "=== Figure D3: test that the ten slopes are equal, p = " %6.4f `peq' ;
preserve ;
clear ;
set obs 10 ;
gen byte d = _n ;
gen double b  = . ;
gen double se = . ;
forvalues d = 1/10 {;
    quietly replace b  = _b[`d'.dec#c.`pv']  if d == `d' ;
    quietly replace se = _se[`d'.dec#c.`pv'] if d == `d' ;
} ;
gen double lo = b - 1.96 * se ;
gen double hi = b + 1.96 * se ;
list, noobs ;
label define dlab 1 "1 (fading)" 10 "10 (thriving)", replace ;
forvalues d = 2/9 {;
    label define dlab `d' "`d'", add ;
} ;
label values d dlab ;
twoway
    (rcap lo hi d, lcolor(gs6) lwidth(medthin))
    (scatter b d, mcolor(gs3) msymbol(circle) msize(small)),
    yline(`bpool', lcolor(gs8) lpattern(dash) lwidth(thin))
    yline(0, lcolor(gs12) lwidth(thin))
    ylabel(, tlength(.75) labsize(medsmall) angle(horizontal) grid glwidth(vvthin) glcolor(gs13) format(%4.2f))
    xscale(range(.4 10.6)) xlabel(1(1)10, valuelabel tlength(.75) labsize(medsmall) nogrid)
    xtitle("Vibrancy of the Field Left Behind, Decile within the Start Year", size(medium))
    ytitle("Effect of Pivoting on Renewal", size(medium))
    legend(off) graphregion(color(white) margin(small)) plotregion(margin(small)) ;
nr_gexport figure_D3 ;
graph close ;
restore ;

/* -----------------------------------------------------------------------------
   5. Table D4, row by row
   ----------------------------------------------------------------------------- */
eststo clear ;
forvalues c = 1/4 {;
    estimates use "estimates/table_D4_c`c'" ;
    eststo c`c' ;
} ;
esttab c1 c2 c3 c4, keep(`pv' pvc fading pv_x_fad) b(%6.4f) se(%6.4f) star(+ 0.10 * 0.05 ** 0.01)
    nomtitles noobs stats(bfad bfad_se meandv ninv N, fmt(%6.4f %6.4f %6.3f %9.0fc %9.0fc))
    title("Table D4 (bfad: the penalty in a fading field, for the text)") ;

local vl1 "Pivoting" ;
local vl2 "Fading field" ;
local vl3 "Pivoting \(\times\) fading field" ;
local vv1 "`pv'" ;
local vv2 "fading" ;
local vv3 "pv_x_fad" ;
tempname fh ;
file open `fh' using "output/tables/table_D4.tex", write replace ;
file write `fh' " & (1) & (2) & (3) & (4) \\" _n ;
file write `fh' "\midrule" _n ;
forvalues v = 1/3 {;
    local r1 "`vl`v''" ;
    local r2 "" ;
    forvalues c = 1/4 {;
        estimates restore c`c' ;
        local b = . ;
        capture local b = _b[`vv`v''] ;
        /* column 4 enters pivoting centered (pvc) */
        if `b' == . & `v' == 1 {;
            capture local b = _b[pvc] ;
        } ;
        if `b' < . {;
            local se = . ;
            capture local se = _se[`vv`v''] ;
            if `se' == . local se = _se[pvc] ;
            nr_star `b' `se' ;
            local r1 "`r1' & `: display %6.3f `b''`r(star)'" ;
            local r2 "`r2' & (`: display %5.3f `se'')" ;
        } ;
        else {;
            local r1 "`r1' & " ;
            local r2 "`r2' & " ;
        } ;
    } ;
    file write `fh' "`r1' \\" _n ;
    file write `fh' "`r2' \\" _n ;
} ;
/* the penalty in a fading field (pivoting + pivoting x fading, bfad) is
   not a row of the table: a row reads as a regressor. It stays in the
   log's screen for the text. */
file write `fh' "\midrule" _n ;
local rs "Sample" ;
local rm "Mean of dependent variable" ;
local rn "Nb. of grant cycles" ;
local ri "Nb. of investigators" ;
local ra "Adjusted \(R^2\)" ;
forvalues c = 1/4 {;
    estimates restore c`c' ;
    local rs = cond(`c' == 1, "`rs' & Table 2", "`rs' & Vibrancy defined") ;
    local mv : display %5.3f e(meandv) ;
    local nv : display %12.0fc e(N) ;
    local iv : display %12.0fc e(ninv) ;
    local av : display %6.4f e(r2_a) ;
    local nv = strtrim("`nv'") ;
    local iv = strtrim("`iv'") ;
    local rm "`rm' & `mv'" ;
    local rn "`rn' & `nv'" ;
    local ri "`ri' & `iv'" ;
    local ra "`ra' & `av'" ;
} ;
file write `fh' "`rs' \\" _n ;
file write `fh' "`rm' \\" _n ;
file write `fh' "`rn' \\" _n ;
file write `fh' "`ri' \\" _n ;
file write `fh' "`ra' \\" _n ;
file close `fh' ;
display as text "table: output/tables/table_D4.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/analysis/27_table_D4_figure_D3.do */
