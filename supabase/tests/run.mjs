// =====================================================================
// 로컬 DB 테스트 — `npm run db:test`
//
// 메모리 안에서 도는 Postgres(PGlite + PostGIS)를 띄워
//   1) Supabase 기본 구성을 흉내내고 (supabase_stubs.sql)
//   2) supabase/migrations/*.sql 을 순서대로 적용한 뒤
//   3) rls_check.sql 로 권한을 점검합니다.
// Docker 나 클라우드 프로젝트 없이 SQL 문법·RLS 로직 오류를 미리 잡는 용도입니다.
// (auth·storage 는 흉내낸 것이므로, 최종 확인은 클라우드 SQL Editor 에서 rls_check.sql 실행)
// =====================================================================
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { postgis } from '@electric-sql/pglite-postgis';

const testsDir = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(testsDir, '..', 'migrations');

const db = new PGlite({ extensions: { postgis } });

async function runFile(label, path) {
  try {
    const results = await db.exec(readFileSync(path, 'utf8'));
    console.log(`  ✓ ${label}`);
    return results;
  } catch (err) {
    console.error(`  ✗ ${label}`);
    console.error(`    ${err.message}`);
    if (err.detail) console.error(`    detail: ${err.detail}`);
    if (err.hint) console.error(`    hint: ${err.hint}`);
    if (err.where) console.error(`    where: ${err.where.split('\n').join('\n           ')}`);
    await db.close();
    process.exit(1);
  }
}

console.log('\n[DB 테스트] PGlite + PostGIS (메모리)\n');

await runFile('Supabase 기본 구성 흉내 (tests/supabase_stubs.sql)', join(testsDir, 'supabase_stubs.sql'));

const migrations = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
for (const file of migrations) {
  await runFile(`migrations/${file}`, join(migrationsDir, file));
}

const results = await runFile('RLS 점검 (tests/rls_check.sql)', join(testsDir, 'rls_check.sql'));
const last = results.at(-1)?.rows?.[0];
console.log(`\n${last ? Object.values(last)[0] : '완료'}\n`);

await db.close();
