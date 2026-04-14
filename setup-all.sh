#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "==================================================="
echo "  SnowSync Pipeline: Complete Environment Setup"
echo "==================================================="

echo ""
echo "[*] Step 1: Flushing existing state (Volumes & Containers)"
cd ms_sql_master && sudo docker compose down -v && cd ..
cd ms_sql_replica && sudo docker compose down -v && cd ..
cd broker && sudo docker compose down -v && cd ..
cd consumer && sudo docker compose down -v && cd ..

echo ""
echo "[*] Step 2: Booting up Replica Data Node"
cd ms_sql_replica
sudo docker compose up -d
echo "    Waiting 20 seconds for Replica SQL Engine to finish booting..."
sleep 20
./setup-replica.sh
cd ..

echo ""
echo "[*] Step 3: Booting up Master Data Node & Initializing Push Replication"
cd ms_sql_master
sudo docker compose up -d
echo "    Waiting 20 seconds for Master SQL Engine to finish booting..."
sleep 20
./setup-master.sh
cd ..

echo ""
echo "[*] Step 4: Booting up Event Broker (Kafka + Zookeeper + Connect)"
cd broker
sudo docker compose up -d
echo "    Waiting 45 seconds for Kafka Connect API to become fully ready..."
sleep 45
./register-connector.sh
cd ..

echo ""
echo "[*] Step 5: Booting up Node.js Snowflake Consumer"
cd consumer
sudo docker compose up -d --build
cd ..

echo ""
echo "==================================================="
echo "                 SUCCESS! "
echo "==================================================="

