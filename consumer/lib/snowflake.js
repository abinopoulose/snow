const snowflake = require('snowflake-sdk');
require('dotenv').config();

const connectionConfig = {
    account: process.env.SNOWFLAKE_ACCOUNT,
    username: process.env.SNOWFLAKE_USER,
    password: process.env.SNOWFLAKE_PASSWORD,
    database: process.env.SNOWFLAKE_DATABASE,
    schema: process.env.SNOWFLAKE_SCHEMA,
    warehouse: process.env.SNOWFLAKE_WAREHOUSE
};

let connection = null;

function connectWithRetry() {
    console.log('[Info] Attempting Snowflake connection...');
    connection = snowflake.createConnection(connectionConfig);
    connection.connect((err) => {
        if (err) {
            console.error(`[Error] Snowflake connection failed: ${err.message}`);
            console.log(`[Info] Retrying Snowflake in 5s...`);
            setTimeout(connectWithRetry, 5000);
        } else {
            console.log('[Success] Snowflake connection success.');
        }
    });
}

connectWithRetry();

module.exports = {
    getConnection: () => connection
};