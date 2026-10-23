/* =============================================================================
   code/analysis/24_table_B2.do

   Purpose: Appendix Table B2, the lower half-spread of the extreme tail
            outcomes measure (median minus min of the citation percentiles
            of the cycle's acknowledging papers) split into its part between
            projects and its part within the weakest paper's project, with
            the median, the upper half-spread and indicators for the number
            of projects (2, 3, 4, 5-6, 7+). Projects as built by
            code/build/27_tail_projects.do: MeSH similarity at 0.3 and same
            first author in the table; at 0.5 and 0.7 in the log.
            Cycles with at least three acknowledging papers with a citation
            percentile and a mean impact factor, and at least two projects.
            Grant output controls of Table 2. Units of 10 percentile points.
            The file also gives numbers that Appendix B quotes:
            - in the log, the regression of renewal on the median and both
              half-spreads, computed on all papers, on all cycles with at
              least three papers with a percentile (Table B1's notes), with
              each half-spread alone on the same cycles;
            - the projects under each definition, on those cycles (shares of
              cycles with one, two, three or more projects, papers per
              project, single-paper projects, weakest paper in a multi-paper
              project), written to estimates/appendix_B_projects.tex and
              printed in the log;
            - in the log, the mean of the between and within parts.

   Input:
     - ${public}/nih_risk_public.dta           (code/build/34_public_file.do)
       with the variables of risk_tail_projects.dta (code/build/27_tail_projects.do)
   Output:
     - output/tables/table_B2.tex             Table B2, written row by row
     - estimates/table_B2_<def>.ster, estimates/table_B2_unsplit_<def>.ster
       (<def>: m3, m5, m7 for MeSH similarity at 0.3, 0.5, 0.7; fa, same
       first author)
     - estimates/appendix_B_projects.tex      the projects, for Appendix B's text
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

log using "logs/24_table_B2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;

/* units of 10 percentile points */
foreach v of varlist tl_med tl_up tl_lo tl_lo_btw_* tl_lo_wth_* {;
    replace `v' = `v' * 10 ;
} ;
label variable tl_med "Median citation percentile" ;
label variable tl_up  "Max \(-\) median" ;
label variable tl_lo  "Median \(-\) min" ;

/* -------------------------------------------------------------------------
   Level and half-spreads on all papers, all cycles with at least three
   papers with a percentile, in the log only: Table B1's notes quote the
   regression with the median and both half-spreads. That regression fixes
   the sample, s1, from which Table B2's cycles are drawn.
   ------------------------------------------------------------------------- */
reghdfe `dv' tl_med tl_up tl_lo `x3' if !missing(tl_med), absorb(`fe3') vce(cluster `clus') ;
gen byte s1 = e(sample) ;
nr_post ;
test tl_up = tl_lo ;
local p13 = r(p) ;
foreach v in tl_med tl_up tl_lo {;
    local b3_`v' = _b[`v'] ;
    local s3_`v' = _se[`v'] ;
} ;
local N1 = e(N) ;
local ni1 = e(ninv) ;
local md1 = e(meandv) ;
reghdfe `dv' tl_up `x3' if s1, absorb(`fe3') vce(cluster `clus') ;
local b1_tl_up = _b[tl_up] ;
local s1_tl_up = _se[tl_up] ;
reghdfe `dv' tl_lo `x3' if s1, absorb(`fe3') vce(cluster `clus') ;
local b2_tl_lo = _b[tl_lo] ;
local s2_tl_lo = _se[tl_lo] ;
correlate tl_med tl_up tl_lo if s1 ;

tempname fh ;

/* -------------------------------------------------------------------------
   The projects, on the cycles of s1 (Appendix B's text quotes these numbers)
   ------------------------------------------------------------------------- */
/* column heads name how projects are defined, not the investigator's position */
local dl_m3 "Similar MeSH (\(\tau = 0.3\))" ;
local dl_m5 "Similar MeSH (\(\tau = 0.5\))" ;
local dl_m7 "Similar MeSH (\(\tau = 0.7\))" ;
local dl_fa "Same First Author" ;
foreach t in m3 m5 m7 fa {;
    quietly count if s1 ;
    local nc = r(N) ;
    quietly count if s1 & nproj_`t' == 1 ;
    local a1_`t' = r(N) / `nc' ;
    quietly count if s1 & nproj_`t' == 2 ;
    local a2_`t' = r(N) / `nc' ;
    quietly count if s1 & nproj_`t' >= 3 ;
    local a3_`t' = r(N) / `nc' ;
    quietly summarize n_tails if s1 ;
    local tp = r(sum) ;
    quietly summarize nproj_`t' if s1 ;
    local tj = r(sum) ;
    local a4_`t' = `tp' / `tj' ;
    gen double nsing_`t' = single_`t' * nproj_`t' ;
    quietly summarize nsing_`t' if s1 ;
    local a5_`t' = r(sum) / `tj' ;
    quietly summarize multi_`t' if s1 ;
    local a6_`t' = r(mean) ;
    quietly count if s1 & nproj_`t' >= 2 ;
    local a7_`t' = r(N) ;
} ;
file open `fh' using "estimates/appendix_B_projects.tex", write replace text ;
file write `fh' " & `dl_m3' & `dl_m5' & `dl_m7' & `dl_fa' \\" _n "\midrule" _n ;
local rl1 "Share of cycles with one project" ;
local rl2 "Share of cycles with two projects" ;
local rl3 "Share of cycles with three or more projects" ;
local rl4 "Mean number of papers per project" ;
local rl5 "Share of projects with a single paper" ;
local rl6 "Share of cycles whose weakest paper is in a multi-paper project" ;
local rl7 "Nb. of cycles with two projects or more" ;
forvalues r = 1/7 {;
    local row "`rl`r''" ;
    foreach t in m3 m5 m7 fa {;
        if `r' == 7 local v = strtrim(string(`a`r'_`t'', "%9.0fc")) ;
        else if `r' == 4 local v = strtrim(string(`a`r'_`t'', "%5.2f")) ;
        else local v = strtrim(string(`a`r'_`t'', "%5.3f")) ;
        local row "`row' & `v'" ;
    } ;
    file write `fh' "`row' \\" _n ;
} ;
file close `fh' ;
type "estimates/appendix_B_projects.tex" ;

/* -------------------------------------------------------------------------
   Table B2: between and within projects
   ------------------------------------------------------------------------- */
foreach t in m5 fa m3 m7 {;
    capture drop bp smp3 ;
    gen byte bp = cond(nproj_`t' <= 4, nproj_`t', cond(nproj_`t' <= 6, 5, 7)) ;
    reghdfe `dv' tl_med tl_up tl_lo_btw_`t' tl_lo_wth_`t' `x3' if s1 & nproj_`t' >= 2, absorb(`fe3' bp) vce(cluster `clus') ;
    gen byte smp3 = e(sample) ;
    nr_post ;
    estimates save "estimates/table_B2_`t'", replace ;
    local m_`t' = _b[tl_med] ;   local sm_`t' = _se[tl_med] ;
    local u_`t' = _b[tl_up] ;    local su_`t' = _se[tl_up] ;
    local bw_`t' = _b[tl_lo_btw_`t'] ; local sbw_`t' = _se[tl_lo_btw_`t'] ;
    local wt_`t' = _b[tl_lo_wth_`t'] ; local swt_`t' = _se[tl_lo_wth_`t'] ;
    test tl_lo_btw_`t' = tl_lo_wth_`t' ;
    local pv_`t' = r(p) ;
    local N3_`t' = e(N) ;
    local ni3_`t' = e(ninv) ;
    local md3_`t' = e(meandv) ;
    reghdfe `dv' tl_med tl_up tl_lo `x3' if smp3, absorb(`fe3' bp) vce(cluster `clus') ;
    estimates save "estimates/table_B2_unsplit_`t'", replace ;
    local lo_`t' = _b[tl_lo] ;   local slo_`t' = _se[tl_lo] ;
    display as result "`t': between " %7.4f `bw_`t'' " (" %6.4f `sbw_`t'' "), within " %7.4f `wt_`t'' " (" %6.4f `swt_`t'' "), p = " %5.3f `pv_`t'' "; unsplit " %7.4f `lo_`t'' " (" %6.4f `slo_`t'' "); N " %7.0fc `N3_`t'' ;
    quietly summarize tl_lo_btw_`t' if smp3 ;
    display as result "     between part: mean " %6.3f r(mean) ", sd " %6.3f r(sd) ;
    quietly summarize tl_lo_wth_`t' if smp3 ;
    display as result "     within part:  mean " %6.3f r(mean) ", sd " %6.3f r(sd) ;
} ;

file open `fh' using "output/tables/table_B2.tex", write replace text ;
file write `fh' " & (1) & (2) \\" _n " & `dl_m3' & `dl_fa' \\" _n "\midrule" _n ;
local nm1 "Median Citation Percentile" ;            local k1 "m" ;
local nm2 "Max \(-\) Median" ;                       local k2 "u" ;
local nm3 "Median \(-\) Min, Between Projects" ;    local k3 "bw" ;
local nm4 "Median \(-\) Min, Within Projects" ;     local k4 "wt" ;
forvalues r = 1/4 {;
    local r1 "`nm`r''" ;
    local r2 "" ;
    foreach t in m3 fa {;
        local bb = ``k`r''_`t'' ;
        local ss = `s`k`r''_`t'' ;
        nr_star `bb' `ss' ;
        local vb = strtrim(string(`bb', "%7.4f")) ;
        local vs = strtrim(string(`ss', "%6.4f")) ;
        local r1 "`r1' & `vb'`r(star)'" ;
        local r2 "`r2' & (`vs')" ;
    } ;
    file write `fh' "`r1' \\" _n "`r2' \\" _n ;
} ;
local r1 "\(H_{0}\): between = within" ;
local r2 "Median \(-\) Min, Unsplit (Same Cycles)" ;
local r3 "" ;
local r4 "Mean of dependent variable" ;
local r5 "Nb. of investigators" ;
local r6 "Nb. of grant cycles" ;
foreach t in m3 fa {;
    local vp = strtrim(string(`pv_`t'', "%5.3f")) ;
    nr_star `lo_`t'' `slo_`t'' ;
    local vl = strtrim(string(`lo_`t'', "%7.4f")) ;
    local vsl = strtrim(string(`slo_`t'', "%6.4f")) ;
    local vm = strtrim(string(`md3_`t'', "%5.3f")) ;
    local vi = strtrim(string(`ni3_`t'', "%9.0fc")) ;
    local vn = strtrim(string(`N3_`t'', "%9.0fc")) ;
    local r1 "`r1' & \(p = `vp'\)" ;
    local r2 "`r2' & `vl'`r(star)'" ;
    local r3 "`r3' & (`vsl')" ;
    local r4 "`r4' & `vm'" ;
    local r5 "`r5' & `vi'" ;
    local r6 "`r6' & `vn'" ;
} ;
file write `fh' "`r1' \\" _n "\midrule" _n "`r2' \\" _n "`r3' \\" _n "\midrule" _n "`r4' \\" _n "`r5' \\" _n "`r6' \\" _n ;
file close `fh' ;
type "output/tables/table_B2.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
