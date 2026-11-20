"""Bounded, app-filtered diagnostics from an ephemeral CI simulator only."""
import subprocess
import sys


def collect(udid):
    commands = [
        ['xcrun', 'simctl', 'list', 'devices', 'booted'],
        ['ps', '-A', '-o', 'pid,ppid,stat,etime,comm'],
        ['xcrun', 'simctl', 'spawn', udid, 'log', 'show', '--last', '3m',
         '--style', 'compact', '--predicate',
         'process == "MadCoreHost" OR process == "MadCoreControl"'],
    ]
    for index, command in enumerate(commands):
        print(f'IOS_LAUNCH_DIAGNOSTIC_{index}', flush=True)
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=15)
            output = result.stdout
            if index == 1:
                output = '\n'.join(line for line in output.splitlines()
                                   if any(name in line for name in ('MadCoreHost', 'MadCoreControl', 'simctl', 'Simulator', 'SpringBoard')))
            print(output[-16000:], flush=True)
            print(f'diagnostic exit={result.returncode}', flush=True)
        except subprocess.TimeoutExpired:
            print('diagnostic timed out after 15s; not test evidence', flush=True)


if __name__ == '__main__':
    collect(sys.argv[1])
