#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "==================================================="
echo "           Archival Pipeline Setup"
echo "==================================================="

echo ""
echo "[*] Step 1: Flushing existing state (Volumes & Containers)"
cd ms_sql_master && sudo docker compose down -v --remove-orphans && cd ..
cd ms_sql_replica && sudo docker compose down -v --remove-orphans && cd ..
cd broker && sudo docker compose down -v --remove-orphans && cd ..
cd consumer && sudo docker compose down -v --remove-orphans && cd ..

echo ""
echo "[*] Step 2: Booting all infrastructure concurrently..."
# These commands boot the containers in the background simultaneously
cd ms_sql_replica && sudo docker compose up -d && cd ..
cd ms_sql_master && sudo docker compose up -d && cd ..
cd broker && sudo docker compose up -d && cd ..

echo ""
echo "[*] Step 3: Polling and Configuring Replica..."
cd ms_sql_replica
# Safely load the .env variables
set -a; source .env; set +a

# Poll using the exact same mssql-tools container method as the setup scripts
until sudo docker run --rm -i --network host mcr.microsoft.com/mssql-tools /opt/mssql-tools/bin/sqlcmd -S 127.0.0.1,1434 -U sa -P "${MSSQL_SA_PASSWORD}" -l 3 -Q "SELECT 1" &> /dev/null; do
    sleep 2
done
echo "    [+] Replica SQL Engine is up! Running Setup..."
./setup-replica.sh
cd ..

echo ""
echo "[*] Step 4: Polling and Configuring Master..."
cd ms_sql_master
# Safely load the .env variables
set -a; source .env; set +a

until sudo docker run --rm -i --network host mcr.microsoft.com/mssql-tools /opt/mssql-tools/bin/sqlcmd -S 127.0.0.1 -U sa -P "${MSSQL_SA_PASSWORD}" -l 3 -Q "SELECT 1" &> /dev/null; do
    sleep 2
done
echo "    [+] Master SQL Engine is up! Running Setup..."
./setup-master.sh
cd ..

echo "[*] Step 5: Waiting for Kafka Connect worker to fully bootstrap..."
until curl -s -f http://localhost:8083/connectors &> /dev/null; do 
    sleep 5
done
echo "    [+] Connect worker is responsive. Waiting 10s for ISR stabilization..."
sleep 10

# Retry connector registration up to 3 times
cd broker
set +e  # Allow failures during retry loop
for attempt in 1 2 3; do
    echo "    [*] Registration attempt ${attempt}/3..."
    ./register-connector.sh 2>&1
    
    # Check if connector was created successfully
    sleep 2
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/connectors/connector/status)
    
    if [ "$STATUS" = "200" ]; then
        echo "    [+] Connector registered successfully!"
        break
    else
        echo "    [!] Attempt ${attempt} failed."
        if [ "$attempt" -lt 3 ]; then
            echo "    [*] Waiting 20s before retry..."
            sleep 20
        else
            echo "    [!] All attempts failed. Dumping Debezium logs:"
            sudo docker logs debezium --tail 50 2>&1
        fi
    fi
done
set -e  # Re-enable strict mode
cd ..

echo ""
echo "[*] Step 6: Booting up Node.js Snowflake Consumer"
cd consumer
sudo docker compose up -d --build
cd ..

echo ""
echo "==================================================="
echo "                 SUCCESS! "
echo "==================================================="