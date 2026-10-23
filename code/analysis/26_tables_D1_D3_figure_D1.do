/* =============================================================================
   code/analysis/26_tables_D1_D3_figure_D1.do

   Purpose: near and far pivots, and the distance of the new pairs (Appendix
            D, which dissects pivoting). The pivoting measure splits into new
            pairs whose two descriptors both appear in the investigator's
            five-year baseline (near) and new pairs with a descriptor absent
            from it (far); the two add up to pivoting
            (code/build/09_pivoting.do).
              Table D1:  the two parts and their descriptives, the share of
                         far pairs in which both descriptors are new and the
                         distance of the new pairs (piv_distance), with the
                         means for new investigators and for the rest (Panel
                         A); the correlations of near, far and the distance
                         with the single-descriptor share, the TF-IDF cosine
                         dissimilarity and the number of baseline papers
                         (Panel B); on the cycles of Table 2's pivoting
                         regression on all cycles.
              Figure D1: the near and far shares and the distance of the new
                         pairs, by renewal status, on the same cycles.
              Table D2:  renewal on pivoting (odd columns) and on its near
                         and far parts (even columns), with the grant output
                         controls of Table 2 and indicators for the number of
                         baseline papers with MeSH (1, 2, 3-4, 5-9, 10-19,
                         20-49, 50+), for all of Table 2's pivoting cycles
                         (1, 2), new investigators (3, 4) and other
                         investigators (5, 6); the p-value of near = far (far
                         minus near goes to the log). Within a group, both
                         columns use the cycles of the odd one.
              Table D3:  how much and how far. Renewal on the distance of
                         the new pairs alone (odd columns) and with pivoting
                         (even columns), the same controls and groups, on
                         the cycles of Table D2 with a distance; one s.d. of
                         the distance in points of renewal.
            Pivoting and its parts enter as fractions; the distance runs from
            0 to 1. The baseline count is n_base_mesh, the baseline papers
            with a MeSH descriptor (code/build/09_pivoting.do), not every
            baseline paper: a paper without MeSH plays no part in the
            measure. The log adds the distance with and without NLM's check
            tags, and the near and far split without the baseline bins.

   Input:
     - ${public}/nih_risk_public.dta           (code/build/34_public_file.do)
       with the variables of risk_pivoting_extras.dta (code/build/10_pivoting_extras.do)
   Output:
     - output/tables/table_D1.tex, table_D2.tex, table_D3.tex (rows only,
       written row by row: the paper supplies the tabular, caption and notes)
     - output/figures/figure_D1_near.pdf, figure_D1_far.pdf,
       figure_D1_dist.pdf; graphs/gph, graphs/svg: the same graphs
     - estimates/tables_D2_D3_g<1|2|3>_<one|two|dist|both>.ster (g: all, new,
       other investigators; one, two: Table D2; dist, both: Table D3)

   Note: a first argument of 0 (do code/analysis/26_tables_D1_D3_figure_D1.do 0)
         reuses the saved estimates, to redraw the figures and the tables
         without re-estimating.
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
/* pivoting's color (c3 in code/programs/_spec.do), kept before section 2
   reuses c1 to c4 */
local pcol "`c3'" ;
include "code/programs/_programs.do" ;

log using "logs/26_tables_D1_D3_figure_D1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate; 0 = reuse the saved estimates. A first argument overrides it
   (do code/analysis/26_tables_D1_D3_figure_D1.do 0), to redraw the figures
   without re-estimating */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

local pv  "frac_setnb_pair" ;
local pvn "frac_setnb_pair_near" ;
local pvf "frac_setnb_pair_far" ;

/* -----------------------------------------------------------------------------
   1. The analysis file, with the extras of code/build/10_pivoting_extras.do
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;
assert abs(`pvn' + `pvf' - `pv') < 1e-9 if !missing(`pv') ;

/* bins of the number of baseline papers with MeSH */
gen byte nprior_bin = 1 if n_base_mesh == 1 ;
replace nprior_bin = 2 if n_base_mesh == 2 ;
replace nprior_bin = 3 if inrange(n_base_mesh, 3, 4) ;
replace nprior_bin = 4 if inrange(n_base_mesh, 5, 9) ;
replace nprior_bin = 5 if inrange(n_base_mesh, 10, 19) ;
replace nprior_bin = 6 if inrange(n_base_mesh, 20, 49) ;
replace nprior_bin = 7 if n_base_mesh >= 50 & !missing(n_base_mesh) ;
capture label drop nprior_bin ;
label define nprior_bin 1 "1" 2 "2" 3 "3-4" 4 "5-9" 5 "10-19" 6 "20-49" 7 "50+" ;
label values nprior_bin nprior_bin ;
assert !missing(nprior_bin) if !missing(`pv') ;
gen double ln_nprior = ln(n_base_mesh) ;

/* Table 2's pivoting sample: its regression on all cycles
   (code/analysis/12_table_2.do) */
gquantiles dec = `pv' if !missing(`pv'), xtile nquantiles(10) by(`pctby') ;
gen byte lo = (dec == 1)  if !missing(dec) ;
gen byte hi = (dec == 10) if !missing(dec) ;
reghdfe `dv' lo hi `x3', absorb(`fe3') vce(cluster `clus') ;
gen byte t2smp = e(sample) ;
local n_t2 = e(N) ;
display as result "=== Table 2 pivoting sample: " %9.0fc `n_t2' " cycles" ;
drop dec lo hi ;

display as result "=== new investigators on the sample, and the baseline bins" ;
tab new_inv if t2smp, missing ;
tab nprior_bin new_inv if t2smp, missing col ;
display as result "=== near and far by baseline bin" ;
tabstat `pv' `pvn' `pvf' far_both_new frac_setnb_mesh cos_dissim_setnb if t2smp,
    by(nprior_bin) stat(mean n) ;

/* -----------------------------------------------------------------------------
   2. Table D1: descriptives and correlations, on Table 2's pivoting sample
   ----------------------------------------------------------------------------- */
local dv1 "`pv'" ;
local dv2 "`pvn'" ;
local dv3 "`pvf'" ;
local dv4 "far_both_new" ;
local dv5 "piv_distance" ;
local dl1 "Pivoting, all new pairs" ;
local dl2 "Near new pairs" ;
local dl3 "Far new pairs" ;
local dl4 "Among far pairs, share with both descriptors new" ;
local dl5 "Distance of the new pairs" ;
local cv1 "frac_setnb_mesh" ;
local cv2 "cos_dissim_setnb" ;
local cv3 "n_base_mesh" ;
local cv4 "ln_nprior" ;
local cl1 "Share of new single descriptors" ;
local cl2 "Cosine dissimilarity from prior work" ;
local cl3 "Number of baseline papers" ;
local cl4 "Number of baseline papers (log)" ;

tempname fh ;
file open `fh' using "output/tables/table_D1.tex", write replace ;
file write `fh' " & & & & & & & \multicolumn{2}{c}{Mean} \\" _n ;
file write `fh' "\cmidrule(lr){8-9}" _n ;
file write `fh' " & Mean & Std. dev. & Median & Share \(=0\) & Cycles & & New inv. & Others \\" _n ;
file write `fh' "\midrule" _n ;
file write `fh' "\multicolumn{9}{l}{\textit{A. The parts of the pivoting measure}} \\" _n ;
forvalues i = 1/5 {;
    quietly summarize `dv`i'' if t2smp, detail ;
    local mu : display %5.3f r(mean) ;
    local sd : display %5.3f r(sd) ;
    local md : display %5.3f r(p50) ;
    local nn = r(N) ;
    local nc : display %9.0fc `nn' ;
    local nc = strtrim("`nc'") ;
    quietly count if t2smp & `dv`i'' == 0 ;
    local z : display %5.3f r(N) / `nn' ;
    quietly summarize `dv`i'' if t2smp & new_inv == 1 ;
    local m1 : display %5.3f r(mean) ;
    quietly summarize `dv`i'' if t2smp & new_inv == 0 ;
    local m0 : display %5.3f r(mean) ;
    file write `fh' "\quad `dl`i'' & `mu' & `sd' & `md' & `z' & `nc' & & `m1' & `m0' \\" _n ;
    display as text "`dl`i'': mean `mu' sd `sd' median `md' zero `z' N `nc' new `m1' others `m0'" ;
} ;
quietly count if t2smp & new_inv == 1 ;
local nni : display %9.0fc r(N) ;
local nni = strtrim("`nni'") ;
quietly count if t2smp & new_inv == 0 ;
local nno : display %9.0fc r(N) ;
local nno = strtrim("`nno'") ;
file write `fh' "\quad\quad{\footnotesize\textit{Cycles}} & & & & & & & {\footnotesize `nni'} & {\footnotesize `nno'} \\" _n ;
file write `fh' "\addlinespace" _n ;
file write `fh' "\multicolumn{9}{l}{\textit{B. Correlations}} \\" _n ;
file write `fh' " & All new pairs & Near & Far & Distance & & & & \\" _n ;
quietly correlate `pv' `pvn' `pvf' `dv5' `cv1' `cv2' `cv3' `cv4' if t2smp ;
matrix C = r(C) ;
local nc : display %9.0fc r(N) ;
local nc = strtrim("`nc'") ;
matrix list C, format(%6.3f) ;
forvalues i = 1/4 {;
    local r = 4 + `i' ;
    local c1 : display %5.3f C[`r', 1] ;
    local c2 : display %5.3f C[`r', 2] ;
    local c3 : display %5.3f C[`r', 3] ;
    local c4 : display %5.3f C[`r', 4] ;
    file write `fh' "\quad `cl`i'' & `c1' & `c2' & `c3' & `c4' & & & & \\" _n ;
} ;
local c12 : display %5.3f C[2, 3] ;
file write `fh' "\quad Near new pairs & & & `c12' & & & & & \\" _n ;
local c41 : display %5.3f C[4, 1] ;
local c42 : display %5.3f C[4, 2] ;
local c43 : display %5.3f C[4, 3] ;
file write `fh' "\quad Distance of the new pairs & `c41' & `c42' & `c43' & & & & & \\" _n ;
file write `fh' "\quad\quad{\footnotesize\textit{Cycles}} & \multicolumn{4}{c}{\footnotesize `nc'} & & & & \\" _n ;
file close `fh' ;
type "output/tables/table_D1.tex" ;

display as result "=== Spearman correlations, same cycles" ;
spearman `pv' `pvn' `pvf' `dv5' `cv1' `cv2' `cv3' if t2smp, stats(rho) ;
display as result "=== the distance with and without NLM's check tags (log only)" ;
summarize piv_distance piv_distance_noct if t2smp ;
correlate piv_distance piv_distance_noct `pv' `pvf' if t2smp ;
display as result "=== the distance by baseline bin and for new investigators" ;
tabstat `dv5' if t2smp, by(nprior_bin) stat(mean sd n) ;
tabstat `dv5' if t2smp, by(new_inv) stat(mean sd n) ;

/* -----------------------------------------------------------------------------
   2b. Figure D1: the near and far shares and the distance of the new pairs,
       by renewal status, on Table 2's pivoting cycles, drawn as Figure 2 draws
       the four measures: 20 bins of equal width, renewed in pivoting's color,
       not renewed in a light tint of it.
   ----------------------------------------------------------------------------- */
graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;
local fv1 "`pvn'" ;
local fv2 "`pvf'" ;
local fv3 "piv_distance" ;
local fg1 "Near New Pairs, Share of the Cycle's MeSH Pairs" ;
local fg2 "Far New Pairs, Share of the Cycle's MeSH Pairs" ;
local fg3 "Distance of the New Pairs" ;
local ft1 "near" ;
local ft2 "far" ;
local ft3 "dist" ;
local fp1 = 1 ;
local fp2 = 11 ;
local fp3 = 1 ;
display as result "=== Figure D1: means by renewal status, Table 2's pivoting cycles" ;
tabstat `pvn' `pvf' piv_distance if t2smp, by(`dv') stat(mean sd n) ;
forvalues j = 1/3 {;
    preserve ;
    keep if t2smp & !missing(`fv`j'') ;
    gen byte bin = min(floor(`fv`j'' * 20), 19) ;
    gen byte one = 1 ;
    gcollapse (sum) n = one, by(bin `dv') ;
    /* each bar is the share of its group's cycles */
    gegen double tot = total(n), by(`dv') ;
    gen double pct = 100 * n / tot ;
    gen double x = (bin + 0.5) / 20 + cond(`dv' == 1, 0.01, -0.01) ;
    quietly summarize pct ;
    nr_pctlab `=r(max)' ;
    local ylabp `"`r(lab)'"' ;
    local ptop = r(top) ;
    twoway
        (bar pct x if `dv' == 0, barwidth(0.02) color("`pcol'%35") lwidth(none))
        (bar pct x if `dv' == 1, barwidth(0.02) color("`pcol'") lwidth(none)),
        xlabel(0(.2)1, labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13) format(%3.1f))
        ylabel(`ylabp', angle(horizontal) labsize(medsmall) tlength(.75)
               grid glwidth(vvthin) glcolor(gs13))
        yscale(range(0 `ptop'))
        xtitle("`fg`j''", size(medium))
        ytitle("Share of Grant Cycles", size(medium))
        legend(order(1 "Not renewed" 2 "Renewed") ring(0) position(`fp`j'') cols(1)
               size(medsmall) region(lcolor(none)))
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_D1_`ft`j'' ;
    graph close ;
    restore ;
} ;
capture erase "scheme-deadzone.scheme" ;

/* -----------------------------------------------------------------------------
   3. Tables D2 and D3: the grant output controls and the baseline bins in
      every column, in three groups: all of Table 2's pivoting cycles, new
      investigators, other investigators. Within a group, both columns of
      Table D2 use the cycles of its first column, and both columns of
      Table D3 those cycles with a distance.
   ----------------------------------------------------------------------------- */
local gc1 "t2smp" ;
local gc2 "t2smp & new_inv == 1" ;
local gc3 "t2smp & new_inv == 0" ;

forvalues g = 1/3 {;
    if `run_regs' {;
        capture drop smp ;
        reghdfe `dv' `pv' `x3' if `gc`g'', absorb(`fe3' nprior_bin) vce(cluster `clus') ;
        gen byte smp = e(sample) ;
        local nn = e(N) ;
        display as result "=== group `g': " %9.0fc `nn' " cycles (Table 2 sample: " %9.0fc `n_t2' ")" ;
        nr_post ;
        estimates save "estimates/tables_D2_D3_g`g'_one.ster", replace ;

        reghdfe `dv' `pvn' `pvf' `x3' if smp, absorb(`fe3' nprior_bin) vce(cluster `clus') ;
        assert e(N) == `nn' ;
        nr_post ;
        test `pvn' = `pvf' ;
        estadd scalar pnf = r(p) ;
        lincom `pvf' - `pvn' ;
        estadd scalar dfn    = r(estimate) ;
        estadd scalar dfn_se = r(se) ;
        estimates save "estimates/tables_D2_D3_g`g'_two.ster", replace ;

        /* log only: the split without the baseline bins */
        quietly reghdfe `dv' `pvn' `pvf' `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
        display as result "NO BINS group `g': near " %7.4f _b[`pvn'] " (" %6.4f _se[`pvn']
            "), far " %7.4f _b[`pvf'] " (" %6.4f _se[`pvf'] ")" ;

        /* Table D3: the distance alone, then with pivoting */
        reghdfe `dv' piv_distance `x3' if smp & !missing(piv_distance), absorb(`fe3' nprior_bin) vce(cluster `clus') ;
        local nd = e(N) ;
        nr_post ;
        quietly summarize piv_distance if e(sample) ;
        local sdx = r(sd) ;
        estadd scalar sdx = `sdx' ;
        estadd scalar eff = 100 * _b[piv_distance] * `sdx' ;
        estimates save "estimates/tables_D2_D3_g`g'_dist.ster", replace ;

        reghdfe `dv' `pv' piv_distance `x3' if smp & !missing(piv_distance), absorb(`fe3' nprior_bin) vce(cluster `clus') ;
        assert e(N) == `nd' ;
        nr_post ;
        quietly summarize piv_distance if e(sample) ;
        local sdx = r(sd) ;
        estadd scalar sdx = `sdx' ;
        estadd scalar eff = 100 * _b[piv_distance] * `sdx' ;
        estimates save "estimates/tables_D2_D3_g`g'_both.ster", replace ;

        /* log only: the distance with and without NLM's check tags, on the
           cycles with both, alone and with pivoting */
        foreach w in piv_distance piv_distance_noct {;
            quietly summarize `w' if smp & !missing(piv_distance, piv_distance_noct) ;
            local sdw = r(sd) ;
            quietly reghdfe `dv' `w' `x3' if smp & !missing(piv_distance, piv_distance_noct), absorb(`fe3' nprior_bin) vce(cluster `clus') ;
            display as result "CHECK TAGS group `g', `w' alone (" %7.0fc e(N) " cycles): " %7.4f _b[`w'] " (" %6.4f _se[`w'] "), one s.d. " %5.2f 100 * _b[`w'] * `sdw' " points" ;
            quietly reghdfe `dv' `pv' `w' `x3' if smp & !missing(piv_distance, piv_distance_noct), absorb(`fe3' nprior_bin) vce(cluster `clus') ;
            display as result "CHECK TAGS group `g', `w' with pivoting: " %7.4f _b[`w'] " (" %6.4f _se[`w'] "), one s.d. " %5.2f 100 * _b[`w'] * `sdw' " points; pivoting " %7.4f _b[`pv'] " (" %6.4f _se[`pv'] ")" ;
        } ;
        drop smp ;
    } ;
} ;

/* screen, for the log */
eststo clear ;
forvalues g = 1/3 {;
    foreach s in one two dist both {;
        estimates use "estimates/tables_D2_D3_g`g'_`s'.ster" ;
        eststo g`g'`s' ;
    } ;
} ;
esttab g1one g1two g2one g2two g3one g3two, keep(`pv' `pvn' `pvf') order(`pv' `pvn' `pvf')
    b(%6.4f) se(%6.4f) star(+ 0.10 * 0.05 ** 0.01) nomtitles noobs
    stats(pnf dfn dfn_se meandv ninv N, fmt(%6.4f %6.4f %6.4f %6.3f %9.0fc %9.0fc))
    title("Table D2") ;
esttab g1dist g1both g2dist g2both g3dist g3both, keep(`pv' piv_distance) order(`pv' piv_distance)
    b(%6.4f) se(%6.4f) star(+ 0.10 * 0.05 ** 0.01) nomtitles noobs
    stats(sdx eff meandv ninv N, fmt(%6.4f %6.2f %6.3f %9.0fc %9.0fc))
    title("Table D3") ;

/* the fragments of Tables D2 (t = 2) and D3 (t = 3): six columns, a gutter
   after columns 2 and 4 */
local vl1 "Pivoting, all new pairs" ;
local vl2 "Near new pairs" ;
local vl3 "Far new pairs" ;
local vl4 "Distance of the new pairs" ;
local vv1 "`pv'" ;
local vv2 "`pvn'" ;
local vv3 "`pvf'" ;
local vv4 "piv_distance" ;

forvalues t = 2/3 {;
    if `t' == 2 {;
        local sfx1 "one" ;
        local sfx2 "two" ;
        local vlist "1 2 3" ;
    } ;
    else {;
        local sfx1 "dist" ;
        local sfx2 "both" ;
        local vlist "1 4" ;
    } ;
    forvalues c = 1/6 {;
        local g = ceil(`c' / 2) ;
        local s = 2 - mod(`c', 2) ;
        local col`c' "g`g'`sfx`s''" ;
    } ;
    file open `fh' using "output/tables/table_D`t'.tex", write replace ;
    file write `fh' " & \multicolumn{2}{c}{All cycles} & & \multicolumn{2}{c}{New investigators} & & \multicolumn{2}{c}{Other investigators} \\" _n ;
    file write `fh' "\cmidrule(lr){2-3}\cmidrule(lr){5-6}\cmidrule(lr){8-9}" _n ;
    file write `fh' " & (1) & (2) & & (3) & (4) & & (5) & (6) \\" _n ;
    file write `fh' "\midrule" _n ;
    foreach v of local vlist {;
        local r1 "`vl`v''" ;
        local r2 "" ;
        forvalues c = 1/6 {;
            estimates restore `col`c'' ;
            local b = . ;
            capture local b = _b[`vv`v''] ;
            if `b' < . {;
                local se = _se[`vv`v''] ;
                nr_star `b' `se' ;
                local r1 "`r1' & `: display %6.3f `b''`r(star)'" ;
                local r2 "`r2' & (`: display %5.3f `se'')" ;
            } ;
            else {;
                local r1 "`r1' & " ;
                local r2 "`r2' & " ;
            } ;
            if inlist(`c', 2, 4) {;
                local r1 "`r1' &" ;
                local r2 "`r2' &" ;
            } ;
        } ;
        file write `fh' "`r1' \\" _n ;
        file write `fh' "`r2' \\" _n ;
    } ;
    if `t' == 2 {;
        /* far minus near (dfn, dfn_se) stays in the log's screen: the
           p-value row carries the test */
        local rp "p-value, near \(=\) far" ;
        forvalues c = 1/6 {;
            estimates restore `col`c'' ;
            if mod(`c', 2) == 0 {;
                local pp = e(pnf) ;
                local pps : display %5.3f `pp' ;
                if `pp' < 0.001 local pps "\(<\)0.001" ;
                local rp "`rp' & `pps'" ;
            } ;
            else local rp "`rp' & " ;
            if inlist(`c', 2, 4) local rp "`rp' &" ;
        } ;
        file write `fh' "\addlinespace" _n ;
        file write `fh' "`rp' \\" _n ;
    } ;
    else {;
        local re "One s.d. of distance, in points of renewal" ;
        forvalues c = 1/6 {;
            estimates restore `col`c'' ;
            local re "`re' & `: display %5.2f e(eff)'" ;
            if inlist(`c', 2, 4) local re "`re' &" ;
        } ;
        file write `fh' "\addlinespace" _n ;
        file write `fh' "`re' \\" _n ;
    } ;
    local rm "Mean of dependent variable" ;
    local rn "Nb. of grant cycles" ;
    local ri "Nb. of investigators" ;
    /* the adjusted R2 closes the table, as in the paper's tables */
    local ra "Adjusted \(R^2\)" ;
    forvalues c = 1/6 {;
        estimates restore `col`c'' ;
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
        if inlist(`c', 2, 4) {;
            local rm "`rm' &" ;
            local rn "`rn' &" ;
            local ri "`ri' &" ;
            local ra "`ra' &" ;
        } ;
    } ;
    file write `fh' "\midrule" _n ;
    file write `fh' "`rm' \\" _n ;
    file write `fh' "`rn' \\" _n ;
    file write `fh' "`ri' \\" _n ;
    file write `fh' "`ra' \\" _n ;
    file close `fh' ;
    type "output/tables/table_D`t'.tex" ;
} ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
