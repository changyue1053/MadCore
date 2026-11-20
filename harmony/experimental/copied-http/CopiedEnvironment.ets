import bridge from 'libmadcore_copied_bridge.so';
import { worker, MessageEvents } from '@kit.ArkTS';

/** Test report contains value IDs only, never native pointers or Kotlin references. */
export class CopiedEnvironmentIds {
  sessions: number[] = [];
  operations: number[] = [];
}

function checkEnvironment(value: boolean, stage: string): void {
  if (!value) throw new Error('Copied environment verification failed: ' + stage);
}
function pauseEnvironment(): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, 20));
}

/** Worker-only test setup. Never pumps requests: the fixed URL performs no I/O.
 * Deliberately leaves C sessions owned by the Worker environment for its cleanup
 * hook. This is not an RCP callback, socket, or native asynchronous drain test. */
export function prepareCopiedEnvironment(): CopiedEnvironmentIds {
  const report = new CopiedEnvironmentIds();
  for (let n: number = 0; n < 4; n++) {
    const session = bridge.open();
    checkEnvironment(session > 0, 'worker opens four sessions');
    report.sessions.push(session);
    const operation = bridge.startTest(session, 'http://127.0.0.1:1/ok', 1);
    checkEnvironment(operation > 0, 'worker queues operation');
    report.operations.push(operation);
    checkEnvironment(bridge.state(session, operation) === 1, 'worker pending without pump');
  }
  return report;
}

/** Finite, network-free real Worker cleanup probe. Termination is observed, then
 * registry capacity is checked separately: onexit is NOT assumed a cleanup fence.
 * Deadlines only fail the test; they never clear another environment's registry. */
export async function verifyCopiedEnvironment(path: string): Promise<void> {
  const thread = new worker.ThreadWorker(path);
  let exited: boolean = false;
  let exitCode: number = -1;
  let failed: boolean = false;
  let reported: boolean = false;
  let report = new CopiedEnvironmentIds();
  const acquired: number[] = [];
  thread.onexit = (code: number): void => { exitCode = code; exited = true; };
  thread.onerror = (): void => { failed = true; };
  thread.onmessageerror = (): void => { failed = true; };
  thread.onmessage = (event: MessageEvents): void => {
    if (reported) { failed = true; return; }
    report = event.data as CopiedEnvironmentIds;
    reported = true;
  };
  try {
    thread.postMessage('prepare');
    const reportDeadline = Date.now() + 10000;
    while (!reported) {
      checkEnvironment(!failed && !exited, 'worker report');
      checkEnvironment(Date.now() < reportDeadline, 'worker report deadline');
      await pauseEnvironment();
    }
    checkEnvironment(!failed && !exited, 'worker alive at report');
    checkEnvironment(report !== null && Array.isArray(report.sessions) && Array.isArray(report.operations), 'report shape');
    checkEnvironment(report.sessions.length === 4 && report.operations.length === 4, 'report count');
    for (const id of report.sessions.concat(report.operations)) {
      checkEnvironment(Number.isInteger(id) && id > 0 && id <= 2147483647, 'report numeric IDs');
    }
    checkEnvironment(new Set<number>(report.sessions).size === 4 && new Set<number>(report.operations).size === 4, 'distinct IDs');
    const capacity = bridge.open();
    if (capacity > 0) { bridge.close(capacity); }
    checkEnvironment(capacity === -3, 'worker occupies shared four-session registry');
    thread.terminate(); // no explicit close of Worker sessions
    const exitDeadline = Date.now() + 10000;
    while (!exited) {
      checkEnvironment(Date.now() < exitDeadline, 'worker exit deadline');
      await pauseEnvironment();
    }
    checkEnvironment(exitCode === 0, 'clean worker exit');
    const recoveryDeadline = Date.now() + 10000;
    while (acquired.length < 4) {
      const session = bridge.open();
      if (session > 0) acquired.push(session);
      else checkEnvironment(session === -3, 'recovery open result');
      if (acquired.length < 4) {
        checkEnvironment(Date.now() < recoveryDeadline, 'cleanup capacity recovery deadline');
        await pauseEnvironment();
      }
    }
    const full = bridge.open();
    if (full > 0) bridge.close(full);
    checkEnvironment(full === -3, 'recovered registry remains bounded');
    for (const session of acquired) {
      for (const oldSession of report.sessions) checkEnvironment(session > oldSession, 'monotonic session IDs');
      for (const oldOperation of report.operations) {
        checkEnvironment(bridge.state(session, oldOperation) === -2, 'stale operation isolated');
        checkEnvironment(bridge.complete(session, oldOperation, 200, '{}', new ArrayBuffer(0)) === -2, 'stale completion isolated');
      }
      const operation = bridge.startTest(session, 'http://127.0.0.1:1/ok', 1);
      for (const oldOperation of report.operations) checkEnvironment(operation > oldOperation, 'monotonic operation IDs');
      checkEnvironment(bridge.state(session, operation) === 1, 'fresh pending without pump');
      checkEnvironment(bridge.cancelTest(session, operation) === 1, 'fresh cancellation');
      checkEnvironment(bridge.pollTest(session, operation, 3) === 1, 'fresh cancelled result');
    }
    for (let n: number = 0; n < 4; n++) {
      checkEnvironment(bridge.complete(report.sessions[n], report.operations[n], 200, '{}', new ArrayBuffer(0)) === -2, 'foreign late completion rejected');
    }
    checkEnvironment(!failed, 'worker callback error');
  } finally {
    for (const session of acquired) bridge.close(session);
    if (!exited) { try { thread.terminate(); } catch (_) {} }
  }
}
