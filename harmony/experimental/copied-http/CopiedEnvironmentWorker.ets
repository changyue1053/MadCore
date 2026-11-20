import { worker } from '@kit.ArkTS';
import { prepareCopiedEnvironment } from 'madcore';

// Test Worker only. Queues four C-owned requests but never pumps/network-fetches.
// The host terminates this environment; do not explicitly close its sessions here.
let prepared: boolean = false;
worker.workerPort.onmessage = (): void => {
  if (prepared) throw new Error('Copied environment preparation repeated');
  prepared = true;
  worker.workerPort.postMessage(prepareCopiedEnvironment());
};
