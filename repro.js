// Repro: load the DuckDB azure extension and trigger a GetToken() call.
// No network creds or DNS needed — the TLS handshake fails before anything
// else does.
const d = require('@duckdb/node-api');

(async () => {
  const instance = await d.DuckDBInstance.create(':memory:');
  const conn = await instance.connect();
  try {
    await conn.run('INSTALL azure');
    await conn.run('LOAD azure');
    await conn.run(`
      CREATE SECRET s (
        TYPE AZURE, PROVIDER SERVICE_PRINCIPAL,
        TENANT_ID 'x', CLIENT_ID 'y', CLIENT_SECRET 'z',
        ACCOUNT_NAME 'nonexistent'
      )
    `);
    await conn.run(`
      SELECT * FROM read_parquet(
        'abfss://x@nonexistent.dfs.core.windows.net/foo.parquet'
      ) LIMIT 1
    `);
    console.log('UNEXPECTED: call did not fail');
  } catch (e) {
    console.log(e.message);
  }
})();
