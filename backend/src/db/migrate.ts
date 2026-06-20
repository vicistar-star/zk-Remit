import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { getPool, closePool } from './client';

async function migrate() {
  const pool = getPool();

  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);

    const { rows: applied } = await client.query(
      'SELECT version FROM schema_migrations ORDER BY version'
    );
    const appliedSet = new Set(applied.map((r: any) => r.version));

    const migrationsDir = join(__dirname, 'migrations');
    const files = readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      const version = file.replace(/\.sql$/, '');
      if (appliedSet.has(version)) {
        console.log(`Skipping ${file} — already applied`);
        continue;
      }

      console.log(`Applying ${file}...`);
      const sql = readFileSync(join(migrationsDir, file), 'utf-8');
      await client.query(sql);
      await client.query(
        'INSERT INTO schema_migrations (version) VALUES ($1)',
        [version]
      );
      console.log(`  ✓ ${file} applied`);
    }

    console.log('\nAll migrations applied.');
  } finally {
    client.release();
    await closePool();
  }
}

migrate().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
