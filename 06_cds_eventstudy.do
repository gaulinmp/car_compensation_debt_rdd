/*
06_cds_eventstudy.do
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Creates initial dataset for CDS event study.

--> Requires "cds_spreads.dta" in directory. Need to say where CDS data comes from (step 6 above)
--> Requires loading "duration_test_data_final_cov.dta" from step 4 above
--> Creates "filing_dates.dta" for CDS, bond and equity event studies
  --> NOTE: It is necessary to construct this file with "cds_eventstudy.do" to perform bond/equity event studies
--> Creates "cds_final.dta", the final analysis file for CDS event study
*/

capture cd "<Insert desired directory here>"

*** Clean CDS spread data - only needs to be run once, thus the conditional statement ***

// capture sets the return code, _rc, to a non-zero error code if the dataset does not exist to be loaded
capture use cds_spreads_cleaned, clear
if _rc { // If the file does not exist, create it
  use cds_spreads, clear

    bysort ticker date: gen dup=cond(_N==1,0,_n)
    tab dup

    local spreads "spread1y1 spread3y1 spread5y1 spread7y1 spread10y1 recovery1"
    foreach k of local spreads {
      bysort ticker date: egen a_`k' = mean(`k')
    }

    drop if dup>1
    drop dup

    gen fyear = year(date)

    local spreads "spread1y1 spread3y1 spread5y1 spread7y1 spread10y1 recovery1"
    foreach k of local spreads {
    bysort ticker fyear: egen aa_`k' = mean(`k')
    }

  save cds_spreads_cleaned, replace
}

// Load main analysis file
use "<insert directory here>/duration_test_data_final.dta", clear

capture drop _merge
keep gvkey permno packageid ticker filingdate drop raise dif_acct_short dif_horizon cov_viol fyear dist

* Prevent missing dates from creating duplicate removal noise (drop missing)
drop if filingdate==.
* Remove firm-filing-violation duplicates
bysort gvkey filingdate cov_viol: gen dup=cond(_N==1,0,_n)
drop if dup>1
drop dup

*Create filing date file for bond and equity event study. Make gvkey a string to match with bond data.
preserve
  gen gvkey2 = string(gvkey, "%06.0f")
  drop gvkey
  rename gvkey2 gvkey

  save filing_dates, replace
restore


***CREATE CDS DATA FILE

** Hand made changes to get more matches **
	gen ticker2=ticker

	replace ticker2 = "ABT"             if ticker=="ABT"
	replace ticker2 = "AGO-AGUS"        if ticker=="AGO"
	replace ticker2 = "FORTIS-Assur"    if ticker=="AIZ"
	replace ticker2 = "ACI-AWR"         if ticker=="ARCH"
	replace ticker2 = "AREE"            if ticker=="ARE"
	replace ticker2 = "CNX"             if ticker=="CEIX"
	replace ticker2 = "CKR"             if ticker=="CKR"
	replace ticker2 = "CNAFNL"          if ticker=="CNA"
	replace ticker2 = "CONRSI"          if ticker=="CXO"
	replace ticker2 = "DSF"             if ticker=="DFS"
	replace ticker2 = "DLRT-LP"         if ticker=="DLR"
	replace ticker2 = "EXPD"            if ticker=="EXPE"
	replace ticker2 = "GE-GNWTH"        if ticker=="GNW"
	replace ticker2 = "HE"              if ticker=="HE"
	replace ticker2 = "HUBBEL"          if ticker=="HUBB.K"
	replace ticker2 = "ALC"             if ticker=="JAH"
	replace ticker2 = "KMPRCOP"         if ticker=="KMPR"
	replace ticker2 = "QUSIR"           if ticker=="KWK"
	replace ticker2 = "LRY"             if ticker=="LPT"
	replace ticker2 = "LVSAND"          if ticker=="LVS"
	replace ticker2 = "MGIC"            if ticker=="MTG"
	replace ticker2 = "NXTL-NIIHdngInc" if ticker=="NIHD"
	replace ticker2 = "PACKAM"          if ticker=="PKG"
	replace ticker2 = "CHX"             if ticker=="PPC"
	replace ticker2 = "PRU"             if ticker=="PRU"
	replace ticker2 = "REG-LP"          if ticker=="REG"
	replace ticker2 = "RELALU"          if ticker=="RS"
	replace ticker2 = "SANEN"           if ticker=="SD"
	replace ticker2 = "SFI"             if ticker=="STAR.K"
	replace ticker2 = "TNIND"           if ticker=="TRN"
	replace ticker2 = "TUP"             if ticker=="TUP"
	replace ticker2 = "UDR"             if ticker=="UDR"
	replace ticker2 = "UNM"             if ticker=="UNM"
	replace ticker2 = "VTR"             if ticker=="VTRB"
	replace ticker2 = "YRCWWI"          if ticker=="YRCW"

rename ticker ticker_old
rename ticker2 ticker

capture drop _merge
joinby ticker using cds_spreads_cleaned

* Identify distance from filing date (analysis relies on same date returns but all included for reference)
gen date_dif = filingdate-date
drop if abs(date_dif)>10

* Remove firm, filing date, date, violation duplicates
bysort gvkey filingdate date cov_viol: gen dup=cond(_N==1,0,_n)
tab dup
drop if dup>1
drop dup

*Only keep violating firms
keep if cov_viol==1

*Remove firm-date duplicates
bysort gvkey date cov_viol: gen dup=cond(_N==1,0,_n)
tab dup
drop if dup>1
drop dup

bysort gvkey filingdate date_dif cov_viol: gen dup=cond(_N==1,0,_n)
tab dup
drop dup

*Set panel
egen id = group(gvkey filingdate cov_viol)
sort id date_dif
xtset id date_dif

*Create CDS daily returns
local spreads "spread1y1 spread3y1 spread5y1 spread7y1 spread10y1 recovery1"
	foreach k of local spreads {
	    sort id date_dif
		gen cds_ret_`k' = ln(`k'/L.`k')
	}

*Account for weekends
local spreads "spread1y1 spread3y1 spread5y1 spread7y1 spread10y1"
	foreach k of local spreads {
		sort id date_dif
		replace cds_ret_`k' = ln(`k'/L2.`k') if cds_ret_`k'==.
		replace cds_ret_`k' = ln(`k'/L3.`k') if cds_ret_`k'==.
		replace cds_ret_`k' = 0 if cds_ret_`k'==. & cds_ret_recovery1!=.
	}

	gen dist2 = dist^2
	gen dist3 = dist^3

	keep gvkey dist filingdate date_dif cov_viol fyear dist2 dist3 drop raise cds_ret_spread1y1 cds_ret_spread3y1 cds_ret_spread5y1 cds_ret_spread7y1 cds_ret_spread10y1

save cds_final, replace
