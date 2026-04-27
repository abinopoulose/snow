const { Kafka, logLevel } = require('kafkajs');
require('dotenv').config();

const positionsHandler = require('./handlers/positions');

const kafka = new Kafka({ 
    brokers: (process.env.KAFKA_BOOTSTRAP_SERVERS || 'localhost:9092,localhost:9093,localhost:9094').split(','),
    clientId: 'fintech-sync-engine',
    logLevel: logLevel.ERROR,
    // Add retry logic for the broker connection itself
    retry: {
        initialRetryTime: 300,
        retries: 10
    }
});

const consumer = kafka.consumer({ 
    groupId: 'snowflake-sync-group',
    sessionTimeout: 30000,
    heartbeatInterval: 3000
});

const run = async () => {
    try {
        await consumer.connect();
        console.log('[Success] Kafka connection success.');

        await consumer.subscribe({ 
            topics: ['snow.snow.dbo.model_positions'], 
            fromBeginning: true 
        });
        
        console.log('[Info] Monitoring...');

        await consumer.run({
            eachMessage: async ({ topic, message }) => {
                if (!message.value) return; 
                
                try {
                    const parsed = JSON.parse(message.value.toString());
                    if (!parsed || !parsed.payload) return;
                    
                    const payload = parsed.payload;
                    console.log(`[Kafka] ${topic} | Op: ${payload.op}`);

                    if (topic.includes('model_positions')) {
                        positionsHandler.processPosition(payload);
                    }
                } catch (err) {
                    console.error("[Error] Message parse error:", err.message);
                }
            },
        });
    } catch (err) {
        console.error(`[Error] Consumer Error: ${err.message}. Restarting loop in 5s...`);
        setTimeout(run, 5000);
    }
};

// Batch flusher
setInterval(() => {
    positionsHandler.flush();
}, 2000);

// Start the app and listen for crash events to trigger auto-reconnect
run().catch(async (err) => {
    console.error(`[Error] Fatal Crash: ${err.message}`);
    setTimeout(run, 5000);
});