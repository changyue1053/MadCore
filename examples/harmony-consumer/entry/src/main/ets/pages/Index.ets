import { MadCore } from 'madcore';

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
      const version: number = MadCore.abiVersion();
      const validObject: boolean = MadCore.isJsonObject('{"hello":"MadCore"}');
      const invalidObject: boolean = MadCore.isJsonObject('{');
      const arrayObject: boolean = MadCore.isJsonObject('[]');
      this.abi = `ABI version: ${version}`;
      this.jsonChecks = `Object: ${validObject}; malformed: ${invalidObject}; array: ${arrayObject}`;
      this.status = version === 1 && validObject && !invalidObject && !arrayObject
        ? 'Runtime checks passed on this device'
        : 'Runtime checks failed';
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
