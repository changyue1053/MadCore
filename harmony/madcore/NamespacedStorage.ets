import { StorageException, StorageFailure } from './Storage';
import type { StringStore } from './Storage';

/**
 * Prefix isolation for host-selected namespaces, not an access-control boundary.
 * No clear/enumeration/flush or backend ownership. The host flushes its backend.
 * Values and backend failures pass through unchanged to the supplied store.
 */
export class NamespacedStringStore implements StringStore {
  private backend: StringStore;
  private namespace: string;

  constructor(backend: StringStore, namespace: string) {
    if (!/^[a-z][a-z0-9_-]{0,31}$/.test(namespace)) {
      throw new StorageException(StorageFailure.InvalidKey);
    }
    this.backend = backend;
    this.namespace = namespace;
  }

  private physicalKey(key: string): string {
    if (!/^[a-z][a-z0-9_.-]{0,94}$/.test(key)) {
      throw new StorageException(StorageFailure.InvalidKey);
    }
    return this.namespace + '.' + key;
  }

  get(key: string): string | null { return this.backend.get(this.physicalKey(key)); }
  put(key: string, value: string): void { this.backend.put(this.physicalKey(key), value); }
  remove(key: string): void { this.backend.remove(this.physicalKey(key)); }
}
