/* =============================================================================
   code/analysis/40_table_L1.do

   Purpose: Appendix Table L1, the downstream outcomes of Table 3 during the
            grant cycle and in the five years after its last payment, on the
            cycles of Table 1e: cycles evaluated by 2020 with at least one
            publication acknowledging the grant and a known number within the
            grant, renewed or terminated (not renewed, and the grant not
            revived later). Means. Every outcome but the direct grant patents
            is built from the publications that acknowledge the grant and on
            which the investigator is an author; the direct grant patents are
            the patents NIH RePORTER links to the grant, by the year their
            application was filed (code/build/33_outcome_windows.do).
              A  during the cycle: the publications of the cycle's first year
                 to the year of its last payment, the patents filed in those
                 years
              B  the five years after the last payment: the outcomes of
                 Table 3, whose means are those of Table 1e

   Input:
     - ${public}/nih_risk_public.dta          (code/build/34_public_file.do)
       with the variables of cycle_windows.dta (code/build/33_outcome_windows.do)
   Output:
     - output/tables/table_L1.tex   (rows only: the paper supplies the
                                     tabular, caption and notes)
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

log using "logs/40_table_L1.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

/* the rows: the stem of the variables of cycle_windows.dta, the label, the
   format (Table 1e's for the six outcomes of Table 3) */
local nr 7 ;
local rv1 "n_pubs" ;       local rl1 "Publications" ;         local rf1 "%9.1f" ;
local rv2 "cites5" ;       local rl2 "Article Citations" ;    local rf2 "%12.1fc" ;
local rv3 "n_grpat" ;      local rl3 "Direct Grant Patents" ; local rf3 "%9.2f" ;
local rv4 "pat_cites" ;    local rl4 "Patent Citations" ;     local rf4 "%12.2fc" ;
local rv5 "pharma_cites" ; local rl5 "FDA Patent Citations" ; local rf5 "%9.2f" ;
local rv6 "kpss_value" ;   local rl6 "KPSS Patent Value" ;    local rf6 "%12.1fc" ;
local rv7 "compot_mean" ;  local rl7 "Commercial Potential" ; local rf7 "%9.3f" ;

/* the panels: the window's suffix and the panel's title */
local pw1 "dur" ; local pl1 "A. During the cycle" ;
local pw2 "aft" ; local pl2 "B. The five years after the cycle's last payment" ;

/* -----------------------------------------------------------------------------
   1. The cycles of Table 1e: the two columns
   ----------------------------------------------------------------------------- */
use "`afile'", clear ;

/* a known number within the grant (first or later cycle, as in Table 2);
   side 1 renewed, side 2 terminated */
gen byte known = cycle_nb == 1 | (cycle_nb >= 2 & cycle_nb < .) ;
gen byte side = . ;
replace side = 1 if known & renewed == 1 ;
replace side = 2 if known & renewed == 0 & next_revival == 0 ;
keep if eval_year <= 2020 & n_ackn >= 1 & !missing(side) ;
display as result "=== the cycles of Table 1e: renewed (1) and terminated (2)" ;
tab side ;

/* -----------------------------------------------------------------------------
   2. The table: the means of each window, renewed and terminated cycles
   ----------------------------------------------------------------------------- */
forvalues p = 1/2 {;
    display as result _newline "=== `pl`p''" ;
    tabstat n_pubs_`pw`p'' cites5_`pw`p'' n_grpat_`pw`p'' pat_cites_`pw`p''
            pharma_cites_`pw`p'' kpss_value_`pw`p'' compot_mean_`pw`p'',
        by(side) stat(n mean) format(%12.3f) ;
} ;

tempname fh ;
file open `fh' using "output/tables/table_L1.tex", write replace ;
file write `fh' " & Renewed & Terminated \\" _n "\midrule" _n ;
local row "Cycles" ;
forvalues s = 1/2 {;
    quietly count if side == `s' ;
    local v : display %12.0fc r(N) ;
    local row "`row' & `=strtrim("`v'")'" ;
} ;
file write `fh' "`row' \\" _n ;
forvalues p = 1/2 {;
    local w "`pw`p''" ;
    file write `fh' "\addlinespace" _n "\multicolumn{3}{l}{\textit{`pl`p''}} \\" _n ;
    forvalues r = 1/`nr' {;
        local row "\quad `rl`r''" ;
        forvalues s = 1/2 {;
            quietly summarize `rv`r''_`w' if side == `s' ;
            local v : display `rf`r'' r(mean) ;
            local row "`row' & `=strtrim("`v'")'" ;
        } ;
        file write `fh' "`row' \\" _n ;
    } ;
    /* commercial potential is a mean over the cycles with a scored
       publication in the window (publications from 1990) */
    local row "\quad\quad{\footnotesize\textit{Cycles with a scored publication}}" ;
    forvalues s = 1/2 {;
        quietly count if side == `s' & !missing(compot_mean_`w') ;
        local v : display %12.0fc r(N) ;
        local row "`row' & {\footnotesize `=strtrim("`v'")'}" ;
    } ;
    file write `fh' "`row' \\" _n ;
} ;
file close `fh' ;
type "output/tables/table_L1.tex" ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
