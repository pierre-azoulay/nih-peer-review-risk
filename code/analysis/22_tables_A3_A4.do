/* =============================================================================
   code/analysis/22_tables_A3_A4.do

   Purpose: Appendix Tables A3 and A4, the penalty of Table 2 on subsamples,
            with the grant output controls of Table 2. Each table has one
            panel per risk measure (bottom and top deciles, as in Table 2)
            and one column per sample, the full sample first.
              Table A3: the sample common to the four measures, the cycles
                        where all four are defined (has_all4); then below
                        and above the median of the investigator's name
                        frequency in Author-ity (name_freq_authority).
              Table A4: below and above the median share of the
                        investigator's papers with an NIH grant, those
                        published from 1980 to the year before the cycle
                        starts (frac_pubs_nih_pre,
                        code/build/20_record_before_cycle.do), so that the
                        split cannot reflect the cycle's outcome. Cycles
                        whose investigator has no paper in that window
                        leave columns 2 and 3.
            Deciles are those of Table 2 (within evaluation year, on every
            cycle where the measure is defined), not recomputed by subsample.
            The log gives each column's number of cycles (the notes of
            Tables A3 and A4 quote them, and the text quotes the cycles
            with all four measures) and the two medians.

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)

   Output:
     - estimates/tex/table_A3_<measure>.tex, estimates/tex/table_A4_<measure>.tex
       (esttab rows), formatted by nr_fmt into
     - output/tables/table_A3_<measure>.tex, output/tables/table_A4_<measure>.tex
       one panel per measure (tails, disr, pivot, so)
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

log using "logs/22_tables_A3_A4.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use "`afile'", clear ;

/* the tables to run: stub, then the conditions defining each subsample
   (the full sample always comes first). The medians of the name frequency
   (Table A3) and of the NIH share (Table A4) are taken over the cycles with
   an acknowledging paper. */
quietly summarize name_freq_authority if n_ackn >= 1, detail ;
local med_nf = r(p50) ;
quietly summarize frac_pubs_nih_pre if n_ackn >= 1, detail ;
local med_nih = r(p50) ;
display as text "cycles without an NIH share before the cycle (no paper from 1980 to cycle_yr - 1)" ;
count if missing(frac_pubs_nih_pre) ;
count if missing(frac_pubs_nih_pre) & n_ackn >= 1 ;
display as text "median name frequency: `med_nf'   median NIH share: `med_nih'" ;

local tables "table_A3 table_A4" ;
local table_A3_n 3 ;
local table_A3_s1 "has_all4 == 1" ;
local table_A3_s2 "name_freq_authority <= `med_nf'" ;
local table_A3_s3 "name_freq_authority > `med_nf' & !missing(name_freq_authority)" ;
local table_A3_h `""Full sample" "Uniform sample" "Below-median name frequency" "Above-median name frequency""' ;
local table_A4_n 2 ;
local table_A4_s1 "frac_pubs_nih_pre <= `med_nih'" ;
local table_A4_s2 "frac_pubs_nih_pre > `med_nih' & !missing(frac_pubs_nih_pre)" ;
local table_A4_h `""Full sample" "Below-median share of NIH-funded papers" "Above-median share of NIH-funded papers""' ;

foreach tb of local tables {;

    forvalues j = 1/`nmeas' {;

        local m "`m`j''" ;
        local t "`t`j''" ;

        capture drop dec lo hi ;
        gquantiles dec = `m' if !missing(`m'), xtile nquantiles(10) by(`pctby') ;
        gen byte lo = (dec == 1)  if !missing(dec) ;
        gen byte hi = (dec == 10) if !missing(dec) ;
        label variable lo "<10\%ile" ;
        label variable hi ">90\%ile" ;

        eststo clear ;
        local models "" ;
        forvalues s = 0/``tb'_n' {;
            local cond = cond(`s' == 0, "1", "``tb'_s`s''") ;
            reghdfe `dv' lo hi `x3' if `cond', absorb(`fe3') vce(cluster `clus') ;
            eststo `tb'_`t'_s`s' ;
            /* each column's number of cycles: in Table A3, sample 1 is the
               cycles where all four measures are defined */
            display as result "`tb' `t' sample `s': N = " e(N) ;
            local models "`models' `tb'_`t'_s`s'" ;
        } ;

        esttab `models', keep(lo hi) order(lo hi) label b(%5.3f) se(%5.3f)
            star(+ 0.10 * 0.05 ** 0.01) nomtitles title("`tb', `l`j''") ;

        /* the first panel carries the column header; the others only rows */
        if `j' == 1 {;
            esttab `models' using "estimates/tex/`tb'_`t'.tex", replace
                `texopts' keep(lo hi) order(lo hi) nonumbers
                mlabels(``tb'_h', prefix(\multicolumn{1}{c}{) suffix(}))
                refcat(lo "\textit{`l`j''}", nolabel) ;
        } ;
        else {;
            esttab `models' using "estimates/tex/`tb'_`t'.tex", replace
                `texopts' keep(lo hi) order(lo hi) nonumbers nomtitles nolines
                refcat(lo "\textit{`l`j''}", nolabel) ;
        } ;
        nr_fmt `tb'_`t' ;
    } ;
} ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
