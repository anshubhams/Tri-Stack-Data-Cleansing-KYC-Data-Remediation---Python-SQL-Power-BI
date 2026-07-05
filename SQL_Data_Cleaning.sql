-- 1. Create the table and import the raw data:

create table raw_banking_data(
	Transaction_timestamp varchar(50),
	Customer_ID varchar(50),
	KYC_Approval_Date varchar(50),
	Customer_Metadata TEXT,
	Fraud_Score varchar(50),
	Account_Details varchar(100)	
);
-- Checking the data import:
select * from raw_banking_data Limit 5;


-- 2. FIX the messy dates using CTE:
with cleaned_dates as (
	select 
		*,
		case

			when KYC_Approval_Date ~ '^[0-9]{5}$'
			then cast('1899-12-30'::DATE + cast(KYC_Approval_Date as INT) * interval '1 day' as DATE)
			
			when KYC_Approval_Date ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
			then to_date(KYC_Approval_Date, 'DD-MM-YYYY')
			
			when KYC_Approval_Date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
			then to_date(KYC_Approval_Date, 'MM/DD/YYYY')
			
			else NULL			
		end as KYC_approval_date_clean
	from raw_banking_data
	),
-- 3. EXTRACT risk tier from messy Metadata column:
cleaned_json as (
	select *,
	case
		-- If it's the legacy plain text string, do a fast keyword search
		when Customer_Metadata like '%High%' then 'High'
		when Customer_Metadata like '%Medium%' then 'Medium'
		when Customer_Metadata like '%Low%' then 'Low'
		when Customer_Metadata like '{"risk_tier"%}' 
		-- If it looks like JSON, isolate the JSON text block and extract 'risk_tier'
		then cast(split_part(Customer_Metadata, '-', 1) as JSON) ->> 'risk_tier'
		else 'Unknown'
	end as Risk_Tier_Clean
	from cleaned_dates
),
-- 4. Removing Duplicate entries by checking latest timestamps:
deduplicated_data as(
	select 
		*,
		row_number() OVER(partition by Customer_ID order by Transaction_timestamp desc) as row_num
	from cleaned_json	
),
-- 5. FIXING account types and fraud scores:
fully_cleaned as(
	select
		*,
		-- Fix Fraud Score: Handle text anomalies AND the -999 outlier using Regex:
		CASE 
			WHEN Fraud_Score IS NULL OR Fraud_Score IN ('NULL', 'N/A') THEN NULL
			WHEN Fraud_Score ~ '^-?[0-9]+(\.[0-9]+)?$' AND CAST(Fraud_Score AS DECIMAL(5,2)) < 0 THEN NULL
			WHEN Fraud_Score ~ '^-?[0-9]+(\.[0-9]+)?$' THEN CAST(Fraud_Score AS DECIMAL(5,2))
			ELSE NULL 
		END AS Fraud_Score_Clean,
		-- Fix Account Details: Standardize mixed separators (_, -, |) to underscores first:
		split_part(
		replace(replace(Account_Details, '|', '_'), '-', '_'), 
		'_' ,1
		) as Account_type
	from deduplicated_data
	where row_num = 1		
)
-- Checking if our code works:
select *
from fully_cleaned 
limit 10;

-- CREATE A NEW TABLE AFTER ENTIRE CLEANING with CTEs (this is done at last)
CREATE TABLE cleaned_customer_transactions AS
-- 2. FIX the messy dates using CTE:
with cleaned_dates as (
	select 
		*,
		case

			when KYC_Approval_Date ~ '^[0-9]{5}$'
			then cast('1899-12-30'::DATE + cast(KYC_Approval_Date as INT) * interval '1 day' as DATE)
			
			when KYC_Approval_Date ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
			then to_date(KYC_Approval_Date, 'DD-MM-YYYY')
			
			when KYC_Approval_Date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
			then to_date(KYC_Approval_Date, 'MM/DD/YYYY')
			
			else NULL			
		end as KYC_approval_date_clean
	from raw_banking_data
	),
-- 3. EXTRACT risk tier from messy Metadata column:
cleaned_json as (
	select *,
	case
		-- If it's the legacy plain text string, do a fast keyword search
		when Customer_Metadata like '%High%' then 'High'
		when Customer_Metadata like '%Medium%' then 'Medium'
		when Customer_Metadata like '%Low%' then 'Low'
		when Customer_Metadata like '{"risk_tier"%}' 
		-- If it looks like JSON, isolate the JSON text block and extract 'risk_tier'
		then cast(split_part(Customer_Metadata, '-', 1) as JSON) ->> 'risk_tier'
		else 'Unknown'
	end as Risk_Tier_Clean
	from cleaned_dates
),
-- 4. Removing Duplicate entries by checking latest timestamps:
deduplicated_data as(
	select 
		*,
		row_number() OVER(partition by Customer_ID order by Transaction_timestamp desc) as row_num
	from cleaned_json	
),
-- 5. FIXING account types and fraud scores:
fully_cleaned as(
	select
		*,
		-- Fix Fraud Score: Handle text anomalies AND the -999 outlier using Regex:
		CASE 
			WHEN Fraud_Score IS NULL OR Fraud_Score IN ('NULL', 'N/A') THEN NULL
			WHEN Fraud_Score ~ '^-?[0-9]+(\.[0-9]+)?$' AND CAST(Fraud_Score AS DECIMAL(5,2)) < 0 THEN NULL
			WHEN Fraud_Score ~ '^-?[0-9]+(\.[0-9]+)?$' THEN CAST(Fraud_Score AS DECIMAL(5,2))
			ELSE NULL 
		END AS Fraud_Score_Clean,
		-- Fix Account Details: Standardize mixed separators (_, -, |) to underscores first:
		split_part(
		replace(replace(Account_Details, '|', '_'), '-', '_'), 
		'_' ,1
		) as Account_type
	from deduplicated_data
	where row_num = 1		
)
select *
from fully_cleaned;