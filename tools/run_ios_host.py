"""Bounded host launch with retained output and explicit, optimization-safe gates."""
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PASS = 'MADCORE_EXTERNAL_IOS_HOST_PASS'
FAIL = 'MADCORE_EXTERNAL_IOS_HOST_FAIL'


def launch(command, output_path, timeout=120, pass_marker=PASS, fail_marker=FAIL):
    print(f'Host launch started {datetime.now(timezone.utc).isoformat()}', flush=True)
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=timeout)
        output = result.stdout
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
        if isinstance(output, bytes):
            output = output.decode('utf-8', errors='replace')
        Path(output_path).write_text(output)
        print(output, flush=True)
        raise SystemExit(f'Host launch timed out after {timeout}s; partial output retained') from error
    Path(output_path).write_text(output)
    print(output, flush=True)
    if result.returncode != 0:
        raise SystemExit(f'Independent host process failed: exit {result.returncode}')
    if output.splitlines().count(pass_marker) != 1:
        raise SystemExit('Missing or duplicate host success marker')
    if fail_marker in output:
        raise SystemExit('Independent host reported failure')
    print('Independent artifact-only iOS host executed successfully', flush=True)


if __name__ == '__main__':
    bundle = sys.argv[3] if len(sys.argv) > 3 else 'com.mad.consumer.smoke'
    marker = sys.argv[4] if len(sys.argv) > 4 else PASS
    launch(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process',
            sys.argv[1], bundle], sys.argv[2], pass_marker=marker)
