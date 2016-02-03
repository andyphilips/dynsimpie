*
*		PROGRAM DYNSIMPIE
*		
*		version 1.3
*		Feb 02, 2016
*
*		Andrew Q. Philips,
*		Texas A&M University
*		aphilips@pols.tamu.edu
*		people.tamu.edu/~aphilips/
*			   &
*		Amanda Rutherford,
*		Guy D. Whitten
*
/* -------------------------------------------------------------------------
* -------------------------------------------------------------------------
* -------------------------------------------------------------------------
	If you use dynsimpie, please cite us:

    Philips, Andrew Q., Amanda Rutherford, and Guy D. Whitten. 2016 
	"Dynsimpie: A program to dynamically examine compositional dependent
	variables". Working Paper.
	
	and:

    Philips, Andrew Q., Amanda Rutherford, and Guy D. Whitten. 2016.
	"Dynamic pie: A strategy for modeling trade-offs in compositional
	variables over time." American Journal of Political Science 60(1): 
	268-283.

*/
* -------------------------------------------------------------------------
capture program drop dynsimpie
capture program define dynsimpie , rclass
syntax [varlist] [if] [in], [ dvs(varlist max = 7) shockvar(varname) 	  ///
Time(numlist integer > 1) SHock(numlist)] 								  ///
[shockvar2(varname) shock2(numlist)] [shockvar3(varname) shock3(numlist)] ///
[dummy(varlist)] [dummyset(numlist)] [sig(numlist integer < 100)]		  ///
[range(numlist integer > 1)] [saving(string)] [NOTABle] [NOSAve] [graph]
	 	 
version 8
marksample touse
preserve

* check to make sure dvs all sum to 1, or 100:
if "`dvs'" == ""	{
	di in r _n "Option dvs( ) must be specified"
	exit 198
}
else	{
	tempvar checksum
	qui gen `checksum' = 0
	qui foreach var of varlist `dvs'	{
		replace `checksum' = `checksum' + `var'
	}
	qui su `checksum'
	if r(min) < .99	{
		di in r _n "The dependent variables must sum to either 1 or 100"
		exit 198
	}
	if r(max) > 1.01 & r(min) < 99	{
		di in r _n "The dependent variables must sum to either 1 or 100"
		exit 198
	}
	if r(max) > 101 {
		di in r _n "The dependent variables must sum to either 1 or 100"
		exit 198
	}
	drop `checksum'
}

if "`sig'" != ""	{						// getting the CI's signif
	loc signif `sig'
}
else	{
	loc signif 95
}
loc sigl = (100-`signif')/2
loc sigu = 100-((100-`signif')/2)

if "`range'" != ""	{						// How far to simulate?
	loc range `range'
}
else	{
	loc range 20
	di ""
	di in y "No range specified; default to t=20"
}
if "`time'" != ""	{
	loc time `time'
}
else	{
	loc time 10
	di in y "No time of shock specified; default to t=10"
}
loc burnin 50								// burn-ins
loc brange = `range' + `burnin'
loc btime = `time' + `burnin'

if `time' >= `range' {
	di in r _n "The range of simulation must be longer than the shock time"
	exit 198
}
if "`shockvar'" == ""	{
	di in r _n "A shockvar, not included in [varlist], must be specified"
	exit 198
}
if "`shock'" == ""	{
	di in r _n "A real number shock, must be specified"
	exit 198
}
* ------------------------Generating Variables & Run Model ---------------------
* create compositions:
loc complist
loc i 1
foreach var of varlist `dvs' {
if "`i'" == "1"	{
	loc basevar `var'
} 
else	{
	capture drop `var'_`basevar'
	gen `var'_`basevar' = ln(`var'/`basevar')
	loc complist `"`complist' `var'_`basevar'"'
}
loc i = `i' + 1	
}

loc lvars 
loc dvars
qui foreach var of varlist `varlist'  {		// create d. and l. indep vars
	capture drop L_`var' D_`var'
	gen L_`var' = l.`var'
	gen D_`var' = d.`var' 
	loc lvars `"`lvars' L_`var'"'
	loc dvars `"`dvars' D_`var'"'
}		

capture drop L_`shockvar' D_`shockvar'
qui gen L_`shockvar' = l.`shockvar'
qui gen D_`shockvar' = d.`shockvar'
loc lagshockvariables `"L_`shockvar'"'
loc diffshockvariables `"D_`shockvar'"'
forv i = 2/3	{							// and the additional shocks
	if "`shockvar`i''" != "" {
		capture drop L_`shockvar`i'' D_`shockvar`i''
		qui gen L_`shockvar`i'' = l.`shockvar`i''
		qui gen D_`shockvar`i'' = d.`shockvar`i''
		loc lagshockvariables `"`lagshockvariables' L_`shockvar`i''"'
		loc diffshockvariables `"`diffshockvariables' D_`shockvar`i''"'
	}
}

loc model
loc i 1
qui foreach var of varlist `complist' {
	capture drop L_`var' D_`var'
	tempvar mdepvar`i'
	gen L_`var' = l.`var'				// gen lag DV
	loc lcomplist `"`lcomplist' L_`var'"'	// needed for future setx
	gen D_`var' = d.`var'				// gen diff DV
	gen `mdepvar`i'' = `var'			// grab means
	* Get the model
	loc model `"`model' (D_`var' L_`var' `dvars' `lvars' `diffshockvariables' `lagshockvariables' `dummy')"'
	loc i = `i' + 1
}
qui sureg `model'						// run the model and keep sample
qui keep if e(sample)
if "`notable'"	!= ""	{
	qui estsimp sureg `model'
}
else	{
	estsimp sureg `model'					// run Clarify
}
* ------------------------ Scalars and Setx ---------------------
qui setx mean							// set everything to means to start

qui su L_`shockvar', meanonly			// scalars for lagged shock
loc sv = r(mean)
loc vs = `sv' + `shock'
qui forv i = 2/3	{					// and the additional shocks
	if "`shockvar`i''" != "" {
		su L_`shockvar`i'', meanonly
		loc sv`i' = r(mean)
		loc vs`i' = `sv`i'' + `shock`i''
		setx L_`shockvar`i'' mean
		setx D_`shockvar`i'' 0
	}
}

qui setx D_`shockvar' 0					// set differenced shock to 0
qui setx L_`shockvar' mean				// set lag shock to mean

loc i 1
foreach var of varlist `lcomplist'	{	// set LDVs to means
	su `mdepvar`i'', meanonly
	scalar m`i' = r(mean)
	setx `var'	m`i'
	loc i = `i' + 1
}

qui setx (`dvars') 0						// set diff indep vars to 0
qui setx (`lvars') mean

loc i 1
if "`dummy'" != "" {						// set our dummies, if they exist
	if "`dummyset'" != "" {
		qui foreach var in `dummy' {
			loc m 1
			foreach k of numlist `dummyset' {
				if `m' == `i' {
					setx `var' `k'
				}
				loc m = `m' + 1
			}
			loc i = `i' + 1
		}
	}
	else {
		qui setx(`dummy') 0
	}
}
* ------------------------ Predict Values, t = 1 ----------------------------------
loc preddv
loc i 1
qui foreach var of varlist `lcomplist'	{
	tempvar td`i'log1
	loc preddv `"`preddv' `td`i'log1' "'
	loc i = `i' + 1
}
qui simqi, ev genev(`preddv')				// grab our expected values

loc denominator1
loc i 1
qui foreach var in `lcomplist' {
	su `mdepvar`i''
	scalar z = r(mean)
	tempvar t`i'log1
	gen `t`i'log1' = z + `td`i'log1'
	su `t`i'log1', meanonly
	scalar m`i' = r(mean)				// these scalars become the new LDV
	loc denominator1 `"`denominator1' + (exp(`t`i'log1'))"' // for below
	loc i = `i' + 1
}
* ------------------------Loop Through Time-------------------------------------
di ""
nois _dots 0, title(Please Wait...Simulation in Progress) reps(`range')
qui forv i = 2/`brange' {
	noi _dots `i' 0
	
	loc x 1
	foreach var of varlist `lcomplist'	{
		setx `var' (m`x')
		loc x = `x' + 1
	}

	* first set all shocks to mean and 0:
 	setx (`lagshockvariables') mean	
	setx (`diffshockvariables') 0
		
	if `i' == `btime' {					// we experience the shock at t
		setx D_`shockvar' (`shock')	// shock affects at time t only
		forv l = 2/3	{				// and additional shocks if != ""
			if "`shockvar`l''" != "" {
				setx D_`shockvar`l'' (`shock`l'')
			}
		}
	}
	if `i' > `btime' {
		setx D_`shockvar' 0			// diff shock back to 0
		setx L_`shockvar' (`vs')		// lag shock now at (mean + shock)
		forv  l = 2/3	{
			if "`shockvar`l''" != ""	{
				setx D_`shockvar`l'' 0
				setx L_`shockvar`l'' (`vs`l'')
			}
		}
	}
	
	setx (`dvars') 0				// just to be sure
	setx (`lvars') mean
	
	loc preddv
	loc x 1
	foreach var of varlist `lcomplist'	{
		tempvar td`x'log`i'
		loc preddv `"`preddv' `td`x'log`i'' "'
		loc x = `x' + 1
	}
	
	simqi, ev genev(`preddv')			// get new predictions
	loc denominator`i'
	loc x 1
	foreach var of varlist `lcomplist'	{
		tempvar t`x'log`i'
		gen `t`x'log`i'' = m`x' + `td`x'log`i'' // add them to old predictions
		su `t`x'log`i'', meanonly
		scalar m`x' = r(mean)
		loc denominator`i' `"`denominator`i'' + (exp(`t`x'log`i''))"' // need this for below
		loc x = `x' + 1
	}
}
* ------------------------Un-Transform------------------------------------------
loc keepthese
loc z : word count `dvs'		// how many DV's?
qui forv i = 1/`brange' {
	loc m 1
	qui foreach var of varlist `lcomplist'	{
		tempvar var`m'_pie`i'
		gen `var`m'_pie`i'' = (exp(`t`m'log`i''))/(1  `denominator`i'')
		_pctile `var`m'_pie`i'', p(`sigl',`sigu')	// grab CIs for each DV
		gen var`m'_pie_ll_`i' = r(r1)
		gen var`m'_pie_ul_`i' = r(r2)
		loc keepthese `"`keepthese' var`m'_pie_ll_`i' var`m'_pie_ul_`i' "'
		loc m = `m' + 1
	}			  
	tempvar var`z'_pie`i' 					// the un-transformation baseline
	gen `var`z'_pie`i'' = 1/(1  `denominator`i'')	
	_pctile `var`z'_pie`i'', p(`sigl',`sigu')
	gen var`z'_pie_ll_`i' = r(r1)
	gen var`z'_pie_ul_`i' = r(r2)
	loc keepthese `"`keepthese' var`z'_pie_ll_`i' var`z'_pie_ul_`i' "'
}

keep `keepthese'
qui keep in 1
tempvar count 
qui gen `count' = _n

loc reshapevar
qui forv i = 1/`z' {					// reshape across `z' vars in `dvs'
	loc reshapevar `"`reshapevar' var`i'_pie_ll_ var`i'_pie_ul_ "'
}

qui reshape long `reshapevar', j(time) i(`count')
qui drop `count' time
qui drop in 1/`burnin'
qui gen time = _n

qui forv i = 1/`z' {					// create mid-points
	gen mid`i' = (var`i'_pie_ll_ + var`i'_pie_ul_)/2
}
order time

if "`nosave'" != ""	{					// save estimates?
}
else	{
	di ""
	if "`saving'" != "" {
		noi save `saving'.dta, replace
	}
	else	{
		noi save dynsimpie_results.dta, replace
	}
}

if "`graph'" != ""	{
	loc ulll 
	loc mid "scatter mid1 time"
	loc legend
	forv i = 1/`z'	{
		loc ulll `"`ulll' || rspike var`i'_pie_ul_ var`i'_pie_ll_ time, lcolor(black) lwidth(thin) "'	
		if "`i'" > "1"	{
			loc mid `"`mid' || scatter mid`i' time "'
		}
		if "`i'" == "1"	{
			loc base : word 1 of `dvs'
		}
		loc iminus1 = `i' - 1
		else	{
			loc dvplace : word `i' of `dvs'
			loc legend `" `legend' `iminus1' "`dvplace'" "'
		}
	}
	twoway `mid' `ulll' legend(order(`legend' `z' "`base'")) xtitle("Time")  ///
	ytitle("Predicted Proportion") graphregion(color(white))	///
	note("Note: `signif'% confidence intervals") 
}
else	{
}

end 									// end dynsimpie
* -----------------------------------------------------------------------------