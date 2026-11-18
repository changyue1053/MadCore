import { runNativeSmoke } from './NativeSmoke';

@Entry
@Component
struct Index {
  @State status: string = 'Not run';
  @State abi: string = 'Not checked';
  @State jsonChecks: string = 'Not checked';

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
    Column({ space: 16 }) {
      Text('MadCore HAR consumer').fontSize(24).fontWeight(FontWeight.Bold)
      Text(this.status).id('madcore-status')
      Text(this.abi).id('madcore-abi')
      Text(this.jsonChecks).id('madcore-json')
      Button('Run checks again').onClick(() => this.checkCore())
      Text('Build success alone does not verify device compatibility.').fontSize(14)
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }
}
