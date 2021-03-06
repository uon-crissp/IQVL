alter table dtl_patientlabresults add ResultReportBy int
go
alter table dtl_patientlabresults add ResultReportDate datetime
go
alter table dtl_patientlabresults add UrgentFlag int
go
alter table dtl_patientlabresults add RejectFlag int
go
alter table dtl_patientlabresults add Confirmed int
go
alter table dtl_patientlabresults add Confirmedby int
go
alter table dtl_patientlabresults add justification int
go

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
	select @query=@query + 'union select ptn_pk from mst_patient where '+FieldName+' like ''%'+@Patientid_aa+''''+@NewLineChar from mst_PatientIdentifier
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

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create proc [dbo].[pr_IQVL_LoadVLOrders] 
  @fromdate datetime
, @todate datetime

as

Declare @allIDs as nvarchar(4000)
Select @allIDs = stuff((select ',Case When Cast(a.[' + cast(fieldName as VARCHAR(1000))+ '] as varchar(50)) = '''' Then Null Else  Cast(a.[' + cast(fieldName as VARCHAR(1000))+ '] as varchar(50)) End '  
from mst_patientidentifier for xml PATH('')),1,1,'')

exec('
Open symmetric key Key_CTC decryption by password=''ttwbvXWpqb5WOLfLrBgisw==''

if exists(select * from sysobjects where name=''tempPharmacyData'' and type=''u'')
	drop table tempPharmacyData

select a.Ptn_Pk, a.visitdate as DispenseDate, b.RegimenType
, ROW_NUMBER() over(partition by a.ptn_pk order by a.visitdate desc) VLNo
into tempPharmacyData
from ord_Visit a
inner join dtl_RegimenMap b on a.Visit_Id=b.Visit_Pk where len(b.RegimenType) > 10

select convert(varchar(100),decryptbykey(a.firstname)) 
	+ '' '' + convert(varchar(100),decryptbykey(a.MiddleName)) 
	+ '' '' +  convert(varchar(100),decryptbykey(a.LastName)) as FullName
, b.LabID
, Cast(coalesce('+@allIDs+') as varchar(50)) ClientIPNo
, (select top 1 x.FacilityName from mst_Facility x where x.FacilityID=a.LocationID) as FacilityName
, (select top 1 x.SatelliteID from mst_Facility x where x.FacilityID=a.LocationID) as MFLCode
, CASE when a.Sex=1 then 1 else 2 end as Sex
, a.DOB
, DATEDIFF(HOUR, a.DOB, GETDATE()) / 8766 AS Age
,''1'' as SampleType
, b.OrderedbyDate as [DateofRequest]
, b.OrderedbyDate AS [DateSampleCollected]
, (select top 1 x.RegimenType from tempPharmacyData x where x.Ptn_Pk=a.Ptn_Pk) as [Current Regimen]
, (select top 1 x.DispenseDate from tempPharmacyData x where x.Ptn_Pk=a.Ptn_Pk) as [Current ART Start Date]
, (select min(x.StartDate) from Lnk_PatientProgramStart x 
	inner join mst_module y on x.ModuleId=y.ModuleID
	where y.ModuleName in (''CCC Patient Card MoH 257'',''KNH SMART ART FORMS'') and x.Ptn_pk=a.Ptn_Pk) AS [Date Started On ART]
, 0 AS Justification
, cast(convert(varchar, GETDATE(), 106) as datetime) AS DateReceived
from mst_Patient a
inner join ord_PatientLabOrder b on a.Ptn_Pk=b.Ptn_pk
inner join dtl_PatientLabResults c on b.LabID = c.LabID and c.LabTestID=3 and c.ParameterID=3
where c.TestResultid is null
and b.OrderedbyDate between cast('''+@fromdate+''' as datetime) and cast('''+@todate+'''  as datetime)
')
go