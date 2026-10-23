/* =============================================================================
   code/analysis/13_figure_3.do

   Purpose: Figure 3, the association of risk taking and grant renewal across
            the ventiles of each measure: one panel per measure. Renewal is
            regressed on indicators for the 20 ventiles of the measure
            (computed within evaluation year, as the deciles of Table 2), the
            tenth ventile (45-50th percentile) omitted, with the grant output
            controls of Table 2. Each coefficient and its 95% confidence
            interval are divided by the mean renewal rate of the estimation
            sample and multiplied by 100: the change in the renewal rate
            relative to its mean, in percent. Each measure has its own color
            (code/programs/_spec.do).

   Usage: do code/analysis/13_figure_3.do      estimate, save and draw
          do code/analysis/13_figure_3.do 0    redraw from the saved estimates

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/figures/figure_3_<t>.pdf, <t> = tails disr pivot so
     - graphs/gph, graphs/svg: the same graphs
     - graphs/data/figure_3_<t>_coefs.dta: the plotted coefficients
     - estimates/figure_3_<t>_k3.ster
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
include "code/programs/_spec.do" ;
include "code/programs/_programs.do" ;

log using "logs/13_figure_3.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;

/* 1 = estimate and save; 0 = reuse the saved estimates (graphs only) */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

/* measures to run (1 tails, 2 disruption, 3 pivoting, 4 standing out) */
local meas_run "1 2 3 4" ;

/* x-axis labels: the 20 ventiles as percentile ranges */
local xl "" ;
forvalues q = 1/20 {;
    local xl `"`xl' `q' "`=5*(`q'-1)'-`=5*`q''""' ;
} ;

use "`afile'", clear ;

foreach j of local meas_run {;

    local m "`m`j''" ;
    local t "`t`j''" ;

    display _newline(2) as text "==== Figure 3, panel `j': `l`j'' (`m') ====" ;

    capture drop vent ;
    gquantiles vent = `m' if !missing(`m'), xtile nquantiles(20) by(`pctby') ;

    if `run_regs' {;
        /* the cycles of the all-cycles columns of Table 2: every control
           defined */
        capture drop smp ;
        reghdfe `dv' ib10.vent `x3', absorb(`fe3') vce(cluster `clus') ;
        quietly summarize `dv' if e(sample) ;
        estadd scalar meandv = r(mean) ;
        estimates save "estimates/figure_3_`t'_k3.ster", replace ;
    } ;

    /* the plotted coefficients, in percent of the mean renewal rate */
    tempname pf ;
    tempfile coefs ;
    postfile `pf' byte(k v) double(b lo hi) using `coefs', replace ;
    forvalues k = 3/3 {;
        estimates use "estimates/figure_3_`t'_k`k'.ster" ;
        forvalues q = 1/20 {;
            if `q' == 10 {;
                post `pf' (`k') (`q') (0) (0) (0) ;
            } ;
            else {;
                local b = 100 * _b[`q'.vent] / e(meandv) ;
                local s = 100 * _se[`q'.vent] / e(meandv) ;
                post `pf' (`k') (`q') (`b') (`b' - 1.96*`s') (`b' + 1.96*`s') ;
            } ;
        } ;
    } ;
    postclose `pf' ;

    preserve ;
    use `coefs', clear ;
    label variable b "Change in renewal rate, percent of its mean" ;
    compress ;
    save "graphs/data/figure_3_`t'_coefs.dta", replace ;
    list, sepby(k) noobs ;

    /* the y-scale: whole multiples of a step that gives about six labels */
    quietly summarize lo ;
    local ymin = r(min) ;
    quietly summarize hi ;
    local ymax = r(max) ;
    local range = `ymax' - `ymin' ;
    local step = cond(`range' > 30, 10, cond(`range' > 15, 5, cond(`range' > 6, 2, 1))) ;
    local ylo = `step' * floor(`ymin' / `step') ;
    local yhi = `step' * ceil(`ymax' / `step') ;

    /* y labels as percentages (the values are already in percent) */
    mylabels `ylo'(`step')`yhi', myscale(@) suffix(%) format(%4.0f) local(ylab) ;

    local col "`c`j''" ;
    forvalues k = 3/3 {;
        twoway
            (rcap lo hi v if k == `k', lcolor("`col'") lwidth(medthin))
            (scatter b v if k == `k' & v != 10, mcolor("`col'") msymbol(circle) msize(medium))
            (scatter b v if k == `k' & v == 10, mcolor("`col'") mfcolor(white) msymbol(circle) msize(medium)),
            yline(0, lcolor(gs6) lwidth(thin))
            xlabel(`xl', angle(45) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
            ylabel(`ylab', angle(horizontal) labsize(medsmall) tlength(.75)
                   grid glwidth(vvthin) glcolor(gs13))
            yscale(range(`ylo' `yhi'))
            xtitle("Percentile of `g`j''", size(medium))
            ytitle("Change in Renewal Rate", size(medium))
            legend(off)
            graphregion(color(white) margin(small)) plotregion(margin(small)) ;
        nr_gexport figure_3_`t' ;
        graph close ;
    } ;
    restore ;
} ;

capture erase "scheme-deadzone.scheme" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
