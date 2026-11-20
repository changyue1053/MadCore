import { verifyNetwork, verifyStorage } from './DeviceVerification';
import { common } from '@kit.AbilityKit';
import { runNativeSmoke } from './NativeSmoke';

@Entry
@Component
struct Index {
  @State status: string = 'Not run';
  @State abi: string = 'Not checked';
  @State jsonChecks: string = 'Not checked';

  @State httpOrigin: string = '';
  @State tlsOrigin: string = '';
  @State runToken: string = '';
  @State deviceResult: string = 'Opt-in device checks not run';
  @State busy: boolean = false;

  private async deviceCheck(kind: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.deviceResult = 'Running ' + kind;
    try {
      if (kind === 'network') await verifyNetwork(this.httpOrigin, this.tlsOrigin);
      else await verifyStorage(getContext(this) as common.UIAbilityContext, this.runToken, kind === 'prepare');
      this.deviceResult = kind === 'prepare' ? 'STORAGE_PREPARED: force-stop and relaunch, then verify same token' :
        (kind === 'network' ? 'NETWORK_DEVICE_PASS' : 'STORAGE_RESTART_DEVICE_PASS');
    } catch (_) { this.deviceResult = 'DEVICE_CHECK_FAILED: no pass; inspect configuration and evidence'; }
    finally { this.busy = false; }
  }

  aboutToAppear(): void {
    this.checkCore();
  }

  private checkCore(): void {
    try {
      const count: number = runNativeSmoke();
      this.abi = 'Native ABI, epoch and UTF-8 boundary checked';
      this.jsonChecks = `${count} required native cases passed`;
      this.status = 'Native boundary smoke passed on this device';
    } catch (_) {
      this.status = 'Native call failed';
      this.abi = 'Unavailable';
      this.jsonChecks = 'Unavailable';
    }
  }

  build() {
    Scroll() {
    Column({ space: 16 }) {
      Text('MadCore HAR consumer').fontSize(24).fontWeight(FontWeight.Bold)
      Text(this.status).id('madcore-status')
      Text(this.abi).id('madcore-abi')
      Text(this.jsonChecks).id('madcore-json')
      Button('Run checks again').onClick(() => this.checkCore())
      TextInput({ placeholder: 'Controlled HTTP origin with port', text: this.httpOrigin }).onChange((v: string) => { this.httpOrigin = v; })
      TextInput({ placeholder: 'Controlled untrusted TLS origin with port', text: this.tlsOrigin }).onChange((v: string) => { this.tlsOrigin = v; })
      Button('Run controlled network tests').enabled(!this.busy).onClick(() => this.deviceCheck('network'))
      TextInput({ placeholder: 'Fresh non-secret storage run token', text: this.runToken }).onChange((v: string) => { this.runToken = v; })
      Button('Prepare storage restart test').enabled(!this.busy).onClick(() => this.deviceCheck('prepare'))
      Button('Verify storage after process restart').enabled(!this.busy).onClick(() => this.deviceCheck('verify'))
      Text(this.deviceResult).id('madcore-device-result')
      Text('Build success alone does not verify device compatibility.').fontSize(14)
    }
    .width('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    }
  }
}
