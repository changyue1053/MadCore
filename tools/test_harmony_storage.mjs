// Executes exact Storage.ets with ONLY its platform import redirected to a fake.
// No Huawei runtime, on-device persistence, flush durability or concurrency proof.
import { mkdtemp, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const dir = await mkdtemp(join(tmpdir(), 'madcore-storage-unit-'));
try {
  const original = await readFile(new URL('../harmony/madcore/Storage.ets', import.meta.url), 'utf8');
  const platform = "'@kit.ArkData'";
  assert.equal(original.split(platform).length, 2, 'Exactly one platform import expected');
  await writeFile(join(dir, 'Storage.ts'), original.replace(platform, "'./preferences_fake.ts'"));
  await copyFile(new URL('fixtures/preferences_fake.ts', import.meta.url), join(dir, 'preferences_fake.ts'));
  const { PreferencesStringStore, StorageFailure, StorageException } = await import(pathToFileURL(join(dir, 'Storage.ts')));
  const { FakePreferences } = await import(pathToFileURL(join(dir, 'preferences_fake.ts')));
  const backend = new FakePreferences();
  const store = new PreferencesStringStore(backend);
  const matches = failure => e => e instanceof StorageException && e.failure === failure &&
    e.message === 'Storage failure: ' + failure && !String(e).includes('private') && e.cause === undefined;
  const fails = (failure, fn) => assert.throws(fn, matches(failure));

  assert.equal(store.get('missing'), null);
  assert.deepEqual(backend.calls, ['has']);
  store.remove('missing');
  store.put('theme', 'dark');
  assert.equal(new PreferencesStringStore(backend).get('theme'), 'dark'); // cache, not disk
  store.put('theme', 'light'); assert.equal(store.get('theme'), 'light');
  store.put('theme', ''); backend.resetCalls();
  assert.equal(store.get('theme'), ''); assert.deepEqual(backend.calls, ['has', 'get', 'get']);
  store.put('theme', '__madcore_type_probe__'); assert.equal(store.get('theme'), '__madcore_type_probe__');
  store.remove('theme'); assert.equal(store.get('theme'), null);

  for (const key of ['', 'A', '0key', 'a b', 'a/b', 'a\n', 'a\0', '中文', 'a'.repeat(129)]) {
    for (const operation of [() => store.get(key), () => store.put(key, 'private'), () => store.remove(key)]) {
      backend.resetCalls(); fails(StorageFailure.InvalidKey, operation); assert.deepEqual(backend.calls, []);
    }
  }
  for (const key of ['a', 'a._-09', 'a'.repeat(128)]) {
    store.put(key, 'ok'); assert.equal(store.get(key), 'ok'); store.remove(key);
  }
  const exact = ['a'.repeat(65536), 'é'.repeat(32768), '中'.repeat(21845) + 'a', '😀'.repeat(16384)];
  for (const value of exact) {
    assert.equal(Buffer.byteLength(value, 'utf8'), 65536);
    store.put('boundary', value); assert.equal(store.get('boundary'), value);
    backend.resetCalls(); fails(StorageFailure.ValueTooLarge, () => store.put('boundary', value + 'a'));
    assert.deepEqual(backend.calls, []);
    backend.values.set('boundary', value + 'a'); fails(StorageFailure.ValueTooLarge, () => store.get('boundary'));
  }
  for (const value of ['\uD800', '\uDC00', 'x\uD800y', '\uD800\uD800', '\uDC00\uD800']) {
    backend.resetCalls(); fails(StorageFailure.InvalidValue, () => store.put('unicode', value));
    assert.deepEqual(backend.calls, []);
    backend.values.set('unicode', value); fails(StorageFailure.InvalidValue, () => store.get('unicode'));
  }
  store.put('unicode', 'a\0é中😀'); assert.equal(store.get('unicode'), 'a\0é中😀');
  for (const value of [123, false, ['private'], null]) {
    backend.values.set('typed', value); backend.resetCalls();
    fails(StorageFailure.InvalidValue, () => store.get('typed'));
    assert.deepEqual(backend.calls, ['has', 'get', 'get']);
  }
  backend.rawWrongType = true; backend.values.set('typed', 123); backend.resetCalls();
  fails(StorageFailure.InvalidValue, () => store.get('typed'));
  assert.deepEqual(backend.calls, ['has', 'get']); backend.rawWrongType = false;

  backend.values.set('empty', '');
  for (const failure of ['has', 'get', 'secondGet']) {
    backend.failure = failure; backend.resetCalls();
    fails(StorageFailure.Backend, () => store.get('empty'));
  }
  backend.failure = 'put'; fails(StorageFailure.Backend, () => store.put('empty', 'private'));
  backend.failure = 'delete'; fails(StorageFailure.Backend, () => store.remove('empty'));
  for (const failure of ['flush', 'flushReject']) {
    backend.failure = failure;
    await assert.rejects(() => store.flush(), matches(StorageFailure.Backend));
  }
  backend.failure = ''; backend.resetCalls(); await store.flush(); assert.deepEqual(backend.calls, ['flush']);
  console.log('Harmony Storage exact-source mocked tests passed; device persistence NOT tested');
} finally {
  await rm(dir, { recursive: true, force: true });
}
