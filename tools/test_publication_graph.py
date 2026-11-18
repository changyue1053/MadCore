import json
from pathlib import Path
import tempfile
from check_publication_graph import inspect

manifest = {'group': 'test.core', 'version': '1', 'umbrella': 'sdk', 'production': ['base'],
            'optInTestOnly': ['testkit'], 'allowedExternal': ['org.jetbrains.kotlin:kotlin-stdlib']}
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    def pom(name, deps):
        (root / (name + '.pom')).write_text('<project xmlns="http://maven.apache.org/POM/4.0.0">'
            + '<groupId>test.core</groupId><artifactId>' + name + '</artifactId><version>1</version><dependencies>'
            + ''.join('<dependency><groupId>' + g + '</groupId><artifactId>' + a + '</artifactId><version>' + v
                + '</version></dependency>' for g, a, v in deps) + '</dependencies></project>')
    def rejected():
        try: inspect(root, manifest)
        except ValueError: return
        raise AssertionError('Unsafe publication graph accepted')
    rejected()
    pom('base', [])
    pom('testkit', [('test.core', 'base', '1')])
    pom('sdk', [('test.core', 'base', '1')])
    assert inspect(root, manifest)['productionClosure'] == ['base', 'sdk']
    for dependencies in [[('test.core', 'testkit', '1')], [('test.core', 'base', '2')],
                         [('test.core', 'base-jvm', '1')], [('unknown', 'runtime', '1')], []]:
        pom('sdk', dependencies)
        rejected()
    print('Publication graph negative tests passed')
