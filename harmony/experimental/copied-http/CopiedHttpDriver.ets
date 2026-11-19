import bridge, { CopiedRequest } from 'libmadcore_copied_bridge.so';
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { RcpRequest, RcpLimits, BoundedResponseBody } from './HttpPolicy';

// Slots are released only by actual fetch Promise settlement, never by timeout/cancel.
// Across driver instances this bounds closures even if a platform Promise never settles.
let platformOutstanding: number = 0;
const platformCapacity: number = 8;
class InFlight {
  private stopped: boolean = false;
  readonly session: rcp.Session;
  readonly request: rcp.Request;
  readonly timer: number;
  constructor(session: rcp.Session, request: rcp.Request, timer: number) {
    this.session = session; this.request = request; this.timer = timer;
  }
  stop(): void {
    if (this.stopped) return;
    this.stopped = true;
    clearTimeout(this.timer);
    try { this.session.cancel(this.request); } catch (_) {}
    try { this.session.close(); } catch (_) {}
  }
}

/** Experimental host-owned owner-loop driver. No native worker or Kotlin references.
 * close invalidates copied delivery and requests RCP cancellation; it does not prove drain.
 * Promise closures keep only JS state/value IDs, never C pointers. */
export class CopiedHttpDriver {
  readonly session: number;
  private closed: boolean = false;
  private timer: number;
  private active: Map<number, InFlight> = new Map<number, InFlight>();
  constructor() {
    this.session = bridge.open();
    if (this.session <= 0) throw new Error('Copied session unavailable');
    this.timer = setInterval(() => this.pump(), 20);
  }
  close(): void {
    if (this.closed) return;
    this.closed = true;
    clearInterval(this.timer);
    // Tombstone first; no late JS result can recreate the C session.
    bridge.close(this.session);
    this.active.forEach((v: InFlight) => v.stop());
    // Keep entries until fetch settles; closing is not a drain assertion.
  }
  pump(): void {
    if (this.closed) return;
    this.active.forEach((v: InFlight, id: number) => {
      if (bridge.state(this.session, id) !== 1) { v.stop(); }
    });
    for (let n: number = 0; n < 8; n++) {
      let request: CopiedRequest | null;
      try { request = bridge.nextRequest(this.session); } catch (_) { this.close(); return; }
      if (request === null) return;
      this.dispatch(request);
    }
  }
  private fail(id: number, code: number): void {
    if (!this.closed) bridge.fail(this.session, id, code);
    const old = this.active.get(id);
    if (old !== undefined) old.stop();
    // Only the actual fetch settlement releases the outstanding slot.
  }
  private dispatch(wire: CopiedRequest): void {
    let platformSession: rcp.Session | undefined = undefined;
    let counted: boolean = false;
    try {
      if (platformOutstanding >= platformCapacity) { bridge.fail(this.session, wire.operation, 1); return; }
      const methods: Array<'GET' | 'POST' | 'PUT' | 'DELETE'> = ['GET', 'POST', 'PUT', 'DELETE'];
      if (wire.method < 1 || wire.method > 4) throw new Error('Method');
      const headers = JSON.parse(wire.headers) as Record<string, string>;
      if (headers === null || Array.isArray(headers) || typeof headers !== 'object') throw new Error('Header shape');
      for (const name of Object.keys(headers)) { if (typeof headers[name] !== 'string') throw new Error('Header value'); }
      const request = new RcpRequest(wire.url, methods[wire.method - 1], headers, wire.body);
      const limits = new RcpLimits(wire.connectTimeout, wire.readTimeout, wire.callTimeout,
        wire.maxResponse, 65536, wire.allowInsecure === 1);
      if (request.url.startsWith('http://') && !limits.allowInsecureHttp) throw new Error('Policy');
      const body = new BoundedResponseBody(limits.maxResponseBytes);
      platformSession = rcp.createSession({ requestConfiguration: { transfer: { autoRedirect: false,
        timeout: { connectMs: limits.connectTimeoutMillis, inactivityMs: limits.readTimeoutMillis,
          transferMs: limits.callTimeoutMillis } } } });
      const nativeRequest = new rcp.Request(request.url, request.method, request.headers,
        request.method === 'POST' || request.method === 'PUT' ? request.body : undefined);
      nativeRequest.destination = (chunk: ArrayBuffer): void => {
        if (this.closed || bridge.state(this.session, wire.operation) !== 1) return;
        try { body.append(chunk); } catch (_) { this.fail(wire.operation, 3); }
      };
      const timer = setTimeout(() => this.fail(wire.operation, 2), limits.callTimeoutMillis);
      const active = new InFlight(platformSession, nativeRequest, timer);
      this.active.set(wire.operation, active);
      platformOutstanding++; counted = true;
      platformSession.fetch(nativeRequest).then((response: rcp.Response) => {
        if (this.closed) return;
        if (bridge.state(this.session, wire.operation) !== 1) { this.fail(wire.operation, 1); return; }
        try {
          const copied: Record<string, string[]> = {};
          let chars: number = 0;
          const names = Object.keys(response.headers);
          if (names.length > 128) throw new Error('Header cap');
          for (const name of names) {
            const value = response.headers[name];
            if (value === undefined) continue;
            if (!/^[A-Za-z0-9-]+$/.test(name)) throw new Error('Header name');
            if (typeof value !== 'string' && value.length > 128) throw new Error('Header cap');
            const values: string[] = typeof value === 'string' ? [value] : value.slice();
            if (values.length > 128) throw new Error('Header cap');
            chars += name.length;
            for (const item of values) chars += item.length;
            if (chars > 16384) throw new Error('Header cap');
            copied[name] = values;
          }
          const json = JSON.stringify(copied);
          if (json.length > 16384 || new util.TextEncoder().encodeInto(json).byteLength > 16384) throw new Error('Header cap');
          if (bridge.complete(this.session, wire.operation, response.statusCode, json, body.finish()) < 0) this.fail(wire.operation, 1);
          active.stop();
        } catch (_) { this.fail(wire.operation, 1); }
      }).catch((e: BusinessError) => this.fail(wire.operation, e.code === 1007900028 ? 2 : 1)).finally(() => {
        active.stop(); this.active.delete(wire.operation); platformOutstanding--;
      });
      counted = false; // Promise chain owns the slot now, even when cancelled/closed.
    } catch (_) {
      if (counted) platformOutstanding--; // fetch threw synchronously, no accepted Promise.
      if (platformSession !== undefined) { try { platformSession.close(); } catch (_) {} }
      this.fail(wire.operation, 1);
      this.active.delete(wire.operation); // no accepted Promise chain owns this entry
    }
  }
}

function check(value: boolean): void { if (!value) throw new Error('Copied HTTP device verification failed'); }
function pause(ms: number): Promise<void> { return new Promise<void>(resolve => setTimeout(resolve, ms)); }
async function waitResult(driver: CopiedHttpDriver, id: number, scenario: number): Promise<void> {
  for (let n: number = 0; n < 250; n++) {
    const code = bridge.pollTest(driver.session, id, scenario);
    if (code !== 0) { check(code === 1); return; }
    await pause(20);
  }
  throw new Error('Copied HTTP verification wait exceeded');
}

/** Explicit loopback-only test harness. Production adapter itself has no hard-coded destinations. */
export async function runCopiedHttpDeviceVerification(http: string, tls: string): Promise<void> {
  check(/^http:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}$/.test(http));
  check(/^https:\/\/127\.0\.0\.1:[1-9][0-9]{0,4}$/.test(tls));
  const driver = new CopiedHttpDriver();
  try {
    const paths = ['/ok', '/bridge-echo', '/slow', '/chunked', '/slow', '/error', '/bridge-headers', '/redirect', '/tls-probe', '/echo', '/echo'];
    for (let scenario: number = 1; scenario <= 11; scenario++) {
      const id = bridge.startTest(driver.session, (scenario === 9 ? tls : http) + paths[scenario - 1], scenario);
      check(id > 0); driver.pump();
      if (scenario === 3) { check(bridge.cancelTest(driver.session, id) === 1); driver.pump(); }
      await waitResult(driver, id, scenario);
    }
    // Capacity is bounded even when consumer has not drained queued requests.
    const ids: number[] = [];
    for (let n: number = 0; n < 8; n++) { const id = bridge.startTest(driver.session, http + '/ok', 1); check(id > 0); ids.push(id); }
    check(bridge.startTest(driver.session, http + '/ok', 1) < 0);
    for (const id of ids) { check(bridge.cancelTest(driver.session, id) === 1); check(bridge.pollTest(driver.session, id, 3) === 1); }
    const late = bridge.startTest(driver.session, http + '/slow', 1); // endpoint rejected by Kotlin harness
    check(late < 0);
    const closing = bridge.startTest(driver.session, http + '/slow', 3);
    check(closing > 0); driver.pump(); driver.close(); driver.close();
    check(bridge.complete(driver.session, closing, 200, '{}', new ArrayBuffer(0)) === -2);
    const fresh = new CopiedHttpDriver();
    try {
      check(fresh.session !== driver.session);
      check(bridge.state(fresh.session, closing) === -2);
      const id = bridge.startTest(fresh.session, http + '/ok', 1); check(id > 0); fresh.pump();
      await waitResult(fresh, id, 1);
      await pause(1200); // allows a late slow RCP settlement; not an assertion of platform drain
      check(bridge.state(fresh.session, closing) === -2);
    } finally { fresh.close(); }
  } finally { driver.close(); }
}
