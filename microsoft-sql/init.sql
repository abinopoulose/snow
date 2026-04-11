USE [master];
GO

-- 1. Create the Database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'${DB_NAME}')
    CREATE DATABASE [${DB_NAME}];
GO

USE [${DB_NAME}];
GO

-- 2. Enable CDC at the Database Level (The "Master Switch")
IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = '${DB_NAME}') = 0
BEGIN
    EXEC sys.sp_cdc_enable_db;
END
GO

-- 3. Create Login, User, and Permissions
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'${DB_USER}')
BEGIN
    CREATE LOGIN [${DB_USER}] WITH PASSWORD = N'${DB_PASS}', CHECK_POLICY = OFF;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'${DB_USER}')
BEGIN
    CREATE USER [${DB_USER}] FOR LOGIN [${DB_USER}];
END
GO

EXEC sp_addrolemember N'db_datareader', N'${DB_USER}';
EXEC sp_addrolemember N'db_datawriter', N'${DB_USER}';

-- Ensure the user can read the CDC logs
IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'cdc')
BEGIN
    GRANT SELECT ON SCHEMA::[cdc] TO [${DB_USER}];
END
GO