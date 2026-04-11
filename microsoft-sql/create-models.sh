#!/bin/bash
export $(grep -v '^#' .env | xargs)

echo "Applying High-TPS Fintech Patches to ${DB_NAME}..."

sudo docker run --rm -i --network host mcr.microsoft.com/mssql-tools \
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" <<EOF

-- 1. Create/Patch Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '${DB_NAME}')
    CREATE DATABASE [${DB_NAME}];
GO

-- 2. APPLY FINTECH HIGH-TPS PATCHES
-- NOTE: Delayed Durability is incompatible with CDC, so we rely on ADR and RCSI for stability.
USE [${DB_NAME}];
GO
ALTER DATABASE [${DB_NAME}] SET ACCELERATED_DATABASE_RECOVERY = ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [${DB_NAME}] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;

-- Pre-allocate log file to prevent fragmentation and growth pauses
ALTER DATABASE [${DB_NAME}] MODIFY FILE ( NAME = '${DB_NAME}_log', SIZE = 1024MB, FILEGROWTH = 512MB );
GO

-- 3. Performance Configurations
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 6144; RECONFIGURE;
EXEC sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE;
GO

-- 4. Table Structure
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
    ALTER TABLE dbo.model_positions SET (LOCK_ESCALATION = DISABLE);
END
GO

-- 5. ENABLE CDC
IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = '${DB_NAME}') = 0
BEGIN
    PRINT 'Enabling CDC...';
    EXEC sys.sp_cdc_enable_db;
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'model_positions' AND is_tracked_by_cdc = 0)
BEGIN
    EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'model_positions', @role_name = NULL;
END
GO

-- 6. CDC Job Tuning
EXEC sys.sp_cdc_change_job @job_type = N'capture', @maxtrans = 5000, @pollinginterval = 5; 
GO

PRINT 'Stress-test ready configuration applied.';
EOF

echo "Process complete."