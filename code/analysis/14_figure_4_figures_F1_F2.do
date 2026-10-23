/* =============================================================================
   code/analysis/14_figure_4_figures_F1_F2.do

   Purpose: the exhibits on novelty. Novelty is the headline measure of
            code/programs/_spec.do (local nov): the share of the cycle's noun
            phrases that are new (frac_new_phrase_oth, Arts, Melluso and
            Veugelers, a phrase counting as new only if a later paper that
            shares no author with the paper uses it;
            code/build/14_novelty_text.do).
              Figure 4: renewal on the 20 ventiles of each risk measure and the
                        20 ventiles of novelty together (both within evaluation
                        year, tenth ventile omitted), with the grant output
                        controls of Table 2; the plot shows both sets of
                        ventiles (the risk measure in its color, novelty in
                        purple), in percent of the mean renewal rate, as
                        Figure 3.
              Appendix Figure F1: distributions of four measures of novelty, by
                        renewal status: the headline (new noun phrases), the
                        share of new MeSH pairs, semantic distance, and the
                        share of new noun-phrase combinations.
              Appendix Figure F2: renewal on the ventiles of each, grant output
                        controls, one y-scale for the four panels.

   Usage: do code/analysis/14_figure_4_figures_F1_F2.do      estimate and draw
          do code/analysis/14_figure_4_figures_F1_F2.do 0    redraw Figure 4
                                    from its saved estimates (the regressions
                                    of Appendix Figure F2 always run)

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/figures/figure_4_<t>.pdf, <t> = tails disr pivot so
     - output/figures/figure_F1_<n>.pdf and figure_F2_<n>.pdf,
       <n> = phrfrac pairfrac semdist pcombfrac
     - graphs/gph, graphs/svg: the same graphs
     - graphs/data/figure_4_<t>_coefs.dta, figure_F2_coefs.dta: the plotted
       coefficients
     - estimates/figure_4_<t>.ster
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

log using "logs/14_figure_4_figures_F1_F2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;

/* 1 = estimate; 0 = reuse the saved estimates. A first argument overrides it
   (do code/analysis/14_figure_4_figures_F1_F2.do 0), to redraw Figure 4
   without re-estimating its regressions */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

/* x-axis labels: the 20 ventiles as percentile ranges */
local xl "" ;
forvalues q = 1/20 {;
    local xl `"`xl' `q' "`=5*(`q'-1)'-`=5*`q''""' ;
} ;

use "`afile'", clear ;

/* novelty ventiles, within evaluation year: the headline measure of
   code/programs/_spec.do */
gquantiles nvent = `nov' if !missing(`nov'), xtile nquantiles(20) by(`pctby') ;
tab nvent ;


/* =============================================================================
   FIGURE 4: each risk measure, controlling for novelty
   ============================================================================= */

forvalues j = 1/`nmeas' {;
    local m "`m`j''" ;
    local t "`t`j''" ;
    capture drop vent ;
    gquantiles vent = `m' if !missing(`m'), xtile nquantiles(20) by(`pctby') ;

    if `run_regs' {;
        reghdfe `dv' ib10.vent ib10.nvent `x3', absorb(`fe3') vce(cluster `clus') ;
        quietly summarize `dv' if e(sample) ;
        estadd scalar meandv = r(mean) ;
        /* cycles per ventile in the estimation sample, column 1 the risk
           measure's, column 2 novelty's; they travel with the .ster file */
        matrix nobsv = J(20, 2, 0) ;
        forvalues q = 1/20 {;
            quietly count if e(sample) & vent == `q' ;
            matrix nobsv[`q', 1] = r(N) ;
            quietly count if e(sample) & nvent == `q' ;
            matrix nobsv[`q', 2] = r(N) ;
        } ;
        estadd matrix nobsv = nobsv ;
        estimates save "estimates/figure_4_`t'.ster", replace ;
    } ;

    /* both main effects of the same regression: the risk measure's ventiles
       (s = 1) and novelty's (s = 2), each in its own color, side by side.
       A ventile with fewer than 100 cycles is not plotted: 13% of cycles
       coin no new noun phrase and all fall in novelty's first ventile,
       which leaves the second nearly empty. */
    tempname pf ;
    tempfile coefs ;
    postfile `pf' byte(s v) double(b lo hi) long nobs using `coefs', replace ;
    estimates use "estimates/figure_4_`t'.ster" ;
    matrix nobsv = e(nobsv) ;
    forvalues q = 1/20 {;
        forvalues s = 1/2 {;
            local fv = cond(`s' == 1, "vent", "nvent") ;
            local n = nobsv[`q', `s'] ;
            if `q' == 10 post `pf' (`s') (`q') (0) (0) (0) (`n') ;
            else {;
                capture local b = 100 * _b[`q'.`fv'] / e(meandv) ;
                if _rc | `n' < 100 post `pf' (`s') (`q') (.) (.) (.) (`n') ;
                else {;
                    local se = 100 * _se[`q'.`fv'] / e(meandv) ;
                    post `pf' (`s') (`q') (`b') (`b' - 1.96*`se') (`b' + 1.96*`se') (`n') ;
                } ;
            } ;
        } ;
    } ;
    postclose `pf' ;

    preserve ;
    use `coefs', clear ;
    label define fig4s 1 "risk measure" 2 "novelty", replace ;
    label values s fig4s ;
    save "graphs/data/figure_4_`t'_coefs.dta", replace ;
    list, sepby(s) noobs ;
    gen double x = v + cond(s == 1, -0.15, 0.15) ;
    quietly summarize lo ;
    local ymin = r(min) ;
    quietly summarize hi ;
    local ymax = r(max) ;
    local range = `ymax' - `ymin' ;
    local step = cond(`range' > 30, 10, cond(`range' > 15, 5, cond(`range' > 6, 2, 1))) ;
    local ylo = `step' * floor(`ymin' / `step') ;
    local yhi = `step' * ceil(`ymax' / `step') ;
    mylabels `ylo'(`step')`yhi', myscale(@) suffix(%) format(%4.0f) local(ylab) ;
    local col "`c`j''" ;
    twoway
        (rcap lo hi x if s == 1, lcolor("`col'") lwidth(medthin))
        (scatter b x if s == 1 & v != 10, mcolor("`col'") msymbol(circle) msize(medium))
        (rcap lo hi x if s == 2, lcolor(`cnov') lwidth(medthin))
        (scatter b x if s == 2 & v != 10, mcolor(`cnov') msymbol(circle) msize(medium))
        (scatter b v if s == 1 & v == 10, mcolor(gs6) mfcolor(white) msymbol(circle) msize(medium)),
        yline(0, lcolor(gs6) lwidth(thin))
        xlabel(`xl', angle(45) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        ylabel(`ylab', angle(horizontal) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        yscale(range(`ylo' `yhi'))
        xtitle("Percentile", size(medium))
        ytitle("Change in Renewal Rate", size(medium))
        legend(order(2 "`g`j''" 4 "Novelty") ring(0) position(1) cols(1) size(medsmall) region(lcolor(none)))
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_4_`t' ;
    graph close ;
    restore ;
} ;

/* =============================================================================
   APPENDIX FIGURES F1 AND F2: four measures of novelty, the headline first
   1 frac_new_phrase_oth   share of the cycle's noun phrases that are new (Arts,
                           Melluso and Veugelers) and used again by a later
                           paper sharing no author with them, the headline
                           measure of code/programs/_spec.do (local nov), as
                           in Figure 4
   2 agepair_cyclefrac     share of the cycle's MeSH-pair instances at most 3
                           years old (code/build/13_novelty_mesh.py)
   3 semdist_mean          semantic distance: mean over the cycle's papers of
                           one minus the highest SPECTER cosine similarity to a
                           paper of the previous five years
   4 frac_new_phrase_comb  new noun-phrase combinations as a share of the
                           possible pairs of the papers' noun phrases (Arts,
                           Melluso and Veugelers count them; the share removes
                           the length of the abstract)
   ============================================================================= */

local nv1 "`nov'" ;                local ng1 "Share of New Noun Phrases" ;              local nt1 "phrfrac" ;
local nv2 "agepair_cyclefrac" ;    local ng2 "Share of New MeSH Pairs" ;               local nt2 "pairfrac" ;
local nv3 "semdist_mean" ;         local ng3 "Semantic Distance" ;                      local nt3 "semdist" ;
local nv4 "frac_new_phrase_comb" ; local ng4 "Share of New Noun-Phrase Combinations" ; local nt4 "pcombfrac" ;
assert "`nov'" == "frac_new_phrase_oth" ;

/* Appendix Figure F1: histograms by renewal status, cycles with an
   acknowledging paper, 20 bins of equal width between the minimum and the
   99th percentile (the top percentile, a long tail of short abstracts for
   the shares, is not shown) */
forvalues n = 1/4 {;
    preserve ;
    keep if n_ackn >= 1 & !missing(`nv`n'') ;
    quietly summarize `nv`n'', detail ;
    local lo = r(min) ;
    local hi = r(p99) ;
    keep if `nv`n'' <= `hi' ;
    local w = (`hi' - `lo') / 20 ;
    gen byte bin = min(floor((`nv`n'' - `lo') / `w'), 19) ;
    gen byte one = 1 ;
    gcollapse (sum) nn = one, by(bin renewed) ;
    /* each bar is the share of its group's cycles */
    gegen double tot = total(nn), by(renewed) ;
    gen double pct = 100 * nn / tot ;
    gen double x = `lo' + (bin + 0.5) * `w' + cond(renewed == 1, 0.2, -0.2) * `w' ;
    quietly summarize pct ;
    nr_pctlab `=r(max)' ;
    local ylabp `"`r(lab)'"' ;
    local ptop = r(top) ;
    twoway
        (bar pct x if renewed == 0, barwidth(`=0.4*`w'') color(`cnov'%35) lwidth(none))
        (bar pct x if renewed == 1, barwidth(`=0.4*`w'') color(`cnov') lwidth(none)),
        xlabel(, labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        ylabel(`ylabp', angle(horizontal) labsize(medsmall) tlength(.75)
               grid glwidth(vvthin) glcolor(gs13))
        yscale(range(0 `ptop'))
        xtitle("`ng`n''", size(medium))
        ytitle("Share of Grant Cycles", size(medium))
        legend(order(1 "Not renewed" 2 "Renewed") ring(0) position(1) cols(1)
               size(medsmall) region(lcolor(none)))
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_F1_`nt`n'' ;
    graph close ;
    restore ;
} ;

/* Appendix Figure F2: renewal on the 20 ventiles of each measure (within
   evaluation year, tenth omitted), grant output controls; ventiles with
   fewer than 100 cycles are not plotted; one y-scale for the four panels; in
   percent of the mean renewal rate */
tempname pf ;
tempfile coefs ;
postfile `pf' byte(n v) double(b lo hi) long nobs using `coefs', replace ;
forvalues n = 1/4 {;
    capture drop nv ;
    gquantiles nv = `nv`n'' if !missing(`nv`n''), xtile nquantiles(20) by(`pctby') ;
    display as text "ventiles of `nv`n'':" ;
    tab nv ;
    quietly reghdfe `dv' ib10.nv `x3', absorb(`fe3') vce(cluster `clus') ;
    capture drop esmp ;
    gen byte esmp = e(sample) ;
    quietly summarize `dv' if esmp ;
    local mdv = r(mean) ;
    forvalues q = 1/20 {;
        quietly count if esmp & nv == `q' ;
        local cnt = r(N) ;
        if `q' == 10 post `pf' (`n') (`q') (0) (0) (0) (`cnt') ;
        else {;
            capture local b = 100 * _b[`q'.nv] / `mdv' ;
            if _rc | `cnt' < 100 post `pf' (`n') (`q') (.) (.) (.) (`cnt') ;
            else {;
                local s = 100 * _se[`q'.nv] / `mdv' ;
                post `pf' (`n') (`q') (`b') (`b' - 1.96*`s') (`b' + 1.96*`s') (`cnt') ;
            } ;
        } ;
    } ;
} ;
postclose `pf' ;
preserve ;
use `coefs', clear ;
save "graphs/data/figure_F2_coefs.dta", replace ;
list, sepby(n) noobs ;
quietly summarize lo ;
local ymin = r(min) ;
quietly summarize hi ;
local ymax = r(max) ;
local range = `ymax' - `ymin' ;
local step = cond(`range' > 30, 10, cond(`range' > 15, 5, cond(`range' > 6, 2, 1))) ;
local ylo = `step' * floor(`ymin' / `step') ;
local yhi = `step' * ceil(`ymax' / `step') ;
mylabels `ylo'(`step')`yhi', myscale(@) suffix(%) format(%4.0f) local(ylab) ;
forvalues n = 1/4 {;
    twoway
        (rcap lo hi v if n == `n', lcolor(`cnov') lwidth(medthin))
        (scatter b v if n == `n' & v != 10, mcolor(`cnov') msymbol(circle) msize(medium))
        (scatter b v if n == `n' & v == 10, mcolor(`cnov') mfcolor(white) msymbol(circle) msize(medium)),
        yline(0, lcolor(gs6) lwidth(thin))
        xlabel(`xl', angle(45) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        ylabel(`ylab', angle(horizontal) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        yscale(range(`ylo' `yhi'))
        xtitle("Percentile of `ng`n''", size(medium))
        ytitle("Change in Renewal Rate", size(medium))
        legend(off)
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_F2_`nt`n'' ;
    graph close ;
} ;
restore ;

capture erase "scheme-deadzone.scheme" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
