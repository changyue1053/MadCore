// Exact ETS implementation; imports alone redirected to local copies and fake Preferences.
// Tests prefix semantics, not Harmony runtime, access control or device persistence.
import { mkdtemp, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const dir = await mkdtemp(join(tmpdir(), 'madcore-namespaced-storage-'));
try {
  for (const [name, originalImport, replacement] of [
    ['NamespacedStorage', "'./Storage'", "'./Storage.ts'"],
    ['Storage', "'@kit.ArkData'", "'./preferences_fake.ts'"]
  ]) {
    const source = await readFile(new URL(`../harmony/madcore/${name}.ets`, import.meta.url), 'utf8');
    assert.equal(source.split(originalImport).length, name === 'NamespacedStorage' ? 3 : 2, 'Expected runtime/type imports');
    await writeFile(join(dir, `${name}.ts`), source.replaceAll(originalImport, replacement));
  }
  await copyFile(new URL('fixtures/preferences_fake.ts', import.meta.url), join(dir, 'preferences_fake.ts'));
  const { NamespacedStringStore } = await import(pathToFileURL(join(dir, 'NamespacedStorage.ts')));
  const { StorageException, StorageFailure, PreferencesStringStore } = await import(pathToFileURL(join(dir, 'Storage.ts')));
  const { FakePreferences } = await import(pathToFileURL(join(dir, 'preferences_fake.ts')));
  class MapStore {
    values = new Map();
    calls = [];
    failure = null;
    record(operation, key) {
      this.calls.push([operation, key]);
      if (this.failure !== null) throw this.failure;
    }
    get(key) { this.record('get', key); return this.values.has(key) ? this.values.get(key) : null; }
    put(key, value) { this.record('put', key); this.values.set(key, value); }
    remove(key) { this.record('remove', key); this.values.delete(key); }
  }
  const backend = new MapStore();
  const alpha = new NamespacedStringStore(backend, 'alpha');
  const beta = new NamespacedStringStore(backend, 'beta');
  assert.equal(alpha.get('theme'), null);
  alpha.put('theme', 'dark'); beta.put('theme', 'light');
  assert.equal(alpha.get('theme'), 'dark'); assert.equal(beta.get('theme'), 'light');
  alpha.put('theme', ''); assert.equal(alpha.get('theme'), ''); assert.equal(beta.get('theme'), 'light');
  alpha.remove('theme'); assert.equal(alpha.get('theme'), null); assert.equal(beta.get('theme'), 'light');
  alpha.remove('absent');
  alpha.put('beta.key', 'one'); beta.put('key', 'two');
  assert.equal(backend.values.get('alpha.beta.key'), 'one'); assert.equal(backend.values.get('beta.key'), 'two');
  const same = new NamespacedStringStore(backend, 'beta'); assert.equal(same.get('theme'), 'light');
  const maximum = new NamespacedStringStore(backend, 'n'.repeat(32));
  maximum.put('k'.repeat(95), 'max');
  assert.equal(backend.calls.at(-1)[1].length, 128);
  assert.equal(maximum.get('k'.repeat(95)), 'max'); maximum.remove('k'.repeat(95));
  new NamespacedStringStore(backend, 'a_0-').put('a._-09', 'ok');
  const invalid = fn => assert.throws(fn, e => e instanceof StorageException &&
    e.failure === StorageFailure.InvalidKey && e.message === 'Storage failure: InvalidKey');
  for (const name of ['', 'A', '0n', 'a.b', 'a/b', 'a b', 'a\n', 'a\0', '中文', 'n'.repeat(33)]) {
    const before = backend.calls.length;
    invalid(() => new NamespacedStringStore(backend, name));
    assert.equal(backend.calls.length, before);
  }
  for (const key of ['', 'A', '0k', 'a/b', 'a b', 'a\n', 'a\0', '中文', 'k'.repeat(96)]) {
    for (const operation of [() => alpha.get(key), () => alpha.put(key, 'x'), () => alpha.remove(key)]) {
      const before = backend.calls.length; invalid(operation); assert.equal(backend.calls.length, before);
    }
  }
  // The facade does not add value policy. Validate that backend receives values untouched.
  for (const value of ['\uD800', 'x'.repeat(65537), 'a\0😀']) {
    alpha.put('raw', value); assert.equal(alpha.get('raw'), value);
  }
  for (const error of [new StorageException(StorageFailure.Backend), new Error('host-owned diagnostic')]) {
    backend.failure = error;
    for (const operation of [() => alpha.get('key'), () => alpha.put('key', 'value'), () => alpha.remove('key')]) {
      assert.throws(operation, e => e === error);
    }
  }
  backend.failure = null;
  // Composition with the actual Preferences adapter retains its validation and error redaction.
  const preferences = new FakePreferences();
  const composed = new NamespacedStringStore(new PreferencesStringStore(preferences), 'app');
  composed.put('key', 'value'); assert.equal(preferences.values.get('app.key'), 'value');
  assert.throws(() => composed.put('key', '\uD800'), e => e.failure === StorageFailure.InvalidValue);
  assert.throws(() => composed.put('key', 'x'.repeat(65537)), e => e.failure === StorageFailure.ValueTooLarge);
  preferences.failure = 'get';
  assert.throws(() => composed.get('key'), e => e.failure === StorageFailure.Backend && !String(e).includes('private'));
  console.log('Harmony namespaced storage exact-source tests passed; no device persistence tested');
} finally {
  await rm(dir, { recursive: true, force: true });
}
