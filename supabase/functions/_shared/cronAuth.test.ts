// deno test supabase/functions/_shared/cronAuth.test.ts   (no network)
import { constantTimeEqual, cronSecretOk } from './cronAuth.ts';

function assert(c: unknown, m: string) { if (!c) throw new Error('FAILED: ' + m); }

Deno.test('cron secret: only an exact match of a non-empty secret passes', async () => {
  assert(await cronSecretOk('s3cret', 's3cret'), 'exact match');
  assert(await cronSecretOk(' s3cret ', 's3cret'), 'surrounding spaces are ignored');
  assert(!(await cronSecretOk('s3cre', 's3cret')), 'prefix');
  assert(!(await cronSecretOk('s3cret!', 's3cret')), 'longer');
  assert(!(await cronSecretOk('other', 's3cret')), 'different');
  assert(!(await cronSecretOk(null, 's3cret')), 'no header');
  assert(!(await cronSecretOk('', '')), 'empty secret and empty header never match');
  assert(!(await cronSecretOk('anything', '')), 'empty secret never matches');
  assert(!(await cronSecretOk('anything', undefined)), 'unset secret never matches');
  assert(!(await cronSecretOk('', 's3cret')), 'empty header');
});

Deno.test('constant time compare', async () => {
  assert(await constantTimeEqual('a', 'a'), 'equal');
  assert(!(await constantTimeEqual('a', 'b')), 'not equal');
  assert(!(await constantTimeEqual('', 'b')), 'empty vs non-empty');
});
