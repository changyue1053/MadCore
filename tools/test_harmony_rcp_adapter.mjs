// Unit tests redirect ONLY module imports to a fake SDK; the adapter algorithm is unchanged.
// No Huawei runtime, actual redirects, TLS, DNS or platform buffering is tested here.
import { mkdtemp, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const dir = await mkdtemp(join(tmpdir(), 'madcore-rcp-unit-'));
try {
  const original = await readFile(new URL('../harmony/madcore/RcpHttpClient.ets', import.meta.url), 'utf8');
  for (const dependency of ["'@kit.RemoteCommunicationKit'", "'@kit.BasicServicesKit'", "'./HttpPolicy'"]) {
    assert.ok(original.includes(dependency), 'Test module mapping must match production imports');
  }
  const adapted = original.replace("'@kit.RemoteCommunicationKit'", "'./rcp_fake.ts'")
    .replace("'@kit.BasicServicesKit'", "'./rcp_fake.ts'")
    .replace("'./HttpPolicy'", "'./HttpPolicy.ts'");
  await writeFile(join(dir, 'RcpHttpClient.ts'), adapted);
  await copyFile(new URL('../harmony/madcore/HttpPolicy.ets', import.meta.url), join(dir, 'HttpPolicy.ts'));
  await copyFile(new URL('fixtures/rcp_fake.ts', import.meta.url), join(dir, 'rcp_fake.ts'));
  const { RcpHttpClient } = await import(pathToFileURL(join(dir, 'RcpHttpClient.ts')));
  const { RcpRequest, RcpLimits, RcpFailure } = await import(pathToFileURL(join(dir, 'HttpPolicy.ts')));
  const { state } = await import(pathToFileURL(join(dir, 'rcp_fake.ts')));
  const reset = mode => {
    Object.assign(state, { mode, creates: 0, cancels: 0, closes: 0, configuration: undefined, request: undefined });
  };
  const client = new RcpHttpClient();
  const request = new RcpRequest('https://example.test/ok');
  const fails = async (failure, operation) => {
    await assert.rejects(operation, e => e.failure === failure && !String(e).includes('private'));
  };
  reset('success');
  const response = await client.execute(request, new RcpLimits(100, 100, 100, 3));
  assert.deepEqual([...new Uint8Array(response.body)], [1, 2, 3]);
  assert.equal(state.configuration.requestConfiguration.transfer.autoRedirect, false);
  assert.equal(state.configuration.requestConfiguration.security, undefined);
  assert.equal(state.configuration.requestConfiguration.tracing, undefined);
  assert.equal(typeof state.request.destination, 'function');
  assert.deepEqual(response.headers.get('set-cookie'), ['a=1', 'b=2']);
  assert.deepEqual(response.headers.get('x-quoted'), ['a,b']);
  assert.deepEqual(response.headers.get('X-Case'), ['upper']);
  assert.deepEqual(response.headers.get('x-case'), ['lower']);
  assert.equal(response.headers.has('missing'), false);
  response.headers.get('set-cookie').push('mutated');
  response.headers.clear();
  state.headers['set-cookie'].push('platform-mutated');
  assert.deepEqual(response.headers.get('set-cookie'), ['a=1', 'b=2']);
  state.headers['set-cookie'].pop();
  assert.equal(state.closes, 1);
  assert.equal(state.cancels, 0);
  reset('redirect');
  assert.equal((await client.execute(request)).status, 302);
  assert.equal(state.configuration.requestConfiguration.transfer.autoRedirect, false);
  reset('success');
  await fails(RcpFailure.InvalidRequest, () => client.execute(new RcpRequest('http://example.test')));
  assert.equal(state.creates, 0);
  reset('success');
  await fails(RcpFailure.RequestTooLarge, () => client.execute(
    new RcpRequest('https://example.test', 'POST', {}, new Uint8Array([1, 2]).buffer),
    new RcpLimits(100, 100, 100, 8, 1)));
  assert.equal(state.creates, 0);
  for (const mode of ['overflow', 'reentrantOverflow']) {
    reset(mode);
    await fails(RcpFailure.ResponseTooLarge, () => client.execute(request, new RcpLimits(100, 100, 100, 3)));
    assert.equal(state.cancels, 1); assert.equal(state.closes, 1);
  }
  for (const mode of ['timeout', 'late']) {
    reset(mode);
    await fails(RcpFailure.Timeout, () => client.execute(request, new RcpLimits(100, 100, 5)));
    await new Promise(resolve => setTimeout(resolve, 30));
    assert.equal(state.cancels, 1); assert.equal(state.closes, 1);
  }
  for (const mode of ['nativeTimeout', 'io', 'syncThrow']) {
    reset(mode);
    await fails(mode === 'nativeTimeout' ? RcpFailure.Timeout : RcpFailure.Io,
      () => client.execute(request));
    assert.equal(state.closes, 1); assert.equal(state.cancels, 1);
  }
  console.log('RCP adapter mocked-state tests passed; actual platform execution NOT tested');
} finally {
  await rm(dir, { recursive: true, force: true });
}
