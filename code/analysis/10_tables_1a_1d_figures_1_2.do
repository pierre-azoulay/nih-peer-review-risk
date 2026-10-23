/* =============================================================================
   code/analysis/10_tables_1a_1d_figures_1_2.do

   Purpose: the descriptive exhibits. Figure 1: the number of publications
            acknowledging the grant in the cycle, by renewal status. Figure 2:
            the distribution of each of the four risk measures, by renewal
            status. Tables 1a to 1d: the investigators, the grant cycles, the
            risk measures and novelty, and their correlations. The sample is
            the cycles with at least one acknowledging publication; the
            analysis file also holds the cycles without one, which Appendix
            Table A1 studies separately.
            Table 1b describes the investigator at the cycle's start:
            publications before cycle_yr and their citations through
            cycle_yr - 1 (code/build/20_record_before_cycle.do; the regression
            control is measured at the evaluation year); citations to the
            cycle's papers are five-year OpenAlex citations
            (code/build/17_cycle_cites.do). Table 1e is written by
            code/analysis/11_tables_1e_3.do.

   Input:
     - ${public}/nih_risk_public.dta   (code/build/34_public_file.do), with
       the investigator's career NIH funding for Table 1a

   Output:
     - output/figures/figure_1.pdf
     - output/figures/figure_2_<t>.pdf, <t> = tails disr pivot so
     - output/tables/table_1a.tex, table_1b.tex, table_1c.tex, table_1d.tex
       (rows only: the paper supplies the tabular, caption and notes)
     - graphs/gph, graphs/svg: the same graphs

   Note: the log reports the counts that the exhibit notes quote: the cycles
         with more than 25 publications, not shown in Figure 1, and the
         cycles behind the listwise correlations of Table 1d.
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

log using "logs/10_tables_1a_1d_figures_1_2.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

graph set window fontface "CMU Sans Serif" ;
grstyle init deadzone, replace ;
grstyle set plain ;

use "`afile'", clear ;
keep if n_ackn >= 1 ;
count ;
tab renewed ;


/* =============================================================================
   FIGURE 1: acknowledging publications per cycle, by renewal status
   ============================================================================= */

count if n_ackn > 25 ;
display as text "cycles with more than 25 publications, not shown: " r(N)
    " (" %4.1f 100*r(N)/_N "%)" ;
quietly count if renewed == 0 ;
local ntot0 = r(N) ;
quietly count if renewed == 1 ;
local ntot1 = r(N) ;

preserve ;
keep if n_ackn <= 25 ;
gen byte one = 1 ;
gcollapse (sum) n = one, by(n_ackn renewed) ;
/* each bar is the share of its group's cycles, all cycles of the group
   including those above 25 publications: in counts, the larger group of
   non-renewed cycles would look as if it had more mass; percent labels from
   nr_pctlab (code/programs/_programs.do) */
gen long tot = cond(renewed == 1, `ntot1', `ntot0') ;
gen double pct = 100 * n / tot ;
gen double x = n_ackn + cond(renewed == 1, 0.2, -0.2) ;
quietly summarize pct ;
nr_pctlab `=r(max)' ;
local ylabp `"`r(lab)'"' ;
local ptop = r(top) ;
twoway
    (bar pct x if renewed == 0, barwidth(0.4) color(gs10) lwidth(none))
    (bar pct x if renewed == 1, barwidth(0.4) color(gs4) lwidth(none)),
    xlabel(1(1)25, labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
    ylabel(`ylabp', angle(horizontal) labsize(medsmall) tlength(.75)
           grid glwidth(vvthin) glcolor(gs13))
    yscale(range(0 `ptop'))
    xtitle("Publications Acknowledging the Grant", size(medium))
    ytitle("Share of Grant Cycles", size(medium))
    legend(order(1 "Not renewed" 2 "Renewed") ring(0) position(1) cols(1)
           size(medsmall) region(lcolor(none)))
    graphregion(color(white) margin(small)) plotregion(margin(small)) ;
nr_gexport figure_1 ;
graph close ;
restore ;


/* =============================================================================
   FIGURE 2: the four measures, by renewal status
   Tails and disruption on the percentile scale (0 to 100), pivoting and
   standing out as fractions; 20 bins each. Each measure keeps its color:
   renewed in the full color, not renewed in a light tint of it.
   ============================================================================= */

forvalues j = 1/`nmeas' {;
    local m "`m`j''" ;
    local t "`t`j''" ;
    local col "`c`j''" ;
    preserve ;
    keep if !missing(`m') ;
    local scale = cond(`j' <= 2, 100, 1) ;
    gen double xv = `m' * `scale' ;
    /* 20 bins of equal width; the top value falls in the last bin */
    gen byte bin = min(floor(`m' * 20), 19) ;
    gen byte one = 1 ;
    gcollapse (sum) n = one, by(bin renewed) ;
    /* each bar is the share of its group's cycles */
    gegen double tot = total(n), by(renewed) ;
    gen double pct = 100 * n / tot ;
    local w = `scale' / 20 ;
    gen double x = (bin + 0.5) * `w' + cond(renewed == 1, 0.2, -0.2) * `w' ;
    local xmax = `scale' ;
    local xstep = `scale' / 5 ;
    /* axis titles name the unit; the panel titles name the measure */
    if `j' <= 2 {;
        local xlab "0(`xstep')`xmax'" ;
        local xtit "Percentile Points" ;
    } ;
    else {;
        local xlab `"0 "0" 0.2 "0.20" 0.4 "0.40" 0.6 "0.60" 0.8 "0.80" 1 "1""' ;
        local xtit "Fraction of MeSH Term Pairs" ;
    } ;
    quietly summarize pct ;
    nr_pctlab `=r(max)' ;
    local ylabp `"`r(lab)'"' ;
    local ptop = r(top) ;
    twoway
        (bar pct x if renewed == 0, barwidth(`=0.4*`w'') color("`col'%35") lwidth(none))
        (bar pct x if renewed == 1, barwidth(`=0.4*`w'') color("`col'") lwidth(none)),
        xlabel(`xlab', labsize(medsmall) tlength(.75) grid glwidth(vvthin) glcolor(gs13))
        ylabel(`ylabp', angle(horizontal) labsize(medsmall) tlength(.75)
               grid glwidth(vvthin) glcolor(gs13))
        yscale(range(0 `ptop'))
        xtitle("`xtit'", size(medium))
        ytitle("Share of Grant Cycles", size(medium))
        legend(order(1 "Not renewed" 2 "Renewed") ring(0) position(1) cols(1)
               size(medsmall) region(lcolor(none)))
        graphregion(color(white) margin(small)) plotregion(margin(small)) ;
    nr_gexport figure_2_`t' ;
    graph close ;
    restore ;
} ;

capture erase "scheme-deadzone.scheme" ;


/* =============================================================================
   TABLES 1a TO 1d
   Rows written directly (file write): mean, median, standard deviation,
   minimum, maximum; renewed cycles first, then cycles not renewed. The
   tabular, the header rule and the notes are in the paper.
   ============================================================================= */

/* one row: label, variable, format; two groups unless onegroup is given */
capture program drop nr_drow ;
program define nr_drow ;
    syntax varname, fh(string) Label(string) [Fmt(string) ONEgroup Renonly] ;
    if "`fmt'" == "" local fmt "%9.2f" ;
    local row "`label'" ;
    local groups = cond("`onegroup'" != "", "all", "1 0") ;
    foreach g of local groups {;
        if "`g'" == "all" quietly summarize `varlist', detail ;
        else quietly summarize `varlist' if renewed == `g', detail ;
        if r(N) == 0 | ("`renonly'" != "" & "`g'" == "0") {;
            local row "`row' & & & & &" ;
        } ;
        else {;
            foreach s in mean p50 sd min max {;
                local v : display `fmt' r(`s') ;
                local row "`row' & `=strtrim("`v'")'" ;
            } ;
        } ;
        if "`g'" == "1" local row "`row' &" ;
    } ;
    file write `fh' "`row' \\" _n ;
end ;

/* the two-group header */
capture program drop nr_dhead ;
program define nr_dhead ;
    syntax , fh(string) ;
    file write `fh' " & \multicolumn{5}{c}{Renewed grant cycles} & & \multicolumn{5}{c}{Not renewed grant cycles} \\" _n ;
    file write `fh' "\cmidrule(lr){2-6}\cmidrule(lr){8-12}" _n ;
    file write `fh' " & Mean & Median & Std. Dev. & Min. & Max. & & Mean & Median & Std. Dev. & Min. & Max. \\" _n ;
    file write `fh' "\midrule" _n ;
end ;

gen double tails100 = spread_minmax_ackn * 100 ;
gen double disr100  = di1nok_ackn_maxpctl * 100 ;
gen int    time2cycle = cycle_yr - deg_year ;
gen byte   first_cycle = (cycle_nb == 1) if !missing(cycle_nb) ;
tempname fh ;

/* Table 1a: investigators of the sample (cycles with an acknowledging paper) */
preserve ;
gegen n_grants = nunique(grant_id), by(inv_id) ;
gegen n_cycles = count(cycle), by(inv_id) ;
gegen elite_inv = max(elite_ever), by(inv_id) ;
bysort inv_id (cycle_yr grant_id cycle): keep if _n == 1 ;
gen byte deg_md    = deg_cat == 1 ;
gen byte deg_phd   = deg_cat == 2 ;
gen byte deg_mdphd = deg_cat == 3 ;
gen byte deg_oth   = deg_cat == 4 ;
/* car_r01 and car_all: the investigator's NIH funding over the whole grant
   file, computed in code/build/34_public_file.do */
keep inv_id female deg_year deg_md deg_phd deg_mdphd deg_oth n_grants n_cycles elite_inv car_r01 car_all ;
count ;
local n_inv = r(N) ;
file open `fh' using "output/tables/table_1a.tex", write replace ;
file write `fh' " & Mean & Median & Std. Dev. & Min. & Max. \\" _n "\midrule" _n ;
nr_drow female,    fh(`fh') label("Female") onegroup ;
nr_drow deg_year,  fh(`fh') label("Degree year") fmt(%9.0f) onegroup ;
nr_drow deg_phd,   fh(`fh') label("Degree: PhD") onegroup ;
nr_drow deg_md,    fh(`fh') label("Degree: MD") onegroup ;
nr_drow deg_mdphd, fh(`fh') label("Degree: MD/PhD") onegroup ;
nr_drow deg_oth,   fh(`fh') label("Degree: Other") onegroup ;
nr_drow n_grants,  fh(`fh') label("Nb. of R01-equivalent grants") onegroup ;
nr_drow n_cycles,  fh(`fh') label("Nb. of R01-equivalent grant cycles") onegroup ;
nr_drow car_r01,   fh(`fh') label("Career NIH R01 funding (2024 dollars)") fmt(%15.0fc) onegroup ;
nr_drow car_all,   fh(`fh') label("Career NIH funding (2024 dollars)") fmt(%15.0fc) onegroup ;
nr_drow elite_inv, fh(`fh') label("Career elite status") onegroup ;
file close `fh' ;
display as result "Table 1a: `n_inv' investigators" ;
restore ;

/* Table 1b: grant cycles */
file open `fh' using "output/tables/table_1b.tex", write replace ;
nr_dhead, fh(`fh') ;
nr_drow cycle_nb,     fh(`fh') label("Grant cycle number") ;
nr_drow first_cycle,  fh(`fh') label("First cycle of grant") ;
nr_drow cycle_yr,     fh(`fh') label("Year started") fmt(%9.0f) ;
nr_drow cycle_length, fh(`fh') label("Cycle length (years)") ;
nr_drow time2cycle,   fh(`fh') label("Time, degree to cycle start (years)") ;
nr_drow pi_pubs_precycle,  fh(`fh') label("Investigator publications before the cycle") fmt(%12.1fc) ;
nr_drow pi_cites_precycle, fh(`fh') label("Investigator citations before the cycle") fmt(%12.0fc) ;
file write `fh' "\addlinespace" _n "\multicolumn{12}{l}{\textit{Publications acknowledging grant}} \\" _n ;
nr_drow n_ackn,          fh(`fh') label("\quad Nb. of publications") ;
nr_drow meanjif_ackn,    fh(`fh') label("\quad Journal impact factor") ;
nr_drow cites5_ackn,     fh(`fh') label("\quad Citations (five years)") fmt(%12.0fc) ;
nr_drow journal_hs_ackn, fh(`fh') label("\quad Highly selective journal") ;
file write `fh' "\addlinespace" _n "\multicolumn{12}{l}{\textit{Publications not acknowledging grant}} \\" _n ;
nr_drow n_noackn,          fh(`fh') label("\quad Nb. of publications") ;
nr_drow meanjif_noackn,    fh(`fh') label("\quad Journal impact factor") ;
nr_drow cites5_noackn,     fh(`fh') label("\quad Citations (five years)") fmt(%12.0fc) ;
nr_drow journal_hs_noackn, fh(`fh') label("\quad Highly selective journal") ;
nr_drow frac_noackn_nih,   fh(`fh') label("\quad Share listing an NIH grant") ;
file close `fh' ;
tab renewed ;

/* Table 1c: the measures and novelty (patent citations are in Table 1e) */
file open `fh' using "output/tables/table_1c.tex", write replace ;
nr_dhead, fh(`fh') ;
nr_drow tails100,            fh(`fh') label("Extreme tail outcomes") ;
nr_drow disr100,             fh(`fh') label("Disruption") ;
nr_drow frac_setnb_pair,     fh(`fh') label("Pivoting") ;
nr_drow frac_icirg_pair,     fh(`fh') label("Standing out") ;
nr_drow `nov',   fh(`fh') label("`novl'") ;
file close `fh' ;

/* Table 1d: correlations, listwise (the cycles where every variable is
   defined) */
local cv "spread_minmax_ackn di1nok_ackn_maxpctl frac_setnb_pair frac_icirg_pair `nov' n_ackn cites5_ackn" ;
correlate `cv' ;
matrix C = r(C) ;
local nc = r(N) ;
local cl1 "(1) Extreme tail outcomes" ;
local cl2 "(2) Disruption" ;
local cl3 "(3) Pivoting" ;
local cl4 "(4) Standing out" ;
local cl5 "(5) Novelty" ;
local cl6 "(6) Nb. of publications" ;
local cl7 "(7) Citations" ;
file open `fh' using "output/tables/table_1d.tex", write replace ;
file write `fh' "Variables & (1) & (2) & (3) & (4) & (5) & (6) & (7) \\" _n "\midrule" _n ;
forvalues r = 1/7 {;
    local row "`cl`r''" ;
    forvalues c = 1/7 {;
        if `c' <= `r' {;
            local v : display %5.3f C[`r', `c'] ;
            local row "`row' & `=strtrim("`v'")'" ;
        } ;
        else local row "`row' &" ;
    } ;
    file write `fh' "`row' \\" _n ;
} ;
file close `fh' ;
display as result "Table 1d: listwise N = `nc'" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
