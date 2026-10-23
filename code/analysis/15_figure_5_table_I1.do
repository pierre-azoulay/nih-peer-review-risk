/* =============================================================================
   code/analysis/15_figure_5_table_I1.do

   Purpose: the penalty by traits of the investigator. Each regression has one
            risk measure as a continuous regressor (tails and disruption in
            units of 10 percentile points, pivoting and standing out in
            fractions), a trait M of the investigator and their interaction,
            with the grant output controls of Table 2, on the cycles where M
            is defined. Six traits, each fixed when the cycle starts: women
            (female); an MD alone, against PhDs, MD-PhDs and other degrees
            (deg_cat == 1); new investigators (new_inv); elite investigators
            (NAS or IOM member, or HHMI investigator, the year before the
            cycle: code/build/19_investigator_flags.do); breadth of earlier
            research (fox: breadth_pre above its study section's median, with
            bins of n_pre absorbed; code/build/22_breadth.do); another
            R01-equivalent grant held in the cycle's first year
            (multi_r01_start, code/build/21_concurrent_grants.do). The main
            effects of gender and degree are absorbed by the fixed effects of
            Table 2.
              Appendix Table I1: one panel per trait, one column per measure.
              Figure 5: the measure's coefficient when M = 0 and its sum with
                        the interaction when M = 1, for the six traits, one
                        panel per measure.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/tables/table_I1.tex   written row by row (rows only: the paper
                                    supplies the tabular, caption and notes)
     - output/figures/figure_5_<t>.pdf, <t> = tails disr pivot so
     - graphs/gph, graphs/svg: the same graphs
     - graphs/data/figure_5_coefs.dta: the plotted coefficients
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

log using "logs/15_figure_5_table_I1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;

use "`afile'", clear ;

/* the measures: tails and disruption in units of 10 percentile points,
   pivoting and standing out in fractions */
forvalues j = 1/`nmeas' {;
    gen double rm_`t`j'' = `m`j'' * cond(`j' <= 2, 10, 1) ;
    label variable rm_`t`j'' "`l`j''" ;
} ;

/* the investigator's traits (Appendix Table I1, Figure 5). An MD alone,
   against PhDs, MD-PhDs and other degrees (deg_cat: 1 MD, 2 PhD, 3 MD-PhD,
   4 other). Breadth: fox = breadth_pre above the median of its study
   section (irg_code), computed on every analysis cycle with breadth, the
   overall median for study sections with fewer than 20 such cycles; bins of
   n_pre (5 to 10 one by one, 11-15, 16-20, 21-30, 31-50, more than 50) enter
   the breadth regressions, since the number of papers behind the index
   varies with the investigator's record */
gen byte md = deg_cat == 1 if !missing(deg_cat) ;
quietly summarize breadth_pre, detail ;
local bmall = r(p50) ;
gegen double bmed_irg = median(breadth_pre), by(irg_code) ;
gegen long bn_irg = count(breadth_pre), by(irg_code) ;
gen byte fox = breadth_pre > cond(bn_irg >= 20 & irg_code != "", bmed_irg, `bmall') if !missing(breadth_pre) ;
quietly count if !missing(breadth_pre) & (bn_irg < 20 | irg_code == "") ;
display as result "=== fox: overall median " %6.4f `bmall' "; cycles given the overall median: " r(N) ;
drop bmed_irg bn_irg ;
gen byte nb = cond(n_pre <= 10, n_pre, cond(n_pre <= 15, 11, cond(n_pre <= 20, 12,
    cond(n_pre <= 30, 13, cond(n_pre <= 50, 14, 15))))) if !missing(breadth_pre) ;
tab nb ;

local mods "female md new_inv elite fox multi_r01_start" ;
tabstat `mods', stat(mean n) ;

/* every regression: one measure, the trait, their interaction, with the
   grant output controls; the trait is always named mod and the interaction
   ix_<t> */
tempname pf ;
tempfile f8 ;
postfile `pf' str5 meas str20 mod byte grp double(b lo hi) using `f8', replace ;

eststo clear ;
foreach mo of local mods {;
    capture drop mod ;
    gen byte mod = `mo' ;
    /* gender and degree are among the fixed effects of Table 2, which absorb
       their main effects; breadth takes the bins of n_pre */
    local mv "mod" ;
    if inlist("`mo'", "female", "md") local mv "" ;
    local xb "" ;
    if "`mo'" == "fox" local xb "nb" ;
    forvalues j = 1/`nmeas' {;
        local t "`t`j''" ;
        capture drop ix_`t' ;
        gen double ix_`t' = rm_`t' * mod ;
        reghdfe `dv' rm_`t' `mv' ix_`t' `x3' if !missing(mod), absorb(`fe3' `xb') vce(cluster `clus') ;
        nr_post ;
        quietly summarize mod if e(sample) ;
        estadd scalar shgrp = r(mean) ;
        eststo `mo'_`t' ;
        if inlist("`mo'", "female", "md", "new_inv", "elite", "fox", "multi_r01_start") {;
            post `pf' ("`t'") ("`mo'") (0) (_b[rm_`t']) (_b[rm_`t'] - 1.96*_se[rm_`t']) (_b[rm_`t'] + 1.96*_se[rm_`t']) ;
            lincom rm_`t' + ix_`t' ;
            post `pf' ("`t'") ("`mo'") (1) (r(estimate)) (r(estimate) - 1.96*r(se)) (r(estimate) + 1.96*r(se)) ;
        } ;
    } ;
} ;
postclose `pf' ;

/* Appendix Table I1: the six traits, one panel each, four columns (the
   measures), on one portrait page. Each panel: the trait (not for gender
   and degree, whose main effects the fixed effects absorb), the measure,
   their interaction, the share of the panel's cycles with the trait, the
   number of cycles and the adjusted R2. */
local trs "female md new_inv elite fox multi_r01_start" ;
local pan_female "Gender" ;                    local lab_female "Woman" ;              local lx_female "woman" ;
local pan_md "Degree" ;                        local lab_md "MD" ;                     local lx_md "MD" ;
local pan_new_inv "Career stage" ;             local lab_new_inv "New investigator" ;  local lx_new_inv "new investigator" ;
local pan_elite "Status" ;                     local lab_elite "Elite investigator" ;  local lx_elite "elite investigator" ;
local pan_fox "Breadth of earlier research" ;  local lab_fox "Broad earlier research" ; local lx_fox "broad earlier research" ;
local pan_multi_r01_start "Other funding" ;    local lab_multi_r01_start "Another R01 when the cycle starts" ; local lx_multi_r01_start "another R01" ;
local letters "A B C D E F" ;

tempname fh ;
file open `fh' using "output/tables/table_I1.tex", write replace text ;
/* the column heads in centered columns of equal width (p columns in the
   paper), the first on two lines */
file write `fh' " & (1) & (2) & (3) & (4) \\" _n ;
file write `fh' " & Extreme tail\newline outcomes & `l2' & `l3' & `l4' \\" _n ;
file write `fh' "\midrule" _n ;
local p 0 ;
foreach mo of local trs {;
    local ++p ;
    local L : word `p' of `letters' ;
    if `p' > 1 file write `fh' "\midrule" _n ;
    file write `fh' "\multicolumn{5}{l}{\textit{Panel `L'. `pan_`mo''}} \\" _n ;
    local Grow "`lab_`mo''" ;          local Gse "" ;
    local Rrow "Risk measure" ;        local Rse "" ;
    local Xrow "Risk measure \(\times\) `lx_`mo''" ; local Xse "" ;
    local srow "Share of cycles with the trait" ;
    local nrow "Nb. of grant cycles" ;
    local arow "Adjusted \(R^2\)" ;
    forvalues j = 1/`nmeas' {;
        local t "`t`j''" ;
        estimates restore `mo'_`t' ;
        if !inlist("`mo'", "female", "md") {;
            nr_star `=_b[mod]' `=_se[mod]' ;
            local Grow "`Grow' & `=strtrim(string(_b[mod], "%7.4f"))'`r(star)'" ;
            local Gse  "`Gse' & (`=strtrim(string(_se[mod], "%6.4f"))')" ;
        } ;
        nr_star `=_b[rm_`t']' `=_se[rm_`t']' ;
        local Rrow "`Rrow' & `=strtrim(string(_b[rm_`t'], "%7.4f"))'`r(star)'" ;
        local Rse  "`Rse' & (`=strtrim(string(_se[rm_`t'], "%6.4f"))')" ;
        nr_star `=_b[ix_`t']' `=_se[ix_`t']' ;
        local Xrow "`Xrow' & `=strtrim(string(_b[ix_`t'], "%7.4f"))'`r(star)'" ;
        local Xse  "`Xse' & (`=strtrim(string(_se[ix_`t'], "%6.4f"))')" ;
        local srow "`srow' & `=strtrim(string(e(shgrp), "%5.3f"))'" ;
        local nrow "`nrow' & `=strtrim(string(e(N), "%9.0fc"))'" ;
        local arow "`arow' & `=strtrim(string(e(r2_a), "%6.4f"))'" ;
        display as result "Table I1, `mo', `t': interaction " %7.4f _b[ix_`t'] " (" %6.4f _se[ix_`t'] "), measure " %7.4f _b[rm_`t'] "; N " %9.0fc e(N) ;
    } ;
    if !inlist("`mo'", "female", "md") file write `fh' "`Grow' \\" _n "`Gse' \\" _n ;
    file write `fh' "`Rrow' \\" _n "`Rse' \\" _n "`Xrow' \\" _n "`Xse' \\" _n ;
    file write `fh' "`srow' \\" _n "`nrow' \\" _n "`arow' \\" _n ;
} ;
file close `fh' ;
type "output/tables/table_I1.tex" ;

/* Figure 5 */
use `f8', clear ;
save "graphs/data/figure_5_coefs.dta", replace ;
gen byte mo = 1 if mod == "female" ;
replace mo = 2 if mod == "md" ;
replace mo = 3 if mod == "new_inv" ;
replace mo = 4 if mod == "elite" ;
replace mo = 5 if mod == "fox" ;
replace mo = 6 if mod == "multi_r01_start" ;
gen double y = (mo - 1) * 3 + grp + 1 ;
list meas mod grp b lo hi, sepby(meas) noobs ;
local yl `"1 "Men" 2 "Women" 4 "Other degrees" 5 "MD" 7 "Not a new investigator" 8 "New investigator" 10 "Not elite" 11 "Elite investigator" 13 "Narrower earlier research" 14 "Broader earlier research" 16 "No other R01" 17 "Another R01""' ;

forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    local col "`c`j''" ;
    local xt = cond(`j' <= 2, "Effect of 10 Percentile Points on Renewal", "Effect of a Unit Change on Renewal") ;
    twoway
        (rcap lo hi y if meas == "`t'", horizontal lcolor("`col'") lwidth(medthin))
        (scatter y b if meas == "`t'" & grp == 0, mcolor("`col'") mfcolor(white) msymbol(circle) msize(medium))
        (scatter y b if meas == "`t'" & grp == 1, mcolor("`col'") msymbol(circle) msize(medium)),
        xline(0, lcolor(gs6) lwidth(thin))
        ylabel(`yl', angle(horizontal) labsize(medsmall) noticks nogrid)
        yscale(reverse range(0.5 17.5))
        xlabel(, labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13) format(%5.3f))
        xtitle("`xt'", size(medium)) ytitle("")
        legend(off)
        graphregion(color(white) margin(l=2 r=6 t=2 b=2)) plotregion(margin(small)) ;
    /* a wider right margin: with margin(small), the rightmost tick label
       runs past the graph region and is clipped */
    nr_gexport figure_5_`t' ;
    graph close ;
} ;

capture erase "scheme-deadzone.scheme" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
