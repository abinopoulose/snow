#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "==================================================="
echo "          Environment Configurator"
echo "==================================================="
echo ""

# Function to dynamically generate .env files
generate_envs() {
    echo "    -> Generating new .env files..."
    
    # Grab the primary LAN IP of this machine
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    echo "    -> Detected Private IP: $PRIVATE_IP"
    echo ""
    
    echo "    -> Please enter your Snowflake credentials (these will be injected into consumer/.env):"
    read -p "       Account:" SF_ACCOUNT
    read -p "       User:" SF_USER
    read -s -p "       Password:" SF_PASSWORD
    echo ""
    read -p "       Warehouse:" SF_WAREHOUSE
    read -p "       Database:" SF_DATABASE
    read -p "       Schema:" SF_SCHEMA
    echo ""

    # Loop through the folders and inject the values
    for dir in "ms_sql_master" "ms_sql_replica" "broker" "consumer" "load_test"; do
        if [ -f "$dir/.env.example" ]; then
            cp "$dir/.env.example" "$dir/.env"
            
            # Replace Replica IP (for Master/Replica/Broker)
            sed -i "s/^REPLICA_DB_HOST=.*/REPLICA_DB_HOST=${PRIVATE_IP}/" "$dir/.env"
            
            # Replace DB_HOST with Private IP (for load_test)
            sed -i "s/^DB_HOST=.*/DB_HOST=${PRIVATE_IP}/" "$dir/.env"
            
            # Replace Snowflake Configs (Using | as delimiter to safely handle passwords with / symbols)
            sed -i "s|^SNOWFLAKE_ACCOUNT=.*|SNOWFLAKE_ACCOUNT=${SF_ACCOUNT}|" "$dir/.env"
            sed -i "s|^SNOWFLAKE_USER=.*|SNOWFLAKE_USER=${SF_USER}|" "$dir/.env"
            sed -i "s|^SNOWFLAKE_PASSWORD=.*|SNOWFLAKE_PASSWORD=${SF_PASSWORD}|" "$dir/.env"
            sed -i "s|^SNOWFLAKE_WAREHOUSE=.*|SNOWFLAKE_WAREHOUSE=${SF_WAREHOUSE}|" "$dir/.env"
            sed -i "s|^SNOWFLAKE_DATABASE=.*|SNOWFLAKE_DATABASE=${SF_DATABASE}|" "$dir/.env"
            sed -i "s|^SNOWFLAKE_SCHEMA=.*|SNOWFLAKE_SCHEMA=${SF_SCHEMA}|" "$dir/.env"
            
            echo "    [+] Created $dir/.env"
        else
            echo "    [!] Warning: No .env.example found in $dir"
        fi
    done
    echo ""
    echo "    [+] All environment files configured successfully."
}

# Check if all .env files already exist
ENVS_EXIST=true
for dir in "ms_sql_master" "ms_sql_replica" "broker" "consumer" "load_test"; do
    if [ ! -f "$dir/.env" ]; then
        ENVS_EXIST=false
        break
    fi
done

if [ "$ENVS_EXIST" = true ]; then
    read -p "    [?] Environment variables are already set. Do you want to refresh/replace them? (y/N): " refresh_env
    if [[ "$refresh_env" =~ ^[Yy]$ ]]; then
        generate_envs
    else
        echo "    -> Keeping existing .env files. Setup aborted."
    fi
else
    generate_envs
fi