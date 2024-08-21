/*
03_pull_variables.sas
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Creates compustat variables from a FUNDA pull from WRDS (compustat_annual.dta).

--> Requires Compustat Annual Fundamentals file downloaded from WRDS (compustat_annual.dta)
--> Creates "compustat_variables.dta"
*/


* Import compustat annual fundamental file;

proc import out= compm
		datafile = "<insert directory here>/compustat_annual.dta"
		DBMS = STATA REPLACE;
run;


* Pull compustat variables;
data comp(DROP=sgvkey);
	set compm(keep = gvkey datadate fyear act lct invt che cogs intan at lt xrd capx ppent ebitda ebit dltt dlc sale xint prcc_f csho pstkrv pstk txdb dcpstk dv prstkc wcap re pi bve mve);
	current_ratio= act/lct;
	pref_stock = pstk;
	if pref_stock = . then pref_stock = pstkrv;
	equitym = prcc_f*csho;
	book_equity = at-lt - pref_stock +txdb + (dcpstk-pref_stock);
	net_worth=at-lt;
	tang_net_worth=at-intan-lt;
	td = dltt+dlc;
	cover_ratio_1 = td/ebitda;
	cover_ratio_2 = td/ebitda;

    /* Z-score Private: 1.23 <--> 2.9 in grey zone */
	zscore_private =(0.717*wcap + 0.847*re + 3.107*pi + 0.998*sale)/at + (0.42*bve/lt);
    /* Z-score Public: 1.81 <--> 2.99 in grey zone */
	zscore_public  =(  1.2*wcap +   1.4*re +   3.3*pi + 0.999*sale)/at + (0.60*mve/lt);

	*Putting in missing as zero for r&d;
	if xrd=. then xrd=0;
	if dv=. then dv=0;
run;

* One year lag of variables;
data laga;
	set comp(keep = gvkey fyear at ppent che capx ebitda xrd invt cogs td sale xint current_ratio dv prstkc equitym zscore_private zscore_public ebit);
	rename at = lat;
	rename ppent = lppent;
	rename capx = lcapx;
	rename ebitda = lebitda;
	rename ebit=lebit;
	rename xrd = lxrd;
	rename che = lche;
	rename invt = linvt;
	rename cogs = lcogs;
	rename td = ltd;
	rename sale = lsale;
	rename xint = lxint;
	rename current_ratio = lcurrent_ratio;
	rename dv = ldv;
	rename prstkc = lprstkc;
	rename equitym = lequitym;
    rename zscore_private = lzscore_private;
    rename zscore_public = lzscore_public;
	fyear = fyear+1;
run;

* Two year lag of variables;
data llaga;
	set comp(keep = gvkey fyear at ppent che capx xrd invt cogs td current_ratio dv prstkc sale ebitda equitym zscore_private zscore_public ebit);
	rename at = llat;
	rename ppent = llppent;
	rename capx = llcapx;
	rename xrd = llxrd;
	rename che = llche;
	rename invt = llinvt;
	rename cogs = llcogs;
	rename td = lltd;
	rename current_ratio = llcurrent_ratio;
	rename dv = lldv;
	rename prstkc = llprstkc;
	rename sale = llsale;
	rename ebitda = llebitda;
	rename ebit = llebit;
	rename equitym = llequitym;
    rename zscore_private = llzscore_private;
    rename zscore_public = llzscore_public;
	fyear = fyear+2;
run;


*Future (1 year ahead) of variables;
data fcomp;
	set comp(keep = gvkey fyear capx xrd che ppent at ebitda invt cogs td sale dv prstkc zscore_private zscore_public);
	rename capx = fcapx;
	rename ppent = fppent;
	rename at = fat;
	rename ebitda = febitda;
	rename xrd = fxrd;
	rename che = fche;
	rename invt = finvt;
	rename cogs = fcogs;
	rename td = ftd;
	rename sale = fsale;
	rename dv = fdv;
	rename prstkc = fprstkc;
    rename zscore_private = fzscore_private;
    rename zscore_public = fzscore_public;
	fyear = fyear-1;
run;

*Future (2 years ahead) variables;
data ffcomp;
	set comp(keep = gvkey fyear capx xrd che invt cogs td sale dv prstkc);
	rename capx = ffcapx;
	rename xrd = ffxrd;
	rename che = ffche;
	rename invt = ffinvt;
	rename cogs = ffcogs;
	rename td = fftd;
	rename sale = ffsale;
	rename dv = ffdv;
	rename prstkc = ffprstkc;
	fyear = fyear-2;
run;



* Merge on lagged assets;
proc sql;
	create table comp as
	select INPUT(a.gvkey, 8.) AS gvkey, a.*, b.*, c.*, d.*, e.*
	from comp as a
    left join laga as b
	    on a.gvkey=b.gvkey & a.fyear=b.fyear
    left join llaga as c
	    on a.gvkey=c.gvkey & a.fyear=c.fyear
    left join fcomp as d
	    on a.gvkey=d.gvkey & a.fyear=d.fyear
    left join ffcomp as e
	on a.gvkey=e.gvkey & a.fyear=e.fyear;
quit;


/* OUTPUT: compustat_variables.dta */
proc export DATA=comp
			FILE="<insert directory here>/compustat_variables.dta"
			DBMS=STATA REPLACE;
run;
