// Test double ONLY. Not included in HAR and never a substitute for device testing.
export const state = {
  mode: 'success',
  creates: 0,
  cancels: 0,
  closes: 0,
  configuration: undefined as any,
  request: undefined as any
};
class Request {
  destination: (chunk: ArrayBuffer) => void = () => {};
  constructor(public url: string, public method: string, public headers: object, public content?: ArrayBuffer) {}
}
class Session {
  fetch(request: Request): Promise<any> {
    state.request = request;
    if (state.mode === 'syncThrow') throw new Error('private diagnostic');
    if (state.mode === 'nativeTimeout') return Promise.reject({ code: 1007900028, message: 'private diagnostic' });
    if (state.mode === 'io') return Promise.reject({ code: 1007900007, message: 'private diagnostic' });
    if (state.mode === 'timeout') return new Promise(() => {});
    if (state.mode === 'late') {
      return new Promise(resolve => setTimeout(() => {
        request.destination(new Uint8Array([9]).buffer);
        resolve({ statusCode: 200 });
      }, 20));
    }
    if (state.mode === 'overflow' || state.mode === 'reentrantOverflow') {
      request.destination(new Uint8Array([1, 2, 3, 4]).buffer);
      request.destination(new Uint8Array([9]).buffer);
      return Promise.resolve({ statusCode: 200 });
    }
    request.destination(new Uint8Array([1, 2]).buffer);
    request.destination(new Uint8Array([3]).buffer);
    return Promise.resolve({ statusCode: state.mode === 'redirect' ? 302 : 200 });
  }
  cancel(request: Request): void {
    state.cancels++;
    if (state.mode === 'reentrantOverflow') {
      request.destination(new Uint8Array([9]).buffer);
      throw new Error('private cancel diagnostic');
    }
  }
  close(): void {
    state.closes++;
    if (state.mode === 'reentrantOverflow') {
      state.request.destination(new Uint8Array([9]).buffer);
      throw new Error('private close diagnostic');
    }
  }
}
export const rcp = {
  Request,
  createSession(configuration: object): Session {
    state.creates++;
    state.configuration = configuration;
    return new Session();
  }
};
export class BusinessError extends Error { code: number = 0; }
