/* =============================================================================
   code/analysis/37_figures_J1_J2_table_J1.do

   Purpose: Appendix J, risk taking and interdisciplinary teams. The distance
            of the team (code/build/28_team_distance.do) and the penalty, with
            the grant output controls of Table 2, column 3, indicators for the
            number of the investigator's outside papers with MeSH in every
            regression, and standard errors clustered by investigator and by
            grant.
            - Appendix Table J1, landscape, twelve columns: for each measure,
              on the same cycles, (1) the measure alone, (2) the measure and
              the distant-team indicator (team distance above the median of
              the study section's cycles, the overall median for study
              sections with fewer than 20, the rule for breadth in Appendix
              Table I1), and (3) the measure, the indicator and their
              interaction, the measure centered at its mean in the
              interaction. The indicator alone and the uncentered version
              are in the log.
            - Appendix Figure J2: the design of Figure 4, team distance in
              novelty's place: each measure's ventiles and team distance's
              in one regression, one panel per measure.
            - Appendix Figure J1: team distance by renewal status, the design
              of Appendix Figure F1.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of cycle_collabteam.dta (code/build/28_team_distance.do)
   Output:
     - output/tables/table_J1.tex             (rows only, written row by row)
     - output/figures/figure_J2_<tag>.pdf     (one file per measure)
     - output/figures/figure_J1.pdf
     - estimates/table_J1_*.ster, estimates/figure_J2_<tag>.ster,
       graphs/data/figure_J2_<tag>_coefs.dta

   Note: a first argument of 0 redraws the table and the figures from the
         saved estimates, without re-estimating.
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

log using "logs/37_figures_J1_J2_table_J1.log", replace text name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate and save, 0 = reuse the saved estimates. A first argument
   overrides it (do code/analysis/37_figures_J1_J2_table_J1.do 0), to redraw
   the table and the figures without re-estimating */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

/* -----------------------------------------------------------------------------
   1. Data
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

/* the four measures, scaled as in Appendix Table I1
   (code/analysis/15_figure_5_table_I1.do): tails and disruption in units of
   10 percentile points */
forvalues j = 1/`nmeas' {;
    gen double rm_`t`j'' = `m`j'' * cond(`j' <= 2, 10, 1) ;
    label variable rm_`t`j'' "`l`j''" ;
} ;

/* bins of the investigator's outside papers with MeSH (the bins of breadth
   in Appendix Table I1, from the floor of 3) */
gen byte nbo = cond(n_fout_mesh <= 10, n_fout_mesh, cond(n_fout_mesh <= 15, 11,
    cond(n_fout_mesh <= 20, 12, cond(n_fout_mesh <= 30, 13, cond(n_fout_mesh <= 50, 14, 15)))))
    if !missing(team_dist) ;
tab nbo ;

/* the distant team: above the median of the study section's cycles with the
   measure, the overall median for study sections with fewer than 20 such
   cycles */
quietly summarize team_dist, detail ;
local tmall = r(p50) ;
gegen double tmed_irg = median(team_dist), by(irg_code) ;
gegen long tn_irg = count(team_dist), by(irg_code) ;
gen byte distant = team_dist > cond(tn_irg >= 20 & irg_code != "", tmed_irg, `tmall') if !missing(team_dist) ;
label variable distant "Distant team" ;
quietly count if !missing(team_dist) & (tn_irg < 20 | irg_code == "") ;
display as result "=== distant team: overall median " %6.4f `tmall' ", cycles given the overall median: " r(N) ;
tab distant ;

/* -----------------------------------------------------------------------------
   2. Appendix Table J1: the penalty and the distance of the team
   ----------------------------------------------------------------------------- */
/* the layout of Appendix Table K1: for each measure, on the same cycles,
   (1) the measure alone, (2) the measure and the distant-team indicator, and
   (3) the measure, the indicator and their interaction, with the measure
   centered at its mean on these cycles in the interaction, so that the
   indicator's coefficient is the gap between distant and close teams at the
   measure's mean. The measure's coefficient (the slope for close teams) and
   the interaction do not depend on the centering. Log only: the uncentered
   version, whose indicator is the gap at a measure of zero, and the
   indicator alone on the same cycles. */
if `run_regs' {;
    forvalues j = 1/`nmeas' {;
        local t "`t`j''" ;
        capture drop ix_`t' ixc_`t' smp ;
        gen double ix_`t' = rm_`t' * distant ;
        reghdfe `dv' rm_`t' distant ix_`t' `x3' if !missing(distant), absorb(`fe3' nbo) vce(cluster `clus') ;
        gen byte smp = e(sample) ;
        nr_post ;
        estimates save "estimates/table_J1_u_`t'.ster", replace ;
        quietly summarize rm_`t' if smp ;
        local mrm = r(mean) ;
        local sdrm = r(sd) ;
        quietly summarize distant if smp ;
        local shd = r(mean) ;
        gen double ixc_`t' = (rm_`t' - `mrm') * distant ;
        reghdfe `dv' rm_`t' distant ixc_`t' `x3' if smp, absorb(`fe3' nbo) vce(cluster `clus') ;
        nr_post ;
        estadd scalar shgrp = `shd' ;
        estadd scalar sdm = `sdrm' ;
        estimates save "estimates/table_J1_`t'.ster", replace ;
        reghdfe `dv' rm_`t' `x3' if smp, absorb(`fe3' nbo) vce(cluster `clus') ;
        nr_post ;
        estadd scalar shgrp = `shd' ;
        estadd scalar sdm = `sdrm' ;
        estimates save "estimates/table_J1_a_`t'.ster", replace ;
        reghdfe `dv' rm_`t' distant `x3' if smp, absorb(`fe3' nbo) vce(cluster `clus') ;
        nr_post ;
        estadd scalar shgrp = `shd' ;
        estadd scalar sdm = `sdrm' ;
        estimates save "estimates/table_J1_b_`t'.ster", replace ;
        reghdfe `dv' distant `x3' if smp, absorb(`fe3' nbo) vce(cluster `clus') ;
        nr_post ;
        estimates save "estimates/table_J1_d_`t'.ster", replace ;
        drop smp ;
    } ;
} ;

display as result _newline "=== Table J1: the measure alone, then the slope for close teams, the interaction, the gap at the measure's mean, the slope for distant teams" ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    estimates use "estimates/table_J1_a_`t'.ster" ;
    estimates store t2a_`t' ;
    display as text "`t': the measure alone " %7.4f _b[rm_`t'] " (" %6.4f _se[rm_`t'] "), one s.d. " %7.4f _b[rm_`t'] * e(sdm) ", N " %9.0fc e(N) ;
    estimates use "estimates/table_J1_b_`t'.ster" ;
    estimates store t2b_`t' ;
    display as text "`t': with the distant team, no interaction: measure " %7.4f _b[rm_`t'] " (" %6.4f _se[rm_`t'] "), distant team " %7.4f _b[distant] " (" %6.4f _se[distant] ")" ;
    estimates use "estimates/table_J1_d_`t'.ster" ;
    display as text "`t': distant team alone " %7.4f _b[distant] " (" %6.4f _se[distant] ")" ;
    estimates use "estimates/table_J1_u_`t'.ster" ;
    display as text "`t': uncentered, distant team indicator " %7.4f _b[distant] " (" %6.4f _se[distant] ")" ;
    estimates use "estimates/table_J1_`t'.ster" ;
    estimates store t2_`t' ;
    display as text "`t': close " %7.4f _b[rm_`t'] " (" %6.4f _se[rm_`t'] "), interaction "
        %7.4f _b[ixc_`t'] " (" %6.4f _se[ixc_`t'] "), distant team at the mean " %7.4f _b[distant] " (" %6.4f _se[distant] "), N " %9.0fc e(N) ;
    lincom rm_`t' + ixc_`t' ;
    display as text "`t': penalty for distant teams " %7.4f r(estimate) " (" %6.4f r(se) "), as a share of the close teams' "
        %5.2f r(estimate) / _b[rm_`t'] ;
} ;

/* -----------------------------------------------------------------------------
   3. The table, written row by row
   ----------------------------------------------------------------------------- */
/* Table J1: landscape, twelve columns. For each measure, on the same cycles,
   (1) the measure alone, (2) the measure and the distant-team indicator,
   (3) the measure, the indicator and their interaction, the measure centered
   in the interaction. Column 1 against column 2 shows whether holding the
   team fixed moves the measure, column 3 the penalty for close and distant
   teams. Under the measure and the interaction, in brackets, the coefficient
   times the measure's s.d. on these cycles. */
tempname fh ;
file open `fh' using "output/tables/table_J1.tex", write replace text ;
file write `fh' " & \multicolumn{3}{c}{`l1'} & & \multicolumn{3}{c}{`l2'} & & \multicolumn{3}{c}{`l3'} & & \multicolumn{3}{c}{`l4'} \\" _n ;
file write `fh' "\cmidrule(lr){2-4}\cmidrule(lr){6-8}\cmidrule(lr){10-12}\cmidrule(lr){14-16}" _n ;
file write `fh' " & (1) & (2) & (3) & & (4) & (5) & (6) & & (7) & (8) & (9) & & (10) & (11) & (12) \\" _n ;
file write `fh' "\midrule" _n ;
local Mrow "Risk measure" ; local Mse "" ; local Msd "" ;
local Grow "Distant team" ; local Gse "" ;
local Xrow "Risk measure \(\times\) distant team" ; local Xse "" ; local Xsd "" ;
local mrow "Mean of dependent variable" ;
local srow "Share of cycles with a distant team" ;
local irow "Nb.\ of investigators" ;
local nrow "Nb.\ of grant cycles" ;
local arow "Adjusted \(R^2\)" ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    if `j' > 1 {;
        foreach r in Mrow Mse Msd Grow Gse Xrow Xse Xsd mrow srow irow nrow arow {;
            local `r' "``r'' &" ;
        } ;
    } ;
    foreach m in t2a t2b t2 {;
        estimates restore `m'_`t' ;
        nr_star `=_b[rm_`t']' `=_se[rm_`t']' ;
        local Mrow "`Mrow' & `=strtrim(string(_b[rm_`t'], "%7.4f"))'`r(star)'" ;
        local Mse  "`Mse' & (`=strtrim(string(_se[rm_`t'], "%6.4f"))')" ;
        local Msd  "`Msd' & {\footnotesize [`=strtrim(string(_b[rm_`t'] * e(sdm), "%7.4f"))']}" ;
        if "`m'" == "t2a" {;
            local Grow "`Grow' & " ;
            local Gse  "`Gse' & " ;
        } ;
        else {;
            nr_star `=_b[distant]' `=_se[distant]' ;
            local Grow "`Grow' & `=strtrim(string(_b[distant], "%7.4f"))'`r(star)'" ;
            local Gse  "`Gse' & (`=strtrim(string(_se[distant], "%6.4f"))')" ;
        } ;
        if "`m'" != "t2" {;
            local Xrow "`Xrow' & " ;
            local Xse  "`Xse' & " ;
            local Xsd  "`Xsd' & " ;
        } ;
        else {;
            nr_star `=_b[ixc_`t']' `=_se[ixc_`t']' ;
            local Xrow "`Xrow' & `=strtrim(string(_b[ixc_`t'], "%7.4f"))'`r(star)'" ;
            local Xse  "`Xse' & (`=strtrim(string(_se[ixc_`t'], "%6.4f"))')" ;
            local Xsd  "`Xsd' & {\footnotesize [`=strtrim(string(_b[ixc_`t'] * e(sdm), "%7.4f"))']}" ;
        } ;
        local mrow "`mrow' & `=strtrim(string(e(meandv), "%5.3f"))'" ;
        local srow "`srow' & `=strtrim(string(e(shgrp), "%5.3f"))'" ;
        local irow "`irow' & `=strtrim(string(e(ninv), "%9.0fc"))'" ;
        local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
        local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
    } ;
} ;
file write `fh' "`Mrow' \\" _n "`Mse' \\" _n "`Msd' \\" _n "\addlinespace" _n ;
file write `fh' "`Grow' \\" _n "`Gse' \\" _n "\addlinespace" _n ;
file write `fh' "`Xrow' \\" _n "`Xse' \\" _n "`Xsd' \\" _n "\midrule" _n ;
file write `fh' "`mrow' \\" _n "`srow' \\" _n "`irow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
file close `fh' ;
type "output/tables/table_J1.tex" ;

/* -----------------------------------------------------------------------------
   4. Appendix Figure J2: each risk measure with team distance, the design of
      Figure 4 (code/analysis/14_figure_4_figures_F1_F2.do) with team distance
      in novelty's place. One regression per measure with 19 ventile
      indicators of the measure and 19 of team distance, both within
      evaluation year, the tenth omitted. Both sets of coefficients in one
      panel, the measure in its color and team distance in teal. A ventile
      with fewer than 100 cycles is not plotted, as in Figure 4.
   ----------------------------------------------------------------------------- */
graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;
local cteam "teal" ;
local xl "" ;
forvalues q = 1/20 {;
    local xl `"`xl' `q' "`=5*(`q'-1)'-`=5*`q''""' ;
} ;
gquantiles tvent = team_dist if !missing(team_dist), xtile nquantiles(20) by(`pctby') ;
tab tvent ;

forvalues j = 1/`nmeas' {;
    local m "`m`j''" ;
    local t "`t`j''" ;
    capture drop vent ;
    /* the measure's ventiles on every cycle where it is defined, as in Figure 4 */
    gquantiles vent = `m' if !missing(`m'), xtile nquantiles(20) by(`pctby') ;
    if `run_regs' {;
        reghdfe `dv' ib10.vent ib10.tvent `x3', absorb(`fe3' nbo) vce(cluster `clus') ;
        quietly summarize `dv' if e(sample) ;
        estadd scalar meandv = r(mean) ;
        matrix nobsv = J(20, 2, 0) ;
        forvalues q = 1/20 {;
            quietly count if e(sample) & vent == `q' ;
            matrix nobsv[`q', 1] = r(N) ;
            quietly count if e(sample) & tvent == `q' ;
            matrix nobsv[`q', 2] = r(N) ;
        } ;
        estadd matrix nobsv = nobsv ;
        estimates save "estimates/figure_J2_`t'.ster", replace ;
    } ;

    tempname pf ;
    tempfile coefs ;
    postfile `pf' byte(s v) double(b lo hi) long nobs using `coefs', replace ;
    estimates use "estimates/figure_J2_`t'.ster" ;
    display as result "=== Figure J2, `t': cycles " %9.0fc e(N) ;
    matrix nobsv = e(nobsv) ;
    forvalues q = 1/20 {;
        forvalues s = 1/2 {;
            local fv = cond(`s' == 1, "vent", "tvent") ;
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
    label define figj2s 1 "risk measure" 2 "team distance", replace ;
    label values s figj2s ;
    save "graphs/data/figure_J2_`t'_coefs.dta", replace ;
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
        (rcap lo hi x if s == 2, lcolor(`cteam') lwidth(medthin))
        (scatter b x if s == 2 & v != 10, mcolor(`cteam') msymbol(circle) msize(medium))
        (scatter b v if s == 1 & v == 10, mcolor(gs6) mfcolor(white) msymbol(circle) msize(medium)),
        yline(0, lcolor(gs6) lwidth(thin))
        xlabel(`xl', angle(45) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        ylabel(`ylab', angle(horizontal) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        yscale(range(`ylo' `yhi'))
        xtitle("Percentile", size(medium))
        ytitle("Change in Renewal Rate", size(medium))
        legend(order(2 "`g`j''" 4 "Team Distance") ring(0) position(1) cols(1) size(medsmall) region(lcolor(none)))
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_J2_`t' ;
    graph close ;
    restore ;
} ;

/* -----------------------------------------------------------------------------
   5. Appendix Figure J1: team distance by renewal status, the design of
      Appendix Figure F1 (code/analysis/14_figure_4_figures_F1_F2.do): cycles
      with the measure, 20 bins of equal width, renewed and not renewed side
      by side. Team distance is bounded by 1, so the bins run from its
      minimum to its maximum (Appendix Figure F1 stops at the 99th percentile
      to cut a long tail).
   ----------------------------------------------------------------------------- */
display as result _newline "=== Figure J1: team distance by renewal status" ;
tabstat team_dist if !missing(team_dist), by(`dv') stat(mean p25 p50 p75 sd n) ;
preserve ;
keep if !missing(team_dist) ;
quietly summarize team_dist ;
local lo = r(min) ;
local hi = r(max) ;
local w = (`hi' - `lo') / 20 ;
gen byte bin = min(floor((team_dist - `lo') / `w'), 19) ;
gen byte one = 1 ;
gcollapse (sum) nn = one, by(bin `dv') ;
/* each bar is the share of its group's cycles: with counts, the larger group
   of non-renewed cycles would look as if it had more mass */
gegen double tot = total(nn), by(`dv') ;
gen double pct = 100 * nn / tot ;
gen double x = `lo' + (bin + 0.5) * `w' + cond(`dv' == 1, 0.2, -0.2) * `w' ;
list, sepby(`dv') noobs ;
/* the y axis in steps of 2.5%, 0% to 20% here, from nr_pctlab
   (code/programs/_programs.do) */
quietly summarize pct ;
nr_pctlab `=r(max)' ;
local ylabp `"`r(lab)'"' ;
local phi = r(top) ;
twoway
    (bar pct x if `dv' == 0, barwidth(`=0.4*`w'') color(`cteam'%35) lwidth(none))
    (bar pct x if `dv' == 1, barwidth(`=0.4*`w'') color(`cteam') lwidth(none)),
    xlabel(, labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
    ylabel(`ylabp', angle(horizontal) labsize(medsmall) tlength(.75)
           grid glwidth(vvthin) glcolor(gs13))
    yscale(range(0 `phi'))
    xtitle("Team Distance", size(medium))
    ytitle("Share of Grant Cycles", size(medium))
    legend(order(1 "Not renewed" 2 "Renewed") ring(0) position(11) cols(1)
           size(medsmall) region(lcolor(none)))
    graphregion(color(white) margin(small)) plotregion(margin(small)) ;
nr_gexport figure_J1 ;
graph close ;
restore ;

capture erase "scheme-deadzone.scheme" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;

/* End of code/analysis/37_figures_J1_J2_table_J1.do */
