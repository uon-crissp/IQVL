SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create proc [dbo].[pr_IQVL_SaveLabResult]
  @Patientid varchar(50)
, @OrderDate datetime
, @Reporteddate datetime
, @result decimal(15,0)
, @userid int

as

begin
	declare @ptn_pk int = 0
	declare @labid int
	declare @locationid int
	declare @testresultid int
	declare @Visit_Pk int

	--Get the ptn_pk
	DECLARE @NewLineChar AS CHAR(2) = CHAR(13) + CHAR(10)
	declare @Patientid_aa varchar(50) = @Patientid
	declare @query nvarchar(max)='select top 1 @x = ptn_pk from '+@NewLineChar+'(select ''0'' as ptn_pk'+@NewLineChar
	select @query=@query + 'union select ptn_pk from mst_patient where '+FieldName+'='''+@Patientid_aa+''''+@NewLineChar from mst_PatientIdentifier
	set @query=@query + ') a where a.ptn_pk <> 0'

	declare @ptn_pk_aa int
	set @ptn_pk_aa = 0

	exec sp_executesql @query, N'@x int out', @ptn_pk_aa out

	set @ptn_pk = (select @ptn_pk_aa)

	set @locationid = (select top 1 FacilityID from mst_Facility where DeleteFlag=0 order by FacilityID)

	if(isnull(@ptn_pk,0) <> 0)
	begin
		set @testresultid = (select case when @result=0.0 then 9998 else 9999 end)

		if exists(select top 1 * from ord_PatientLabOrder where Ptn_pk=@ptn_pk and OrderedbyDate=@OrderDate)
		begin
			set @labid = (select top 1 LabID from ord_PatientLabOrder where Ptn_pk=@ptn_pk and OrderedbyDate=@OrderDate)

			if exists(select * from dtl_PatientLabResults where LabID=@labid and LabTestID=3 and ParameterID=3)
			begin
				update dtl_PatientLabResults set TestResults=@result,TestResultId=@testresultid,ResultReportBy=@userid,ResultReportDate=@Reporteddate
				, UrgentFlag=0, Confirmed=0, Confirmedby=0
				where LabID=@labid and LabTestID=3 and ParameterID=3
			end
			else
			begin
				insert into dtl_PatientLabResults(labid,LocationID,LabTestID,ParameterID,TestResults, TestResultId,
					Financed, UserID,CreateDate,ResultReportBy,ResultReportDate,UrgentFlag,RejectFlag, Confirmed, Confirmedby)
				values(@labid,@locationid,3,3,@result,@testresultid,1,@userid,getdate(),@userid,@Reporteddate,0,0,0,0)
			end
		end
		else
		begin
			INSERT INTO ord_Visit(Ptn_pk,LocationId,VisitDate,VisitType,DataQuality,UserID,Createdate,OrderedDate)
			VALUES (@Ptn_pk,@locationid,CONVERT(DATETIME, @OrderDate, 103),6,0,1,GETDATE(),CONVERT(DATETIME, @OrderDate, 103))

			SET @Visit_Pk = IDENT_CURRENT('ord_Visit')

			INSERT INTO ord_PatientLabOrder (Ptn_pk,LocationId,OrderedByName,OrderedByDate,Createdate,UserID,VisitID,ReportedByName,ReportedByDate)
			VALUES (@Ptn_pk,@locationid,1,CONVERT(DATETIME, @OrderDate, 103),GETDATE(),@userid,@Visit_Pk,@userid,CONVERT(DATETIME, @Reporteddate, 103))

			SET @LabId = IDENT_CURRENT('ord_PatientLabOrder')

			UPDATE ord_PatientLabOrder
			SET LabNumber = REPLACE(CONVERT(VARCHAR(10), OrderedbyDate, 102), '.', '') + '-' + REPLICATE('0', 7 - LEN(@LabId)) + CONVERT(VARCHAR, @LabId)
			WHERE ord_PatientLabOrder.LabID = @LabId

			INSERT INTO Dtl_PatientLabResults (LabID,LocationId,LabTestID,ParameterID,Financed,UserID,CreateDate,
			UrgentFlag, TestResults, TestResultId,ResultReportBy,ResultReportDate,RejectFlag, Confirmed, Confirmedby)
			values(@LabId,@locationid,3,3,1,@userid,GETDATE(),0,@result,@testresultid,@userid,@Reporteddate,0,0,0)
		end
	end
	else
	begin
		declare @errormsg varchar(100) = 'patient not found'
		RAISERROR (@errormsg,16,1)
	end
end
go
--==

create proc pr_IQVL_LoadVLOrders 
  @fromdate datetime
, @todate datetime

as

Declare @allIDs as nvarchar(4000)
Select @allIDs = stuff((select ',Case When Cast(pt.[' + cast(fieldName as VARCHAR(1000))+ '] as varchar(50)) = '''' Then Null Else  Cast(pt.[' + cast(fieldName as VARCHAR(1000))+ '] as varchar(50)) End '  
from mst_patientidentifier for xml PATH('')),1,1,'')

exec('
Open symmetric key Key_CTC decryption by password=''ttwbvXWpqb5WOLfLrBgisw==''
select
convert(varchar(100),decryptbykey(pt.firstname)) + '' '' + convert(varchar(100),decryptbykey(pt.MiddleName)) + '' '' +  convert(varchar(100),decryptbykey(pt.LastName)) as FullName,
plabs.LabId,

Cast(coalesce('+@allIDs+') as varchar(50)) ClientIPNo,

f.FacilityName,f.SatelliteID as MFLCode, CASE dc.Name
    WHEN ''Female'' THEN ''2''
    WHEN ''Male'' THEN ''1''
  END AS [Sex]
  , pt.DOB
  , DATEDIFF(HOUR, pt.DOB, GETDATE()) / 8766 AS Age
   ,''1'' as SampleType
,plabs.OrderedbyDate as [DateofRequest]
  ,CASE WHEN plabs.ReceivedDatetime is null then plabs.OrderedbyDate else plabs.ReceivedDatetime  end AS[DateSampleCollected] 
  ,CASE 
    WHEN
    arv.regimen LIKE   ''%3TC+EFV+TDF'' THEN ''4''
    WHEN  
	arv.regimen LIKE ''%EFV/3TC/TDF'' THEN ''4''
	when
	 arv.regimen LIKE
	 ''%3TC/TDF/EFV'' then ''4''
    WHEN
	
	arv.regimen LIKE ''%3TC+AZT+NVP'' THEN ''1''
	WHEN 
	arv.regimen LIKE''%AZT/3TC/NVP'' then  ''1''
    WHEN 
	arv.regimen LIKE ''%NVP/3TC/AZT'' THEN ''1''
	WHEN
	arv.regimen like ''%3TC/NVP/AZT%'' then ''1''
    WHEN 
	arv.regimen LIKE ''%3TC+AZT+EFV'' THEN ''2''
	when 
	arv.regimen like ''%3TC/AZT/EFV%'' then ''2''
	WHEN 
	arv.regimen LIKE ''%AZT/3TC/EFV'' then ''2''
    WHEN 
	 arv.regimen LIKE ''%EFV/3TC/AZT'' THEN ''2''
	WHEN 
	arv.regimen LIKE ''%3TC/NVP/TDF'' then ''3''
	WHEN 
	arv.regimen LIKE ''%3TC/TDF/NVP%'' then ''3''
    WHEN 
	arv.regimen LIKE ''%3TC+NVP+TDF'' THEN ''3''
    WHEN 
	arv.regimen LIKE ''%NVP/3TC/TDF'' THEN ''3''
    WHEN 
	 arv.regimen LIKE ''%3TC+AZT+LPV/r'' THEN ''5''
	WHEN  
   arv.regimen LIKE 	''%3TC/AZT/LOPr''   THEN ''5''
	WHEN 
   arv.regimen LIKE 	''%3TC/AZT/LPV/r'' then ''5''
	WHEN 
  arv.regimen LIKE	''%LOPr/3TC/AZT''  then ''5''
    WHEN 
 arv.regimen LIKE	''%LPVr/3TC/AZT'' THEN ''5''
    WHEN  
arv.regimen LIKE	''%3TC+ABC+AZT'' THEN ''6''
    WHEN 
   arv.regimen LIKE	''%3TC/ABC/AZT'' then ''6''
    WHEN 
	arv.regimen LIKE ''%ABC/3TC/AZT'' THEN ''6''
    WHEN 
	arv.regimen LIKE ''%3TC+LPVr+TDF'' THEN ''7''
	WHEN arv.regimen like ''%3TC/TDF/LOPr%'' then ''7''
	WHEN arv.regimen like ''%3TC/LOPr/TDF%'' then ''7''
    WHEN 
	 arv.regimen LIKE  ''%LOPr/3TC/TDF%'' THEN ''7''
    WHEN 
	 arv.regimen LIKE  ''%LPVr/3TC/TDF%'' THEN ''7''
    WHEN 
	arv.regimen LIKE
	''%3TC+ATVr+AZT%'' THEN ''8''
    WHEN 
     arv.regimen LIKE	''%ATVr/3TC/AZT%'' THEN ''8''
    WHEN 
     arv.regimen LIKE	''%3TC+ATVr+TDF%'' THEN ''9''
    WHEN 
	 arv.regimen LIKE  ''%ATVr/3TC/TDF%'' THEN ''9''
    WHEN 
    arv.regimen LIKE 	''%3TC+ABC+ATVr%'' THEN ''10''
	WHEN  
    arv.regimen LIKE 	''%3TC/ABC/ATVr%'' then''10''
    WHEN 
	 arv.regimen LIKE  ''%ATVr/3TC/ABC%'' THEN ''10''
    WHEN 
	arv.regimen LIKE  ''%3TC+ABC+NVP%'' THEN ''11''
	WHEN 
	arv.regimen LIKE  ''%3TC/ABC/NVP%'' then ''11''
	WHEN 
	  arv.regimen LIKE ''%ABC/3TC/NVP%'' then ''11''
    WHEN  
	arv.regimen LIKE ''%NVP/3TC/ABC%'' THEN ''11''
    WHEN 
	arv.regimen LIKE  ''%3TC+ABC+EFV%'' THEN ''12''
	WHEN  
	arv.regimen LIKE ''%3TC/ABC/EFV%'' then ''12''
	WHEN  
	arv.regimen LIKE ''%ABC/3TC/EFV%'' then ''12''
    WHEN 
	arv.regimen LIKE ''%EFV/3TC/ABC%'' THEN ''12''

    WHEN arv.regimen LIKE  ''%3TC+ABC+LPVr%'' THEN ''13''
	WHEN arv.regimen LIKE ''%3TC/ABC/LOPr%'' then ''13''
	WHEN arv.regimen LIKE ''%LOPr/ABC/3TC%'' then ''13''
    WHEN arv.regimen LIKE ''%LPVr/3TC/ABC%'' THEN ''13''
    WHEN arv.regimen LIKE ''Other'' THEN ''14''
    WHEN  arv.regimen LIKE ''None'' THEN ''15''
    WHEN arv.regimen like  NULL  THEN ''16''
    WHEN arv.regimen LIKE ''%No Data'' THEN ''16''
	ELSE ''0''
  END AS [Current Regimen],
  arv.dispenseDate[Current ART Start Date],
  arvinitial.dispenseDate AS[Date Started On ART],
 CASE WHEN  plabs.Justification is null then ''0'' else plabs.Justification end  AS Justification,
 cast(convert(varchar, GETDATE(), 106) as datetime) AS DateReceived

from(
select a.LabID, a.Ptn_pk, a.LocationID, a.OrderedByName, a.OrderedByDate, a.ReportedByName, a.ReportedByDate, a.CheckedByName, a.CheckedByDate, a.PreClinicLabDate,CAST(Convert(nvarchar(10),lsp.ReceivedDatetime,101) as datetime) as ReceivedDatetime,
 a.LabPeriod,  b.Justification,


b.LabTestID, c.SubTestId, b.TestResults, b.TestResults1, b.TestResultId, b.Financed,

c.subtestname[SubTestName], d.LabTypeID ''LabTypeID'', d.LabName, b.Units, e.name as UnitName,

f.MinBoundaryValue, f.MaxBoundaryValue, a.LabNumber

from ord_PatientlabOrder a
left join mst_LabSpecimen  lsp   on lsp.LabID=a.LabID

inner join dtl_PatientLabResults b on a.labid = b.labid

left outer join mst_Decode e on e.Id= b.Units


left outer join lnk_labValue f on  f.UnitId= b.units and f.SubTestId= b.ParameterId

left outer join lnk_testParameter c on c.subtestid= b.parameterId

inner join mst_labtest d on c.testid= d.labtestid
where d.LabName like ''%Viral%'' and (a.DeleteFlag=''0'' or a.DeleteFlag is null))plabs
inner join mst_patient pt on pt.Ptn_pk=plabs.Ptn_Pk
LEFT JOIN mst_Facility f
  ON f.FacilityID = pt.LocationID
left join mst_Decode dc on dc.ID=pt.Sex
left join(
select arvlist.Ptn_Pk, arvlist.dispenseDate,
arvlist.regimen from(select arv.Ptn_Pk, arv.regimen, arv.dispenseDate, ROW_NUMBER() OVER(partition by arv.Ptn_pk order by arv.VisitID desc) as rownum from(Select Distinct
   m.Ptn_pk,
   a.VisitID,
   a.DispensedByDate dispenseDate,

   Case When g.RegimenType = '''' Then f.DrugName Else g.RegimenType End As regimen,
    SubString(g.RegimenType, 0, 4) [1],
Case
When CharIndex(''/'', g.RegimenType) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType) + 1, 3) End As[2],
Case
When CharIndex(''/'', g.RegimenType, 6) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType, 6) + 1, 3) Else Null End As[3],
Case
When CharIndex(''/'', g.RegimenType, 10) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType, 10) + 1, 3) Else Null End As[4],
Case
When CharIndex(''/'', g.RegimenType, 14) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType, 14) + 1, 3) Else Null End As[5],
--Max(b.Duration) duration,
h.Name Provider,
j.Name regimenLine,
i.Name treatmentType

From mst_Patient m
LEFT Join ord_PatientPharmacyOrder a On m.Ptn_Pk = a.Ptn_pk
LEFT join dtl_PatientPharmacyOrder b On a.ptn_pharmacy_pk = b.ptn_pharmacy_pk
LEFT join lnk_DrugGeneric c on b.Drug_Pk = c.Drug_pk
LEFT join lnk_DrugTypeGeneric d on c.GenericID = d.GenericId
LEFT join mst_DrugType e on d.DrugTypeId = e.DrugTypeID
LEFT join mst_Drug f on b.Drug_Pk = f.Drug_pk
LEFT Join dtl_RegimenMap g On a.VisitID = g.Visit_Pk
LEFT Join mst_Provider h On a.ProviderID = h.ID
LEFT Join mst_Decode i On a.ProgID = i.ID
LEFT Join mst_RegimenLine j On a.RegimenLine = j.ID

Where
m.RegistrationDate <= a.DispensedByDate

AND e.DrugTypeName = ''ARV Medication''
AND(a.DeleteFlag = 0 OR a.DeleteFlag IS NULL)
AND(m.DeleteFlag = 0 OR m.DeleteFlag IS NULL)
)arv )arvlist where arvlist.rownum=''1'')arv on arv.Ptn_Pk=pt.Ptn_Pk
left join(
select arvlist.Ptn_Pk, arvlist.dispenseDate,
arvlist.regimen from(select arv.Ptn_Pk, arv.regimen, arv.dispenseDate, ROW_NUMBER() OVER(partition by arv.Ptn_pk order by arv.VisitID asc) as rownum from(Select Distinct
   m.Ptn_pk,
   a.VisitID,
   a.DispensedByDate dispenseDate,

   Case When g.RegimenType = '''' Then f.DrugName Else g.RegimenType End As regimen,
    SubString(g.RegimenType, 0, 4) [1],
Case
When CharIndex(''/'', g.RegimenType) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType) + 1, 3) End As[2],
Case
When CharIndex(''/'', g.RegimenType, 6) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType, 6) + 1, 3) Else Null End As[3],
Case
When CharIndex(''/'', g.RegimenType, 10) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType, 10) + 1, 3) Else Null End As[4],
Case
When CharIndex(''/'', g.RegimenType, 14) > 0 Then SubString(g.RegimenType,
CharIndex(''/'', g.RegimenType, 14) + 1, 3) Else Null End As[5],
h.Name Provider,
j.Name regimenLine,
i.Name treatmentType
From mst_Patient m
LEFT Join ord_PatientPharmacyOrder a On m.Ptn_Pk = a.Ptn_pk
LEFT join dtl_PatientPharmacyOrder b On a.ptn_pharmacy_pk = b.ptn_pharmacy_pk
LEFT join lnk_DrugGeneric c on b.Drug_Pk = c.Drug_pk
LEFT join lnk_DrugTypeGeneric d on c.GenericID = d.GenericId
LEFT join mst_DrugType e on d.DrugTypeId = e.DrugTypeID
LEFT join mst_Drug f on b.Drug_Pk = f.Drug_pk
LEFT Join dtl_RegimenMap g On a.VisitID = g.Visit_Pk
LEFT Join mst_Provider h On a.ProviderID = h.ID
LEFT Join mst_Decode i On a.ProgID = i.ID
LEFT Join mst_RegimenLine j On a.RegimenLine = j.ID

Where
m.RegistrationDate <= a.DispensedByDate

AND e.DrugTypeName = ''ARV Medication''
AND(a.DeleteFlag = 0 OR a.DeleteFlag IS NULL)
AND(m.DeleteFlag = 0 OR m.DeleteFlag IS NULL)
)arv )arvlist where arvlist.rownum=''1'')arvinitial on arvinitial.Ptn_Pk=pt.Ptn_Pk
where plabs.TestResults is null and plabs.OrderedbyDate  between cast('''+@fromdate+''' as datetime) and cast('''+@todate+'''  as datetime)
and plabs.TestResultId is null
')
go