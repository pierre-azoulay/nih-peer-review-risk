/* =============================================================================
   code/build/14_novelty_text.do

   Purpose: Textual novelty of each cycle's acknowledging papers, from the
            published release of Arts, Melluso and Veugelers
            (novelty_metrics_2024.dta), one row per cycle:
              frac_new_phrase_oth  new noun phrases as a share of all noun
                               phrases in the cycle's scored papers, a phrase
                               counting as new only if a later paper that
                               shares no author with the paper uses it
                               (phrase_novelty_by_author_2024.dta): the paper's
                               measure of novelty (Figure 4, Appendix Table F1,
                               Appendix Figures F1 and F2)
              frac_new_phrase  the same with the release's count, in which a
                               later paper by the same authors also makes a
                               phrase new
              avg_new_phrase   new noun phrases per scored paper
              frac_new_phrase_comb  new noun-phrase combinations over the
                                    possible pairs of the papers' noun phrases
                                    (Appendix Figures F1 and F2)
              frac_new_word_comb    the same for words
            (the release counts new combinations; the counts rise with the
            length of the abstract, so they are shares here, pooled over the
            cycle's scored papers like frac_new_phrase);
              semdist_mean     the mean over the cycle's papers of one minus the
                               highest SPECTER cosine similarity to any paper of
                               the previous five years (the release's embedding
                               measure; Appendix Figures F1 and F2)
            and, as alternatives, avg_new_word and frac_new_word (new words)
            and avg_new_word_comb (new pairwise word combinations). The
            release's reuse variants are left out: they count later uptake,
            closer to an outcome. The counts are raw; the release's
            documentation warns that counts fall for recent papers, so
            analyses compare cycles within evaluation year (semantic distance
            is free of this).

   Input:
     - ${data}/build/cycle_papers.dta   (code/build/03_cycle_papers.do)
     - ${pubmed_root}/novelty_artsetal/novelty_metrics_2024.dta   the release of
       Arts, Melluso and Veugelers, by PMID
     - ${pubmed_root}/novelty_artsetal/phrase_novelty_by_author_2024.dta   for
       every acknowledging paper with a new noun phrase in the release, its new
       noun phrases used again by a later paper of the release that shares no
       OpenAlex author with it, by PMID (from data provided by N. Melluso)

   Output:
     - ${data}/build/novelty_text.dta, one row per cycle with a scored
       acknowledging paper
   ============================================================================= */

#delimit ;
clear all ;
version 19.5 ;
pause on ;
program drop _all ;
set more off ;
capture log close nih_risk ;

include "config.do" ;
log using "logs/14_novelty_text.log", replace name(nih_risk) ;

local start_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;

use setnb project_number cycle pmid ackn using "${data}/build/cycle_papers.dta", clear ;
keep if ackn == 1 ;
drop ackn ;
gisid setnb project_number cycle pmid ;

merge m:1 pmid using "${pubmed_root}/novelty_artsetal/novelty_metrics_2024.dta",
    keepusing(new_phrase n_phrases new_word n_words new_word_comb new_phrase_comb semantic_distance) ;
tab _merge ;
drop if _merge == 2 ;
drop _merge ;
gen byte scored = !missing(new_phrase) & n_phrases > 0 & !missing(n_phrases) ;
display as text "share of acknowledging papers with a score, and with a semantic distance:" ;
gen byte has_sd = !missing(semantic_distance) ;
summarize scored has_sd ;

/* new noun phrases used again by a later paper of the release that shares no
   author with the paper. The file covers every acknowledging paper with a new
   noun phrase in the release; a paper outside it has none. */
merge m:1 pmid using "${pubmed_root}/novelty_artsetal/phrase_novelty_by_author_2024.dta",
    keepusing(new_phrase_other) ;
tab _merge ;
drop if _merge == 2 ;
assert _merge == 3 if new_phrase > 0 & !missing(new_phrase) ;
replace new_phrase_other = 0 if _merge == 1 & new_phrase == 0 ;
drop _merge ;
foreach v in new_phrase n_phrases new_word n_words new_word_comb new_phrase_comb new_phrase_other {;
    replace `v' = . if !scored ;
} ;
/* the possible pairs of a paper's words and of its noun phrases, the
   denominators of the combination shares */
gen double pairs_w = n_words * (n_words - 1) / 2 ;
gen double pairs_p = n_phrases * (n_phrases - 1) / 2 ;
keep if scored | has_sd ;

gcollapse (mean) avg_new_phrase = new_phrase avg_new_word = new_word
                 avg_new_word_comb = new_word_comb semdist_mean = semantic_distance
          (sum) s_np = new_phrase s_ap = n_phrases s_nw = new_word s_aw = n_words
                s_nwc = new_word_comb s_pw = pairs_w s_npc = new_phrase_comb s_pp = pairs_p
                s_npo = new_phrase_other
          (count) n_scored = new_phrase n_semdist = semantic_distance,
    by(setnb project_number cycle) ;
gen double frac_new_phrase = s_np / s_ap if n_scored > 0 ;
gen double frac_new_word   = s_nw / s_aw if n_scored > 0 ;
gen double frac_new_word_comb   = s_nwc / s_pw if n_scored > 0 & s_pw > 0 ;
gen double frac_new_phrase_comb = s_npc / s_pp if n_scored > 0 & s_pp > 0 ;
gen double frac_new_phrase_oth  = s_npo / s_ap if n_scored > 0 ;
drop s_np s_ap s_nw s_aw s_nwc s_pw s_npc s_pp s_npo ;
label variable avg_new_phrase    "New noun phrases per scored acknowledging paper" ;
label variable frac_new_phrase   "New noun phrases as a share of all noun phrases" ;
label variable frac_new_phrase_oth "New noun phrases used again by other authors, as a share of all noun phrases" ;
label variable avg_new_word      "New words per scored acknowledging paper" ;
label variable frac_new_word     "New words as a share of all words" ;
label variable avg_new_word_comb "New word combinations per scored acknowledging paper" ;
label variable frac_new_word_comb   "New word combinations as a share of the possible pairs of words" ;
label variable frac_new_phrase_comb "New noun-phrase combinations as a share of the possible pairs of phrases" ;
label variable semdist_mean      "Mean semantic distance (SPECTER) of the acknowledging papers" ;
label variable n_scored          "Acknowledging papers with a textual-novelty score" ;
label variable n_semdist         "Acknowledging papers with a semantic distance" ;
summarize avg_new_phrase frac_new_phrase avg_new_word frac_new_word avg_new_word_comb
    frac_new_word_comb frac_new_phrase_comb semdist_mean n_scored n_semdist, detail ;
summarize frac_new_phrase_oth, detail ;
correlate frac_new_phrase frac_new_phrase_oth ;
display as text "share of cycles at zero:" ;
foreach v in avg_new_phrase frac_new_phrase avg_new_word avg_new_word_comb frac_new_word_comb frac_new_phrase_comb frac_new_phrase_oth {;
    quietly count if `v' == 0 ;
    local z = r(N) ;
    quietly count if !missing(`v') ;
    display as text "  `v': " %5.3f `z' / r(N) ;
} ;

sort setnb project_number cycle ;
compress ;
save "${data}/build/novelty_text.dta", replace ;

local end_time = clock("`c(current_date)' `c(current_time)'", "DMYhms") ;
local elapsed  = (`end_time' - `start_time') / 1000 ;
local hrs  = floor(`elapsed' / 3600) ;
local mins = floor(mod(`elapsed', 3600) / 60) ;
local secs = round(mod(`elapsed', 60), 1) ;
display _newline as text "Total runtime: `hrs'h `mins'm `secs's" ;

log close nih_risk ;
