const connection = require('../lib/snowflake');

let buffer = [];

const processPosition = (payload) => {
    // payload.op map: 'c' (create), 'u' (update), 'd' (delete), 'r' (snapshot read)
    const data = payload.after || payload.before;
    
    if (!data) {
        console.warn(`[Warn] processPosition: Payload missing 'before' and 'after'. Skipping.`);
        return;
    }

    buffer.push([
        data.model_ticker, 
        data.security_ticker, 
        data.allocation_percentage, 
        data.drift_percentage, 
        payload.op || 'u'
    ]);
    
    console.log(`[Buffer] Queued Position ${data.model_ticker}/${data.security_ticker} (Queue size: ${buffer.length})`);
};

const flush = () => {
    if (buffer.length === 0) return;
    
    const batch = [...buffer];
    buffer = []; // Clear buffer immediately to avoid race conditions

    console.log(`[Snowflake] Attempting to bulk insert ${batch.length} Positions...`);

    const sql = `INSERT INTO MODEL_POSITIONS_HISTORY (model_ticker, security_ticker, allocation_percentage, drift_percentage, cdc_operation) VALUES (?, ?, ?, ?, ?)`;
    
    connection.execute({
        sqlText: sql,
        binds: batch,
        complete: (err, stmt, rows) => { 
            if (err) {
                console.error(`[Error] Snowflake Sync Failed for Positions:`, err.message);
            } else {
                console.log(`[Success] Successfully Synced ${batch.length} Positions to Snowflake`); 
            }
        }
    });
};

module.exports = { processPosition, flush };