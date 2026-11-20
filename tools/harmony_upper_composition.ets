// Test-only composition probe injected into the independent artifact consumer.
// Core and both upper libraries are imported by the generated host page.
class CompositionMemory implements StringStore {
  private values: Map<string, string> = new Map<string, string>();
  get(key: string): string | null { return this.values.get(key) ?? null; }
  put(key: string, value: string): void { this.values.set(key, value); }
  remove(key: string): void { this.values.delete(key); }
}

export function upperComposition(): void {
  const backend = new CompositionMemory();
  const shared: NamespacedStringStore = alphaStore(backend);
  const returned: StringStore = betaUse(shared);
  if (returned !== shared || !(returned instanceof NamespacedStringStore) ||
      shared.get('shared') !== 'beta' || backend.get('alpha.shared') !== 'beta') {
    throw new Error('Composition identity or state failed');
  }
  returned.put('shared', 'host');
  if (shared.get('shared') !== 'host') throw new Error('Shared mutation failed');
  shared.remove('shared');
  if (returned.get('shared') !== null || backend.get('alpha.shared') !== null) {
    throw new Error('Shared removal failed');
  }
}
