/*
08_bond_eventstudy.do
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Process to get to the final analysis (event study)
	1.) Run cds_eventstudy.do to obtain filing_dates.dta
	2.) Run bond_eventstudy_enhanced.sas to match filing_dates with bond transaction and offering data
	3.) Run this do file, bond_eventstudy.do

	Data files:
		filing_dates.dta --> bond_eventstudy.dta --> bond_final.dta

	Data programs:
		cds_eventstudy.do --> bond_eventstudy_enhanced.sas --> bond_eventstudy

--> Requires "bond_eventstudy.dta" in directory
--> Requires "index_ret.dta" in directory; pulled from FRED database (see appendix 3 of paper)
--> Creates "bond_final.dta", the final analysis file for bond event study
*/


clear all
set more off

cd "<insert directory here>\Event Study"



***This runs the factor loadings. Uncomment to run factor loadings again (change settings)

use bond_eventstudy, clear

	rename *, lower

	** Create trade-size-weighted bond prices for each bond
	bysort gvkey filingdate cusip trd_exctn_dt: egen t_tradesize=total(trade_size)
	gen trade_ratio = trade_size/t_tradesize
	gen w_price = trade_ratio*price
	bysort gvkey filingdate cusip trd_exctn_dt: egen b_price = total(w_price)
	*Remove transaction-level data - now at cusip/day level
	bysort gvkey filingdate cusip trd_exctn_dt: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	drop dup w_price trade_ratio trade_amount price trade_size

	* Cusip-day level panel
	egen id = group(gvkey filingdate cusip)
	gen dif_date = filingdate-trd_exctn_dt
	sort id dif_date
	xtset id dif_date

	* Calculate returns - up to 6 day missing transactions
	gen bond_return = ln(b_price/L.b_price)
	replace bond_return = ln(b_price/L2.b_price) if bond_return==.
	replace bond_return = ln(b_price/L3.b_price) if bond_return==.
	replace bond_return = ln(b_price/L4.b_price) if bond_return==.
	replace bond_return = ln(b_price/L5.b_price) if bond_return==.
	replace bond_return = ln(b_price/L6.b_price) if bond_return==.

	rename trd_exctn_dt date

	joinby date using index_ret, unmatched(master)

	** Remove firms with insufficient data
	gen pre_date = 0
	replace pre_date = 1 if dif_date<-10
	bysort gvkey filingdate cusip: egen count = total(pre_date)
	drop if count<10


	*Calculate abnormal returns -
	sort cusip
	egen group = group(cusip)
	su group, meanonly

	gen ar = .

	forvalues i = 1/`r(max)' {
		capture reg bond_return ret_sg ret_ig if  group == `i' & dif_date<0
		predict y
		replace ar=bond_return-y if group==`i'
		capture drop y
		}

	drop if dif_date<0
	*Number of days in CAR
	local n "0"
	drop if dif_date>`n'
	*replace ar= bond_return-y

	** Bond-level CARs
	bysort gvkey filingdate cusip: egen car = total(ar)
	keep if dif_date==0

	**Aggregate to firm-level: value weighted abnorm. returns
	bysort gvkey filingdate: egen t_offer = total(offering_amt)
	gen offer_ratio = offering_amt/t_offer
	gen w_car = car*offer_ratio
	gen w_mat = maturity_days*offer_ratio
	bysort gvkey filingdate: egen abnorm_ret = total(w_car)
	bysort gvkey filingdate: egen bond_duration = total(w_mat)
	bysort gvkey filingdate: gen dup=cond(_N==1,0,_n)
	drop if dup>1

	replace bond_duration= bond_duration/365

	gen dist2 = dist^2
	gen dist3 = dist^3

save bond_final, replace
