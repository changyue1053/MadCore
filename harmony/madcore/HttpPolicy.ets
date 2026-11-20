/** Pure bounded policy shared by the ArkTS adapter and host-side semantic tests. */
export enum RcpFailure {
  InvalidRequest = 'InvalidRequest',
  RequestTooLarge = 'RequestTooLarge',
  ResponseTooLarge = 'ResponseTooLarge',
  Timeout = 'Timeout',
  Io = 'Io'
}

export class RcpTransportException extends Error {
  readonly failure: RcpFailure;
  constructor(failure: RcpFailure) {
    super('HTTP transport failure: ' + failure);
    this.failure = failure;
  }
}

export class RcpLimits {
  readonly connectTimeoutMillis: number;
  readonly readTimeoutMillis: number;
  readonly callTimeoutMillis: number;
  readonly maxResponseBytes: number;
  readonly maxRequestBytes: number;
  readonly allowInsecureHttp: boolean;
  constructor(connectTimeoutMillis: number = 10000, readTimeoutMillis: number = 10000,
    callTimeoutMillis: number = 30000, maxResponseBytes: number = 1048576,
    maxRequestBytes: number = 1048576, allowInsecureHttp: boolean = false) {
    for (const value of [connectTimeoutMillis, readTimeoutMillis, callTimeoutMillis]) {
      if (!Number.isInteger(value) || value < 1 || value > 2147483647) {
        throw new RcpTransportException(RcpFailure.InvalidRequest);
      }
    }
    for (const value of [maxResponseBytes, maxRequestBytes]) {
      if (!Number.isInteger(value) || value < 1 || value > 16777216) {
        throw new RcpTransportException(RcpFailure.InvalidRequest);
      }
    }
    this.connectTimeoutMillis = connectTimeoutMillis;
    this.readTimeoutMillis = readTimeoutMillis;
    this.callTimeoutMillis = callTimeoutMillis;
    this.maxResponseBytes = maxResponseBytes;
    this.maxRequestBytes = maxRequestBytes;
    this.allowInsecureHttp = allowInsecureHttp;
  }
}

export class RcpRequest {
  readonly url: string;
  readonly method: 'GET' | 'POST' | 'PUT' | 'DELETE';
  private headerValues: Record<string, string>;
  private payload: ArrayBuffer;
  constructor(url: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE' = 'GET',
    headers: Record<string, string> = {}, body: ArrayBuffer = new ArrayBuffer(0)) {
    // Conservative ASCII DNS/IPv4 authority only. IPv6/IDN must not be silently misparsed.
    const match = url.match(/^https?:\/\/([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(?:[/?][^#\\]*)?$/);
    if (url.length > 8192 || match === null || /[\u0000-\u0020\u007f\\]/.test(url) ||
      (method !== 'GET' && method !== 'POST' && method !== 'PUT' && method !== 'DELETE')) {
      throw new RcpTransportException(RcpFailure.InvalidRequest);
    }
    if (match[2] !== undefined && (Number(match[2]) < 1 || Number(match[2]) > 65535)) {
      throw new RcpTransportException(RcpFailure.InvalidRequest);
    }
    if (body.byteLength > 16777216) throw new RcpTransportException(RcpFailure.RequestTooLarge);
    if ((method === 'GET' || method === 'DELETE') && body.byteLength !== 0) throw new RcpTransportException(RcpFailure.InvalidRequest);
    this.headerValues = {};
    const names = new Set<string>();
    for (const name of Object.keys(headers)) {
      const value = headers[name];
      const lower = name.toLowerCase();
      if (!/^[A-Za-z0-9-]+$/.test(name) || /[\u0000-\u001f\u007f]/.test(value) ||
        names.has(lower) || ['host', 'content-length', 'transfer-encoding', 'connection'].includes(lower)) {
        throw new RcpTransportException(RcpFailure.InvalidRequest);
      }
      names.add(lower);
      this.headerValues[name] = value;
    }
    this.url = url;
    this.method = method;
    this.payload = body.slice(0);
  }
  get headers(): Record<string, string> {
    const copy: Record<string, string> = {};
    for (const key of Object.keys(this.headerValues)) copy[key] = this.headerValues[key];
    return copy;
  }
  get body(): ArrayBuffer { return this.payload.slice(0); }
  get bodySize(): number { return this.payload.byteLength; }
  toString(): string { return 'RcpRequest'; }
}

/** Bounds retained bytes, not the platform's incoming chunk allocation/internal buffers. */
export class BoundedResponseBody {
  private bytes: Uint8Array;
  private used: number = 0;
  constructor(capacity: number) {
    if (!Number.isInteger(capacity) || capacity < 1 || capacity > 16777216) {
      throw new RcpTransportException(RcpFailure.InvalidRequest);
    }
    this.bytes = new Uint8Array(capacity);
  }
  append(chunk: ArrayBuffer): void {
    if (chunk.byteLength > this.bytes.length - this.used) {
      throw new RcpTransportException(RcpFailure.ResponseTooLarge);
    }
    this.bytes.set(new Uint8Array(chunk), this.used);
    this.used += chunk.byteLength;
  }
  finish(): ArrayBuffer { return this.bytes.slice(0, this.used).buffer as ArrayBuffer; }
}

export class RcpResponse {
  readonly status: number;
  private headerValues: Map<string, string[]>;
  private payload: ArrayBuffer;
  constructor(status: number, body: ArrayBuffer, headers: Map<string, string[]> = new Map<string, string[]>()) {
    if (!Number.isInteger(status) || status < 100 || status > 599) {
      throw new RcpTransportException(RcpFailure.Io);
    }
    this.status = status;
    this.headerValues = new Map<string, string[]>();
    headers.forEach((values: string[], name: string) => { this.headerValues.set(name, values.slice()); });
    this.payload = body.slice(0);
  }
  get body(): ArrayBuffer { return this.payload.slice(0); }
  get bodySize(): number { return this.payload.byteLength; }
  get headers(): Map<string, string[]> {
    const copy = new Map<string, string[]>();
    this.headerValues.forEach((values: string[], name: string) => { copy.set(name, values.slice()); });
    return copy;
  }
  toString(): string { return 'RcpResponse(status=' + this.status + ')'; }
}
