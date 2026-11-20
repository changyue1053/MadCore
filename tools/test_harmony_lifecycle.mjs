// Executes exact pure ETS source. No Harmony runtime or Kotlin bridge involved.
import { mkdtemp, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const dir = await mkdtemp(join(tmpdir(), 'madcore-lifecycle-'));
try {
  const file = join(dir, 'ResourceScope.ts');
  await copyFile(new URL('../harmony/madcore/ResourceScope.ets', import.meta.url), file);
  const { ResourceScope, FatalCleanupError, ScopeClosedException } = await import(pathToFileURL(file));
  const events = [];
  const scope = new ResourceScope();
  const first = scope.register({ close() { events.push(1); } });
  let detachedCalls = 0;
  const detachedResource = { close() { detachedCalls++; } };
  const detached = scope.register(detachedResource);
  scope.register({ close() { events.push(3); } });
  assert.equal(detached.detach(), true); assert.equal(detached.detach(), false);
  assert.equal(scope.isClosed, false);
  const report = scope.close();
  assert.deepEqual(events, [3, 1]);
  assert.equal(report.attempted, 2); assert.equal(report.failed, 0);
  assert.equal(detachedCalls, 0); detachedResource.close(); assert.equal(detachedCalls, 1);
  assert.equal(scope.isClosed, true); assert.equal(first.detach(), false);
  assert.equal(scope.close().attempted, 0); assert.equal(scope.close().failed, 0);
  assert.deepEqual(events, [3, 1]);

  const reentrant = new ResourceScope();
  const order = [];
  const earliest = reentrant.register({ close() { order.push('earliest'); } });
  reentrant.register({ close() { throw new Error('private diagnostic'); } });
  reentrant.register({ close() {
    assert.equal(reentrant.isClosed, true);
    assert.equal(earliest.detach(), false);
    assert.equal(reentrant.close().attempted, 0);
    assert.throws(() => reentrant.register({ close() { order.push('rejected'); } }), ScopeClosedException);
    order.push('latest');
  } });
  const mixed = reentrant.close();
  assert.equal(mixed.attempted, 3); assert.equal(mixed.failed, 1);
  assert.deepEqual(order, ['latest', 'earliest']);
  assert.deepEqual(Object.keys(mixed).sort(), ['attempted', 'failed']);
  assert.equal(reentrant.toString().includes('private'), false);
  let rejectedCalls = 0;
  const rejected = { close() { rejectedCalls++; } };
  assert.throws(() => reentrant.register(rejected), ScopeClosedException);
  assert.equal(rejectedCalls, 0); rejected.close(); assert.equal(rejectedCalls, 1);

  const duplicates = new ResourceScope();
  let calls = 0;
  const resource = { close() { calls++; } };
  duplicates.register(resource); duplicates.register(resource);
  assert.equal(duplicates.close().attempted, 2); assert.equal(calls, 2);
  const oneDetached = new ResourceScope();
  const registration = oneDetached.register(resource); oneDetached.register(resource);
  assert.equal(registration.detach(), true); assert.equal(oneDetached.close().attempted, 1);
  assert.equal(calls, 3);

  const fatalScope = new ResourceScope();
  const cleanup = [];
  const firstFatal = new FatalCleanupError();
  const secondFatal = new FatalCleanupError();
  fatalScope.register({ close() { cleanup.push(1); } });
  fatalScope.register({ close() { throw secondFatal; } });
  fatalScope.register({ close() { cleanup.push(3); } });
  fatalScope.register({ close() { throw firstFatal; } });
  fatalScope.register({ close() { cleanup.push(5); } });
  assert.throws(() => fatalScope.close(), e => e === firstFatal);
  assert.deepEqual(cleanup, [5, 3, 1]);
  assert.equal(fatalScope.isClosed, true); assert.equal(fatalScope.close().attempted, 0);
  const ordinary = new ResourceScope();
  for (const value of [new Error('private'), new TypeError('private'), 'private', null, undefined, 42]) {
    ordinary.register({ close() { throw value; } });
  }
  const failures = ordinary.close();
  assert.equal(failures.attempted, 6); assert.equal(failures.failed, 6);
  const empty = new ResourceScope();
  assert.equal(empty.close().attempted, 0); assert.equal(empty.isClosed, true);
  console.log('Harmony lifecycle exact-source tests passed; no platform lifecycle or Kotlin bridge tested');
} finally {
  await rm(dir, { recursive: true, force: true });
}
