/*
05_duration_test_data_creation_2.do
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Create final dataset for RDD analysis.

--> Requires "duration_test_data_1.dta"
--> Requires "compustat_incentivelab_link.dta" (see note above for creation)
--> Requires Compustat Annual Fundamentals file
--> Requires "lender_relations_start_by_packageid.dta"
--> Creates "duration_test_data_final.dta", the final analysis file for RDD analysis
*/

** SET DIRECTORY
capture cd "<insert desired directory>"


/* INPUT_DATASET: duration_test_data_1.dta */
use duration_test_data_1, clear
rename *, lower

	*Date difference
	gen date_dif = datadate-dealactivedate

	*Distance Function
	winsor2 control_nw2, replace cuts(1, 99)
	winsor2 control_cr2, replace cuts(1, 99)
	drop if control_cr2 ==. & control_nw2==.
	sort packageid fyear _all
		by packageid fyear: egen control_cr3 = min(control_cr2)
		by packageid fyear: egen control_nw3 = min(control_nw2)

	gen dist = control_nw3
	replace dist = control_cr3 if control_cr3<dist & dist!=.
	replace dist = control_cr3 if dist==.

	replace dist=dist*100
	** NOTE: Distance variable is scaled and reported in percent terms

	** Aggregate treatment and rdd status to package/year level then remove duplicates
	*Violations
	sort packageid fyear _all
	by packageid fyear: egen total_cr = total(cr_viol)
	by packageid fyear: egen total_nw = total(nw_viol)
	by packageid fyear: egen total_tnw = total(tnw_viol)
	gen cov_viol = 0
	replace cov_viol = 1 if total_cr >0 & total_cr!=.
	replace cov_viol = 1 if total_nw >0 & total_nw!=.
	replace cov_viol = 1 if total_tnw >0 & total_tnw!=.

	*Remove Duplicates
	bysort packageid fyear: gen dup=cond(_N==1,0,_n)
	drop if dup>1
	xtset packageid fyear

	** Simple Distance Measure Polynomials
	gen dist2 = dist^2
	gen dist3 = dist^3
	gen dist4 = dist^4
	gen dist5 = dist^5
	gen dist6 = dist^6
	gen dist7 = dist^7
	gen inter1 = cov_viol*dist
	gen inter2 = cov_viol*dist2
	gen inter3 = cov_viol*dist3
	gen inter4 = cov_viol*dist4
	gen inter5 = cov_viol*dist5
	gen inter6 = cov_viol*dist6
	gen inter7 = cov_viol*dist7

	*** Drop pre-disclosure years
	drop if fyear<2006

	** Merge on CIKs using downloaded link data to allow for link to INCENTIVE LAB data
    /* INPUT_DATASET: compustat_incentivelab_link.dta */
	joinby gvkey fyear using compustat_incentivelab_link, unmatched(master)
	capture drop _merge

	**Adjust year to be the year before the compensation package is created
	replace fyear = fyear + 1

    /* INPUT_DATASET: incentivelab_master.dta */
	local k ""
	** put _allexecs to make it for all executives
	joinby cik fyear using "<insert directory here>/incentivelab_master`k'", unmatched(master)
	capture drop _merge
	** Remove observations where incentive lab data not available
	bysort gvkey: egen total_c=total(il)
	drop if total_c==0

  preserve
    tempfile lag_il
    use "<insert directory here>/incentivelab_master`k'", clear
    keep cik fyear filingdate a_grant_award a_cashflow_award a_o_award a_rsu_award a_c_award a_stock_award a_acct_award a_acct_award_c a_other_award a_acct_other_award a_acct_income_award a_acct_return_award a_acct_sale_award a_time_award a_cf_award1 a_cf_award2 a_cf_award3 *_horizon* a_grant_award_wt a_grant_award_cash il a_acct_short_award   a_grant_award_no a_time_stock_award a_grant_award_cash a_acct_short_award_no earn1_maxm earn1_minm earn1_tvm earn1_tvms earn2_maxm earn2_minm earn2_tvm earn2_tvms earn3_maxm earn3_minm earn3_tvm earn3_tvms earn4_maxm earn4_minm earn4_tvm earn4_tvms earn5_maxm earn5_minm earn5_tvm earn5_tvms earn6_maxm earn6_minm earn6_tvm earn6_tvms earn7_maxm earn7_minm earn7_tvm earn7_tvms

    replace fyear = fyear + 1

    foreach v in *_* il {
      rename `v' l`v'
    }
    save "`lag_il'`k'", replace
  restore
  joinby cik fyear using "`lag_il'`k'", unmatched(master)
  capture drop _merge

  preserve
    tempfile llag_il
    use "<insert directory here>/incentivelab_master`k'", clear
    keep cik fyear filingdate a_grant_award a_cashflow_award a_o_award a_rsu_award a_c_award a_stock_award a_acct_award a_acct_award_c a_other_award a_acct_other_award a_acct_income_award a_acct_return_award a_acct_sale_award a_time_award a_cf_award1 a_cf_award2 a_cf_award3 *_horizon* a_grant_award_wt a_grant_award_cash il a_acct_short_award a_grant_award_no a_time_stock_award a_acct_short_award_no earn1_maxm earn1_minm earn1_tvm earn1_tvms earn2_maxm earn2_minm earn2_tvm earn2_tvms earn3_maxm earn3_minm earn3_tvm earn3_tvms earn4_maxm earn4_minm earn4_tvm earn4_tvms earn5_maxm earn5_minm earn5_tvm earn5_tvms earn6_maxm earn6_minm earn6_tvm earn6_tvms earn7_maxm earn7_minm earn7_tvm earn7_tvms

    replace fyear = fyear + 2

    foreach v in *_* il {
      rename `v' ll`v'
    }
    save "`llag_il'`k'", replace
  restore
  joinby cik fyear using "`llag_il'`k'", unmatched(master)
  capture drop _merge

	**Change bonus to same level as Incentive Lab awards
	replace bonus=bonus*1000
	replace bonus = 0 if bonus==.

	** Accounting Ratio
	gen acct_ratio_wb = (a_acct_award+bonus)/(a_grant_award+a_time_award+bonus)

	** Short Accounting Ratio
	gen acct_short_ratio_wb = (a_acct_short_award+bonus)/(a_grant_award+a_time_award+bonus)
	gen lacct_short_ratio_wb = (la_acct_short_award+bonus)/(la_grant_award+la_time_award+bonus)

	**Remaining maturity
	gen remain = .
	replace remain = (loanenddate-datadate)/30

	rename net_worth net_worth_test
	rename tang_net_worth tang_net_worth_test
	rename current_ratio current_ratio_test

	*** Changes
	bysort packageid participantid fyear: gen dups=cond(_N==1,0,_n)
	tab dup

	*** FIX THE DUPLICATES HERE - none at package/participant/year level
	drop dups
	bysort participantid fyear: gen dups=cond(_N==1,0,_n)
	tab dups
	drop dups

	*Create group id for package/participant
	bysort participantid packageid: gen newid = 1 if _n==1
        replace newid = sum(newid)
        replace newid = . if missing(packageid)
		replace newid = . if missing(participantid)

	bysort newid fyear: gen dups=cond(_N==1,0,_n)
	tab dups
	drop dups

	bysort newid fyear: gen dups=cond(_N==1,0,_n)
	tab dups
	drop if dups>1
	drop dups

	xtset newid fyear

** MERGE ON ADDITIONAL VARIABLES (COMPUSTAT)
  preserve
    /* INPUT_DATASET: compustat_annual.dta */
	* Create lags file
    use "<insert directory here>/compustat_annual.dta", clear
    keep gvkey fyear at total_debt adjex_f prcc_f pstkrv
    sort gvkey fyear at
    duplicates drop gvkey fyear, force
    foreach v in at total_debt adjex_f prcc_f pstkrv {
      rename `v' lag_`v'
    }
    replace fyear = fyear + 1
    tempfile lags
    save "`lags'"

    /* Now that we have a lags file, reload compustat and merge it in */
    use "<insert directory here>/compustat_annual.dta", clear
    merge 1:1 gvkey fyear using "`lags'", keep(match master) nogenerate

    sort gvkey fyear at
    duplicates drop gvkey fyear, force

    destring(gvkey), replace
    xtset gvkey fyear

    ** Initial Variable Creation **
    gen ln_assets = ln(1+at)
    gen earnings = ebitda/at
    gen tobinsq = (prcc_f*csho-ceq + at)/at
    gen book_lev = total_debt / at
    gen xrd_0 = cond(missing(xrd), 0, xrd)
    gen investment = (xrd_0+capx)/at
    gen lxrd_0 = L.xrd_0
	gen cash_holdings = che/lag_at

	tostring(sic), replace
	gen sic2 = substr(sic, 1, 2)
	destring(sic2), replace

	destring(sic), replace
	capture ffind sic, newvar(ff48) type(48)

	** High Cash Holdings
	bysort ff48 fyear: egen median_ch = median(cash_holdings)
	gen high_ch = .
	replace high_ch = 1 if cash_holdings>median_ch & cash_holdings!=.
	replace high_ch = 0 if cash_holdings<=median_ch

    label variable ln_assets "Ln(Assets)"
    label variable investment "Investment"
    label variable earnings "Earnings"
    label variable tobinsq "Tobin's Q"

    replace fyear = fyear+1

    keep gvkey fyear ln_assets investment earnings tobinsq sic high_ch book_lev xrd_0 cash_holdings
    tempfile lagged
    save "`lagged'"

	replace fyear = fyear - 2
	foreach k in ln_assets investment earnings tobinsq sic high_ch book_lev xrd_0 cash_holdings {
		rename `k' `k'_future
	}

	tempfile future
	save "`future'"

  restore

  ** Merge on STATA-created compustat variables
	joinby gvkey fyear using "`lagged'", unmatched(master)
	capture drop _merge

  **Future variables currently unused
	*joinby gvkey fyear using "`future'", unmatched(master)
	*capture drop _merge


	/* Remove observations that are not current year */
	drop if lag!=0
	/* Convert main variable to annual (from monthly) */
	replace total_horizon=total_horizon/12
	/* Nullify observations when missing associated compensation (redundant safety check) */
	replace total_horizon=. if remain==.
	replace ltotal_horizon=. if remain==.
	replace ltotal_horizon=. if remain<1

  ** Merge on additional SAS-created compustat variables not included in initial funda pull
	/* INPUT_DATASET: compustat_variables.dta */
	capture drop _merge
	joinby gvkey fyear using compustat_variables, unmatched(master)
	capture drop _merge

	*** Input lender relationships
	capture drop _merge
	joinby packageid using lender_relations_start_by_packageid, unmatched(master)
	rename *, lower

	**Construct differenced form of dependent variables
	replace ltotal_horizon = ltotal_horizon/12
	gen dif_horizon = total_horizon-ltotal_horizon

	gen dif_acct_short = acct_short_ratio_wb - lacct_short_ratio_wb

	gen drop = .
	replace drop = 0 if dif_horizon>=0 & dif_horizon!=.
	replace drop = 1 if dif_horizon<0 & dif_horizon!=.

	gen raise = .
	replace raise = 0 if dif_acct_short<=0 & dif_acct_short!=.
	replace raise = 1 if dif_acct_short>0 & dif_acct_short!=.

	** Construct Fama-French 48 for median cuts (sample)
	destring sic, replace
	capture ffind sic, newvar(ff48) type(48)

	sort newid fyear

	** Long/Short Remaining Maturity
		**Using exact median, although it is roughly 2 years (24 months)
		sum remain, det
		gen mat = .
		replace mat = 0 if remain>23.6
		replace mat = 1 if remain<=23.6

	** High/Low Interest Coverage
		gen cashflow_int_ratio_l = lebitda/lxint
		replace cashflow_int_ratio_l = lebit/lxint if sic2==67 & cashflow_int_ratio_l==.
		gen high_cashflowint = .
		sum cashflow_int_ratio_l, det
		replace high_cashflowint = 1 if cashflow_int_ratio_l>5.42
		replace high_cashflowint = 0 if cashflow_int_ratio_l<=5.42

	**  High/Low R&D
		gen l_rd = lxrd/llat
		gen high_rd = .
		bysort ff48 fyear: egen m_rd = median(l_rd)
		replace high_rd = 1 if l_rd > m_rd & m_rd!=. & l_rd!=.
		replace high_rd = 0 if l_rd <= m_rd & m_rd!=. & l_rd!=.

	** High/Low Tobin's Q
		*rename ltobins_q tobinsq
		sum tobinsq
		gen tob = .
		bysort ff48 fyear: egen ff48_year_tobin = median(tobinsq)
		replace tob=0 if tobinsq>=ff48_year_tobin & tobinsq!=. & ff48_year_tobin!=.
		replace tob=1 if tobinsq<ff48_year_tobin & tobinsq!=. & ff48_year_tobin!=.

	**  High/Low Book leverage
		sum book_lev, det
		gen high_lev=.
		bysort ff48 fyear: egen m_bl = median(book_lev)
		replace high_lev=1 if book_lev>=m_bl & !missing(book_lev) & !missing(m_bl)
		replace high_lev=0 if book_lev<m_bl & !missing(book_lev) & !missing(m_bl)

	**  Bank Relationship
		gen bank_rel = fyear-first_year
		sum bank_rel, det
		gen high_rel = .
		bysort ff48 fyear: egen m_rel = median(bank_rel)
		replace high_rel = 0 if bank_rel<=m_rel & m_rel!=.
		replace high_rel = 1 if bank_rel>m_rel & m_rel!=.

	** Winsorize dependent variables
		winsor2 total_horizon, cuts(1,99)
		winsor2 acct_ratio_wb, cuts(1,99)
		winsor2 acct_short_ratio_wb, cuts(1,99)

** SAVE OUTPUT FOR ANALYSIS
/* OUTPUT: duration_test_data_final.dta */
	* `k' will save file with "allexecs" attached if needed
	save duration_test_data_final`k', replace
