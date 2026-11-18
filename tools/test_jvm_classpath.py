import tempfile
from pathlib import Path
import zipfile
from check_jvm_classpath import check

with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    def jar(name, entries):
        p = root / name
        with zipfile.ZipFile(p, 'w') as z:
            for entry in entries: z.writestr(entry, b'test-only-not-bytecode')
        return p
    a = jar('a.jar', ['com/mad/core/net/HttpTransport.class'])
    b = jar('b.jar', ['com/mad/core/net/HttpTransport.class'])
    c = jar('c.jar', ['com/mad/core/time/Clock.class'])
    assert check([a, c]) == 2
    for inputs in ([a, b], [], [jar('unrelated.jar', ['org/example/Other.class'])]):
        try: check(inputs)
        except ValueError: pass
        else: raise AssertionError('Invalid classpath accepted')
    print('Classpath duplicate/empty rejection tests passed')
