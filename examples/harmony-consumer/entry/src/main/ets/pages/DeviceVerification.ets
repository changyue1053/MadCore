import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PreferencesStringStore, NamespacedStringStore, RcpHttpClient, RcpRequest, RcpLimits, RcpResponse, RcpFailure, RcpTransportException } from 'madcore';

// Evaluation host only. No production SDK export and no automatic execution.
let preparedInThisProcess: boolean = false;
let running: boolean = false;

function requireCheck(ok: boolean, label: string): void {
  if (!ok) throw new Error('Device verification failed: ' + label);
}
function ascii(response: RcpResponse): string {
  let result: string = '';
  for (const byte of new Uint8Array(response.body)) result += String.fromCharCode(byte);
  return result;
}
function origin(value: string, scheme: string): string {
  // Explicit private IPv4/loopback only: no DNS, credentials, paths or public targets.
  const match = value.match(/^(http|https):\/\/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+):([0-9]+)$/);
  requireCheck(match !== null, 'fixture origin format');
  if (match === null) throw new Error('Missing origin');
  const a = Number(match[2]); const b = Number(match[3]);
  const c = Number(match[4]); const d = Number(match[5]); const port = Number(match[6]);
  requireCheck(match[1] === scheme && [a, b, c, d].every((v: number) => v >= 0 && v <= 255) &&
    port >= 1 && port <= 65535 && (a === 127 || a === 10 || (a === 192 && b === 168) ||
    (a === 172 && b >= 16 && b <= 31)), 'controlled private fixture required');
  return value;
}
async function failure(client: RcpHttpClient, request: RcpRequest, limits: RcpLimits,
  expected: RcpFailure): Promise<void> {
  try { await client.execute(request, limits); }
  catch (error) {
    requireCheck(error instanceof RcpTransportException && error.failure === expected, 'failure category');
    return;
  }
  throw new Error('Expected transport failure');
}
export async function verifyNetwork(httpOrigin: string, tlsOrigin: string): Promise<void> {
  requireCheck(!running, 'already running'); running = true;
  try {
    const http = origin(httpOrigin, 'http'); const tls = origin(tlsOrigin, 'https');
    const client = new RcpHttpClient();
    const limits = new RcpLimits(3000, 3000, 5000, 4096, 4096, true);
    const request = async (path: string): Promise<RcpResponse> =>
      client.execute(new RcpRequest(http + path), limits);
    requireCheck(ascii(await request('/ok')) === 'hello', 'fixture identity');
    requireCheck((await request('/error')).status === 400, 'HTTP error preserved');
    const redirects = ascii(await request('/redirect-count'));
    requireCheck(redirects === '0', 'fresh dedicated fixture required');
    requireCheck((await request('/redirect')).status === 302, 'redirect not followed');
    requireCheck(ascii(await request('/redirect-count')) === '0', 'redirect target untouched');
    await failure(client, new RcpRequest(http + '/chunked'),
      new RcpLimits(3000, 3000, 5000, 4, 4096, true), RcpFailure.ResponseTooLarge);
    await failure(client, new RcpRequest(http + '/slow'),
      new RcpLimits(1000, 1000, 100, 4096, 4096, true), RcpFailure.Timeout);
    requireCheck(ascii(await request('/tls-ready')) === 'ready', 'TLS fixture ready');
    const before = Number(ascii(await request('/tls-attempts')));
    requireCheck(Number.isInteger(before) && before >= 0, 'TLS counter');
    requireCheck(ascii(await request('/tls-count')) === '0', 'TLS HTTP count initially zero');
    await failure(client, new RcpRequest(tls + '/probe'), new RcpLimits(3000, 3000, 5000), RcpFailure.Io);
    const after = Number(ascii(await request('/tls-attempts')));
    requireCheck(Number.isInteger(after) && after > before, 'TLS connection actually attempted');
    requireCheck(ascii(await request('/tls-count')) === '0', 'untrusted TLS never reached HTTP');
    requireCheck(ascii(await request('/ok')) === 'hello', 'request after failures');
  } finally { running = false; }
}
export async function verifyStorage(context: common.Context, token: string, prepare: boolean): Promise<void> {
  requireCheck(!running, 'already running');
  requireCheck(/^[a-z0-9-]{8,32}$/.test(token), 'fresh non-secret run token 8-32 characters');
  requireCheck(prepare || !preparedInThisProcess, 'force-stop and relaunch before restart verification');
  running = true;
  try {
    // Dedicated evaluation file. Never enumerate/clear other app preferences.
    const backend = preferences.getPreferencesSync(context, { name: 'madcore_device_verification' });
    const storage = new PreferencesStringStore(backend);
    const store = new NamespacedStringStore(storage, 'devicecheck');
    const key = 'run-' + token;
    if (prepare) {
      requireCheck(store.get(key) === null, 'use a fresh token');
      store.put(key, 'initial');
      requireCheck(store.get(key) === 'initial', 'create/read');
      store.put(key, 'restart-中文-🙂');
      requireCheck(store.get(key) === 'restart-中文-🙂', 'update');
      await storage.flush();
      preparedInThisProcess = true;
    } else {
      requireCheck(store.get(key) === 'restart-中文-🙂', 'persisted value after process restart');
      store.remove(key);
      requireCheck(store.get(key) === null, 'remove');
      await storage.flush();
    }
  } finally { running = false; }
}
