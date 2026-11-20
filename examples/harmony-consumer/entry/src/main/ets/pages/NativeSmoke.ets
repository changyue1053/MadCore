import { MadCore } from 'madcore';

/** Runs only on the host device. A successful unsigned build is not a test result. */
export function runNativeSmoke(): number {
  let checks: number = 0;
  const expect = (condition: boolean): void => {
    if (!condition) throw new Error('Native boundary assertion failed');
    checks++;
  };
  expect(MadCore.abiVersion() === 1);
  const epoch: number = MadCore.epochMillis();
  expect(Number.isSafeInteger(epoch) && epoch > 0);
  expect(MadCore.isJsonObject('{"hello":"MadCore"}'));
  expect(MadCore.isJsonObject('{"text":"中文😀"}'));
  expect(!MadCore.isJsonObject('{'));
  expect(!MadCore.isJsonObject('[]'));
  expect(!MadCore.isJsonObject('null'));
  expect(!MadCore.isJsonObject(''));
  expect(!MadCore.isJsonObject('{}\u0000{}'));
  // Exactly 64 KiB UTF-8 is accepted by the bridge, one byte beyond is rejected.
  expect(MadCore.isJsonObject('{"x":"' + 'a'.repeat(65528) + '"}'));
  let overLimitRejected: boolean = false;
  try { MadCore.isJsonObject('{"x":"' + 'a'.repeat(65529) + '"}'); }
  catch (_) { overLimitRejected = true; }
  expect(overLimitRejected);
  return checks;
}
