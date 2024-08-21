/*
04_lender_relations.sas
Copyright (c) 2024, Akins, Bitting, De Angelis, Gaulin. See LICENSE for details.

Create file containing lender-borrower relationship.

--> Requires dealscan link
--> Requires "package.sas7bdat", "facility.sas7bdat", "lendershares.sas7bdat" from Dealscan Database
--> Creates "lender_relations_start_by_packageid.dta"
*/

* Import link of gvkey to bcoid;
/* INPUT_DATASET: dealscan_link.dta */
PROC IMPORT OUT = dclink
        DATAFILE= "<insert desired path here>\dealscan_link.dta"
        DBMS = STATA REPLACE;
RUN;


*** To run on your computer, adjust these libraries;
libname dealscan '<insert directory containing dealscan databases>';

*package file;
data package;
	set dealscan.package;
	drop comment;
	rename borrowercompanyid = bcoid;
run;

proc sort data=package nodup out=package;
	by packageid;
quit;


*unique facilityid's;
data fac;
	set dealscan.facility(keep = packageid facilityid facilitystartdate facilityenddate);
run;

proc sort data=fac nodup out=fac;
	by packageid facilityid;
quit;

*Lender File;
data lender;
	set dealscan.lendershares;
run;

* link to gvkeys;
proc sql;
	create table fac as
	select a.*, b.*
	from fac as a inner join lender as b
	on a.facilityid=b.facilityid;
quit;

proc sort data=fac nodup out=fac;
	by packageid facilityid companyid;
quit;

* link to gvkeys;
proc sql;
	create table package as
	select a.*, b.*
	from package as a inner join dclink as b
	on a.bcoid=b.bcoid;
quit;

proc sort data=package nodup out=package;
	by packageid gvkey;
quit;

data package;
	set package(keep=packageid gvkey);
run;

proc sql;
	create table fac as
	select a.*, b.*
	from fac as a inner join package as b
	on a.packageid=b.packageid;
quit;

data master;
	set fac(keep = facilityid packageid facilitystartdate facilityenddate companyid leadarrangercredit gvkey);
	year_start = year(facilitystartdate);
run;

proc sql;
	create table master as
	select a.*, min(year_start) as first_year
	from master as a
	group by companyid, gvkey;
quit;

proc sort data=master;
	by companyid gvkey;
run;

data master;
	set master;
	if leadarrangercredit^="Yes" then delete;
run;


proc sql;
	create table master as
	select a.*, min(first_year) as first_year2
	from master as a
	group by packageid;
quit;

data master;
	set master;
	if first_year2^=first_year then delete;
run;

proc sort data=master nodupkey out=master;
	by packageid;
quit;

data master;
	set master(keep = packageid companyid first_year2);
	rename first_year2 = first_year;
run;



/* OUTPUT: lender_relations_start_by_packageid.dta.dta */
proc export DATA=master
			FILE="<insert desired output directory here>\lender_relations_start_by_packageid.dta"
			DBMS=STATA REPLACE;
run;
