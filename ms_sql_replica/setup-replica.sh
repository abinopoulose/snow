#!/bin/bash
export $(grep -v '^#' .env | xargs)

echo "Setting up Replica Node and CDC for ${DB_NAME} from ${MASTER_DB_HOST}..."

sudo docker run --rm -i --network host mcr.microsoft.com/mssql-tools /opt/mssql-tools/bin/sqlcmd -S 127.0.0.1,1434 -U sa -P "${MSSQL_SA_PASSWORD}" <<EOF

-- 1. Create Subscriber Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '${DB_NAME}')
    CREATE DATABASE [${DB_NAME}];
GO

USE master;
GO
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 2560; RECONFIGURE;
GO

-- 2. Pre-create table structure because CDC requires it to run 'sp_cdc_enable_table'
USE [${DB_NAME}];
GO
IF OBJECT_ID('dbo.model_positions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.model_positions (
        model_ticker VARCHAR(50) NOT NULL,
        security_ticker VARCHAR(50) NOT NULL,
        allocation_percentage DECIMAL(5,2),
        drift_percentage DECIMAL(5,2),
        CONSTRAINT PK_ModelPos PRIMARY KEY (model_ticker, security_ticker)
    );
END
GO

-- Note: Master is configured to use a PUSH subscription, so no pull agent is needed here.

-- 4. ENABLE CDC ON REPLICA DATABASE
IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = '${DB_NAME}') = 0
BEGIN
    PRINT 'Enabling CDC on Replica database...';
    EXEC sys.sp_cdc_enable_db;
END
GO

-- 5. ENABLE CDC ON TABLE
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'model_positions' AND is_tracked_by_cdc = 0)
BEGIN
    PRINT 'Enabling CDC on model_positions table...';
    EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'model_positions', @role_name = NULL;
END
GO

-- 6. CDC Job Tuning 
EXEC sys.sp_cdc_change_job @job_type = N'capture', @maxtrans = 5000, @pollinginterval = 1; 
GO

-- 7. Create Dedicated CDC User for Debezium
USE master;
GO
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'${CDC_USER}')
BEGIN
    CREATE LOGIN [${CDC_USER}] WITH PASSWORD = '${CDC_PASSWORD}';
END
GRANT VIEW SERVER STATE TO [${CDC_USER}];
GO

USE [${DB_NAME}];
GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'${CDC_USER}')
BEGIN
    CREATE USER [${CDC_USER}] FOR LOGIN [${CDC_USER}];
END
ALTER ROLE db_datareader ADD MEMBER [${CDC_USER}];
GO

PRINT 'Replica Setup and CDC enabled.';
WAITFOR DELAY '00:00:02';
GO
QUIT
EOF

echo "Replica process complete."