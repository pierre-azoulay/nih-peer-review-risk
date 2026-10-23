/* supermessoudar varlist: standardize names for matching. Each string
   variable is trimmed and lowercased; accented letters become their plain
   letters (ae and oe for the ligatures); periods, spaces, apostrophes and
   hyphens are removed. */
#delimit;
program supermessoudar;
	syntax [varlist(string)];
	foreach i of local varlist {;
		replace `i'=trim(lower(`i'));
		replace `i'=subinstr(`i',uchar(0232),"e",.); /* è */
		replace `i'=subinstr(`i',uchar(0233),"e",.); /* é */
		replace `i'=subinstr(`i',uchar(0235),"e",.); /* ë */
		replace `i'=subinstr(`i',uchar(0234),"e",.); /* ê */
		replace `i'=subinstr(`i',uchar(0226),"a",.); /* â */
		replace `i'=subinstr(`i',uchar(0227),"a",.); /* ã */
		replace `i'=subinstr(`i',uchar(0228),"a",.); /* ä */
		replace `i'=subinstr(`i',uchar(0229),"a",.); /* å */
		replace `i'=subinstr(`i',uchar(0225),"a",.); /* á */
		replace `i'=subinstr(`i',uchar(0224),"a",.); /* à */
		replace `i'=subinstr(`i',uchar(0249),"u",.); /* ù */
		replace `i'=subinstr(`i',uchar(0252),"u",.); /* ü */
		replace `i'=subinstr(`i',uchar(0251),"u",.); /* û */
		replace `i'=subinstr(`i',uchar(0250),"u",.); /* ú */
		replace `i'=subinstr(`i',uchar(0241),"n",.); /* ñ */
		replace `i'=subinstr(`i',uchar(0236),"i",.); /* ì */
		replace `i'=subinstr(`i',uchar(0237),"i",.); /* í */
		replace `i'=subinstr(`i',uchar(0238),"i",.); /* î */
		replace `i'=subinstr(`i',uchar(0239),"i",.); /* ï */
		replace `i'=subinstr(`i',uchar(0231),"c",.); /* ç */
		replace `i'=subinstr(`i',uchar(0230),"ae",.); /* æ */
		replace `i'=subinstr(`i',uchar(0339),"oe",.); /* œ */
		replace `i'=subinstr(`i',uchar(0242),"o",.); /* ò */
		replace `i'=subinstr(`i',uchar(0243),"o",.); /* ó */
		replace `i'=subinstr(`i',uchar(0244),"o",.); /* ô */
		replace `i'=subinstr(`i',uchar(0246),"o",.); /* ö */
		replace `i'=subinstr(`i',uchar(0248),"o",.); /* ø */
		replace `i'=subinstr(`i',uchar(0216),"O",.); /* Ø */
		replace `i'=subinstr(`i',".","",.);
		replace `i'=subinstr(`i'," ","",.);
		replace `i'=subinstr(`i',"'","",.);
		replace `i'=subinstr(`i',"-","",.);
	};
end;