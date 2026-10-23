/* =============================================================================
   code/analysis/38_figures_K1_K2.do

   Purpose: Appendix K, risk taking and the structure of NIH: the penalty by
            NIH institute and over time. Each measure enters as a continuous
            regressor (tails and disruption in units of 10 percentile points,
            pivoting and standing out in fractions), with the grant output
            controls of Table 2, column 3.
              Appendix Figure K1: one regression with the measure interacted
                        with each of the 11 largest institutes (GM CA HL AI NS
                        DK HD EY MH AG AR), no common slope. Cycles of other
                        institutes dropped.
              Appendix Figure K2: the penalty year by year, in one regression
                        with a separate coefficient on the measure for each
                        evaluation year (new_eval_year, 1980 and 1981 pooled
                        with 1982, and 2020 to 2023, 181 cycles, pooled with
                        2019) and no common slope, the controls in common, as
                        Figure K1 does for institutes.
            Log only, for the text and the notes of Appendix K: the structure
            of NIH in the analysis sample (how institutes and study sections
            cross), the renewal rate by five-year block and by year, and the
            penalty by five-year block of evaluation year (1981-85 to
            2016-22), estimated as in Figure K2, in one regression.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - output/figures/figure_K1_<tag>.pdf, output/figures/figure_K2_<tag>.pdf
     - graphs/data/figure_K1_coefs.dta, graphs/data/figure_K2_coefs.dta
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

log using "logs/38_figures_K1_K2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;

use "`afile'", clear ;
replace ic = upper(ic) ;
tab ic, sort ;

/* log only: the structure of NIH in the analysis sample, for the text of
   Appendix K (counts that an earlier study reports for NIH as a whole,
   recomputed on our cycles). Institutes fund, study sections score, and a
   study section's cycles can be decided by several institutes. */
preserve ;
    keep if !missing(ic) & !missing(irg_code) & !missing(new_eval_year) ;
    display as text _newline "=== the structure of NIH: analysis cycles with an institute, a study section and an evaluation year" ;
    count ;
    /* over the whole sample */
    bysort irg_code ic: gen byte t_si = _n == 1 ;
    bysort irg_code: egen int n_ic_s = total(t_si) ;
    bysort ic: egen int n_s_ic = total(t_si) ;
    bysort irg_code: gen byte t_s = _n == 1 ;
    bysort ic: gen byte t_i = _n == 1 ;
    display as text "institutes, study sections, institute x study section cells:" ;
    count if t_i ;
    count if t_s ;
    count if t_si ;
    gen byte s2 = n_ic_s >= 2 ;
    display as text "share of study sections whose cycles were decided by 2 or more institutes, 1982-2022" ;
    summarize s2 if t_s ;
    display as text "institutes per study section, 1982-2022" ;
    summarize n_ic_s if t_s, detail ;
    display as text "study sections per institute, 1982-2022" ;
    summarize n_s_ic if t_i, detail ;
    /* within an evaluation year */
    bysort new_eval_year irg_code ic: gen byte u_si = _n == 1 ;
    bysort new_eval_year irg_code: egen int n_ic_sy = total(u_si) ;
    bysort new_eval_year ic: egen int n_s_iy = total(u_si) ;
    bysort new_eval_year irg_code: gen byte u_sy = _n == 1 ;
    bysort new_eval_year ic: gen byte u_iy = _n == 1 ;
    gen byte s2y = n_ic_sy >= 2 ;
    display as text "share of study section-years whose cycles were decided by 2 or more institutes" ;
    summarize s2y if u_sy ;
    display as text "share of cycles in such study section-years" ;
    summarize s2y ;
    display as text "study sections per institute-year" ;
    summarize n_s_iy if u_iy, detail ;
restore ;

forvalues j = 1/`nmeas' {;
    gen double rm_`t`j'' = `m`j'' * cond(`j' <= 2, 10, 1) ;
} ;

/* five-year blocks of evaluation year, for the log: the renewal rate and the
   penalty by block */
gen int period = 1981 + 5 * floor((eval_year - 1981) / 5) ;
replace period = 1981 if eval_year < 1981 ;
replace period = 2016 if eval_year >= 2016 ;
display as text "renewal rate by period:" ;
tabstat renewed if n_ackn >= 1, by(period) stat(mean n) ;

/* evaluation years for Figure K2: new_eval_year (the fixed effects' year,
   1980 and 1981 pooled with 1982), with 2020 to 2023 pooled with 2019 */
gen int yr = min(new_eval_year, 2019) if !missing(new_eval_year) ;
display as text "cycles and renewal rate by year of Figure K2, cycles with an acknowledging paper:" ;
tabstat renewed if n_ackn >= 1, by(yr) stat(mean n) ;

local ics "GM CA HL AI NS DK HD EY MH AG AR" ;

/* the coefficients of Figure K1 (fa1) and Figure K2 (fa2y) */
tempname pa py ;
tempfile fa1 fa2y ;
postfile `pa' str5 meas str2 ic double(b lo hi) using `fa1', replace ;
postfile `py' str5 meas int yr double(b lo hi rate) long nobs using `fa2y', replace ;

forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;

    /* Figure K1 */
    local ia "" ;
    foreach c of local ics {;
        capture drop ia_`c' ;
        gen double ia_`c' = rm_`t' * (ic == "`c'") if !missing(rm_`t') ;
        local ia "`ia' ia_`c'" ;
    } ;
    gen byte keepic = 0 ;
    foreach c of local ics {;
        replace keepic = 1 if ic == "`c'" ;
    } ;
    quietly reghdfe `dv' `ia' `x3' if keepic, absorb(`fe3') vce(cluster `clus') ;
    foreach c of local ics {;
        post `pa' ("`t'") ("`c'") (_b[ia_`c']) (_b[ia_`c'] - 1.96*_se[ia_`c']) (_b[ia_`c'] + 1.96*_se[ia_`c']) ;
    } ;
    drop keepic `ia' ;

    /* Figure K2: one regression, a coefficient on the measure for each
       evaluation year, no common slope, the controls in common */
    reghdfe `dv' ibn.yr#c.rm_`t' `x3', absorb(`fe3') vce(cluster `clus') ;
    tempvar es ;
    gen byte `es' = e(sample) ;
    levelsof yr if `es', local(yrs) ;
    foreach y of local yrs {;
        quietly summarize `dv' if `es' & yr == `y' ;
        post `py' ("`t'") (`y') (_b[`y'.yr#c.rm_`t']) (_b[`y'.yr#c.rm_`t'] - 1.96*_se[`y'.yr#c.rm_`t'])
            (_b[`y'.yr#c.rm_`t'] + 1.96*_se[`y'.yr#c.rm_`t']) (r(mean)) (r(N)) ;
    } ;
    drop `es' ;

    /* log only: the five-year blocks in one regression, as above (the
       penalty by block that the text of Appendix K quotes) */
    display as result _newline "`t': the five-year blocks in one regression (log only)" ;
    reghdfe `dv' ibn.period#c.rm_`t' `x3', absorb(`fe3') vce(cluster `clus') ;
} ;
postclose `pa' ;
postclose `py' ;

/* Figure K1: institutes sorted by their coefficient, within measure */
use `fa1', clear ;
save "graphs/data/figure_K1_coefs.dta", replace ;
list, sepby(meas) noobs ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    local col "`c`j''" ;
    preserve ;
    keep if meas == "`t'" ;
    sort b ic ;
    gen byte pos = _n ;
    gen double y = pos ;
    local yl "" ;
    levelsof pos, local(ps) ;
    foreach p of local ps {;
        levelsof ic if pos == `p', local(nm) clean ;
        local yl `"`yl' `p' "`nm'""' ;
    } ;
    local xt = cond(`j' <= 2, "Effect of 10 Percentile Points on Renewal", "Effect of a Unit Change on Renewal") ;
    twoway
        (rcap lo hi y, horizontal lcolor("`col'") lwidth(medthin))
        (scatter y b, mcolor("`col'") msymbol(circle) msize(medium)),
        xline(0, lcolor(gs6) lwidth(thin))
        ylabel(`yl', angle(horizontal) labsize(medsmall) noticks nogrid)
        xlabel(, labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13) format(%5.3f))
        xtitle("`xt'", size(medium)) ytitle("")
        legend(off)
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_K1_`t' ;
    graph close ;
    restore ;
} ;

/* Figure K2: year by year (2019 includes 2020 to 2023). The list gives the
   cycles and the renewal rate of each year's estimation sample, for the
   figure's note */
use `fa2y', clear ;
save "graphs/data/figure_K2_coefs.dta", replace ;
format b lo hi rate %7.4f ;
list, sepby(meas) noobs ;
forvalues j = 1/`nmeas' {;
    local t "`t`j''" ;
    local col "`c`j''" ;
    local yt = cond(`j' <= 2, "Effect of 10 Percentile Points on Renewal", "Effect of a Unit Change on Renewal") ;
    twoway
        (rcap lo hi yr if meas == "`t'", lcolor("`col'") lwidth(thin))
        (scatter b yr if meas == "`t'", mcolor("`col'") msymbol(circle) msize(small)),
        yline(0, lcolor(gs6) lwidth(thin))
        xlabel(1982 1985(5)2015 2019, labsize(medsmall) tlength(.75) angle(45))
        xscale(range(1981 2020))
        ylabel(, angle(horizontal) labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13) format(%5.3f))
        xtitle("Evaluation Year", size(medium)) ytitle("`yt'", size(medium))
        legend(off)
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_K2_`t' ;
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
