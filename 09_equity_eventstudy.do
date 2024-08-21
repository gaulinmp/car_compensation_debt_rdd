/*
09_equity_eventstudy.do
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Creates final dataset for equity event study.

--> Requires "filing_dates.dta" in directory
--> Method involves use of WRDS event study tool
--> Creates "equity_final.dta", the final analysis file for equity event study
*/

cd "<Insert desired directory here>"

** STEP 1: Create set of firms and dates in proper text file format to put into WRDS event study

use filing_dates, clear

/* Create file for WRDS Event Study */
	keep if cov_viol==1
	bysort gvkey filingdate: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	keep filingdate gvkey permno drop
	format %tdCCYY-NN-DD filingdate
	bysort permno filingdate: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	gen date = filingdate

save firm_date_drop, replace

keep permno date
format %tdCCYY-NN-DD date
 format %5.0g permno
export delimited using "<Insert desired directory here>\firm_dates.txt", delimiter(tab) novarnames replace

** STEP 2: Run event study on WRDS, download data
	/*
	1. Run event study using firm_dates.txt
	2. Download event time results - file will include permno and date for merging (titled "equity_eventstudy.dta")
	*/

** Create final analysis file
use firm_date_drop, clear

	joinby permno date using equity_eventstudy
	keep if evttime==0

	bysort permno evtdate: egen car = total(abret)
	bysort permno evtdate: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	drop dup

	gen fyear = year(evtdate)
	keep permno evtdate car drop fyear

	joinby permno using gvkey_permno, unmatched(master)
	drop _merge
	bysort permno evtdate: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	drop dup
	rename evtdate filingdate

	joinby gvkey filingdate using event_study_final, unmatched(master)
	tab _merge

	keep permno gvkey filingdate fyear car drop dif_horizon dist
	bysort gvkey filingdate: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	drop dup

	gen dist2=dist^2
	gen dist3=dist^3


save equity_eventstudy_final, replace

erase firm_date_drop.dta
