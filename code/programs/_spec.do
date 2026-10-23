/* --------------------------------------------------------------------------
   _spec.do  --  the specification every analysis do-file shares

   Purpose : declare, in one place, the outcome, the four risk measures and
             their labels, the control sets of Table 2, the clustering and the
             options of esttab, so that every exhibit uses the same
             definitions.
   Used by : every do-file of code/analysis, via
             `include "code/programs/_spec.do"' right after
             `include "config.do"'. Locals, not globals: an included file
             shares the caller's locals, and nothing lingers in the Stata
             session between runs.
   -------------------------------------------------------------------------- */

#delimit ;

/* the public analysis file: one row per analysis-sample cycle, with the
   side files' variables and generic identifiers
   (code/build/34_public_file.do) */
local afile "${public}/nih_risk_public.dta" ;

/* outcome: renewed within three fiscal years of the last payment */
local dv "renewed" ;

/* the four risk measures, in the paper's order: variable, file tag, name in
   the paper, and the description used in row labels */
local nmeas 4 ;
local m1 "spread_minmax_ackn" ;  local t1 "tails" ;
local m2 "di1nok_ackn_maxpctl" ; local t2 "disr" ;
local m3 "frac_setnb_pair" ;     local t3 "pivot" ;
local m4 "frac_icirg_pair" ;     local t4 "so" ;
local l1 "Extreme tail outcomes" ;
local l2 "Disruption" ;
local l3 "Pivoting" ;
local l4 "Standing out" ;
local d1 "max-min citation percentile" ;
local d2 "maximum disruption index" ;
local d3 "fraction new MeSH pairs" ;
local d4 "fraction unique MeSH pairs" ;

/* names in graph axis titles, and one color per measure in every graph:
   tails blue, disruption a brick red (distinct from novelty's purple where
   the two interleave in Figure 4), pivoting green, standing out dark orange,
   novelty purple. An RGB color must be in double quotes inside the color
   option where it is used: unquoted, Stata reads only its first number and
   falls back to the default color with a note and rc 0. */
local g1 "Extreme Tail Outcomes" ;
local g2 "Disruption" ;
local g3 "Pivoting" ;
local g4 "Standing Out" ;
local c1 "stblue" ;
local c2 "200 40 40" ;
local c3 "stgreen" ;
local c4 "dkorange" ;
local cnov "purple" ;

/* the headline novelty measure: new noun phrases as a share of the cycle's
   noun phrases (Arts, Melluso and Veugelers), a phrase counting as new only if
   a later paper that shares no author with the paper uses it
   (code/build/14_novelty_text.do). 15% of cycles coin no new phrase, so its
   lowest ventiles are nearly empty. */
local nov  "frac_new_phrase_oth" ;
local novl "Novelty (share of new noun phrases)" ;

/* percentile groups of a measure are computed within evaluation year, on all
   cycles where the measure is defined */
local pctby "new_eval_year" ;

/* control sets. fe: absorbed; x: continuous regressors.
   1: investigator demographics (gender, degree, career-age bins), grant
      evaluation year and cycle length, institute x study section
   2: + institution funding (institution quality), career citations and prior
      NIH funding with a flag for none (investigator quality)
   3: + mean journal impact factor, top-journal flags, bins of acknowledging
      and other papers, and the flag for windows past 2018 (the grant output
      controls: the specification of every exhibit)                        */
local fe1 "female deg_cat agepi_* new_eval_year new_cycle_length ic_irg" ;
local x1  "" ;
local fe2 "`fe1' no_pi_priorgrants" ;
local x2  "log_amount_allgrants log_pi_careercites_evalyr log_pi_priorgrants_all" ;
local fe3 "`fe2' journal_hs_ackn journal_hs_noackn bin_ackn bin_noackn authority_partial" ;
local x3  "`x2' log_meanjif_all" ;

/* clustering: investigator and grant */
local clus "inv_id grant_id" ;

/* esttab options shared by every LaTeX fragment: rows only (the paper
   supplies the tabular, caption and notes) */
local texopts `"booktabs fragment label nomtitles collabels(none) nonotes noobs b(%5.3f) se(%5.3f) star(\dagger 0.10 * 0.05 ** 0.01)"' ;
