/**
6/23 clean-up 
the curren methodologies consist of 3 parts:
1. calculate the encounters 
2. merge P14 header and detail, Encounter, FQHC 
3. manually update the grouping criteria on the clinical group excel sheet based on the info from clinics 
**/

-- first step: calculate all the encounters from the EPICTblEncounter DB 
-- Note: ADM_DATE_TIME between '2021-07-01' and '2021-12-31' -- only this column(patient admission time related) is needed.
	-- date range might if time series analysis is conducted
--Note for adding select grouping criteria (add-on). The info is not finalized and it is a moving piece. 


--DROP TABLE #95_TH1

/**Note: create temp tables #95_TH1, #95_TH2, # enc_test1 
   only need modifer that contains %95% 
*/
SELECT 
HSP_ACCOUNT_ID
,MODIFIER
,REVERSE(PARSENAME(REPLACE(REVERSE(MODIFIER),',','.'),1)) AS 'MODIFIER_1'
,REVERSE(PARSENAME(REPLACE(REVERSE(MODIFIER),',','.'),2)) AS 'MODIFIER_2'
,REVERSE(PARSENAME(REPLACE(REVERSE(MODIFIER),',','.'),3)) AS 'MODIFIER_3'
,REVERSE(PARSENAME(REPLACE(REVERSE(MODIFIER),',','.'),4)) AS 'MODIFIER_4'
INTO #95_TH1
FROM [Finance].[dbo].[P14_EPIC_Detail]
WHERE MODIFIER LIKE ('%95%')

--DROP TABLE #95_TH2 -- this is a helping table 

SELECT
* 
INTO #95_TH2
FROM
(SELECT
*
FROM
#95_TH1
WHERE MODIFIER_1 IN ('95')
UNION
SELECT
*
FROM
#95_TH1
WHERE MODIFIER_2 IN ('95')
UNION
SELECT
*
FROM
#95_TH1
WHERE MODIFIER_3 IN ('95')
UNION
SELECT
*
FROM
#95_TH1
WHERE MODIFIER_4 IN ('95')
) A

--DROP TABLE #enc_test1; 
/**
enc_test1 table needed to calculate all encounters from the EpicTblEncounter DB (left join the finance table) 
save it as csv for encounters only.
date format: 01 for July, 02 for Aug, 03 for Spet. fiscal year/month calculation. 
**/
select * INTO #enc_test1 FROM (
SELECT
HSP_ACCOUNT_ID 
,PAT_ENC_CSN_ID
,[ADM_DATE_TIME]
,PRIMARY_PAYOR_ID
,PRIMARY_PAYOR_NAME
,a.DEPARTMENT_ID
,a.DEPARTMENT_NAME
,ENC_TYPE
,APPT_PRC_ID
,PRC_NAME
,[NAME]
,Grouper
,PC_Specialty_Other
,DATENAME(MONTH, [ADM_DATE_TIME]) AS Month_Name
,YEAR([ADM_DATE_TIME]) AS Cal_Yr
,CASE WHEN MONTH([ADM_DATE_TIME]) < 7 THEN YEAR([ADM_DATE_TIME]) 
	WHEN MONTH([ADM_DATE_TIME]) >= 7 THEN YEAR([ADM_DATE_TIME]) + 1
	END AS FISCAL_YEAR
,CASE WHEN MONTH([ADM_DATE_TIME])=7 THEN '01-Jul'  
	WHEN MONTH([ADM_DATE_TIME])=8 THEN '02-Aug'
	WHEN MONTH([ADM_DATE_TIME])=9 THEN '03-Sep'
	WHEN MONTH([ADM_DATE_TIME])=10 THEN '04-Oct'
	WHEN MONTH([ADM_DATE_TIME])=11 THEN '05-Nov'
	WHEN MONTH([ADM_DATE_TIME])=12 THEN '06-Dec'
	WHEN MONTH([ADM_DATE_TIME])=1 THEN '07-Jan'
	WHEN MONTH([ADM_DATE_TIME])=2 THEN '08-Feb'
	WHEN MONTH([ADM_DATE_TIME])=3 THEN '09-Mar'
	WHEN MONTH([ADM_DATE_TIME])=4 THEN '10-Apr'
	WHEN MONTH([ADM_DATE_TIME])=5 THEN '11-May'
	WHEN MONTH([ADM_DATE_TIME])=6 THEN '12-Jun'
	END AS FISCAL_MONTH
,APPT_STATUS_C
,APPT_STATUS
,CASE WHEN a.APPT_PRC_ID IN ('100000','100002','9000','100001','1781','105751','100006','100003','100007')
	THEN 'Y' ELSE 'N' END AS 'PRC_Telehealth'  -- for now, we are ok with the grouping filtering criteria. this may change later
,CASE WHEN HSP_ACCOUNT_ID IN 
							(SELECT HSP_ACCOUNT_ID 
							FROM #95_TH2 
							GROUP BY HSP_ACCOUNT_ID) 
							THEN 'Y' ELSE NULL END AS 'TELEHEALTH_95' -- appt might be named as followup. but billed as telehealth_95 
,CASE WHEN HSP_ACCOUNT_ID IN 
							(SELECT HSP_ACCOUNT_ID 
							FROM [Finance].[dbo].[P14_EPIC_Detail] 
							WHERE HCPCS_CODE LIKE ('9944%')
							GROUP BY HSP_ACCOUNT_ID) THEN 'Y' END AS 'TELEHEALTH' 
,CASE WHEN ENC_TYPE_C IN ('70','76','2532')
	THEN 'Y' END AS 'ENC_Telehealth'  --- 4th groups. (everything from encounter left join  finance) 
FROM EPIC_2019.dbo.EpicTblEncounter a
LEFT OUTER JOIN [FINANCE].[finance].[FQHC_List] b
			ON a.DEPARTMENT_ID = b.DEPARTMENT_ID
			LEFT OUTER JOIN [Finance].[finance].[EPIC_Clinic_Grouping] c
			ON a.DEPARTMENT_ID = c.[Dept ID]
where (ADM_DATE_TIME between '2021-07-01' and '2022-05-31') --- need to be flex. filter  
group by
HSP_ACCOUNT_ID 
,PAT_ENC_CSN_ID
,[ADM_DATE_TIME]
,PRIMARY_PAYOR_ID
,PRIMARY_PAYOR_NAME
,a.DEPARTMENT_ID
,a.DEPARTMENT_NAME
,ENC_TYPE
,ENC_TYPE_C
,APPT_PRC_ID
,PRC_NAME
,[NAME]
,Grouper
,PC_Specialty_Other
,APPT_STATUS_C
,APPT_STATUS) enc_test1
--test Evan 1,818,537 6/23PM
--test 6/24AM 1,818,555

/** this is the export for encounters only! **/

--run this to get FINAL ENOCUNTER # -> export to csv file -current method 
-- 1,584,523 6/23 
-- 1,584,531 6/24
select * FROM #enc_test1
where APPT_PRC_ID IS NOT NULL


/**
2nd file PrimaryCareQuery_2022_MI 
Creating modifier 95 flag table ----medical billing codes 
creating temp tables #95_1, #95_2 in order to get to priority appointments -- same process 
**/

--DROP TABLE #95_1



/*Creating table for Priority Appt Order*/
/*1124 rows; need to periodically check if there are appts not yet assigned a priority */

--DROP TABLE #PriorityAppt; 

SELECT * INTO #PriorityAppt FROM (
SELECT
APPT_PRC_ID
,PRC_NAME 
,
		ELSE NULL END AS 'PriorityAppt'
from EPIC_2019.dbo.EpicTblEncounterCASE WHEN APPT_PRC_ID IN ('10001','10018','1003','1005','1006','1008','1017','1024','1030'
						,'1050000573','105000600','105000601','105000602','105002256','105002260'
						,'105002263','105002328','105002497','105002531','10504652','10504653','1050520'
						,'1050524','1050550','1050551','1050694','1050701','1050736','1050742','1050750'
						,'1050757','1051101','1051114','1051284','1051285','1051694','1051953','1054289'
						,'1070','1080','1083','1086','1091','1091002','1093','1095','1098','1099','1100'
						,'1116','1117','1118','1119','1121','1129','1151','117104','117105','117108','117109'
						,'11711','117111','11720','11721','11723','11724','1180010010','1181001','1181002'
						,'1181002501','1181004','1181008','1181010','1181011','1181013','1181014','1181015'
						,'1181018','1181020','1181021','1181023','1181027','118103','1181030','118107','118110'
						,'118111','118113','118114','118117','118118','11811845','11811888','11811889','118222'
						,'12001','12014','12101','1230','1231','1232','1241','1242','1243','1244','1245','1246'
						,'1249','1250','1253','1255','1256','1257','1264','1265','1294','1295','1330','1331'
						,'1332','1333','1334','1336','1338','1340','1341','1342','1343','1345','1346','1348'
						,'1349','1350','1353','1354','1355','1360','1361','1362','1363','1364','1365','1366'
						,'1367','1370','1371','1372','1373','1374','1375','1376','1379','1380','1383','1386'
						,'1390','1395','1404','1412','1417','1428','1429','1436','15108','15147','1559','1561'
						,'1562','1563','1597','1611','1613','1615','1616','1670','1671','1672','17020','17104'
						,'171100','171102','1717','1725','1727','1738','1743','1744','1745','1751','1752','1758'
						,'1760','1777','1778','1779','1780','1782','1783','1784','1785','1791','1799','1800'
						,'18002','1801','1802','1803','1822','1823','1826','1827','1828','1830','1831','1833'
						,'1835','1836','1840','1841','1842','1850','1888','1900','1901','1904','1906','1909'
						,'1910','19100','1911','19110','19111','19112','19116','1912','19120','19121','19122'
						,'19126','1919','19200','19210','19211','19212','19216','19220','19221','19226','1924'
						,'1925','19300','19304','19311','19316','1937','19400','19404','19500','19600','1979'
						,'1981','1982','1994','1995','19999','2000','2001','2002','2003','2004','2005','2006'
						,'2007','2016','231','245','246','250','311','33001','33042','33044','33235','334','335'
						,'336','337','338','339','341','343','349','350','352','354','356','366','367','372'
						,'60007','60009','60016','60023','60024','60025','60028','60029','60034','60042','60049'
						,'60050','60051','60052','60056','60058','60062','60063','60066','60070','60071','60072'
						,'60074','60081','60084','60085','60086','60087','60088','60090','60091','644','645','646'
						,'648','650','652','653','654','655','656','657','659','661','662','663','665','666','667'
						,'668','669','670','671','672','673','674','675','676','677','679','685','687','688','693'
						,'694','695','696','700','701','702','703','704','705','706','707','708','710','711','712'
						,'713','714','715','717','721','724','725','726','727','728','729','730','734','735','739'
						,'740','741','743','746','756','757','758','797','802','808','810','811','812','834','837'
						,'838','840','841','100004','10027','105002500','1096','1181019','1181024','1378','1491'
						,'15107','171101','1883','1907','19326','362','60067','60068','60092','760','814') THEN ('1')
 WHEN APPT_PRC_ID IN ('100000','100001','100002','100003','100006','100007','10005','10007','10015','10016'
			,'1002','10023','10025','10030','1004','1012','1018','1037','1050','105002133','1050191','1050192','1050193'
			,'1050200','1050202','1050203','1050217','1050218','1050219','1050220','1050221','1050222','1050223','1050237'
			,'1050238','1050248','1050275','1050277','1050279','1050280','1050281','1050282','1050283','1050284','1050285'
			,'1050286','1050287','1050289','1050291','1050293','1050294','1050297','1050298','1050316','1050317','1050319'
			,'1050321','1050331','10504651','1050621','1050783','1050784','1050785','1050794','1051000','1051001','1051003'
			,'1051040','1051124','1051226','1051245','1051256','1051282','1051283','1051327','1051328','1051329','1051330'
			,'1051333','1051338','1051339','1051340','1051341','1051343','1051344','1051345','1051346','1051388','1051389'
			,'1051390','1051391','1051393','1051398','1051399','1051400','1051402','1051403','1051404','1051414','1051416'
			,'1051418','1051432','1051628','1051629','1051752','1051753','1052017','10560','1056000','1056002','1056004'
			,'1057003','1057004','1057005','1057006','105751','1081','1084','1090','1092','1154','11725','1180002','1180010007'
			,'1181002301','1181026','1181029','1181031','118106','118200','1191','1198','12000','12100','12203','1233','1234'
			,'1235','1236','1237','1240','1258','1260','1261','1268','1269','1282','1283','1287','13000','1302','1326','1327'
			,'1328','1329','1426','1437','1438','1439','1440','1441','1442','1443','1445','1446','1447','1448','1449','1450'
			,'1451','1452','1453','1454','1455','1456','1457','1459','1460','1461','1462','1463','1464','1466','1468','1469'
			,'1470','1471','1472','1473','1474','1475','1476','1477','1479','1480','1483','1484','1485','1486','1487','1489'
			,'1490','1492','1493','1495','1496','1498','1499','1501','1502','1503','1505','1506','1508','1527','1535','1537'
			,'1540','1542','1543','1550','1551','1556','1557','1558','1567','1568','1569','1570','1571','1572','1573','1574'
			,'1575','1577','1578','1579','1583','1584','1585','1587','1589','1590','1591','1592','1593','1594','1595','1600'
			,'1601','1606','1607','1608','1609','1641','1645','1652','1653','1654','1655','1656','1657','1658','1659','1660'
			,'1663','1664','1674','1675','1677','1678','1680','1681','1682','1684','1685','1686','1687','1688','1690','1691'
			,'1692','1693','1694','1695','17003','1708','1709','1710','17108','17109','1711','1712','1713','1714','1715','1716'
			,'1739','1762','1763','1764','1765','1766','1767','1768','1769','1781','1788','1789','1792','1794','1796','18000'
			,'18004','1818','1821','1829','1837','1844','1882','1898','1899','1902','1903','1905','19101','19102','19113','19117'
			,'19123','19127','19201','19202','19204','19217','19227','19301','19302','19317','19327','19401','19402','19417'
			,'19427','19502','19602','1974','1980','233','234','242','262','29203','33006','333','358','380','381','388','389'
			,'391','399','400','403','404','405','406','407','408','409','410','412','413','414','416','417','418','419','422'
			,'423','424','425','426','427','428','429','430','431','432','433','434','438','439','440','442','443','444','445'
			,'446','447','448','449','450','451','452','453','454','455','456','457','458','459','461','462','463','464','465'
			,'466','467','468','469','470','471','472','473','474','475','476','477','478','479','480','481','482','483','484'
			,'485','486','487','488','491','492','493','494','495','496','497','498','499','500','503','504','505','506','507'
			,'508','509','510','511','512','513','514','515','516','518','520','522','523','524','525','526','527','528','529'
			,'530','531','532','533','534','535','536','537','538','539','540','541','542','543','544','545','546','547','548'
			,'549','550','551','552','553','554','555','556','557','558','559','560','562','563','565','566','567','569','571'
			,'572','573','574','575','576','577','578','579','580','581','582','583','584','585','586','587','588','589','590'
			,'591','592','593','594','595','596','597','598','599','600','60002','60010','60011','60013','60030','60033','60036'
			,'60037','60038','60039','60040','60041','60043','60044','60045','60046','60048','60054','60057','60059','60060','60061'
			,'60064','60065','60075','60076','60077','60079','60083','60089','602','603','604','605','606','607','608','609'
			,'610','611','612','613','614','615','616','617','618','619','620','621','622','623','624','625','626','627','630'
			,'631','633','635','636','637','638','639','640','641','642','643','699','70001','731','732','748','751','765','771'
			,'772','773','774','775','776','783','784','787','788','796','800','803','819','825','827','828','9000'
			,'100008','10008','1051686','1136','1564','1651','1689','1886','19421','1984','280','40004','747') THEN ('2')
		WHEN APPT_PRC_ID IN ('1023','1091001','1200','1996','1997','1999','2009','2010','2011','2012','2013'
		,'2014','2015','33031','50001','60018','60053','60082','807','17000','32107','40002','40005') THEN ('3')
		WHEN APPT_PRC_ID IN ('11722','1728','1750','1832','1998','60012','60015','60035') THEN ('4')
where APPT_PRC_ID IS NOT NULL
GROUP BY APPT_PRC_ID ,PRC_NAME ) PriorityAppt

/******************************************/
--count of how many Completed CSN there are per unique HAR and where the HAR is not NULL
-- below is how the primary care payment is calculated. underlying assumption for using 3 CSNs for 1 HAR. 

SELECT
sum(D.[1CSN]) as '1csn'
,sum(D.[2CSN]) as '2csn'
,sum(D.[3CSN]) as '3csn'
,sum(D.[4CSN]) as '4csn'
,sum(D.[5CSN]) as '5csn'
,sum(D.[6CSN]) as '6csn'
,sum(D.[7CSN]) as '7csn'
,sum(D.[8CSN]) as '8csn'
,sum(D.[9CSN]) as '9csn'
,sum(D.[10CSN]) as '10csn'
,sum(D.[10PlusCSN]) as '10pluscsn'
FROM (
	SELECT
	CASE WHEN NoOfCSN = 1 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '1CSN'
	,CASE WHEN NoOfCSN = 2 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '2CSN'
	,CASE WHEN NoOfCSN = 3 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '3CSN'
	,CASE WHEN NoOfCSN = 4 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '4CSN'
	,CASE WHEN NoOfCSN = 5 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '5CSN'
	,CASE WHEN NoOfCSN = 6 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '6CSN'
	,CASE WHEN NoOfCSN = 7 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '7CSN'
	,CASE WHEN NoOfCSN = 8 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '8CSN'
	,CASE WHEN NoOfCSN = 9 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '9CSN'
	,CASE WHEN NoOfCSN = 10 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '10CSN'
	,CASE WHEN NoOfCSN > 10 THEN COUNT(HSP_ACCOUNT_ID) ELSE '' END AS '10PlusCSN'
	FROM
		(SELECT
		HSP_ACCOUNT_ID
		,NoOfCSN
		FROM
			(SELECT
			HSP_ACCOUNT_ID
			,count(PAT_ENC_CSN_ID) OVER (PARTITION BY HSP_ACCOUNT_ID) AS NoOfCSN -- counts number of csn per har
			FROM EPIC_2019.dbo.EpicTblEncounter
			WHERE APPT_STATUS_C IN ('2') AND HSP_ACCOUNT_ID IS NOT NULL
			GROUP BY HSP_ACCOUNT_ID, PAT_ENC_CSN_ID
			) A 
		GROUP BY
		HSP_ACCOUNT_ID
		,NoOfCSN ) B
	GROUP BY NoOfCSN) D

--result 
--1csn                                                                            10plusscan
--4204097	135512	26612	9324	4780	2997	2130	1679	1462	1137	7048


/***this is the current table being used****/
/******************************************/

--this creates a temp table of HARs with completed appointments, and the list of appt type
-- assumption of the PC payment calculation: 1 HAR: 3 CSNs 
-- needed for NoOfCSN and NoOfDept
---same table as the previous script. However, finance needs to keep both for different reporting purposes. 

--DROP TABLE #encounters; 

SELECT * INTO #encounters FROM (
SELECT
HSP_ACCOUNT_ID
,PAT_ENC_CSN_ID
,count(PAT_ENC_CSN_ID) OVER (PARTITION BY HSP_ACCOUNT_ID) AS NoOfCSN -- counts number of csn per har
,count(DEPARTMENT_ID) OVER (PARTITION BY PAT_ENC_CSN_ID) AS NoOfDept -- counts number of Dept per csn
,DEPARTMENT_ID
,DEPARTMENT_NAME
,[Grouper]
,b.PC_Specialty_Other
,CASE WHEN DEPARTMENT_ID IN ('101050015','101025012','101064004','101046002','101053005','101003055'
							,'101013003','101029011','101025002','101042003','101015003','101050028'
							,'101049003','101022003','101027003','101045003','101014003','101016003'
							,'101003052','101003074','101000014') THEN ('2') -- labs
		WHEN DEPARTMENT_ID IN ('101050050','101064009','101053008','101013020','101029010','101003094'
							,'101025020','101050045','101049012','101003095','101045009','101003093'
							,'101014009','101016020') THEN ('3') -- financial assistance
		WHEN PC_Specialty_Other IN ('01_Community Based Primary Care'
								,'02_ZSFG Primary Care'
								,'03_Specialty'
								,'04_Whole Person Integrated Care') THEN ('1') -- this i is the most important element(weight) the lower the num the greater importance 
								--Q: overlapping numbers in different groups 
		--there is a new list 
		ELSE ('3') END AS 'PriorityDept'
,a.APPT_PRC_ID
,CASE WHEN a.APPT_PRC_ID IN ('100000','100002','9000','100001','1781','105751','100006','100003','100007')
		THEN 'Y' ELSE 'N' END AS 'PRC_Telehealth' -- should be the same screning criteria as the 1st script 
,a.PRC_NAME
,PriorityAppt
,ENC_TYPE_C
,ENC_TYPE
,CASE WHEN ENC_TYPE_C IN ('70','76','2532')
		THEN 'Y' ELSE 'N' END AS 'ENC_Telehealth'
FROM EPIC_2019.dbo.EpicTblEncounter a
LEFT JOIN [Finance].[finance].[EPIC_Clinic_Grouping] b on a.DEPARTMENT_ID = b.[Dept ID]
LEFT JOIN #PriorityAppt c on a.APPT_PRC_ID = c.APPT_PRC_ID
WHERE APPT_STATUS_C IN ('2') AND a.APPT_PRC_ID IS NOT NULL
GROUP BY HSP_ACCOUNT_ID, PAT_ENC_CSN_ID,DEPARTMENT_ID
,DEPARTMENT_NAME
,b.Grouper
,b.PC_Specialty_Other
,a.APPT_PRC_ID
,a.PRC_NAME
,PriorityAppt
,ENC_TYPE_C
,ENC_TYPE
) encounters
-- 4,933,700 6/24

--drop table #test_enc1; 
/**
6/23 priorityapp. needed for operations but not needed for reimbursement. priorityapp might not necessarily be clinical visits! 
if combo is (CSN+ HAR) not unique, vlookup might only show lab (not reimbursed or vice versa). -> need to have certain hierarchy in order to get 
correct $. --- working in progress concepts. finetune might be needed. 
combo(CSN+ HAR) as unique key to identify paymeent in both encounter and finance tables. 
**/

--the inner join of 2 tables with 1 importance * 
SELECT * INTO #test_enc1 FROM (
select
HSP_ACCOUNT_ID, PAT_ENC_CSN_ID, NoOfCSN, NoOfDept, DEPARTMENT_ID, DEPARTMENT_NAME, Grouper, PC_Specialty_Other, PriorityDept, APPT_PRC_ID, PRC_NAME, PriorityAppt
,case when HSP_ACCOUNT_ID = HSP_ACCOUNT_ID then SUM((try_cast([PriorityAppt] as int)+(try_cast([prioritydept] as int)))) else 0 end as 'test sum'
FROM #encounters  
where HSP_ACCOUNT_ID is not null
group by HSP_ACCOUNT_ID, PAT_ENC_CSN_ID, NoOfCSN, NoOfDept, DEPARTMENT_ID, DEPARTMENT_NAME, Grouper, PC_Specialty_Other, PriorityDept, APPT_PRC_ID, PRC_NAME, PriorityAppt
) test_enc1

SELECT *
from #ENCOUNTERS

--this identifies the top prioirty combo (department and encounter) for each HAR
--4,806,959 6/23 
--4,933,700 6/24 

--DROP TABLE #PrioirtyTop; 

SELECT * INTO #PrioirtyTop 
FROM (
	SELECT
	HSP_ACCOUNT_ID
	,min([test sum]) AS PrioirtyTop
	FROM #test_enc1
	--where NoOfCSN = 1
	--and grouper is not null and grouper not in ('DPH')
	GROUP BY HSP_ACCOUNT_ID) PrioirtyTop

--if there is no har, it is missing from this list 
--NEED TO RUN THIS
--encounters from EPIC Tbl Encounters and where HAR IS NOT NULL
--4,806,959 6/23/2022
--4,933,700 6/24 
--DROP TABLE #test_enc2; 

SELECT * INTO #test_enc2 FROM (
SELECT
a.*, b.PrioirtyTop
FROM #encounters a INNER JOIN #PrioirtyTop b ON a.hsp_account_id = b.HSP_ACCOUNT_ID) test_enc2

--4,241,724 total rows
--3,876,742 distinct HAR
--1 3,707,392 rows
--2 238,354
--3 69,672
--4 32,516
--5 21,115

--4,809,884 total rows 6/24 
--4,396,778 distincdt HAR 6/24
--1 4,204,097
--2 271,024
--3 79,836
--4 37,296
--5 23,900

-- this is needed. qualifier.
--748,329 6/24AM 
--DROP TABLE #PCFY22; 
-- temp table feeding into 
SELECT * INTO #PCFY22 FROM (
SELECT * FROM finance.dbo.P14_EPIC_Header
WHERE (ADM_DATE_TIME between '2021-07-01' and '2022-05-31')
and HSP_ACCOUNT_ID is not null 
AND IS_VALID_PAT_YN IN ('Y')) PCFY22

--epic encounters table
--6/23/22
--748,307
--6/24
--748,329
--DROP TABLE #EPICencounters; 

--- calculate the CSN encounters from finance header and finance detail tables 
---this is the only table needed for the 2nd SQL script  
SELECT * INTO #EPICencounters FROM (

SELECT
ENC.HSP_ACCOUNT_ID as 'ENC.HSP_ACCOUNT_ID'
,ENC.PAT_ENC_CSN_ID
,hd.HSP_ACCOUNT_ID
,hd.PRIM_ENC_CSN_ID
--,NoOfCSN
--,NoOfDept
--,ENC.ApptSchedTime
--,ENC.ApptCheckinTime
,hd.[ADM_DATE_TIME]
,hd.[DISCH_DATE_TIME]
,DATENAME(MONTH, hd.[ADM_DATE_TIME]) AS Month_Name
,YEAR(hd.[ADM_DATE_TIME]) AS Cal_Yr
,CASE WHEN MONTH(hd.[ADM_DATE_TIME]) < 7 THEN YEAR(hd.[ADM_DATE_TIME]) 
	WHEN MONTH(hd.[ADM_DATE_TIME]) >= 7 THEN YEAR(hd.[ADM_DATE_TIME]) + 1
	END AS FISCAL_YEAR
,CASE WHEN MONTH(hd.[ADM_DATE_TIME])=7 THEN '01Jul' 
	WHEN MONTH(hd.[ADM_DATE_TIME])=8 THEN '02-Aug'
	WHEN MONTH(hd.[ADM_DATE_TIME])=9 THEN '03-Sep'
	WHEN MONTH(hd.[ADM_DATE_TIME])=10 THEN '04-Oct'
	WHEN MONTH(hd.[ADM_DATE_TIME])=11 THEN '05-Nov'
	WHEN MONTH(hd.[ADM_DATE_TIME])=12 THEN '06-Dec'
	WHEN MONTH(hd.[ADM_DATE_TIME])=1 THEN '07-Jan'
	WHEN MONTH(hd.[ADM_DATE_TIME])=2 THEN '08-Feb'
	WHEN MONTH(hd.[ADM_DATE_TIME])=3 THEN '09-Mar'
	WHEN MONTH(hd.[ADM_DATE_TIME])=4 THEN '10-Apr'
	WHEN MONTH(hd.[ADM_DATE_TIME])=5 THEN '11-May'
	WHEN MONTH(hd.[ADM_DATE_TIME])=6 THEN '12-Jun'
	END AS FISCAL_MONTH
--,ENC.APPT_STATUS_C
--,ENC.APPT_STATUS
--,ENC.HOSP_SERV_C
--,ENC.HospService
,[BILL_STATUS]
,BILL_IND
,[ACCT_BILLED_DATE]
,HSP_ACCT_STOP_BILL
,[PAT_MRN]
,[PAT_LAST_NAME]
,[PAT_FIRST_NAME]
,ACCT_BASE_CLASS
,ACCT_CLASS
,SUBSTRING([ACCT_FIN_CLASS],CHARINDEX('{',[ACCT_FIN_CLASS])+1,CHARINDEX('}',[ACCT_FIN_CLASS])-CHARINDEX('{',[ACCT_FIN_CLASS] )-1) AS 'ACCT_FIN_CLASS_ID'
,LEFT([ACCT_FIN_CLASS], CHARINDEX('{',[ACCT_FIN_CLASS]) - 2) AS 'ACCT_FIN_CLASS'
,SERV_PROV_TITLE
,SERV_PROV_NAME
,ADM_PROV_NAME
,ADM_PROV_TITLE
,ATT_PROV_NAME
,ATT_PROV_TITLE
,ENC.DEPARTMENT_ID
,ENC.DEPARTMENT_NAME
,Grouper
,PC_Specialty_Other
,PriorityDept
--,ENC.VisitMD
--,ENC.AttndMD
,ENC.ENC_TYPE_C
,ENC.ENC_TYPE
,ENC.APPT_PRC_ID
,ENC.PRC_NAME
,ENC_Telehealth
,PriorityAppt
,PrioirtyTop
,PRC_Telehealth
,CASE WHEN enc.HSP_ACCOUNT_ID IN 
							(SELECT HSP_ACCOUNT_ID 
							FROM #95_2 
							GROUP BY HSP_ACCOUNT_ID) 
							THEN 'Y' ELSE NULL END AS 'TELEHEALTH_95'
,CASE WHEN enc.HSP_ACCOUNT_ID IN 
							(SELECT HSP_ACCOUNT_ID 
							FROM [Finance].[dbo].[P14_EPIC_Detail] 
							WHERE HCPCS_CODE LIKE ('9944%')
							GROUP BY HSP_ACCOUNT_ID) THEN 'Y' END AS 'TELEHEALTH'
,LOC_NAME
,HB_PB
,HSP_SERV
,LENGTH_OF_STAY
,ADM_SOURCE
,ADM_TYPE
,PAT_STATUS
,[TOT_CHGS]
,[TOT_PMTS]
,[TOT_INS_PMTS]
,[TOT_PAT_PMTS]
,[TOT_ADJ]
,[TOT_INS_ADJ]
,[TOT_PAT_ADJ]
,[TOT_ACCT_BAL]
,ACCT_ZERO_BAL_DT
,SUBSTRING([PYR1_NAME],CHARINDEX('{',[PYR1_NAME])+1,CHARINDEX('}',[PYR1_NAME])-CHARINDEX('{',[PYR1_NAME] )-1) AS 'PYR1_PAYOR_ID'
,LEFT([PYR1_NAME], CHARINDEX('{',[PYR1_NAME]) - 2) AS 'PYR1_NAME'
,SUBSTRING([PYR2_NAME],CHARINDEX('{',[PYR2_NAME])+1,CHARINDEX('}',[PYR2_NAME])-CHARINDEX('{',[PYR2_NAME] )-1) AS 'PYR2_PAYOR_ID'
,LEFT([PYR2_NAME], CHARINDEX('{',[PYR2_NAME]) - 2) AS 'PYR2_NAME'
,SUBSTRING([PYR3_NAME],CHARINDEX('{',[PYR3_NAME])+1,CHARINDEX('}',[PYR3_NAME])-CHARINDEX('{',[PYR3_NAME] )-1) AS 'PYR3_PAYOR_ID'
,LEFT([PYR3_NAME], CHARINDEX('{',[PYR3_NAME]) - 2) AS 'PYR3_NAME'
,SUBSTRING([PYR4_NAME],CHARINDEX('{',[PYR4_NAME])+1,CHARINDEX('}',[PYR4_NAME])-CHARINDEX('{',[PYR4_NAME] )-1) AS 'PYR4_PAYOR_ID'
,LEFT([PYR4_NAME], CHARINDEX('{',[PYR4_NAME]) - 2) AS 'PYR4_NAME'
,PYR1_AID_CODE
,PYR2_AID_CODE
,BAD_DEBT_YN
,MOM_HSP_ACCT_ID
,RUN_DATE
FROM #PCFY22 Hd  
LEFT JOIN #test_enc2 ENC ON
((hd.HSP_ACCOUNT_ID = ENC.HSP_ACCOUNT_ID) AND (hd.PRIM_ENC_CSN_ID = ENC.PAT_ENC_CSN_ID))

) EPICencounters


/*****************************************************/
/*to create joined table of Encounter Only Table and Finance Encounter Table */

DROP TABLE #EPICencounters; 

/*export*/
SELECT
*
FROM #EPICencounters