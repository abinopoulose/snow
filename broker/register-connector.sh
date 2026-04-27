#!/bin/bash

# Load environment variables
export $(grep -v '^#' .env | xargs)

echo "[*] Registering Connector for ${REPLICA_DB_HOST}..."

# Drop the old names
curl -s -X DELETE ${KAFKA_CONNECT_URL}/connector > /dev/null

# Register with retry logic for SQL Server
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
     ${KAFKA_CONNECT_URL}/ -d '{
  "name": "connector",
  "config": {
    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
    "database.hostname": "'"${REPLICA_DB_HOST}"'",
    "database.port": "'"${DB_PORT}"'",
    "database.user": "'"${CDC_USER}"'",
    "database.password": "'"${CDC_PASSWORD}"'",
    "database.names": "'"${DB_NAME}"'",
    "topic.prefix": "'"${KAFKA_TOPIC_PREFIX}"'",
    "table.include.list": "'"${CDC_TABLE_LIST}"'",
    "database.encrypt": "false",
    "decimal.handling.mode": "double",
    "schema.history.internal.kafka.bootstrap.servers": "'"${KAFKA_BOOTSTRAP_SERVERS}"'",
    "schema.history.internal.kafka.topic": "schemahistory.snow",
    "schema.history.internal.kafka.replication.factor": "3",
    "snapshot.mode": "'"${SNAPSHOT_MODE}"'",
    "errors.retry.delay.max.ms": "60000",
    "errors.tolerance": "all"
  }
}'

echo -e "\n\n[*] Check status: curl ${KAFKA_CONNECT_URL}/connector/status"