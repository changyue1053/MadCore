import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { RcpRequest, RcpLimits, RcpResponse, RcpFailure, RcpTransportException, BoundedResponseBody } from './HttpPolicy';

/**
 * Experimental API18 HarmonyOS RCP facade, NOT a Kotlin HttpTransport callback bridge.
 * Private session per call; no retries/auth/cookies/tracing configuration or TLS trust bypass.
 * Host supplies INTERNET permission. Runtime redirect/TLS/cancellation tests are still required.
 */
export class RcpHttpClient {
  execute(request: RcpRequest, limits: RcpLimits = new RcpLimits()): Promise<RcpResponse> {
    return new Promise<RcpResponse>((resolve, reject) => {
      let session: rcp.Session | undefined = undefined;
      let nativeRequest: rcp.Request | undefined = undefined;
      let settled: boolean = false;
      let timer: number = -1;
      const cleanup = (): void => {
        if (timer !== -1) clearTimeout(timer);
        if (session !== undefined) {
          try { session.close(); } catch (_) {}
        }
      };
      const fail = (failure: RcpFailure): void => {
        if (settled) return;
        settled = true;
        if (session !== undefined && nativeRequest !== undefined) {
          try { session.cancel(nativeRequest); } catch (_) {}
        }
        cleanup();
        reject(new RcpTransportException(failure));
      };
      try {
        if (request.url.startsWith('http://') && !limits.allowInsecureHttp) {
          fail(RcpFailure.InvalidRequest);
          return;
        }
        if (request.bodySize > limits.maxRequestBytes) {
          fail(RcpFailure.RequestTooLarge);
          return;
        }
        const body = new BoundedResponseBody(limits.maxResponseBytes);
        session = rcp.createSession({
          requestConfiguration: {
            transfer: {
              autoRedirect: false,
              timeout: {
                connectMs: limits.connectTimeoutMillis,
                inactivityMs: limits.readTimeoutMillis,
                transferMs: limits.callTimeoutMillis
              }
            }
          }
        });
        nativeRequest = new rcp.Request(request.url, request.method, request.headers,
          request.method === 'POST' ? request.body : undefined);
        // Explicit streaming destination avoids the default full-response array buffer.
        nativeRequest.destination = (chunk: ArrayBuffer): void => {
          if (settled) return;
          try { body.append(chunk); }
          catch (error) {
            fail(error instanceof RcpTransportException && error.failure === RcpFailure.ResponseTooLarge
              ? RcpFailure.ResponseTooLarge : RcpFailure.Io);
          }
        };
        timer = setTimeout(() => fail(RcpFailure.Timeout), limits.callTimeoutMillis);
        session.fetch(nativeRequest).then((response: rcp.Response) => {
          if (settled) return;
          try {
            // Preserve SDK-reported field names and value arrays. Never split comma values
            // (Set-Cookie and quoted values cannot be safely reconstructed that way).
            const headers = new Map<string, string[]>();
            for (const name of Object.keys(response.headers)) {
              const value = response.headers[name];
              if (value !== undefined) headers.set(name, typeof value === 'string' ? [value] : value.slice());
            }
            const result = new RcpResponse(response.statusCode, body.finish(), headers);
            settled = true;
            cleanup();
            resolve(result);
          } catch (_) { fail(RcpFailure.Io); }
        }).catch((error: BusinessError) => {
          fail(error.code === 1007900028 ? RcpFailure.Timeout : RcpFailure.Io);
        });
      } catch (_) {
        fail(RcpFailure.Io);
      }
    });
  }
}
