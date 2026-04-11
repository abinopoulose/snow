const mssql = require('mssql');
require('dotenv').config();

// 1. Database Configuration
const config = {
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    server: process.env.DB_HOST,
    database: process.env.DB_NAME,
    options: {
        encrypt: false,
        trustServerCertificate: true
    },
    pool: {
        max: 50,
        min: 10,
        idleTimeoutMillis: 30000
    }
};

const MODEL_TICKER = 'Dummy_Model';
const TARGET_TPS = parseInt(process.env.TARGET_TPS) || 2;
const INTERVAL_MS = 1000 / TARGET_TPS;

let createCounter = 0;
let errorCounter = 0;

// 2. Initialize Connection Pool
const poolPromise = new mssql.ConnectionPool(config)
    .connect()
    .then(pool => {
        console.log('[success] Connected to MS SQL Server');
        return pool;
    })
    .catch(err => {
        console.error('[error] SQL Connection Failed:', err);
        process.exit(1);
    });

/**
 * Creates a NEW unique position row
 */
async function createPosition(pool) {
    // Generate a unique ticker using high-res timestamp + random suffix
    const uniqueTicker = `IDX-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    
    try {
        await pool.request()
            .input('model', mssql.VarChar(50), MODEL_TICKER)
            .input('ticker', mssql.VarChar(50), uniqueTicker)
            .query(`
                INSERT INTO model_positions (model_ticker, security_ticker, allocation_percentage, drift_percentage)
                VALUES (@model, @ticker, 10.00, 0.00)
            `);
        createCounter++;
    } catch (err) {
        errorCounter++;
    }
}

/**
 * Main Execution Loop
 */
const start = async () => {
    const pool = await poolPromise;
    
    console.log(`[*] Starting Load Test...`);
    console.log(`[*] Target: ${TARGET_TPS} Creates/sec`);
    console.log(`[*]  Interval: ${INTERVAL_MS.toFixed(2)}ms`);

    // High-frequency insert loop
    setInterval(() => {
        // Fire and forget to maintain TPS despite network latency
        createPosition(pool);
    }, INTERVAL_MS);

    // Statistics Logger (Per Second)
    setInterval(() => {
        console.log(`[STATS] Generated: ${createCounter}/s | Errors: ${errorCounter}`);
        createCounter = 0;
        errorCounter = 0;
    }, 1000);
};

start().catch(err => console.error("[error] Fatal error in load tester:", err));