// Test double only. Never packaged; simulates serialized in-memory Preferences,
// including getSync returning its default for a stored value of a different type.
export class FakePreferences {
  values = new Map<string, unknown>();
  calls: string[] = [];
  failure = '';
  rawWrongType = false;
  private getCount = 0;
  resetCalls(): void { this.calls = []; this.getCount = 0; }
  private record(operation: string): void {
    this.calls.push(operation);
    if (this.failure === operation) throw new Error('private backend diagnostic');
  }
  hasSync(key: string): boolean { this.record('has'); return this.values.has(key); }
  getSync(key: string, fallback: string): unknown {
    this.getCount++;
    this.record('get');
    if (this.failure === 'secondGet' && this.getCount === 2) throw new Error('private second diagnostic');
    if (!this.values.has(key)) return fallback;
    const value = this.values.get(key);
    if (typeof value !== typeof fallback && !this.rawWrongType) return fallback;
    return value;
  }
  putSync(key: string, value: string): void { this.record('put'); this.values.set(key, value); }
  deleteSync(key: string): void { this.record('delete'); this.values.delete(key); }
  flush(): Promise<void> {
    this.record('flush');
    return this.failure === 'flushReject'
      ? Promise.reject(new Error('private flush diagnostic')) : Promise.resolve();
  }
}
export const preferences = { Preferences: FakePreferences };
