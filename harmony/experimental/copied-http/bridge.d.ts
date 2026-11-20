export interface CopiedRequest {
  operation: number; method: number; url: string; headers: string; body: ArrayBuffer;
  maxResponse: number; connectTimeout: number; readTimeout: number; callTimeout: number; allowInsecure: number;
}
export const open: () => number;
export const close: (session: number) => number;
export const state: (session: number, operation: number) => number;
export const nextRequest: (session: number) => CopiedRequest | null;
export const complete: (session: number, operation: number, status: number, headers: string, body: ArrayBuffer) => number;
export const fail: (session: number, operation: number, failure: number) => number;
export const startTest: (session: number, url: string, scenario: number) => number;
export const pollTest: (session: number, operation: number, scenario: number) => number;
export const cancelTest: (session: number, operation: number) => number;
