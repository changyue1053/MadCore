import nativeCore from 'libmadcore_napi.so';
/** Primitive-only initial facade. Native implementation owns no ArkTS/Kotlin objects across calls. */
export class MadCore {
  static abiVersion(): number { return nativeCore.abiVersion(); }
  static epochMillis(): number { return nativeCore.epochMillis(); }
  static isJsonObject(input: string): boolean { return nativeCore.isJsonObject(input); }
}

export { PreferencesStringStore, StorageFailure, StorageException, StringStore } from './Storage';
export { RcpHttpClient } from './RcpHttpClient';
export { RcpRequest, RcpLimits, RcpResponse, RcpFailure, RcpTransportException } from './HttpPolicy';

export { NamespacedStringStore } from './NamespacedStorage';

export { ResourceScope, ResourceRegistration, CloseReport, ScopeClosedException, FatalCleanupError, CloseableResource } from './ResourceScope';
