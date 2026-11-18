// Executes the exact platform-independent policy source using Node's TS transform.
// This is NOT an RCP platform/runtime test; Hvigor separately compiles the original ETS.
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const dir = await mkdtemp(join(tmpdir(), 'madcore-http-policy-'));
try {
  const source = await readFile(new URL('../harmony/madcore/HttpPolicy.ets', import.meta.url), 'utf8');
  const file = join(dir, 'HttpPolicy.ts');
  await writeFile(file, source);
  const { RcpRequest, RcpLimits, RcpResponse, RcpFailure, BoundedResponseBody } = await import(pathToFileURL(file));
  const fails = (failure, fn) => assert.throws(fn, e => e.failure === failure && !e.message.includes('private'));
  for (const url of ['https://user:private@host', 'https://host/#private', 'https://host:0', 'https://host:65536', 'https://host/\r\n', 'https://host\\evil', 'ftp://host', 'https://[::1]/']) {
    fails(RcpFailure.InvalidRequest, () => new RcpRequest(url));
  }
  assert.equal(new RcpRequest('https://example.com:443/path?q=x').method, 'GET');
  fails(RcpFailure.InvalidRequest, () => new RcpRequest('https://host', 'GET', {}, new Uint8Array([1]).buffer));
  fails(RcpFailure.InvalidRequest, () => new RcpRequest('https://host', 'GET', { Host: 'private' }));
  fails(RcpFailure.InvalidRequest, () => new RcpRequest('https://host', 'GET', { Test: 'a', test: 'b' }));
  fails(RcpFailure.InvalidRequest, () => new RcpRequest('https://host', 'GET', { Test: 'private\r\n' }));
  const bytes = new Uint8Array([1, 2]);
  const headers = { test: 'one' };
  const req = new RcpRequest('https://host', 'POST', headers, bytes.buffer);
  bytes[0] = 9; headers.test = 'two';
  assert.equal(new Uint8Array(req.body)[0], 1);
  req.headers.test = 'three';
  assert.equal(req.headers.test, 'one');
  for (const n of [0, -1, Infinity, NaN, 1.5, 2147483648]) {
    fails(RcpFailure.InvalidRequest, () => new RcpLimits(n));
  }
  fails(RcpFailure.InvalidRequest, () => new RcpLimits(1, 1, 1, 16777217));
  assert.equal(new RcpLimits().allowInsecureHttp, false);
  const body = new BoundedResponseBody(3);
  body.append(new Uint8Array([1, 2]).buffer);
  fails(RcpFailure.ResponseTooLarge, () => body.append(new Uint8Array([3, 4]).buffer));
  body.append(new Uint8Array([3]).buffer);
  assert.deepEqual([...new Uint8Array(body.finish())], [1, 2, 3]);
  const output = body.finish(); new Uint8Array(output)[0] = 9;
  assert.equal(new Uint8Array(body.finish())[0], 1);
  const response = new RcpResponse(302, body.finish());
  new Uint8Array(response.body)[0] = 9;
  assert.equal(new Uint8Array(response.body)[0], 1);
  assert.equal(response.status, 302);
  console.log('Harmony HTTP pure policy tests passed; no platform HTTP execution');
} finally {
  await rm(dir, { recursive: true, force: true });
}
