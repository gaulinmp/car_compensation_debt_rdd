/*
02_clean_combine_IL.do
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Incentive Lab Composition Code

This code is intended to clean and combine the multiple datasets of Incentive Lab to form a panel of data at the executive-year level.

The code creates a file "incentivelab_master.dta" that is the master file of ceo/executive contract data.

The option to limit the sample to only CEOs or to all executives is above (global all_execs)

--> Requires Incentive Lab databases listed above
--> Creates "incentivelab_master.dta"
*/

capture cd "<insert directory here>"

/* 0 for only CEOs, 1 for all execs */
global all_execs 0


*** Load directory with datafiles from Incentive Lab ***


 global inclab_dir "<insert directory to Incentive Lab Data here>"



*** Company Identifier File ***
/* INPUT_DATASET: Data Creation/IncentiveLabAcademicDataSTATA/companyfy.dta */
use "${inclab_dir}/companyfy", clear
	sort cik fiscalyear

*** Remove duplicates: only 5 duplicates found (out of >20,000 obs)
	gsort cik fiscalyear fiscalmonth, mfirst
	by cik fiscalyear: gen dup=cond(_N==1,0,_n)
	tab dup
	drop if dup>1
	drop dup

*** Create Master file to hold cleaned data ***
tempfile incentivelab_master
save `incentivelab_master', replace

*** Merge Participants and Companies ***
use `incentivelab_master', clear
    /* INPUT_DATASET: Data Creation/IncentiveLabAcademicDataSTATA/participantfy.dta */
	joinby cik fiscalyear using "${inclab_dir}/participantfy", unmatched(none)
	sort cik participantid fiscalyear
save `incentivelab_master', replace

	/* The purpose of this section is to identify a specific subgroup
	and compile their compensation contracts.  */

	** Create CEO file **

	*** Check for "currentceo" errors

	sort cik participantid fiscalyear
	egen corpid = group(cik participantid)

	gsort corpid fiscalyear currentceo, mfirst
	by corpid fiscalyear: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	drop dup


	xtset corpid fiscalyear
	gen error = 0
	replace error = 1 if L.currentceo==1 & F.currentceo==1 & currentceo==0
	replace currentceo=1 if error==1

	** Use only CEOs by setting all_execs to 0 at the top of the file (can change to CFO if desired)
    if (!$all_execs) {
	    keep if currentceo==1
		*keep if currentcfo == 1
    }

	gen founder=0
	replace founder = 1 if rolecode1=="F"
	replace founder = 1 if rolecode2=="F"
	replace founder = 1 if rolecode3=="F"

save `incentivelab_master', replace

	keep cik fiscalyear title currentceo currentcfo
	rename fiscalyear fyear

tempfile title
save `title', replace

/* This section joins both absolute and relative performance goals and matches them to the grant file (gpbagrant).
	This appears to be the only way to match the performance goal data to specific participants in a firm */

	*** Remove duplicates - no duplicates
/* INPUT_DATASET: gpbagrant.dta */
use "${inclab_dir}/gpbagrant", clear
		sort grantid
		drop if grantid==.
		by grantid: gen dup=cond(_N==1,0,_n)
		tab dup
		drop if dup>1
		drop dup

	** Save overall grant file as temp to merge with specific goals
tempfile master2
save `master2', replace

/* INPUT_DATASET: gpbaabs.dta */
use "${inclab_dir}/gpbaabs", clear

	** duplicates - no duplicates across grantid, absid, and periodid
		sort grantid absid periodid
		by grantid absid periodid: gen dup=cond(_N==1,0,_n)
		tab dup
		drop dup

	** Append to relative performance data
        /* INPUT_DATASET: gpbarel.dta */
		append using "${inclab_dir}/gpbarel", force


	foreach x of varlist _all {
		rename `x' pm_`x'
	}

	rename pm_grantid grantid

tempfile master3
save `master3', replace


*Merge contracts onto the grant file
use `master2', clear

	joinby grantid using `master3', unmatched(master)

tempfile master4
save `master4', replace



**** Merge on performance goal data to CEO/Executive participant data

  use `incentivelab_master', clear

	joinby cik fiscalyear participantid using `master4'


*** Form the ratios of payout / performance metric types
		replace nonequitytarget = . if nonequitytarget==-9999
		replace grantdatefv = . if grantdatefv==-9999

		gen option_award = .
		replace option_award=1 if awardtype=="Option"
		replace option_award=1 if awardtype=="reloadOption"

		gen stock_award = .
		replace stock_award=1 if awardtype=="rsu"
		replace stock_award=1 if awardtype=="phantomStock"
		replace stock_award=1 if awardtype=="stock"
		replace stock_award=1 if awardtype=="sarEquity"

		gen cash_award = .
		replace cash_award=1 if awardtype == "sarCash"
		replace cash_award=1 if awardtype == "sarCash"
		replace cash_award=1 if awardtype == "cashShort"
		replace cash_award=1 if awardtype == "cashLong"
		replace cash_award=1 if awardtype=="unitCash"

		gen grant_ind = 0
		replace grant_ind = 1 if grantdatefv!=.

		gen noneq_ind = 0
		replace noneq_ind = 1 if nonequitytarget!=.

		tab grant_ind noneq_ind
		**(Not a whole lot of overlap - 570 obs)


	** Pay Horizon - Vesting and Performance Horizons
		gen gv_hor = .
		replace gv_hor = vesthighgrant if performancetype=="Time"
		replace gv_hor = .5*(vesthighgrant^2 - vestlowgrant^2 - vesthighgrant - vestlowgrant)/(vesthighgrant-vestlowgrant) if vestingschedule=="Ratable" & vestingunitlength=="M"
		replace gv_hor = 12*.5*((vesthighgrant/12)^2 - (vestlowgrant/12)^2 - (vesthighgrant/12) - (vestlowgrant/12))/((vesthighgrant/12)-(vestlowgrant/12)) if vestingschedule=="Ratable" & vestingunitlength=="Y"
		replace gv_hor = 6*.5*((vesthighgrant/6)^2 - (vestlowgrant/6)^2 - (vesthighgrant/6) - (vestlowgrant/6))/((vesthighgrant/6)-(vestlowgrant/6)) if vestingschedule=="Ratable" & vestingunitlength=="S"
		replace gv_hor = 3*.5*((vesthighgrant/3)^2 - (vestlowgrant/3)^2 - (vesthighgrant/3) - (vestlowgrant/3))/((vesthighgrant/3)-(vestlowgrant/3)) if vestingschedule=="Ratable" & vestingunitlength=="Q"


		gen gp_hor = .
		replace gp_hor = vesthigh if performancetype!="Time"
		replace gp_hor = .5*(vesthighgrant^2 - vestlowgrant^2 - vesthighgrant - vestlowgrant)/(vesthighgrant-vestlowgrant) if vestingschedule=="Ratable" & vestingunitlength=="M"
		replace gp_hor = 12*.5*((vesthighgrant/12)^2 - (vestlowgrant/12)^2 - (vesthighgrant/12) - (vestlowgrant/12))/((vesthighgrant/12)-(vestlowgrant/12)) if vestingschedule=="Ratable" & vestingunitlength=="Y"
		replace gp_hor = 6*.5*((vesthighgrant/6)^2 - (vestlowgrant/6)^2 - (vesthighgrant/6) - (vestlowgrant/6))/((vesthighgrant/6)-(vestlowgrant/6)) if vestingschedule=="Ratable" & vestingunitlength=="S"
		replace gp_hor = 3*.5*((vesthighgrant/3)^2 - (vestlowgrant/3)^2 - (vesthighgrant/3) - (vestlowgrant/3))/((vesthighgrant/3)-(vestlowgrant/3)) if vestingschedule=="Ratable" & vestingunitlength=="Q"


		gen gp_hor_cash = .
		replace gp_hor_cash = vesthigh if performancetype!="Time" & cash_award==1
		replace gp_hor_cash = .5*(vesthighgrant^2 - vestlowgrant^2 - vesthighgrant - vestlowgrant)/(vesthighgrant-vestlowgrant) if vestingschedule=="Ratable" & vestingunitlength=="M" & cash_award==1
		replace gp_hor_cash = 12*.5*((vesthighgrant/12)^2 - (vestlowgrant/12)^2 - (vesthighgrant/12) - (vestlowgrant/12))/((vesthighgrant/12)-(vestlowgrant/12)) if vestingschedule=="Ratable" & vestingunitlength=="Y" & cash_award==1
		replace gp_hor_cash = 6*.5*((vesthighgrant/6)^2 - (vestlowgrant/6)^2 - (vesthighgrant/6) - (vestlowgrant/6))/((vesthighgrant/6)-(vestlowgrant/6)) if vestingschedule=="Ratable" & vestingunitlength=="S" & cash_award==1
		replace gp_hor_cash = 3*.5*((vesthighgrant/3)^2 - (vestlowgrant/3)^2 - (vesthighgrant/3) - (vestlowgrant/3))/((vesthighgrant/3)-(vestlowgrant/3)) if vestingschedule=="Ratable" & vestingunitlength=="Q" & cash_award==1

	** Pay Horizon - Item specific Measures
		gen ai_option = option_award
		gen ai_stock = stock_award
		gen ai_cash = cash_award

		replace ai_option = 0 if ai_option==.
		replace ai_stock = 0 if ai_option ==.
		replace ai_cash = 0 if ai_cash ==.

		replace ai_option = vesthighgrant if ai_option==1 & performancetype=="Time"
		replace ai_stock = vesthighgrant if ai_stock==1 & performancetype=="Time"

	** Ruling out time-based awards
		gen noneq_time = .
		replace noneq_time = nonequitytarget if performancetype == "Time"
		gen grant_time = .
		replace grant_time = grantdatefv if performancetype == "Time"

		replace nonequitytarget =. if performancetype == "Time"
		replace grantdatefv =. if performancetype == "Time"

		gen time_award = .
		replace time_award = noneq_time if cash_award == 1
		replace time_award = grant_time if stock_award == 1
		replace time_award = grant_time if option_award == 1
		replace time_award = . if time_award < -9998

		gen time_option_award = .
		replace time_option_award = grant_time if option_award==1 & performancetype=="Time"
		gen time_stock_award = .
		replace time_stock_award = grant_time if stock_award==1 & performancetype=="Time"

		replace option_award=0 if performancetype == "Time"
		replace stock_award=0 if performancetype == "Time"
		replace cash_award=0 if performancetype == "Time"

	** Value of each award - depends on how it is paid (nonequitytarget or grantdatefv depending on award type)

		tab stock_award cash_award
		gen grant_award = .

		tab cash_award noneq_ind
		replace grant_award = nonequitytarget if cash_award==1

		tab stock_award grant_ind
		replace grant_award = grantdatefv if stock_award ==1

		tab option_award grant_ind
		replace grant_award = grantdatefv if option_award ==1

		replace grant_award =. if grant_award<-9998
		summ time_award, detail
		summ grant_award, detail

		gen grant_award_cash = .
		replace grant_award_cash = nonequitytarget if cash_award==1
		replace grant_award_cash =. if grant_award_cash<-9998


	** Performance Metric used for each award - will often be split between multiple metrics

		**First, group metrics into more generalized groups (i.e. income, accounting return, other etc)

		gen metric_stock = .
		replace metric_stock = 1 if pm_metrictype == "Stock Price"

		gen metric_acct = .
		replace metric_acct = 1 if pm_metrictype == "Accounting"

		gen metric_acct_short = .
		replace metric_acct_short =1 if pm_metrictype == "Accounting" & gp_hor<=12

		gen metric_acct_short_cash = .
		replace metric_acct_short_cash =1 if pm_metrictype == "Accounting" & gp_hor_cash<=12

		gen metric_acct_short_cash_no = .
		replace metric_acct_short_cash_no =1 if pm_metrictype == "Accounting" & gp_hor_cash<=12 &  option_award!=1

		gen metric_other = .
		replace metric_other = 1 if pm_metrictype=="Other"

		gen metric_cs = .
		replace metric_cs = 1 if pm_metric=="Customer Satisfaction"

		*Debt-related Incentives
		gen debt_related =  0
		replace debt_related = 1 if pm_metric=="Debt Related"
		replace debt_related =1 if strpos(pm_metricother, "debt") > 0
		replace debt_related = 1 if strpos(pm_metricother, "Debt") > 0

		** Accounting metric types

		**Sales
		gen accmetric_sale = .
		replace accmetric_sale = 1 if metric_acct == 1 & pm_metric == "Sales"

		**Accounting Return
		gen accmetric_return = .
		replace accmetric_return = 1 if metric_acct == 1 & pm_metric == "ROA"
		replace accmetric_return = 1 if metric_acct == 1 & pm_metric == "ROE"
		replace accmetric_return = 1 if metric_acct == 1 & pm_metric == "ROI"
		replace accmetric_return = 1 if metric_acct == 1 & pm_metric == "ROIC"

		**Other
		gen accmetric_other = .
		replace accmetric_other = 1 if metric_acct == 1 & pm_metric == "Other"
		replace accmetric_other = 1 if metric_acct == 1 & pm_metric == "Cashflow"
		replace accmetric_other = 1 if metric_acct == 1 & pm_metric == "FFO"
		replace accmetric_other = 1 if metric_acct == 1 & pm_metric == "Profit Margin"
		**(Note that cash flows and profit margin are included in other, and that "vague" is not included)

		**Income
		gen accmetric_income = .
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "EBIT"
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "EPS"
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "EBITDA"
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "EBT"
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "EVA"
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "Earnings"
		replace accmetric_income = 1 if metric_acct == 1 & pm_metric == "Operating Income"

		** Cashflows
		gen accmetric_cashflow = .
		*replace accmetric_cashflow = 1 if pm_metric == "EBITDA"
		replace accmetric_cashflow = 1 if pm_metric == "Cashflow"
		replace accmetric_cashflow = 1 if pm_metric == "Other" & strpos(pm_metricother, "ash")>0

		** Qualitative Identifier
		gen acc_type = ""
		replace acc_type = "Sales" if accmetric_sale==1
		replace acc_type = "Return" if accmetric_return==1
		replace acc_type = "Other" if accmetric_other==1
		replace acc_type = "Income" if accmetric_income==1
		replace acc_type = "Cashflow" if accmetric_cashflow==1

		** Creditor Friendly Acct
		gen cf_metric1 = .
		replace cf_metric1 = 1 if metric_acct == 1 & pm_metric == "Cashflow"

		gen cf_metric1_short = .
		replace cf_metric1_short = 1 if metric_acct==1 & pm_metric=="Cashflow" & gp_hor<=12

		gen cf_metric2 = .
		replace cf_metric2 = 1 if metric_acct == 1 & pm_metric == "Cashflow"
		replace cf_metric2 = 1 if metric_acct == 1 & pm_metric == "EBITDA"

		gen cf_metric3 = .
		replace cf_metric3 = 1 if metric_acct == 1 & pm_metric == "Cashflow"
		replace cf_metric3 = 1 if metric_acct == 1 & pm_metric == "EBITDA"
		replace cf_metric3 = 1 if metric_acct == 1 & pm_metric == "Operating Income"



	*** Distribution of awards

	** Grant totals for each metric type:

		bysort grantid: egen total_stock = total(metric_stock)
		bysort grantid: egen total_acct = total(metric_acct)
		bysort grantid: egen total_acct_short = total(metric_acct_short)
		bysort grantid: egen total_acct_short_no = total(metric_acct_short_cash_no)
		bysort grantid: egen total_other = total(metric_other)
		bysort grantid: egen total_cs = total(metric_cs)

		bysort grantid: egen total_acc_other = total(accmetric_other)
		bysort grantid: egen total_acc_income = total(accmetric_income)
		bysort grantid: egen total_acc_return = total(accmetric_return)
		bysort grantid: egen total_acc_sale = total(accmetric_sale)
		bysort grantid: egen total_acc_cashflow = total(accmetric_cashflow)

		bysort grantid: egen total_cf_metric1 = total(cf_metric1)
		bysort grantid: egen total_cf_metric2 = total(cf_metric2)
		bysort grantid: egen total_cf_metric3 = total(cf_metric3)
		bysort grantid: egen total_cf_metric1_short = total(cf_metric1_short)

		bysort grantid: egen gav_hor = mean(gv_hor)
		bysort grantid: egen gap_hor = mean(gp_hor)
		bysort grantid: egen gap_hor_cash = mean(gp_hor_cash)

		bysort grantid: egen gai_option = mean(ai_option)
		bysort grantid: egen gai_stock = mean(ai_stock)

		bysort grantid: egen gtime_option_award = total(time_option_award)
		bysort grantid: egen gtime_stock_award = total(time_stock_award)

		*Debt-related goals
		bysort grantid: egen gdebt_related = total(debt_related)
		capture drop debt_related

		** Goal targets, minimums, and maximums

		gen sale_tv = .
		replace sale_tv = pm_metrictargetvalue/1000000 if pm_metric=="Sales"
		replace sale_tv = pm_goaltarget/1000000 if pm_metric=="Sales" & pm_metrictargetvalue<0
		replace sale_tv = pm_goaltarget/1000000 if pm_metric=="Sales" & pm_metrictargetvalue==.
		replace sale_tv =. if sale_tv <0

		gen sale_min = .
		replace sale_min = pm_goalthreshold/1000000 if pm_metric=="Sales"
		replace sale_min = . if sale_min<0

		gen earn1_tvs = .
		replace earn1_tvs = pm_metrictargetvalue/1000000 if pm_metric=="EBITDA" & vesthigh<13
		replace earn1_tvs = pm_goaltarget/1000000 if pm_metric=="EBITDA" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn1_tvs = pm_goaltarget/1000000 if pm_metric=="EBITDA" & pm_metrictargetvalue==. & vesthigh<13
		replace earn1_tvs = . if earn1_tvs<0
		gen earn2_tvs = .
		replace earn2_tvs = pm_metrictargetvalue/1000000 if pm_metric=="EBIT" & vesthigh<13
		replace earn2_tvs = pm_goaltarget/1000000 if pm_metric=="EBIT" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn2_tvs = pm_goaltarget/1000000 if pm_metric=="EBIT" & pm_metrictargetvalue==. & vesthigh<13
		replace earn2_tvs = . if earn2_tvs<0
		gen earn3_tvs = .
		replace earn3_tvs = pm_metrictargetvalue/1000000 if pm_metric=="EBT" & vesthigh<13
		replace earn3_tvs = pm_goaltarget/1000000 if pm_metric=="EBT" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn3_tvs = pm_goaltarget/1000000 if pm_metric=="EBT" & pm_metrictargetvalue==. & vesthigh<13
		replace earn3_tvs = . if earn3_tvs<0
		gen earn4_tvs = .
		replace earn4_tvs = pm_metrictargetvalue/1000000 if pm_metric=="Earnings" & vesthigh<13
		replace earn4_tvs = pm_goaltarget/1000000 if pm_metric=="Earnings" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn4_tvs = pm_goaltarget/1000000 if pm_metric=="Earnings" & pm_metrictargetvalue==. & vesthigh<13
		replace earn4_tvs = . if earn4_tvs<0
		gen earn5_tvs = .
		replace earn5_tvs = pm_metrictargetvalue/1000000 if pm_metric=="EVA" & vesthigh<13
		replace earn5_tvs = pm_goaltarget/1000000 if pm_metric=="EVA" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn5_tvs = pm_goaltarget/1000000 if pm_metric=="EVA" & pm_metrictargetvalue==. & vesthigh<13
		replace earn5_tvs = . if earn5_tvs<0
		gen earn6_tvs = .
		replace earn6_tvs = pm_metrictargetvalue/1000000 if pm_metric=="Operating Income" & vesthigh<13
		replace earn6_tvs = pm_goaltarget/1000000 if pm_metric=="Operating Income" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn6_tvs = pm_goaltarget/1000000 if pm_metric=="Operating Income" & pm_metrictargetvalue==. & vesthigh<13
		replace earn6_tvs = . if earn6_tvs<0
		gen earn7_tvs = .
		replace earn7_tvs = pm_metrictargetvalue if pm_metric=="EPS" & vesthigh<13
		replace earn7_tvs = pm_goaltarget if pm_metric=="EPS" & pm_metrictargetvalue<0 & vesthigh<13
		replace earn7_tvs = pm_goaltarget if pm_metric=="EPS" & pm_metrictargetvalue==. & vesthigh<13
		replace earn7_tvs = . if earn7_tvs<0

		gen earn1_tv = .
		replace earn1_tv = pm_metrictargetvalue/1000000 if pm_metric=="EBITDA"
		replace earn1_tv = pm_goaltarget/1000000 if pm_metric=="EBITDA" & pm_metrictargetvalue<0
		replace earn1_tv = pm_goaltarget/1000000 if pm_metric=="EBITDA" & pm_metrictargetvalue==.
		replace earn1_tv = . if earn1_tv<0
		gen earn2_tv = .
		replace earn2_tv = pm_metrictargetvalue/1000000 if pm_metric=="EBIT"
		replace earn2_tv = pm_goaltarget/1000000 if pm_metric=="EBIT" & pm_metrictargetvalue<0
		replace earn2_tv = pm_goaltarget/1000000 if pm_metric=="EBIT" & pm_metrictargetvalue==.
		replace earn2_tv = . if earn2_tv<0
		gen earn3_tv = .
		replace earn3_tv = pm_metrictargetvalue/1000000 if pm_metric=="EBT"
		replace earn3_tv = pm_goaltarget/1000000 if pm_metric=="EBT" & pm_metrictargetvalue<0
		replace earn3_tv = pm_goaltarget/1000000 if pm_metric=="EBT" & pm_metrictargetvalue==.
		replace earn3_tv = . if earn3_tv<0
		gen earn4_tv = .
		replace earn4_tv = pm_metrictargetvalue/1000000 if pm_metric=="Earnings"
		replace earn4_tv = pm_goaltarget/1000000 if pm_metric=="Earnings" & pm_metrictargetvalue<0
		replace earn4_tv = pm_goaltarget/1000000 if pm_metric=="Earnings" & pm_metrictargetvalue==.
		replace earn4_tv = . if earn4_tv<0
		gen earn5_tv = .
		replace earn5_tv = pm_metrictargetvalue/1000000 if pm_metric=="EVA"
		replace earn5_tv = pm_goaltarget/1000000 if pm_metric=="EVA" & pm_metrictargetvalue<0
		replace earn5_tv = pm_goaltarget/1000000 if pm_metric=="EVA" & pm_metrictargetvalue==.
		replace earn5_tv = . if earn5_tv<0
		gen earn6_tv = .
		replace earn6_tv = pm_metrictargetvalue/1000000 if pm_metric=="Operating Income"
		replace earn6_tv = pm_goaltarget/1000000 if pm_metric=="Operating Income" & pm_metrictargetvalue<0
		replace earn6_tv = pm_goaltarget/1000000 if pm_metric=="Operating Income" & pm_metrictargetvalue==.
		replace earn6_tv = . if earn6_tv<0
		gen earn7_tv = .
		replace earn7_tv = pm_metrictargetvalue if pm_metric=="EPS"
		replace earn7_tv = pm_goaltarget if pm_metric=="EPS" & pm_metrictargetvalue<0
		replace earn7_tv = pm_goaltarget if pm_metric=="EPS" & pm_metrictargetvalue==.
		replace earn7_tv = . if earn7_tv<0

		gen earn1_min = .
		replace earn1_min = pm_goalthreshold/1000000 if pm_metric=="EBITDA"
		replace earn1_min = . if earn1_min<0
		gen earn2_min = .
		replace earn2_min = pm_goalthreshold/1000000 if pm_metric=="EBIT"
		replace earn2_min = . if earn2_min<0
		gen earn3_min = .
		replace earn3_min = pm_goalthreshold/1000000 if pm_metric=="EBT"
		replace earn3_min = . if earn3_min<0
		gen earn4_min = .
		replace earn4_min = pm_goalthreshold/1000000 if pm_metric=="Earnings"
		replace earn4_min = . if earn4_min<0
		gen earn5_min = .
		replace earn5_min = pm_goalthreshold/1000000 if pm_metric=="EVA"
		replace earn5_min = . if earn5_min<0
		gen earn6_min = .
		replace earn6_min = pm_goalthreshold/1000000 if pm_metric=="Operating Income"
		replace earn6_min = . if earn6_min<0
		gen earn7_min = .
		replace earn7_min = pm_goalthreshold if pm_metric=="EPS"
		replace earn7_min = . if earn7_min<0

		gen earn1_mins = .
		replace earn1_mins = pm_goalthreshold/1000000 if pm_metric=="EBITDA" & vesthigh<13
		replace earn1_mins = . if earn1_mins<0
		gen earn2_mins = .
		replace earn2_mins = pm_goalthreshold/1000000 if pm_metric=="EBIT" & vesthigh<13
		replace earn2_mins = . if earn2_mins<0
		gen earn3_mins = .
		replace earn3_mins = pm_goalthreshold/1000000 if pm_metric=="EBT" & vesthigh<13
		replace earn3_mins = . if earn3_mins<0
		gen earn4_mins = .
		replace earn4_mins = pm_goalthreshold/1000000 if pm_metric=="Earnings" & vesthigh<13
		replace earn4_mins = . if earn4_mins<0
		gen earn5_mins = .
		replace earn5_mins = pm_goalthreshold/1000000 if pm_metric=="EVA" & vesthigh<13
		replace earn5_mins = . if earn5_mins<0
		gen earn6_mins = .
		replace earn6_mins = pm_goalthreshold/1000000 if pm_metric=="Operating Income" & vesthigh<13
		replace earn6_mins = . if earn6_mins<0
		gen earn7_mins = .
		replace earn7_mins = pm_goalthreshold if pm_metric=="EPS" & vesthigh<13
		replace earn7_mins = . if earn7_mins<0

		gen earn1_min2 = .
		replace earn1_min2 = pm_goalmax/1000000 if pm_metric=="EBITDA"
		replace earn1_min2 = . if earn1_min2<0
		gen earn2_min2 = .
		replace earn2_min2 = pm_goalmax/1000000 if pm_metric=="EBIT"
		replace earn2_min2 = . if earn2_min2<0
		gen earn3_min2 = .
		replace earn3_min2= pm_goalmax/1000000 if pm_metric=="EBT"
		replace earn3_min2 = . if earn3_min2<0
		gen earn4_min2 = .
		replace earn4_min2 = pm_goalmax/1000000 if pm_metric=="Earnings"
		replace earn4_min2 = . if earn4_min2<0
		gen earn5_min2= .
		replace earn5_min2= pm_goalmax/1000000 if pm_metric=="EVA"
		replace earn5_min2 = . if earn5_min2<0
		gen earn6_min2 = .
		replace earn6_min2 = pm_goalmax/1000000 if pm_metric=="Operating Income"
		replace earn6_min2 = . if earn6_min2<0
		gen earn7_min2 = .
		replace earn7_min2 = pm_goalmax if pm_metric=="EPS"
		replace earn7_min2 = . if earn7_min2<0

		gen earn1_min2s = .
		replace earn1_min2s = pm_goalmax/1000000 if pm_metric=="EBITDA" & vesthigh<13
		replace earn1_min2s = . if earn1_min2s<0
		gen earn2_min2s = .
		replace earn2_min2s = pm_goalmax/1000000 if pm_metric=="EBIT" & vesthigh<13
		replace earn2_min2s = . if earn2_min2s<0
		gen earn3_min2s = .
		replace earn3_min2s= pm_goalmax/1000000 if pm_metric=="EBT" & vesthigh<13
		replace earn3_min2s = . if earn3_min2s<0
		gen earn4_min2s = .
		replace earn4_min2s = pm_goalmax/1000000 if pm_metric=="Earnings" & vesthigh<13
		replace earn4_min2s = . if earn4_min2s<0
		gen earn5_min2s= .
		replace earn5_min2s= pm_goalmax/1000000 if pm_metric=="EVA" & vesthigh<13
		replace earn5_min2s = . if earn5_min2s<0
		gen earn6_min2s = .
		replace earn6_min2s = pm_goalmax/1000000 if pm_metric=="Operating Income" & vesthigh<13
		replace earn6_min2s = . if earn6_min2s<0
		gen earn7_min2s = .
		replace earn7_min2s = pm_goalmax if pm_metric=="EPS" & vesthigh<13
		replace earn7_min2s = . if earn7_min2s<0


		forvalue k=1/7 {
			bysort cik fiscalyear: egen earn`k'_tvm = max(earn`k'_tv)
			winsor2 earn`k'_tvm, replace cuts(1,99)
			label variable earn`k'_tvm "Earnings Target"
			}

		forvalue k=1/7 {
			bysort cik fiscalyear: egen earn`k'_tvms = max(earn`k'_tvs)
			winsor2 earn`k'_tvms, replace cuts(1,99)
			label variable earn`k'_tvms "Earnings Target Short"
			}

		forvalue k=1/7 {
			bysort cik fiscalyear: egen earn`k'_minms = max(earn`k'_mins)
			winsor2 earn`k'_minms, replace cuts(1,99)
			label variable earn`k'_minms "Earnings Min Short"
			}

		forvalue k=1/7 {
			bysort cik fiscalyear: egen earn`k'_maxms = max(earn`k'_min2s)
			winsor2 earn`k'_maxms, replace cuts(1,99)
			label variable earn`k'_maxms "Earnings Max Short"
			}

		forvalue k=1/7 {
			bysort cik fiscalyear: egen earn`k'_minm = min(earn`k'_min)
			winsor2 earn`k'_minm, replace cuts(1,99)
			label variable earn`k'_minm "Earnings Min"
			}

			forvalue k=1/7 {
			bysort cik fiscalyear: egen earn`k'_maxm = max(earn`k'_min2)
			winsor2 earn`k'_min2, replace cuts(1,99)
			label variable earn`k'_maxm "Earnings Max"
			}

			bysort cik fiscalyear: egen sale_tvm = max(sale_tv)
			bysort cik fiscalyear: egen sale_tvms = max(sale_min)
			winsor2 sale_tvm, replace cuts(1,99)
			winsor2 sale_tvms, replace cuts(1,99)

		forvalue k=1/7 {
			drop earn`k'_tv earn`k'_min earn`k'_min2 earn`k'_tvs earn`k'_mins earn`k'_min2s
			}


	**Grant-level amounts and weights
		bysort grantid: gen total_count = _n
		bysort grantid: egen max_count = max(total_count)
		drop total_count


		gen stock_weight = total_stock / max_count
		gen acct_weight = total_acct / max_count
		gen acct_short_weight = total_acct_short / max_count
		gen acct_short_weight_no = total_acct_short_no / max_count
		gen other_weight = total_other / max_count
		gen cs_weight = total_cs / max_count
		gen cashflow_weight = total_acc_cashflow/ max_count

		gen cf_weight1 = total_cf_metric1/ max_count
		gen cf_weight1_short = total_cf_metric1_short/max_count
		gen cf_weight2 = total_cf_metric2/ max_count
		gen cf_weight3 = total_cf_metric3/ max_count

		gen stock_award_t = stock_weight*grant_award
		gen acct_award_t = acct_weight*grant_award
		gen acct_short_award_t = acct_short_weight*grant_award
		gen acct_short_award_t_no = acct_short_weight_no*grant_award
		gen other_award_t = other_weight*grant_award
		gen cs_award_t = cs_weight*grant_award
		gen cashflow_award_t = cashflow_weight*grant_award

		replace cash_award=0 if cash_award==.
		replace option_award=0 if option_award==.
		replace stock_award=0 if stock_award==.
		gen acct_award_c = acct_weight*grant_award*cash_award

		gen cf_award1 = cf_weight1*grant_award
		gen cf_award1_short = cf_weight1_short*grant_award
		gen cf_award2 = cf_weight2*grant_award
		gen cf_award3 = cf_weight3*grant_award

		gen acc_other_weight = total_acc_other / total_acct
		gen acc_income_weight = total_acc_income / total_acct
		gen acc_return_weight = total_acc_return / total_acct
		gen acc_sale_weight = total_acc_sale / total_acct

		gen acc_cf_weight1 = total_cf_metric1 / total_acct
		gen acc_cf_weight2 = total_cf_metric2 / total_acct
		gen acc_cf_weight3 = total_cf_metric3 / total_acct
		gen acc_cf_weight1_short = total_cf_metric1_short / total_acct

		*
		gen acc_other_award = acc_other_weight*acct_weight*grant_award
		gen acc_income_award = acc_income_weight*acct_weight*grant_award
		gen acc_return_award = acc_return_weight*acct_weight*grant_award
		gen acc_sale_award = acc_sale_weight*acct_weight*grant_award

		gen acc_cf_award1 = acc_cf_weight1*acct_weight*grant_award
		gen acc_cf_award2 = acc_cf_weight2*acct_weight*grant_award
		gen acc_cf_award3 = acc_cf_weight3*acct_weight*grant_award
		gen acc_cf_award1_short = acc_cf_weight1_short*acct_weight*grant_award

		gen o_award = .
		gen rsu_award = .
		gen c_award = .
		replace o_award = grant_award if option_award==1
		replace rsu_award = grant_award if stock_award==1
		replace c_award = grant_award if cash_award==1


		** Sort variables of interest
		gsort grantid cf_award1 cf_award2 cf_award3 acc_cf_award1 acc_cf_award2 acc_cf_award3 cs_award_t o_award rsu_award c_ award gav_hor gap_hor gap_hor_cash earn1_tvm earn2_tvm earn3_tvm earn4_tvm earn5_tvm earn6_tvm earn7_tvm earn1_minm earn2_minm earn3_minm earn4_minm earn5_minm earn6_minm earn7_minm earn1_maxm earn2_maxm earn3_maxm earn4_maxm earn5_maxm earn6_maxm earn7_maxm cik fiscalyear ticker companyname cusip  fiscalmonth type fiscalyearend filingdate meetingdate splitadjustmentfactor businessstreet businesscity businessstate businesszip mailingstreet mailingcity mailingstate mailingzip participantcik fullname prefix firstname middlename lastname suffix title rolecode1 rolecode2 rolecode3 rolecode4 currentceo currentcfo currentdirector age corpid error founder awardtype paidincash performancetype grantdate nonequitythreshold nonequitytarget nonequitymax equitythreshold equitytarget equitymax stockaward optionaward exerciseprice grantdatefv expirationdate numabsolute numaccelerated numrelative performancegrouping vestingschedule vestaftercontingency vestlowgrant vesthighgrant vestingunitlength isexchange grantdatefvinferred legacypercentoptions analystcomments _merge pm_absid pm_periodid pm_metrictype pm_metric pm_metricother pm_metrictargetoperand pm_metrictargetvalue pm_metricgrowthvalue pm_metricispershare pm_metricismargin pm_metricisgrowth pm_metricisbusgeo pm_percentvest pm_vestlow pm_vesthigh pm_onetimehit pm_payoutstructure pm_goalthreshold pm_goaltarget pm_goalmax pm_payoutthreshold pm_payouttarget pm_payoutmax pm_interpolationthreshold pm_interpolationtarget pm_interpolationmax pm_rollover pm_distribution1 pm_distribution2 pm_distribution3 pm_analystcomments pm_relid pm_relativebenchmark pm_relativebenchmarkother pm_comparemethod pm_comparemethodother option_award stock_award cash_award grant_ind noneq_ind noneq_time grant_time time_award grant_award metric_stock metric_acct metric_other accmetric_sale accmetric_other accmetric_return accmetric_income acc_type total_stock total_acct total_other total_acc_other total_acc_income total_acc_return total_acc_sale max_count stock_weight acct_weight other_weight stock_award_t acct_award_t other_award_t acc_other_weight acc_income_weight acc_return_weight acc_sale_weight acc_other_award acc_income_award acc_return_award acc_sale_award, mfirst
			by grantid: gen dup=cond(_N==1,0,_n)
			drop if dup>1
			drop dup
            /* duplicates drop grantid, force */


		gsort cik participantid fiscalyear cf_award1 cf_award2 cf_award3 acc_cf_award1 acc_cf_award2 acc_cf_award3 cs_award_t o_award rsu_award c_ award  gav_hor gap_hor gap_hor_cash earn1_tvm earn2_tvm earn3_tvm earn4_tvm earn5_tvm earn6_tvm earn7_tvm earn1_minm earn2_minm earn3_minm earn4_minm earn5_minm earn6_minm earn7_minm earn1_maxm earn2_maxm earn3_maxm earn4_maxm earn5_maxm earn6_maxm earn7_maxm ticker companyname cusip  fiscalmonth type fiscalyearend filingdate meetingdate splitadjustmentfactor businessstreet businesscity businessstate businesszip mailingstreet mailingcity mailingstate mailingzip participantcik fullname prefix firstname middlename lastname suffix title rolecode1 rolecode2 rolecode3 rolecode4 currentceo currentcfo currentdirector age corpid error founder grantid awardtype paidincash performancetype grantdate nonequitythreshold nonequitytarget nonequitymax equitythreshold equitytarget equitymax stockaward optionaward exerciseprice grantdatefv expirationdate numabsolute numaccelerated numrelative performancegrouping vestingschedule vestaftercontingency vestlowgrant vesthighgrant vestingunitlength isexchange grantdatefvinferred legacypercentoptions analystcomments _merge pm_absid pm_periodid pm_metrictype pm_metric pm_metricother pm_metrictargetoperand pm_metrictargetvalue pm_metricgrowthvalue pm_metricispershare pm_metricismargin pm_metricisgrowth pm_metricisbusgeo pm_percentvest pm_vestlow pm_vesthigh pm_onetimehit pm_payoutstructure pm_goalthreshold pm_goaltarget pm_goalmax pm_payoutthreshold pm_payouttarget pm_payoutmax pm_interpolationthreshold pm_interpolationtarget pm_interpolationmax pm_rollover pm_distribution1 pm_distribution2 pm_distribution3 pm_analystcomments pm_relid pm_relativebenchmark pm_relativebenchmarkother pm_comparemethod pm_comparemethodother option_award stock_award cash_award grant_ind noneq_ind noneq_time grant_time time_award grant_award metric_stock metric_acct metric_other accmetric_sale accmetric_other accmetric_return accmetric_income acc_type total_stock total_acct total_other total_acc_other total_acc_income total_acc_return total_acc_sale max_count stock_weight acct_weight other_weight stock_award_t acct_award_t other_award_t acc_other_weight acc_income_weight acc_return_weight acc_sale_weight acc_other_award acc_income_award acc_return_award acc_sale_award, mfirst


		*** Annual level amounts
		by cik participantid fiscalyear: egen a_grant_award = total(grant_award)
		by cik participantid fiscalyear: egen a_grant_award_cash = total(grant_award_cash)
		replace a_grant_award_cash = . if a_grant_award_cash==0
		by cik participantid fiscalyear: egen a_o_award = total(o_award)
		by cik participantid fiscalyear: egen a_rsu_award = total(rsu_award)
		by cik participantid fiscalyear: egen a_c_award = total(c_award)

		by cik participantid fiscalyear: egen a_stock_award = total(stock_award_t)
		by cik participantid fiscalyear: egen a_acct_award = total(acct_award_t)
		by cik participantid fiscalyear: egen a_acct_short_award = total(acct_short_award_t)
		by cik participantid fiscalyear: egen a_acct_short_award_no = total(acct_short_award_t_no)
		by cik participantid fiscalyear: egen a_cashflow_award = total(cashflow_award_t)
		by cik participantid fiscalyear: egen a_acct_award_c = total(acct_award_c)
		by cik participantid fiscalyear: egen a_other_award = total(other_award_t)
		by cik participantid fiscalyear: egen a_cs_award = total(cs_award_t)
		by cik participantid fiscalyear: egen a_acct_other_award = total(acc_other_award)
		by cik participantid fiscalyear: egen a_acct_income_award = total(acc_income_award)
		by cik participantid fiscalyear: egen a_acct_return_award = total(acc_return_award)
		by cik participantid fiscalyear: egen a_acct_sale_award = total(acc_sale_award)

		by cik participantid fiscalyear: egen a_time_award = total(time_award)

		by cik participantid fiscalyear: egen a_cf_award1 = total(cf_award1)
		by cik participantid fiscalyear: egen a_cf_award1_short = total(cf_award1_short)
		by cik participantid fiscalyear: egen a_cf_award2 = total(cf_award2)
		by cik participantid fiscalyear: egen a_cf_award3 = total(cf_award3)

		*Debt related goals
		by cik participantid fiscalyear: egen debt_related = total(gdebt_related)
		replace debt_related = 1 if debt_related!=0
		capture drop gdebt_related

		by cik participantid fiscalyear: egen a_time_option_award = total(gtime_option_award)
		by cik participantid fiscalyear: egen a_time_stock_award = total(gtime_stock_award)

		** Weight Durations
        /* Weighted durations is SUM (weight_i * value_i) / TOTAL WEIGHT
        For equal weight, that's just 1 per, divided by SUM (1 per) = N, or the mean */
        /* Step 1: Weight horizons by award / total award (a_*_award is total) */
		gen gavf_hor = .
		gen gapf_hor = .
		gen gapf_hor_cash = .
		replace gavf_hor = gav_hor*(time_award/a_time_award) if time_award!=.
		replace gapf_hor = gap_hor*(grant_award/a_grant_award) if grant_award!=.
		replace gapf_hor_cash = gap_hor_cash*(grant_award_cash/a_grant_award_cash) if grant_award_cash!=.

		gen option_hor = .
		gen stock_hor = .
		replace option_hor = gai_option*(gtime_option_award/a_time_option_award) if a_time_option_award!=.
		replace stock_hor = gai_stock*(gtime_stock_award/a_time_stock_award) if a_time_stock_award!=.

        /* Step 2: Sum up weighted horizons. */
		by cik participantid fiscalyear: egen vest_horizon = sum(gavf_hor)
		by cik participantid fiscalyear: egen perf_horizon = sum(gapf_hor)
		by cik participantid fiscalyear: egen perf_horizon_cash = sum(gapf_hor_cash)
		replace perf_horizon_cash=. if perf_horizon_cash==0

		by cik participantid fiscalyear: egen vest_horizon_count = count(gavf_hor)
		by cik participantid fiscalyear: egen perf_horizon_count = count(gapf_hor)
		by cik participantid fiscalyear: egen perf_horizon_cash_count = count(gapf_hor_cash)

		by cik participantid fiscalyear: egen option_horizon = sum(option_hor)
		by cik participantid fiscalyear: egen stock_horizon = sum(stock_hor)

		by cik participantid fiscalyear: egen option_horizon_count = count(option_hor)
		by cik participantid fiscalyear: egen stock_horizon_count = count(stock_hor)

        /* Set missing to missing. This is because sum in Stata is silly. */
        replace vest_horizon = . if vest_horizon_count == 0 | missing(vest_horizon_count)
        replace perf_horizon = . if perf_horizon_count == 0 | missing(perf_horizon_count)

		replace option_horizon = . if option_horizon_count == 0 | missing(option_horizon_count)
		replace stock_horizon = . if stock_horizon_count == 0 | missing(stock_horizon_count)

        capture drop vest_horizon_count perf_horizon_count
		capture drop option_horizon_count stock_horizon_count

		by cik participantid fiscalyear: egen sd_grantdate = sd(grantdate)

		gen a_grant_award_wt = a_grant_award+a_time_award

		gen total_horizon = (a_grant_award/a_grant_award_wt)*perf_horizon + (a_time_award/a_grant_award_wt)*vest_horizon
		replace total_horizon = vest_horizon if perf_horizon==.
		replace total_horizon = perf_horizon if vest_horizon==.

		gen a_grant_award_no = a_grant_award+a_time_stock_award

		gen total_horizon_no = (a_grant_award/a_grant_award_no)*perf_horizon + (a_time_stock_award/a_grant_award_no)*stock_horizon
		replace total_horizon_no = perf_horizon if stock_horizon==.
		replace total_horizon_no = stock_horizon if perf_horizon==.

		** Performance Periods
		/* Note - This code does not account for multiple, rollover periods in awards. It treats the "vesthigh-vestlow" value
			as the length of the performance period from the grant date
		*/

		gen perf_period = pm_vesthigh-pm_vestlow
		label variable perf_period "Performance Period Length"
		label variable pm_vestlow "Performance Period Start"

		gen match_date = fiscalyearend+364

		keep cik participantid fiscalyear currentceo currentcfo filingdate debt_related perf_horizon total_horizon vest_horizon perf_horizon_cash option_horizon stock_horizon total_horizon_no a_grant_award a_cashflow_award a_acct_award_c a_o_award a_rsu_award a_c_award a_cf_award1 a_cf_award1_short a_cf_award2 a_cf_award3 a_stock_award a_acct_award a_acct_short_award a_acct_short_award_no  a_other_award a_acct_other_award a_acct_income_award a_acct_return_award a_acct_sale_award a_time_award a_grant_award_wt a_grant_award_cash match_date earn1_maxm earn1_maxms earn1_minm earn1_minms earn1_tvm earn1_tvms earn2_maxm earn2_maxms earn2_minm earn2_minms earn2_tvm earn2_tvms earn3_maxm earn3_maxms earn3_minm earn3_minms earn3_tvm earn3_tvms earn4_maxm earn4_maxms earn4_minm earn4_minms earn4_tvm earn4_tvms earn5_maxm earn5_maxms earn5_minm earn5_minms earn5_tvm earn5_tvms earn6_maxm earn6_maxms earn6_minm earn6_minms earn6_tvm earn6_tvms earn7_maxm earn7_maxms earn7_minm earn7_minms earn7_tvm earn7_tvms a_grant_award_no  a_time_stock_award sale_tvm sale_tvms

		gsort cik participantid fiscalyear filingdate perf_horizon total_horizon vest_horizon a_acct_award_c a_o_award a_rsu_award a_c_award earn1_tvm earn2_tvm earn3_tvm earn4_tvm earn5_tvm earn6_tvm earn7_tvm earn1_minm earn2_minm earn3_minm earn4_minm earn5_minm earn6_minm earn7_minm earn1_maxm earn2_maxm earn3_maxm earn4_maxm earn5_maxm earn6_maxm earn7_maxm a_grant_award a_stock_award a_acct_award a_other_award a_acct_other_award a_acct_income_award a_acct_return_award a_acct_sale_award match_date a_time_award a_grant_award_wt, mfirst
		by cik participantid fiscalyear: gen dup=cond(_N==1,0,_n)
		drop if dup>1
		drop dup

		gen il=1
		rename fiscalyear fyear

		winsor2 total_horizon, cuts(1,99)


/* CD to desired output directory */
cd "<insert desired output directory here>"

/* For all execs */
if ($all_execs) {
    /* OUTPUT: incentivelab_master_allexecs.dta */
    save "incentivelab_master_allexecs", replace

}
else {
    /* For just CEOS */
    /* OUTPUT: incentivelab_master.dta */
    save "incentivelab_master", replace
}
