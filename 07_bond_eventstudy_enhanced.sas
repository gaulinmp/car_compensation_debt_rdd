/*
07_bond_eventstudy_enhanced.do
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

--> Requires "filing_dates.dta" in directory (made by cds_eventstudy.do)
--> Requires WRDS link for Compustat-CRSP, CRSP-TRACE
--> Creates "bond_eventstudy.dta"
*/

libname link '<Insert path holding wrds link data here>';

* Import filing dates;
/* INPUT_DATASET: filing_dates.dta */
PROC IMPORT OUT = filing
        DATAFILE= "<Insert path>\filing_dates.dta"
        DBMS = STATA REPLACE;
RUN;

*Upload CRSP-COMPUSTAT link;
proc sql;
	create table filing as
	select a.*, b.lpermno as permno
	from filing as a left join link.crsp_comp_link as b
	on a.gvkey=b.gvkey;
quit;

*Upload CRSP-TRACE link;
proc sql;
	create table filing as
	select a.*, b.cusip
	from filing as a left join link.trace_crsp_link as b
	on a.permno=b.permno;
quit;

*Rsubmit code;

%let wrds=wrds.wharton.upenn.edu 4016;
options comamid=TCP remote=WRDS;
signon username=_prompt_;



rsubmit;

libname trace '/wrds/trace/sasdata/enhanced';
libname fisd '/wrds/mergent/sasdata/fisd';

*upload filing date file;
proc upload data=filing out=filing;
run;

* Collect data for 100-day window around filingdate;
proc sql;
	create table filing as
	select a.*, b.bond_sym_id, b.trd_exctn_dt, b.entrd_vol_qt as trade_size, b.rptd_pr as price
	from filing as a left join trace.trace_enhanced as b
	on a.cusip=b.cusip_id & a.filingdate+101>b.trd_exctn_dt & a.filingdate-101<b.trd_exctn_dt;
quit;

* Collect additional information on security;
proc sql;
	create table filing as
	select a.*, b.offering_amt, b.maturity as maturity_date, b.offering_date as fisd_date
	from filing as a left join fisd.fisd_mergedissue as b
	on a.cusip=b.complete_cusip;
quit;

proc download out=filing;
run;

endrsubmit;

* Remove missing obs;
data filing;
	set filing;
	if cusip="" then delete;
run;

* Remove small trades, annualize maturity of securities;
data filing;
	set filing;
	trade_amount = price*trade_size;
	maturity_days = maturity_date-trd_exctn_dt;
	if trade_amount<100000 then delete;
	maturity = .08;
	if maturity_days>60 & maturity<183 then maturity=.25;
	if maturity_days>182 & maturity<548 then maturity=1;
	if maturity_days>547 & maturity_days<913 then maturity =2;
	if maturity_days>912 & maturity_days<1460 then maturity =3;
	if maturity_days>1459 & maturity_days<2190 then maturity =5;
	if maturity_days>2189 & maturity_days<3102 then maturity =7;
	if maturity_days>3101 then maturity =10;
run;

/* OUTPUT: bond_eventstudy.dta */
proc export DATA=filing
			FILE="<Insert desired path here>\bond_eventstudy.dta"
			DBMS=STATA REPLACE;
run;
