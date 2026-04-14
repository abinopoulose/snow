#!/bin/bash

# Load environment variables
export $(grep -v '^#' .env | xargs)

echo "[*] Registering Connector for ${REPLICA_DB_HOST}..."

# Drop the old names
curl -s -X DELETE http://localhost:8083/connectors/connector > /dev/null

# Register with retry logic for SQL Server
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
     http://localhost:8083/connectors/ -d '{
  "name": "connector",
  "config": {
    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
    "database.hostname": "'"${REPLICA_DB_HOST}"'",
    "database.port": "'"${DB_PORT}"'",
    "database.user": "'"${CDC_USER}"'",
    "database.password": "'"${CDC_PASSWORD}"'",
    "database.names": "'"${DB_NAME}"'",
    "topic.prefix": "'"${KAFKA_TOPIC_PREFIX}"'",
    "table.include.list": "dbo.model_positions",
    "database.encrypt": "false",
    "decimal.handling.mode": "double",
    "schema.history.internal.kafka.bootstrap.servers": "kafka:29092",
    "schema.history.internal.kafka.topic": "schemahistory.snow",
    "snapshot.mode": "initial",
    "errors.retry.delay.max.ms": "60000",
    "errors.tolerance": "all"
  }
}'

echo -e "\n\n[*] Check status: curl localhost:8083/connectors/connector/status"