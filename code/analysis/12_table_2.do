/* =============================================================================
   code/analysis/12_table_2.do

   Purpose: Table 2, the association of risk taking and grant renewal: one
            table, twelve columns, the four risk measures side by side, each
            in three samples (all cycles, first cycles, later cycles). Renewal
            is regressed on indicators for the bottom and top deciles of the
            measure (computed within evaluation year; the middle eight deciles
            are omitted), with the grant output controls (fe3 and x3 of
            code/programs/_spec.do). A log-only check follows each measure:
            the measure standardized on the estimation sample, entered
            linearly.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - estimates/tex/table_2.tex   the esttab fragment
     - output/tables/table_2.tex   the same, formatted (nr_fmt; rows only: the
                                   paper supplies the tabular, caption and
                                   notes)
     - estimates/table_2_<t>_s<sample>_k3.ster, <t> = tails disr pivot so

   Note: a first argument of 0 (do code/analysis/12_table_2.do 0) reuses the
         saved estimates, to redraw the table without re-estimating.
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

log using "logs/12_table_2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* 1 = estimate and save; 0 = reuse the saved estimates (formatting only). A
   first argument overrides it */
local run_regs = 1 ;
if "`1'" != "" local run_regs = `1' ;

use "`afile'", clear ;

/* the three samples */
local s1 "1" ;
local s2 "cycle_nb == 1" ;
local s3 "cycle_nb >= 2 & !missing(cycle_nb)" ;

eststo clear ;
local models "" ;

forvalues j = 1/`nmeas' {;

    local m "`m`j''" ;
    local t "`t`j''" ;

    display _newline(2) as text "==== Table 2, `l`j'' (`m') ====" ;

    /* deciles within evaluation year, on every cycle where the measure is
       defined: 10% of the cycles in each tail */
    capture drop dec lo hi ;
    gquantiles dec = `m' if !missing(`m'), xtile nquantiles(10) by(`pctby') ;
    gen byte lo = (dec == 1)  if !missing(dec) ;
    gen byte hi = (dec == 10) if !missing(dec) ;
    tab dec, missing ;

    forvalues s = 1/3 {;

        if `run_regs' {;
            reghdfe `dv' lo hi `x3' if `s`s'', absorb(`fe3') vce(cluster `clus') ;
            nr_post, coefs(lo hi) ;
            estimates save "estimates/table_2_`t'_s`s'_k3.ster", replace ;

            /* log-only check: the measure standardized on this sample,
               entered linearly */
            if `s' == 1 {;
                capture drop z smp ;
                gen byte smp = e(sample) ;
                quietly summarize `m' if smp ;
                gen z = (`m' - r(mean)) / r(sd) ;
                quietly reghdfe `dv' z `x3' if smp, absorb(`fe3') vce(cluster `clus') ;
                display as result "CHECK `t' one-SD, grant output controls: "
                    %7.4f _b[z] " (" %6.4f _se[z] ")  N = " %9.0fc e(N) ;
                drop z smp ;
            } ;
        } ;

        estimates use "estimates/table_2_`t'_s`s'_k3.ster" ;
        eststo `t'_s`s' ;
        local models "`models' `t'_s`s'" ;
    } ;
} ;

local statlist "meandv sdeff1 sdeff2 ninv N r2_a" ;
local coefl `"lo "Bottom decile (\(<\)10\textsuperscript{th} percentile)" hi "Top decile (\(>\)90\textsuperscript{th} percentile)""' ;

/* screen, for the log */
esttab `models',
    keep(lo hi) order(lo hi) coeflabels(`coefl') b(%5.3f) se(%5.3f)
    star(+ 0.10 * 0.05 ** 0.01) noobs
    mtitles("All" "First" "Later" "All" "First" "Later" "All" "First" "Later" "All" "First" "Later")
    stats(`statlist',
          labels("Mean DV" "Bottom, SD" "Top, SD" "Investigators" "Cycles" "Adj R2")
          fmt(%9.3f %9.3f %9.3f %9.0fc %9.0fc %9.4f))
    mgroups("`l1'" "`l2'" "`l3'" "`l4'", pattern(1 0 0 1 0 0 1 0 0 1 0 0))
    title("Table 2") ;

/* LaTeX fragment: one table, the four measures side by side */
esttab `models' using "estimates/tex/table_2.tex", replace
    `texopts'
    keep(lo hi) order(lo hi) coeflabels(`coefl')
    mlabels("All" "First" "Later" "All" "First" "Later" "All" "First" "Later" "All" "First" "Later",
            prefix(\multicolumn{1}{c}{) suffix(}))
    stats(`statlist',
          labels("Mean of dependent variable"
                 "Effect of bottom decile, in s.d. units"
                 "Effect of top decile, in s.d. units"
                 "Nb. of investigators"
                 "Nb. of grant cycles"
                 "Adjusted \(R^2\)")
          fmt(%9.3f %9.3f %9.3f %12.0fc %12.0fc %9.4f))
    mgroups("`l1'" "`l2'" "`l3'" "`l4'",
            pattern(1 0 0 1 0 0 1 0 0 1 0 0) span
            prefix(\multicolumn{@span}{c}{) suffix(})
            erepeat(\cmidrule(lr){@span})) ;

nr_fmt table_2, groups(3,3,3,3) ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
