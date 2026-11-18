import { preferences } from '@kit.ArkData';

export enum StorageFailure {
  InvalidKey = 'InvalidKey',
  ValueTooLarge = 'ValueTooLarge',
  InvalidValue = 'InvalidValue',
  Backend = 'Backend'
}

export class StorageException extends Error {
  readonly failure: StorageFailure;
  constructor(failure: StorageFailure) {
    super('Storage failure: ' + failure);
    this.failure = failure;
  }
}

function checkKey(key: string): void {
  if (!/^[a-z][a-z0-9_.-]{0,127}$/.test(key)) {
    throw new StorageException(StorageFailure.InvalidKey);
  }
}

function checkValue(value: string): void {
  if (value.length > 65536) throw new StorageException(StorageFailure.ValueTooLarge);
  let bytes: number = 0;
  for (let i: number = 0; i < value.length; i++) {
    const code: number = value.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF) {
      i++;
      if (i >= value.length || value.charCodeAt(i) < 0xDC00 || value.charCodeAt(i) > 0xDFFF) {
        throw new StorageException(StorageFailure.InvalidValue);
      }
      bytes += 4;
    } else if (code >= 0xDC00 && code <= 0xDFFF) {
      throw new StorageException(StorageFailure.InvalidValue);
    } else {
      bytes += code < 0x80 ? 1 : (code < 0x800 ? 2 : 3);
    }
  }
  if (bytes > 65536) throw new StorageException(StorageFailure.ValueTooLarge);
}

/**
 * Host-owned isolated Preferences instance; caller serializes all access including outside writers.
 * Cache operations only: await flush() for the platform's flush acknowledgement, not crash durability.
 * Non-secret, unencrypted. No enumeration, global clear, context capture or automatic file creation.
 * This ArkTS API is NOT a bridge implementing the Kotlin StringStore interface.
 */
export class PreferencesStringStore {
  private backend: preferences.Preferences;
  constructor(backend: preferences.Preferences) { this.backend = backend; }

  get(key: string): string | null {
    checkKey(key);
    let value: string;
    try {
      if (!this.backend.hasSync(key)) return null;
      const first = this.backend.getSync(key, '');
      if (typeof first !== 'string') throw new StorageException(StorageFailure.InvalidValue);
      value = first as string;
      // Preferences returns the supplied default for wrong types, not just missing keys.
      // Two defaults distinguish a real empty string without reading unrelated preferences.
      if (value === '') {
        const second = this.backend.getSync(key, '__madcore_type_probe__');
        if (second !== '') throw new StorageException(StorageFailure.InvalidValue);
      }
    } catch (error) {
      if (error instanceof StorageException) throw error;
      throw new StorageException(StorageFailure.Backend);
    }
    checkValue(value);
    return value;
  }

  put(key: string, value: string): void {
    checkKey(key);
    checkValue(value);
    try { this.backend.putSync(key, value); }
    catch (_) { throw new StorageException(StorageFailure.Backend); }
  }

  remove(key: string): void {
    checkKey(key);
    try { this.backend.deleteSync(key); }
    catch (_) { throw new StorageException(StorageFailure.Backend); }
  }

  async flush(): Promise<void> {
    try { await this.backend.flush(); }
    catch (_) { throw new StorageException(StorageFailure.Backend); }
  }
}
