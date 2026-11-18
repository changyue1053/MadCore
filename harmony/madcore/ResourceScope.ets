/** Synchronous cleanup only; host serializes all scope and registration access. */
export interface CloseableResource {
  close(): void;
}

export class ScopeClosedException extends Error {
  constructor() { super('Resource scope is closed'); }
}

/**
 * Explicit fatal marker: JavaScript has no Kotlin Throwable/Exception taxonomy.
 * Only this marker triggers deferred rethrow; other thrown values are counted.
 */
export class FatalCleanupError extends Error {
  constructor() { super('Fatal resource cleanup failure'); }
}

/** Counts only; no resource names, values or exception diagnostics retained. */
export class CloseReport {
  readonly attempted: number;
  readonly failed: number;
  constructor(attempted: number, failed: number) {
    this.attempted = attempted;
    this.failed = failed;
  }
}

/** Detach transfers ownership to caller WITHOUT closing the resource. */
export class ResourceRegistration {
  private detachAction: () => boolean;
  constructor(detachAction: () => boolean) { this.detachAction = detachAction; }
  detach(): boolean { return this.detachAction(); }
}

class ResourceEntry {
  resource: CloseableResource | null;
  constructor(resource: CloseableResource) { this.resource = resource; }
}

/**
 * Host-serialized synchronous ownership, not platform lifecycle or a Kotlin bridge.
 * No scheduler, async cancellation, thread safety or backend ownership inference.
 * Each registration is distinct, even when the same resource is registered twice.
 * Closing releases all entries before LIFO callbacks. Ordinary thrown values are
 * isolated/countable; the first FatalCleanupError is rethrown after the batch.
 */
export class ResourceScope {
  private entries: ResourceEntry[] = [];
  private closed: boolean = false;
  get isClosed(): boolean { return this.closed; }

  register(resource: CloseableResource): ResourceRegistration {
    if (this.closed) throw new ScopeClosedException();
    const entry = new ResourceEntry(resource);
    this.entries.push(entry);
    return new ResourceRegistration((): boolean => {
      if (entry.resource === null) return false;
      entry.resource = null;
      const index = this.entries.indexOf(entry);
      if (index >= 0) this.entries.splice(index, 1);
      return true;
    });
  }

  close(): CloseReport {
    if (this.closed) return new CloseReport(0, 0);
    this.closed = true;
    const pending: CloseableResource[] = [];
    for (const entry of this.entries) {
      if (entry.resource !== null) pending.push(entry.resource);
      entry.resource = null;
    }
    this.entries = [];
    let failed: number = 0;
    let fatal: FatalCleanupError | null = null;
    for (let index = pending.length - 1; index >= 0; index--) {
      try { pending[index].close(); }
      catch (error) {
        failed++;
        if (error instanceof FatalCleanupError && fatal === null) fatal = error;
      }
    }
    if (fatal !== null) throw fatal;
    return new CloseReport(pending.length, failed);
  }

  toString(): string { return 'ResourceScope(isClosed=' + this.closed + ')'; }
}
