# Replication package: "Does Peer Review Penalize Scientific Risk Taking? Evidence from NIH Grant Renewals"

Pierre Azoulay and Wesley H. Greenblatt

## Replicating the tables and figures

The package contains the data and the code that reproduce every table and figure of the paper and its appendices: Tables 1a to 1e, 2 and 3, Figures 1 to 5, and the appendix exhibits A1 to L1. The data are the public analysis file, `data/nih_risk_public.zip` (described below). Numbers quoted in the text that do not appear in a table or figure were computed by the authors' own checks, some from the raw sources; they are not part of the package.

1. Install the software listed under "Computational requirements": Stata 19.5 with the community packages listed there; a Python 3 interpreter for Stata's embedded Python (`python set exec`), which formats the tables; and Inkscape with the CMU Sans Serif font, which produce the figures. The other Python packages are needed only to build the data.
2. If Stata does not find Python or Inkscape on its own, give their paths in `config.do`, section 3. Nothing else needs editing.
3. Start Stata with this folder as its working directory and run `do master.do` (in batch: `stata-mp -b do master.do`, or `StataMP-64.exe /e do master.do` on Windows). If your `profile.do` changes the working directory at startup, run a do-file of two lines instead: `cd "<this folder>"`, then `do master.do`.

As distributed, `master.do` has `local build 0`. It unzips `data/nih_risk_public.zip` into `data/nih_risk_public.dta` and runs the 27 do-files of `code/analysis/`, in the paper's order (31 runs, since Table 3 runs once for each measure and once to write the table). It writes the tables to `output/tables/`, the figures to `output/figures/`, and one log for each do-file to `logs/`. On the machine described under "Memory, storage and runtime", the run took 1 hour 18 minutes in one Stata session. Do not run the do-files of `code/build/`: they build the public analysis file from the raw sources, which the package does not include. After a first run of `master.do`, any analysis do-file can be rerun alone from this folder, e.g. `do code/analysis/12_table_2.do`.

## Overview of the build

The code in this package also builds the public analysis file from its raw sources (the build, `code/build/`, 34 stages): from the NIH grant records, PubMed and the other sources to the analysis file, the side files that some appendix exhibits read, and the public analysis file, which gathers what the analysis uses, with generic identifiers. The build is written in Stata (StataNow 19.5 MP), with Python (DuckDB, pandas) for the steps that handle the largest files. On a 16-core machine with 128 GB of memory, with one Stata process per do-file, the build takes about 1 hour 45 minutes and the analysis about 30 minutes when its do-files run six at a time; in one Stata session, as `master.do` runs it with `local build 1`, the whole package takes about five hours.

The unit of analysis is the grant cycle: one funding cycle of an R01-equivalent NIH grant, from the competing award that starts it to its last payment, with its principal investigator (PI). Cycles are built at the grant level and numbered within the grant. A cycle enters if the competing award that starts it lists one PI and that PI holds every year of the cycle: a co-PI added during the cycle does not exclude it, a PI replaced during it does. The cycle carries that PI and the PI's own characteristics (career, record, gender, degree), and its outcome is the grant's renewal, whoever applies. Three filters are tested on each cycle's own records: at least three distinct budget years; no record at an institution without a code, or at a firm, a national laboratory, a society or a foreign university; and an application ID on the award that starts the cycle, which links it to its study section. The analysis file holds the 123,018 cycles of the analysis sample, of which 103,484 have at least one publication acknowledging the grant.

## Data availability and provenance statements

The data required to replicate every table and figure of the paper and its appendices are included in the package: `data/nih_risk_public.zip`. The data required to build that file from the ground up, the raw sources listed below, are available from the authors on request.

### Statement about rights

- [x] We certify that the authors of the manuscript have legitimate access to and permission to use the data used in this manuscript.
- [ ] We certify that the authors of the manuscript have documented permission to redistribute/publish the data contained within this replication package. **This package contains the public analysis file (`data/nih_risk_public.zip`, below) and the CPI series (`data/cpiaucsl_fred.csv`, public). The raw sources of the build are not included; they are available from the authors on request.**

### The public analysis file

`data/nih_risk_public.zip` holds `nih_risk_public.dta` (Stata format, 123,018 rows, 233 variables; about 133 MB unzipped, 68 MB zipped). It is written by the build's last stage, `code/build/34_public_file.do`, and it is the only file that the analysis reads. It holds one row per grant cycle of the analysis sample and the variables that the analysis uses, and no other: those of the analysis file, those of the side files that appendix exhibits read, and two blocks computed from files that are not included (the citation percentiles of the papers on which the investigator is first, last or single author, for Appendix Table B1; the investigator's NIH funding over the whole grant file, for Table 1a).

Its identifiers are generic. Investigators, grants, study sections and the groups of institute and study section are numbered in a random order, drawn with a fixed seed, so that clustering and fixed effects are those of the build while no row can be looked up by a person's or a grant's identifier. The file does not contain the investigator's identifier in the grant data, the NIH grant number, the application identifier, the Author-ity identifier (only a flag for its presence) or the institution codes. Institutes keep their names, which Appendix K reports. We ask its users not to attempt to identify the investigators or the grants it describes.

### Licenses

The code is licensed under the Modified BSD License (BSD-3-Clause); the README, the exhibits in `output/` and the public analysis file (`data/nih_risk_public.zip`) under the Creative Commons Attribution 4.0 International License (CC BY 4.0). We ask the users of the public analysis file not to attempt to identify any investigator or grant it describes. The CPI series in `data/` is a public-domain work of the U.S. Bureau of Labor Statistics. See `LICENSE.txt`.

### Summary of availability

- [ ] All data **are** publicly available.
- [x] Some data **cannot be made** publicly available.
- [ ] **No data can be made** publicly available.

These statements concern the raw sources of the build, none of which is included in the package except the CPI series; all are available from the authors on request. Most derive from public sources (NIH RePORTER and ExPORTER, PubMed, OpenAlex, PatentsView, Reliance on Science, the FDA Orange Book). The table below gives the status of each input.

### Details on each data source

`config.do` names the root of the raw sources (`${src}`) and the folder of the PubMed parquet files (`${bulk}`); the paths below are relative to them. Every input is read and never written. The last column gives the build stages that read each input (`code/build/NN_...`).

| input (path under `${src}` unless stated) | content | source | public? | read by |
|---|---|---|---|---|
| `CGAF/2019/r01_project/nih_risk/data/input/cgaf_nih_risk.dta` | NIH grant-year records of R01-equivalent and other awards, FY1938 to 2025: activity, institute, serial number, application type, support year, amount, institution; a disambiguated investigator identifier, names, degrees and degree years, and the investigator's gender (version of 18 October 2026) | NIH grant records, with the investigator identifiers, degrees and degree years compiled by the authors from many sources over two decades; gender from a mix of Genni (Torvik 2018) and the authors' own records; written by the authors' `CGAF_new_0013.do` | no (the award records are public through NIH RePORTER; the investigator links are not) | 01, 02, 12, 19, 21, 24, 25, 32 |
| `CGAF/2019/ccrd_app_id2project_num.dta` | application ID of each full project number and year, FY1970 to 2023 | assembled by the authors from the NIH ExPORTER project files (application ID, fiscal year, full project number) | no (derived from public files) | 01 |
| `CGAF/2019/cgaf_study_sections_000.dta` | study section of each application, FY1980 to 2021 | assembled by the authors from the NIH ExPORTER project files (IRG code through FY1984, study section after) | no (derived from public files) | 01, 11 |
| `CGAF/2019/data/CGAF_by_ipfcode.dta` | NIH research funding by institution and year (2024 dollars, deflated by the NIH Biomedical Research and Development Price Index; centered five-year moving average; version of 17 October 2026) | computed by the authors from the grant records: research awards of contact PIs, by standardized institution and fiscal year; the price index of the NIH Office of Budget, its latest version as of October 2026 | no | 04 |
| `CGAF/2019/data/CGAF_all_2025_it.dta` | NIH research funding by investigator and year (2024 dollars, deflated as above; version of 17 October 2026) | computed by the authors from the grant records, with the same price index | no | 04, 34 |
| `CGAF/2019/raw/link_tables/` (the `.csv` files, FY1980 to 2025) | links between NIH projects and the PubMed records that acknowledge them (the file of FY2025 as updated on 14 October 2026) | NIH ExPORTER, publication link tables | yes | 02 |
| `CGAF/2019/raw/abstracts/` (the `.csv` files) | project abstracts | NIH ExPORTER (CRISP and RePORTER) | yes | 11 |
| `CGAF/2019/raw/patents/Patents.csv` | patents linked to NIH projects (version of 14 October 2026) | NIH RePORTER, patents | yes | 33 |
| `CGAF/2008/aux_files/ipf_interm.dta` | institution codes (IPF) to standardized institutions and the authors' classification of institution types | compiled by the authors | no | 01 |
| `Bambino/star_files_polished/stars_all_new.dta` | honors of investigators by year (members of the National Academy of Sciences and of the Institute of Medicine, HHMI investigators, Nobel and Lasker prizes) | compiled by the authors from public lists of elections, appointments and prizes, matched by hand to NIH investigators | no | 19 |
| `PubMed2025/authority/matchCGAF/matches2022/cnsldt_goodmatches.dta` | Author-ity identifier of each NIH investigator (version of 18 October 2026) | matched by the authors | no | 01 |
| `CGAF/2019/r01_project/nih_risk/data/input/namefreq_authority.dta` | frequency of the last name of each investigator matched to Author-ity: the number of Author-ity identifiers that share the last name once standardized (version of 18 October 2026) | computed by the authors from Author-ity 2018, last names standardized by `supermessoudar.ado` (in `code/programs/`) | no (derived from public data) | 19 |
| `PubMed2025/authority/authority_pmids_clean.dta` | Author-ity 2018: disambiguated authors of PubMed records, with their position on each paper | Torvik and Smalheiser (2021), Author-ity 2018, Illinois Data Bank | yes | 03, 04, 05, 09, 10, 15, 19, 20, 22, 24 to 29, 32 |
| `PubMed2025/pubmed/` `pubmed_universe_2025.dta`, `overall_typology_2025.dta`, `overall_language_2025.dta`, `overall_nb_of_authors_2025.dta`, `overall_meshterms_2025.dta`, `overall_dates_2025.dta`, `overall_grants_2025.dta`, `overall_journals_2025.dta`, `overall_pubtypes_2025.dta` | every PubMed record published through 2025: year, publication type, language, number of authors, MeSH descriptors, dates, grants, journal | parsed by the authors from the National Library of Medicine's PubMed 2026 baseline and update files (through 31 July 2026) | yes (the source) | most build stages |
| `PubMed2025/pubmed/overall_jif_2025.dta` | journal impact factor of each PubMed record's journal | Clarivate, Journal Citation Reports | no | 05 |
| `${bulk}/PubMed2026/parquet_merged/auth_names.parquet` | author names of every PubMed record | parsed by the authors from the PubMed 2026 baseline | yes (the source) | 02 |
| `PubMed2025/mesh2025/mesh_trees_2025.dta`, `mesh_descriptors_2025.dta` | MeSH descriptors and their tree numbers (2026 vocabulary) | National Library of Medicine, MeSH | yes | 10, 32 |
| `PubMed2025/WoS/panel_cites_pubmed2pubmed_openalex_2026.dta`, `oaid_x_pmid_2026.dta` | citations among PubMed records by year, and the OpenAlex identifier of each PubMed record | OpenAlex (2026 snapshot) | yes | 04, 05, 20 |
| `PubMed2025/disruption_index/di_index_pubmed2025.dta` | disruption index of every PubMed record with citations, in several versions | computed by the authors from OpenAlex citations | no (derived from public data) | 05, 30 |
| `PubMed2025/PMRA/pmra_links_part1.dta` to `_part3.dta`, `harvested_pmids.dta` | PubMed related articles of each source record (the store as of 18 October 2026) | harvested by the authors from NCBI's E-utilities (elink) | yes (the source) | 26 |
| `PubMed2025/novelty_artsetal/novelty_metrics_2024.dta` | new noun phrases, new word and phrase combinations and semantic distance of each paper | Arts, Melluso and Veugelers (2025), public release | yes | 14 |
| `PubMed2025/novelty_artsetal/phrase_novelty_by_author_2024.dta` | for every acknowledging paper with a new noun phrase in the release, the number of its new noun phrases used again by a later paper of the release that shares no OpenAlex author with it | computed by the authors from data that N. Melluso provided at their request (October 2026): each new noun phrase of these papers, each later paper that uses it, and the OpenAlex authors the two share | provided by N. Melluso | 14 |
| `PubMed2025/reliance_on_science/pmid2patent_2026.dta` | citations from patents to PubMed records, with a match confidence | Reliance on Science (Marx and Fuegi), 2026 release | yes | 16, 33 |
| `PubMed2025/reliance_on_science/kpss/KPSS_2023.csv` | private value of patents | Kogan, Papanikolaou, Seru and Stoffman (2017), 2023 update | yes | 16, 33 |
| `PubMed2025/reliance_on_science/g_application.tsv` | application (filing) date of each patent | PatentsView | yes | 33 |
| `PubMed2025/reliance_on_science/comm_pot/consolidated_comm_pot_2026.dta` | commercial potential of each publication (version of 15 October 2026) | Masclans, Hasan and Cohen (2025): their release of August 2026, with scores that R. Masclans computed at the authors' request for the papers it lacks | provided by R. Masclans, without terms of use | 18, 33 |
| `PubMed2025/russet_book/russet_patents.dta` | drug- and device-related patents: the NBER Orange Book (editions 1985 to 2016), the FDA Orange Book (March 2024), patents of new drug applications, the patents associated with the therapeutic biologics approved by January 2025, and the USPTO's patent term extensions (through September 2026) | compiled by the authors from these sources; the patents on biologics are the issued patents of Frakes and Wasserman (2026), provided by M. Frakes and M. Wasserman (October 2026) | no (the sources are public, Frakes and Wasserman's once the NBER releases it) | 16, 33 |
| `CGAF/2019/r01_project/project/abstract_data/aux_files/mtimesh_single4pub.dta` | MeSH descriptors assigned to grant abstracts by the National Library of Medicine's Medical Text Indexer (MTI) | tagged by the authors with MTI's batch service in 2022 and 2024, from the NIH ExPORTER abstracts of FY1980 to 2020; NLM has since retired MTI, so the tags cannot be regenerated | no (derived from public data) | 11 |
| `data/cpiaucsl_fred.csv` (in this package) | consumer price index, all urban consumers, monthly, through August 2026 | FRED, series CPIAUCSL, downloaded 9 October 2026 | yes, included | 16, 33 |

### Data citations

- Arts, Sam, Nicola Melluso, and Reinhilde Veugelers (2025). "Beyond Citations: Measuring Novel Scientific Ideas and Their Impact in Publication Text." *Review of Economics and Statistics*, https://doi.org/10.1162/rest_a_01561. Data: the authors' public release, and the reuse of each new noun phrase by later papers, with their shared authors, provided by Nicola Melluso.
- Durvasula, Maya, C. Scott Hemphill, Lisa Larrimore Ouellette, Bhaven Sampat, and Heidi L. Williams (2023). "The NBER Orange Book Dataset: A User's Guide." *Research Policy* 52(7): 104791.
- Frakes, Michael D., and Melissa F. Wasserman (2026). "Unveiling the Patent Landscape of Biologic Drugs." *Northwestern University Law Review* 120(5): 1315-1374. Data: the patents associated with the therapeutic biologics approved by January 2025, provided by the authors.
- Kogan, Leonid, Dimitris Papanikolaou, Amit Seru, and Noah Stoffman (2017). "Technological Innovation, Resource Allocation, and Growth." *Quarterly Journal of Economics* 132(2): 665-712. Data: patent values, 2023 update.
- Lin, Jimmy, and W. John Wilbur (2007). "PubMed Related Articles: A Probabilistic Topic-Based Model for Content Similarity." *BMC Bioinformatics* 8: 423.
- Marx, Matt, and Aaron Fuegi (2020). "Reliance on Science: Worldwide Front-Page Patent Citations to Scientific Articles." *Strategic Management Journal* 41(9): 1572-1594; and (2022) "Reliance on Science by Inventors: Hybrid Extraction of In-Text Patent-to-Article Citations." *Journal of Economics and Management Strategy* 31(2): 369-392. Data: the 2026 release.
- Masclans, Roger, Sharique Hasan, and Wesley M. Cohen (2025). "Measuring the Commercial Potential of Science." *Strategic Management Journal* 46(9): 2199-2236.
- National Institutes of Health. RePORTER and ExPORTER: project, abstract, publication-link and patent files. https://reporter.nih.gov/exporter
- National Institutes of Health, Office of Budget. Biomedical Research and Development Price Index (BRDPI), latest version as of October 2026. https://officeofbudget.od.nih.gov/gbipriceindexes.html
- National Library of Medicine. PubMed baseline 2026 and update files, https://ftp.ncbi.nlm.nih.gov/pubmed/; Medical Subject Headings 2026, https://www.nlm.nih.gov/mesh/; E-utilities (related articles), https://www.ncbi.nlm.nih.gov/books/NBK25501/.
- OpenAlex (2026 snapshot). https://openalex.org
- PatentsView. Table g_application. https://patentsview.org
- Torvik, Vetle (2018). "Genni + Ethnea for the Author-ity 2009 dataset." Illinois Data Bank, https://doi.org/10.13012/B2IDB-9087546_V1.
- Torvik, Vetle, and Neil Smalheiser (2021). "Author-ity 2018: PubMed Author Name Disambiguated Dataset." Illinois Data Bank, https://doi.org/10.13012/B2IDB-2273402_V1.
- U.S. Bureau of Labor Statistics. Consumer Price Index for All Urban Consumers: All Items in U.S. City Average (CPIAUCSL), retrieved from FRED, Federal Reserve Bank of St. Louis, 9 October 2026.
- U.S. Food and Drug Administration. Orange Book data files (March 2024). U.S. Patent and Trademark Office. Patent terms extended under 35 U.S.C. 156 (September 2026).

## Dataset list

The build writes its intermediates to `${data}/build/`, the analysis file to `${data}/output/nih_risk_analysis.dta` (one row per cycle of the analysis sample, 123,018 rows), and the public analysis file to `data/nih_risk_public.dta` in the package, zipped as `data/nih_risk_public.zip`. `${data}` is set in `config.do`; it needs about 2 GB. Of these files, only the public analysis file is distributed (above); each is rebuilt by the program named below.

| file (under `${data}/`) | content | built by (`code/build/`) |
|---|---|---|
| `build/cycles.dta` | one row per grant cycle with a single PI on its starting award, keyed by the PI, the grant and the cycle: dates, renewal, sample flags, institute, study section, the PI's attributes | `01_cycles.do` |
| `build/am_successor.dta` | the grants of NIADDK (AM) linked to their successors at NIDDK (DK) or NIAMS (AR) across the 1986 split | `01_cycles.do` |
| `build/ackn_links_unchecked.dta`, `ackn_links.dta`, `cycle_paper_counts.dta` | links from grants to acknowledging papers, before and after the author check; counts by cycle | `02_ackn_links.do` |
| `build/cycle_papers.dta` | one row per cycle x paper: acknowledging papers and the investigator's other papers in the cycle's window | `03_cycle_papers.do` |
| `build/cycle_controls.dta` | investigator and institution controls, fixed-effect groups | `04_cycle_controls.do` |
| `build/paper_attributes.dta` | one row per paper: citation percentile, disruption percentile, journal impact factor, top-journal flag | `05_paper_attributes.do` |
| `build/cycle_output.dta` | the grant output controls | `06_cycle_output.do` |
| `build/risk_tails.dta` | extreme tail outcomes | `07_tails.do` |
| `build/risk_disruption.dta` | disruption | `08_disruption.do` |
| `build/risk_pivoting.dta` | pivoting, and its near and far parts | `09_pivoting.do` |
| `build/risk_pivoting_extras.dta`; `build/explore/mesh_nodes.dta`, `desc_nodes.dta`, `check_tags.dta`, `desc_distance.dta` | the parts and distance of pivoting; the MeSH tree's nodes and NLM's check tags | `10_pivoting_extras.do` |
| `build/abstract_pool.dta`, `abstract_tags.dta`, `mti_vocab.dta` | the applications funded in each institute x study section x year, their MeSH tags, the common vocabulary | `11_abstract_tags.do` |
| `build/risk_standout.dta` | standing out | `12_standing_out.do` |
| `build/novelty_mesh.dta`, `meshpair_birthyear.parquet`, `meshsingle_birthyear.parquet` | MeSH-pair novelty; the first year of every MeSH descriptor and pair in PubMed | `13_novelty_mesh.do`, `13_novelty_mesh.py` |
| `build/novelty_text.dta` | textual novelty of the cycle's papers | `14_novelty_text.do` |
| `build/proposal_pivot.dta` | pivoting in the application that starts the cycle | `15_proposal_pivot.do` |
| `build/cycle_patents.dta` | patent citations, drug and device patent citations, patent value | `16_patents.do` |
| `build/cycle_cites.dta` | five-year citations; the next cycle's papers | `17_cycle_cites.do` |
| `build/cycle_commpot.dta` | commercial potential of the cycle's papers | `18_commercial_potential.do` |
| `build/cycle_investigator.dta` | new investigators, honors, name frequency, NIH share of the investigator's papers | `19_investigator_flags.do` |
| `build/cycle_record.dta` | the investigator's record at the cycle's start | `20_record_before_cycle.do` |
| `build/cycle_concurrent.dta` | the investigator's other R01-equivalent grants | `21_concurrent_grants.do` |
| `build/cycle_breadth.dta`; `build/explore/breadth_*.dta` | breadth of the investigator's work before the cycle | `22_breadth.do` |
| `output/nih_risk_analysis.dta` | **the analysis file**: one row per cycle of the analysis sample (123,018) | `23_analysis_file.do` |
| `build/risk_windows.dta` | the measures on the early and late years of the cycle | `24_risk_windows.do` |
| `build/risk_lagged.dta` | the measures before the cycle | `25_lagged_risk.do` |
| `build/risk_fading.dta`; `build/explore/paper_vibrancy.dta` | vibrancy of the field the investigator leaves | `26_fading_fields.do` |
| `build/risk_tail_projects.dta` | the tail measure split between and within projects | `27_tail_projects.do` |
| `build/cycle_collabteam.dta` | distance of the team | `28_team_distance.do` |
| `build/risk_other.dta` | the measures on the investigator's other work | `29_other_work_risk.do` |
| `build/paper_disruption_versions.dta` | versions of the disruption index, by paper | `30_disruption_versions.do` |
| `build/risk_disruption_versions.dta` | versions and summaries of disruption, by cycle | `31_disruption_versions_cycle.do` |
| `build/risk_standout_extras.dta`; `build/explore/standout_examples.dta` | the parts of standing out, a placebo study section; the example of Appendix E | `32_standout_extras.do` |
| `build/cycle_windows.dta` | the outcomes of Tables 1e and 3, in the five years after the cycle's last payment | `33_outcome_windows.do` |
| `data/nih_risk_public.dta`, `.zip` (in the package) | **the public analysis file**: the variables the analysis uses, from the analysis file, the side files and two computed blocks, with generic identifiers (123,018 rows); the only file the analysis reads, and the only data file distributed | `34_public_file.do` |

## Computational requirements

### Software

- **StataNow 19.5 MP** (the do-files declare `version 19.5`). Community packages, all from SSC unless noted, with the versions used:
  - `reghdfe` 6.12.3 and `ftools` 2.49.1 (Correia)
  - `ppmlhdfe` 2.3.0 (Correia, Guimarães and Zylkin)
  - `gtools` 1.11.8 (Caceres Bravo): `gegen`, `gcollapse`, `gisid`, `gquantiles`, `gduplicates`, `gdistinct`, `gcontract`
  - `estout` 3.31 (Jann): `esttab`, `eststo`, `estadd`
  - `grstyle` 1.1.1 (Jann), with `palettes` and `colrspace`
  - `mylabels` (Cox), `distinct` (Cox), `unique`, `psacalc` 2.1 (Oster), `egenmore` (for `egen nvals()`)
  - `supermessoudar`, a short program that standardizes names for matching, is included in `code/programs/` and put on the adopath by `config.do`.
- **Python 3.13** with `duckdb` 1.5.4, `pandas` 3.0.3, `pyarrow` 25.0.0 and `numpy` 2.2.1. Stata's embedded Python (`python set exec`) must point to this interpreter, and `config.do` names it (`${python}`) for the one stage that runs as a separate process (`code/build/13_novelty_mesh.py`).
- **Inkscape** 1.4.2, which converts the figures from SVG to PDF (`code/programs/svg2pdf.py`), and the **CMU Sans Serif** font (Computer Modern Unicode), in which the figures are set. Inkscape substitutes another typeface, without a warning, when it does not find the font; `svg2pdf.py` therefore reads the fonts embedded in each PDF and stops the run with an error unless all are CMU Sans Serif. To check a figure by hand: `pdffonts output/figures/figure_1.pdf` (Poppler) lists only `CMUSansSerif` fonts.

### Controlled randomness

Two build stages draw at random, each with a fixed seed set just before the draw: `code/build/22_breadth.do` (`set seed 20261010`: at most 50 papers per investigator for breadth) and `code/build/32_standout_extras.do` (`set seed 20261013` and NumPy's `default_rng(20261013)`: the five placebo study sections of each cycle). No analysis do-file draws at random. The DuckDB steps that sum floating-point numbers with several threads (stages 10, 22 and 28) sum them as exact decimals, and stage 26 sorts explicitly before its means, so that no result depends on the order in which threads finish: a rerun reproduces every dataset and every exhibit exactly.

### Memory, storage and runtime

- The runs reported here used a desktop with an AMD Ryzen 9 5900XT (16 cores, 32 threads), 128 GB of memory, Windows 11 Pro, and local SSDs. `code/build/13_novelty_mesh.py` lets DuckDB use up to 90 GB of memory and 24 threads; the other DuckDB steps are capped at 5 to 32 GB (or run without a cap) and spill to the machine's temporary folder.
- The raw sources take about 60 GB (the largest: the disruption index, 15 GB; the PMRA neighbors, 15 GB; OpenAlex citations, 12 GB). The build writes about 2 GB to `${data}`, plus temporary files of up to 20 GB in the machine's temporary folder.
- Runtime, with one Stata process per do-file: the build took 104 minutes, one stage after another (63 minutes to the analysis file, 41 for the side files; table below); the analysis took 30 minutes with up to six do-files at once and the figure do-files one at a time, 110 minutes of Stata time in all, of which 17 for Table 3's four measures (about 5 minutes when they run at once, as `run_parallel.py` runs them). Inside one long Stata session, as `master.do` runs the package, the estimation commands run two to three times slower, for a reason not established, and the whole run takes about five hours; `logs/master.log` then gives each stage's runtime. Running each do-file in its own Stata process, in the order of `master.do`, gives the same datasets and exhibits. From the public analysis file, `master.do` as distributed (the analysis alone) took 1 hour 18 minutes in one Stata session.

## Description of programs

- `config.do`: the paths to the raw sources, the package's data root, Python and Inkscape. The only file to edit.
- `master.do`: runs every stage in order, with one switch per do-file; writes `logs/master.log` with the runtime of each stage.
- `code/build/`: the build, numbered in run order (table below). Stages 01 to 23 build the analysis file; stages 24 to 33 build the side files that some appendix exhibits read, after the analysis file; stage 34 gathers them into the public analysis file, with generic identifiers. Stage 22 reads the cycles and four variables it needs from the build files that stage 23 merges, since stage 23 merges its output.
- `code/analysis/`: one do-file per exhibit or group of exhibits, in the paper's order: 10 to 15 for the main text, 20 to 40 for Appendices A to L. Each reads the public analysis file alone and writes its exhibits to `output/`.
- `code/programs/`: `_spec.do` (the outcome, the measures, the control sets, the clustering, the options of esttab: the specification every exhibit shares), `_programs.do` (helpers: summary rows, the table formatter, figure export, significance marks), `format_table.py` (inserts the gutter columns and centers the row labels of a table fragment), `svg2pdf.py` (SVG to PDF with Inkscape), `run_parallel.py` (runs the four measures of Table 3 as four Stata processes at once), `supermessoudar.ado`.
- `output/tables/`: the table fragments (rows only, LaTeX, booktabs), one per printed table or, for Tables A3 and A4, one per measure; the paper supplies the tabular environment, the caption and the notes.
- `output/figures/`: the figures (PDF), one file per figure or, for four-panel figures, per panel (`_tails`, `_disr`, `_pivot`, `_so` for the four measures; Figures F1 and F2 by measure of novelty; Figure D1 by panel).

The build stages, with their runtimes on the machine described above (each stage in its own Stata process, one after another):

| stage | builds | minutes |
|---|---|---|
| `01_cycles.do` | the cycle file | 1.6 |
| `02_ackn_links.do` | acknowledgment links, author check | 2.9 |
| `03_cycle_papers.do` | papers attributed to cycles | 2.5 |
| `04_cycle_controls.do` | investigator and institution controls | 5.4 |
| `05_paper_attributes.do` | paper attributes (citations, disruption, impact factor) | 4.0 |
| `06_cycle_output.do` | output controls | 0.1 |
| `07_tails.do` | extreme tail outcomes | 0.1 |
| `08_disruption.do` | disruption | 0.1 |
| `09_pivoting.do` | pivoting | 3.5 |
| `10_pivoting_extras.do` | pivoting's parts and distance | 11.9 |
| `11_abstract_tags.do` | the pools of applications and their MeSH tags | 5.3 |
| `12_standing_out.do` | standing out | 1.4 |
| `13_novelty_mesh.do` | MeSH-pair novelty (Python) | 3.7 |
| `14_novelty_text.do` | textual novelty | 0.2 |
| `15_proposal_pivot.do` | pivoting in the proposal | 3.2 |
| `16_patents.do` | patent citations and value | 0.4 |
| `17_cycle_cites.do` | citations, next cycle | 0.1 |
| `18_commercial_potential.do` | commercial potential | 0.1 |
| `19_investigator_flags.do` | investigator flags | 1.1 |
| `20_record_before_cycle.do` | record before the cycle | 6.0 |
| `21_concurrent_grants.do` | concurrent grants | 0.1 |
| `22_breadth.do` | breadth | 8.9 |
| `23_analysis_file.do` | the analysis file | 0.1 |
| `24_risk_windows.do` | early and late windows | 4.0 |
| `25_lagged_risk.do` | lagged risk | 3.5 |
| `26_fading_fields.do` | fading fields (PMRA) | 5.3 |
| `27_tail_projects.do` | tail measure by project | 5.0 |
| `28_team_distance.do` | distance of the team | 7.1 |
| `29_other_work_risk.do` | risk of the other work | 3.9 |
| `30_disruption_versions.do` | versions of the disruption index | 5.3 |
| `31_disruption_versions_cycle.do` | the same, by cycle | 0.2 |
| `32_standout_extras.do` | standing out's parts | 5.5 |
| `33_outcome_windows.do` | outcomes after the cycle | 1.2 |
| `34_public_file.do` | the public analysis file | 0.1 |

## Building the data from the raw sources

To rebuild the public analysis file from the ground up, obtain the raw sources from the authors, then:

1. Install the software above. In Stata: `ssc install reghdfe`, `ftools`, `ppmlhdfe`, `gtools` (then `gtools, upgrade`), `estout`, `grstyle`, `palettes`, `colrspace`, `mylabels`, `distinct`, `unique`, `psacalc`, `egenmore`; then `python set exec <path to the Python 3.13 interpreter>, permanently`.
2. Obtain the raw sources (Data availability) and place them under one folder, keeping the relative paths of the table above.
3. Edit `config.do`, sections 1 to 3: `src` (the folder of the raw sources), `bulk` (the folder that holds `PubMed2026/parquet_merged/`), `data` (where the build may write), `python`, and `inkscape` if Inkscape is not on the PATH. In `master.do`, set `local build 1`.
4. Start Stata in this folder and run `do master.do`, or in batch: `stata-mp -b do master.do` (`StataMP-64.exe /e do master.do` on Windows). Every do-file expects Stata's working folder to be this one; if your `profile.do` changes the working folder at startup, run a two-line do-file instead, `cd "<this folder>"` then `do master.do`. To save time on Table 3, set the switches of its five runs to 0 in `master.do` and, after the rest, run them from this folder with the four measures at once: `python code/programs/run_parallel.py code/analysis/11_tables_1e_3.do --runs 1 2 3 4 --then 0 --stata <path to Stata>` (about 5 minutes instead of 17).
5. Each do-file writes its log to `logs/`. A stage reads only what earlier stages wrote, so after a full run any stage can be rerun alone from this folder, e.g. `do code/analysis/12_table_2.do`. The analysis do-files that save their estimates take a first argument of 0, which redraws their tables and figures from the saved estimates without estimating again (e.g. `do code/analysis/12_table_2.do 0`): 12, 13, 14, 25 to 31, 34, 35, 37 and 39.
6. Run the figure do-files (10, 13, 14, 15, 26, 27, 37 and 38) one at a time, as `master.do` does: run at the same time as one another, they can draw their figures at the wrong size.

## List of tables and programs

The exhibits are named for the numbers the paper prints. Every program is in `code/analysis/`.

| exhibit | title | file(s) in `output/tables/` or `output/figures/` | program in `code/analysis/` |
|---|---|---|---|
| Table 1a | Descriptive Statistics: Investigator Characteristics | `table_1a.tex` | `10_tables_1a_1d_figures_1_2.do` |
| Table 1b | Descriptive Statistics: Grant Cycle | `table_1b.tex` | `10_tables_1a_1d_figures_1_2.do` |
| Table 1c | Descriptive Statistics: Measures of Risk Taking and Novelty | `table_1c.tex` | `10_tables_1a_1d_figures_1_2.do` |
| Table 1d | Descriptive Statistics: Correlations across Measures of Risk Taking and Novelty | `table_1d.tex` | `10_tables_1a_1d_figures_1_2.do` |
| Table 1e | Descriptive Statistics: Downstream Outcomes of Renewed and Terminated Grant Cycles | `table_1e.tex` | `11_tables_1e_3.do` |
| Figure 1 | Distribution of Grant Cycle Publications by Renewal Status | `figure_1.pdf` | `10_tables_1a_1d_figures_1_2.do` |
| Figure 2 | Distribution of Risk-Taking Measures by Renewal Status | `figure_2_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `10_tables_1a_1d_figures_1_2.do` |
| Table 2 | Association of Risk Taking and Grant Renewal | `table_2.tex` | `12_table_2.do` |
| Figure 3 | Association of Risk Taking and Grant Renewal | `figure_3_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `13_figure_3.do` |
| Figure 4 | Association of Risk Taking and Novelty with Grant Renewal | `figure_4_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `14_figure_4_figures_F1_F2.do` |
| Figure 5 | The Penalty for Risk Taking and the Traits of the Investigator | `figure_5_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `15_figure_5_table_I1.do` |
| Table 3 | Risk Taking and the Downstream Outcomes of Renewed and Terminated Grant Cycles | `table_3.tex` | `11_tables_1e_3.do` |
| Table A1 | Cycles without an Acknowledging Publication | `table_A1.tex` | `20_table_A1.do` |
| Table A2 | Risk before the Cycle, for Cycles with and without an Acknowledging Publication | `table_A2.tex` | `21_table_A2.do` |
| Table A3 | The Penalty on a Sample Common to the Four Measures, and by Frequency of the Investigator's Name | `table_A3_*.tex` (`_tails`, `_disr`, `_pivot`, `_so`) | `22_tables_A3_A4.do` |
| Table A4 | The Penalty and the Investigator's Attachment to NIH Funding | `table_A4_*.tex` (`_tails`, `_disr`, `_pivot`, `_so`) | `22_tables_A3_A4.do` |
| Table B1 | Level and Spread of Citation Outcomes within the Grant Cycle | `table_B1.tex` | `23_table_B1.do` |
| Table B2 | Failed Bets and Slicing: The Lower Tail Between and Within Projects | `table_B2.tex` | `24_table_B2.do` |
| Table C1 | Versions of the Disruption Index and Grant Renewal | `table_C1.tex` | `25_tables_C1_C2.do` |
| Table C2 | What the Disruption Measure Picks Up, and How It Is Aggregated | `table_C2.tex` | `25_tables_C1_C2.do` |
| Table D1 | The Parts of the Pivoting Measure, and the Distance of the New Pairs | `table_D1.tex` | `26_tables_D1_D3_figure_D1.do` |
| Figure D1 | Near and Far Pivots and the Distance of the New Pairs, by Renewal Status | `figure_D1_near.pdf`, `figure_D1_far.pdf`, `figure_D1_dist.pdf` | `26_tables_D1_D3_figure_D1.do` |
| Table D2 | Near and Far Pivots and Grant Renewal | `table_D2.tex` | `26_tables_D1_D3_figure_D1.do` |
| Table D3 | How Much and How Far: The Distance of a Pivot and Grant Renewal | `table_D3.tex` | `26_tables_D1_D3_figure_D1.do` |
| Table D4 | Pivoting and the Vibrancy of the Field Left Behind | `table_D4.tex` | `27_table_D4_figure_D3.do` |
| Figure D3 | The Penalty on Pivoting, by Vibrancy of the Field Left Behind | `figure_D3.pdf` | `27_table_D4_figure_D3.do` |
| Table D5 | Pivots Proposed in the Application | `table_D5.tex` | `28_table_D5.do` |
| Table E1 | The Parts of the Standing Out Measure | `table_E1.tex` | `29_tables_E1_E4.do` |
| Table E2 | Where the Unique Pairs Are Found, and Grant Renewal | `table_E2.tex` | `29_tables_E1_E4.do` |
| Table E3 | Pivoting and the Section's Portfolio | `table_E3.tex` | `29_tables_E1_E4.do` |
| Table E4 | Standing Out against a Placebo Study Section | `table_E4.tex` | `29_tables_E1_E4.do` |
| Figure F1 | Four Measures of Novelty, by Renewal Status | `figure_F1_*.pdf` (`_phrfrac`, `_pairfrac`, `_semdist`, `_pcombfrac`) | `14_figure_4_figures_F1_F2.do` |
| Figure F2 | Novelty and Grant Renewal | `figure_F2_*.pdf` (the same four panels) | `14_figure_4_figures_F1_F2.do` |
| Table F1 | Novelty, Risk Taking, and Grant Renewal | `table_F1.tex` | `30_table_F1.do` |
| Table G1 | Risk Taking Early and Late in the Grant Cycle | `table_G1.tex` | `31_table_G1.do` |
| Table G2 | Renewal, the Cycle's Risk, and Risk Measured before the Cycle | `table_G2.tex` | `32_table_G2.do` |
| Table G3 | Persistence of Risk Taking across the Cycles of a Grant | `table_G3.tex` | `33_table_G3.do` |
| Table G4 | The Risk of the Grant's Work and of the Investigator's Other Work | `table_G4.tex` | `34_tables_G4_G5.do` |
| Table G5 | Renewal, the Risk of the Grant's Work, and the Risk of the Investigator's Other Work | `table_G5.tex` | `34_tables_G4_G5.do` |
| Table H1 | The Four Measures of Risk Taking in One Regression | `table_H1.tex` | `35_table_H1.do` |
| Table H2 | Unobserved Confounders: Oster's delta | `table_H2.tex` | `36_table_H2.do` |
| Table I1 | The Penalty for Risk Taking and the Traits of the Investigator | `table_I1.tex` | `15_figure_5_table_I1.do` |
| Figure J1 | The Distance of the Team, by Renewal Status | `figure_J1.pdf` | `37_figures_J1_J2_table_J1.do` |
| Figure J2 | Risk Taking, the Distance of the Team, and Grant Renewal | `figure_J2_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `37_figures_J1_J2_table_J1.do` |
| Table J1 | The Penalty for Risk Taking and the Distance of the Team | `table_J1.tex` | `37_figures_J1_J2_table_J1.do` |
| Figure K1 | The Penalty for Risk Taking by NIH Institute | `figure_K1_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `38_figures_K1_K2.do` |
| Figure K2 | The Penalty for Risk Taking over Time | `figure_K2_*.pdf` (`_tails`, `_disr`, `_pivot`, `_so`) | `38_figures_K1_K2.do` |
| Table K1 | The Penalty and the Scarcity of Money at the Institute | `table_K1.tex` | `39_table_K1.do` |
| Table L1 | Downstream Outcomes during the Grant Cycle and in the Five Years after Its Last Payment | `table_L1.tex` | `40_table_L1.do` |

The two diagrams of the appendices (Figures C1 and D2) are drawn in LaTeX and use no data.

## References

- Bornmann, Lutz, Sitaram Devarakonda, Alexander Tekles, and George Chacko (2020). "Are Disruption Index Indicators Convergently Valid? The Comparison of Several Indicator Variants with Assessments by Peers." *Quantitative Science Studies* 1(3): 1242-1259.
- Funk, Russell J., and Jason Owen-Smith (2017). "A Dynamic Network Measure of Technological Change." *Management Science* 63(3): 791-817.
- Oster, Emily (2019). "Unobservable Selection and Coefficient Stability: Theory and Evidence." *Journal of Business and Economic Statistics* 37(2): 187-204.
- Torvik, Vetle I., and Neil R. Smalheiser (2009). "Author Name Disambiguation in MEDLINE." *ACM Transactions on Knowledge Discovery from Data* 3(3): 11.
- Wu, Lingfei, Dashun Wang, and James A. Evans (2019). "Large Teams Develop and Small Teams Disrupt Science and Technology." *Nature* 566(7744): 378-382.
