#!/bin/bash
export $(grep -v '^#' .env | xargs)

echo "Setting up Master Node and Publication for ${DB_NAME}..."

# Resolve "Invalid working directory" for Distribution publisher
sudo docker exec mssql-master bash -c "mkdir -p /var/opt/mssql/ReplData && chown -R 10001:0 /var/opt/mssql/ReplData" || true

sudo docker run --rm -i --network host mcr.microsoft.com/mssql-tools /opt/mssql-tools/bin/sqlcmd -S 127.0.0.1 -U sa -P "${MSSQL_SA_PASSWORD}" <<EOF

-- 1. Create/Patch Database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = '${DB_NAME}')
    CREATE DATABASE [${DB_NAME}];
GO

-- 2. APPLY FINTECH HIGH-TPS PATCHES
USE [${DB_NAME}];
GO
ALTER DATABASE [${DB_NAME}] SET ACCELERATED_DATABASE_RECOVERY = ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [${DB_NAME}] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;

-- Pre-allocate log file
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

-- 5. Setup Distribution
USE master;
GO
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'distribution')
BEGIN
    EXEC sp_adddistributor @distributor = @@servername;
    EXEC sp_adddistributiondb @database = 'distribution';
    EXEC sp_adddistpublisher @publisher = @@servername, @distribution_db = 'distribution';
END
GO

-- 6. Setup Publication
USE [${DB_NAME}];
GO
EXEC sp_replicationdboption @dbname = '${DB_NAME}', @optname = 'publish', @value = 'true';
GO

EXEC sp_addpublication @publication = 'Pub_Model_Positions', @status = 'active', @allow_push = 'true', @allow_pull = 'true';
GO

EXEC sp_addpublication_snapshot @publication = 'Pub_Model_Positions', @publisher_security_mode = 0, @publisher_login = 'sa', @publisher_password = '${MSSQL_SA_PASSWORD}';
GO

EXEC sp_addarticle @publication = 'Pub_Model_Positions', @article = 'model_positions', @source_object = 'model_positions', @type = N'logbased', @pre_creation_cmd = N'delete';
GO

EXEC sp_addsubscription 
    @publication = 'Pub_Model_Positions', 
    @subscriber = '${REPLICA_DB_HOST},${REPLICA_DB_PORT}', 
    @destination_db = '${DB_NAME}';
GO

EXEC sp_addpushsubscription_agent 
    @publication = 'Pub_Model_Positions', 
    @subscriber = '${REPLICA_DB_HOST},${REPLICA_DB_PORT}', 
    @subscriber_db = '${DB_NAME}', 
    @subscriber_security_mode = 0, 
    @subscriber_login = 'sa', 
    @subscriber_password = '${MSSQL_SA_PASSWORD}';
GO

-- Ensure Snapshot Agent starts
EXEC sp_startpublication_snapshot @publication='Pub_Model_Positions';
GO

-- 7. App User Setup
USE master;
GO
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'${DB_APP_USER}')
    CREATE LOGIN [${DB_APP_USER}] WITH PASSWORD = '${DB_APP_PASSWORD}';
GO

USE [${DB_NAME}];
GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'${DB_APP_USER}')
    CREATE USER [${DB_APP_USER}] FOR LOGIN [${DB_APP_USER}];
ALTER ROLE db_datawriter ADD MEMBER [${DB_APP_USER}];
ALTER ROLE db_datareader ADD MEMBER [${DB_APP_USER}];
GO

PRINT 'Master Node Setup Complete.';
EOF

echo "Master process complete."
