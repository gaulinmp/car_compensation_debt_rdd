/*
01_duration_test_data_creation.sas
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Pulls compustat and dealscan data from WRDS.

--> Requires dealscan link
--> Requires Dealscan databases listed above
--> Requires Compustat Annual Fundamentals file
--> Requires ExecuComp Annual Compensation file
--> Creates "duration_test_data_1.dta"
*/

*** Covenant Violations ***;

* Library to hold dealscan link: done for easier upload using wrds submit*;
libname cv '<insert path for sas file of dealscan link>';


* Import link of gvkey to bcoid;
/* INPUT_DATASET: Data Creation/dealscan_link.dta */
/* Data used was in stata .dta format - adjust for whatever format dealscan link is in */
PROC IMPORT OUT = dclink
        DATAFILE= "<Insert path to dealscan link here>\dealscan_link.dta"
        DBMS = STATA REPLACE;
RUN;

data cv.dclink;
	set dclink;
run;

** RSUBMIT NOTE: The following code can be run without rsubmit. The user will need to download the dealscan data files listed
	in the README file and reference them with their own path; **

*Rsubmit code;

%let wrds=wrds.wharton.upenn.edu 4016;
options comamid=TCP remote=WRDS;
signon username=_prompt_;



RSUBMIT;

  libname dealscan '/wrdslin/tfn/sasdata/dealscan';
  libname compm '/wrds/comp/sasdata/nam';
  libname exec '/wrds/comp/sasdata/execcomp';

  *upload link file;
  proc upload data=cv.dclink out=dclink;
  run;

  *package file;
  data package;
    set dealscan.package;
    drop comment;
    rename borrowercompanyid = bcoid;
  run;

  *financial covenant file;
  data fcov;
    set dealscan.financialcovenant;
    rename comment=fcov_comment;
    *if covenanttype!='Min. Current Ratio' then delete;
  run;

  *net worth covenant file;
  data nwcov;
    set dealscan.networthcovenant;
    if baseamt=. then delete;
    if baseamt<100 then delete;
  run;

  *merge financial covenants;
  proc sql;
    create table f_merge as
    select a.*, b.*
    from package as a inner join fcov as b
    on a.packageid=b.packageid;
  quit;

  *merge net worth covenants;
  proc sql;
    create table nw_merge as
    select a.*, b.*
    from package as a inner join nwcov as b
    on a.packageid=b.packageid;
  quit;

  * append both merged data sets;
  data packages;
    set f_merge nw_merge;
  run;

  * link to gvkeys;
  proc sql;
    create table packages as
    select a.*, b.*
    from packages as a inner join dclink as b
    on a.bcoid=b.bcoid;
  quit;

  *unique facilityid's;
  data fac;
    set dealscan.facility(keep = packageid facilityid);
  run;

  proc sort data=fac nodup out=fac;
    by packageid facilityid;
  quit;


  * create a window to merge firm fundamentals onto - using first facility start date and last facility end date in a package;
  data facility;
    set dealscan.facility;
    if facilityenddate=. then delete;
    if facilitystartdate=. then delete;
  run;

  proc sort data = facility;
    by packageid descending facilityenddate;
  run;

  data max_date;
    set facility(keep=packageid facilityenddate);
    by packageid;
    if first.packageid then output max_date;
    rename facilityenddate=loanenddate;
  run;


  proc sort data = facility;
    by packageid facilitystartdate;
  run;

  data min_date;
    set facility(keep=packageid facilitystartdate);
    by packageid;
    if first.packageid then output min_date;
    rename facilitystartdate=loanstartdate;
  run;


  * merge start date;
  proc sql;
    create table packages as
    select a.*, b.*
    from packages as a inner join max_date as b
    on a.packageid=b.packageid;
  quit;

  *merge end date;
  proc sql;
    create table packages as
    select a.*, b.*
    from packages as a inner join min_date as b
    on a.packageid=b.packageid;
  quit;


  * Create compustat file for merging;
  data comp;
    set compm.funda(keep = gvkey datadate fyear act lct intan at lt);
    current_ratio= act/lct;
    net_worth=at-lt;
    tang_net_worth=at-intan-lt;
  run;

  * Create execucomp file for merging;
  data exec;
    set exec.anncomp;
    if ceoann^="CEO" then delete;
    start = year(joined_co);
    tenure= year-start;
    year=year+1;
  run;

  * merge compustat and execucomp;
  proc sql;
    create table comp as
    select a.*, b.*
    from comp as a left join exec as b
    on a.gvkey=b.gvkey & a.fyear=b.year;
  quit;

  * link dealscan and compustat;
  proc sql;
    create table master as
    select a.*, b.*
    from packages as a inner join comp as b
    on a.gvkey=b.gvkey & a.loanstartdate-370<=b.datadate & a.loanenddate>=b.datadate;
  quit;


  * download file;
  proc download out=master;
  run;


  endrsubmit;


  * Covenant violation and type indicators with RDD indicator;
    *Preliminary variables. See duration_test_data_creation_2.do for RDD variables;
  data master2;
    set master;
    cr_viol=0;
    nw_viol=0;
    tnw_viol=0;
    nw_cov = baseamt/1000000;
    if baseamt=. then nw_cov=.;
    if current_ratio = . & covenanttype="Min. Current Ratio" then delete;
    if net_worth =. & covenanttype="Net Worth" then delete;
    if tang_net_worth =. & covenanttype="Tangible Net Worth" then delete;
    if initialratio=. & covenanttype="Min. Current Ratio" then delete;
    if nw_cov =. & covenanttype="Net Worth" then delete;
    if nw_cov =. & covenanttype="Tangible Net Worth" then delete;
    if initialratio>current_ratio & covenanttype="Min. Current Ratio" then cr_viol=1;
    if nw_cov>net_worth & covenanttype="Net Worth" then nw_viol=1;
    if nw_cov>tang_net_worth & covenanttype="Tangible Net Worth" then tnw_viol=1;
    rdd=0;
    if 1.2*initialratio>=current_ratio & .8*initialratio<=current_ratio & initialratio^=. & current_ratio^=. & covenanttype="Min. Current Ratio" then rdd=1;
    if 1.2*nw_cov>=net_worth & .8*nw_cov<=net_worth  & nw_cov^=. & net_worth^=. & covenanttype="Net Worth" then rdd=1;
    if 1.2*nw_cov>=tang_net_worth & .8*nw_cov<=tang_net_worth & nw_cov^=. & tang_net_worth^=. & covenanttype="Tangible Net Worth" then rdd=1;
    control_cr=.;
    if covenanttype="Min. Current Ratio" then control_cr=(current_ratio-initialratio);
    control_nw=.;
    if covenanttype="Net Worth" then control_nw=net_worth-nw_cov;
    if covenanttype="Tangible Net Worth" then control_nw=tang_net_worth-nw_cov;
    if covenanttype="Min. Current Ratio" then control_cr2=(current_ratio-initialratio)/initialratio;
    if covenanttype="Net Worth" then control_nw2=(net_worth-nw_cov)/nw_cov;
    if covenanttype="Tangible Net Worth" then control_nw2=(tang_net_worth-nw_cov)/nw_cov;
    if covenanttype="Min. EBITDA" then earn_cov = 1;
    if covenanttype="Max. Senior Debt to EBITDA" then earn_cov=1;
    if covenanttype="Max. Debt to EBITDA" then earn_cov=1;
    else earn_cov=0;
    lag=0;
    if loanstartdate>datadate then lag=1;
      new_gvkey = input(gvkey, 6.);
    drop gvkey;
    rename new_gvkey=gvkey;
  run;


  /* OUTPUT: duration_test_data_1.dta */
  proc export DATA=master2
        FILE="<insert desired path here>\duration_test_data_1.dta"
        DBMS=STATA REPLACE;
  run;

ENDRSUBMIT;
