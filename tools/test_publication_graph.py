import json
from pathlib import Path
import tempfile
from check_publication_graph import inspect

manifest = {'group': 'test.core', 'version': '1', 'umbrella': 'sdk', 'production': ['base'],
            'optInTestOnly': ['testkit'], 'allowedExternal': ['org.jetbrains.kotlin:kotlin-stdlib']}
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    def pom(name, deps, extra=''):
        path = root / 'test/core' / name / '1' / (name + '-1.pom')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('<project xmlns="http://maven.apache.org/POM/4.0.0">'
            + '<groupId>test.core</groupId><artifactId>' + name + '</artifactId><version>1</version><dependencies>'
            + ''.join('<dependency><groupId>' + g + '</groupId><artifactId>' + a + '</artifactId><version>' + v
                + '</version>' + extra + '</dependency>' for g, a, v in deps) + '</dependencies></project>')
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
    pom('sdk', [('test.core', 'base', '1')], '<scope>test</scope>')
    rejected()
    pom('sdk', [('test.core', 'base', '1')], '<optional>true</optional>')
    rejected()
    pom('sdk', [('test.core', 'base', '1')])
    pom('sdk-jvm', [])
    rejected()  # complete metadata umbrella cannot hide an incomplete JVM variant
    pom('sdk-jvm', [('test.core', 'base', '1')])
    assert len(inspect(root, manifest)['variantClosures']) == 2
    (root / 'test/core/base/1/base-1.pom').rename(root / 'misplaced.pom')
    rejected()
    print('Publication graph negative tests passed')

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    snapshot_manifest = {'group': 'test.core', 'version': '1-SNAPSHOT', 'umbrella': 'sdk',
                         'production': [], 'optInTestOnly': [], 'allowedExternal': []}
    directory = root / 'test/core/sdk/1-SNAPSHOT'
    directory.mkdir(parents=True)
    (directory / 'sdk-1-20260101.000000-1.pom').write_text('<project xmlns="http://maven.apache.org/POM/4.0.0">'
        '<groupId>test.core</groupId><artifactId>sdk</artifactId><version>1-SNAPSHOT</version></project>')
    metadata = '<metadata><versioning><snapshotVersions><snapshotVersion><extension>pom</extension>{classifier}' \
        '<value>1-20260101.000000-1</value></snapshotVersion></snapshotVersions></versioning></metadata>'
    path = directory / 'maven-metadata.xml'
    path.write_text(metadata.format(classifier='<classifier>sources</classifier>'))
    try: inspect(root, snapshot_manifest)
    except ValueError: pass
    else: raise AssertionError('Classified metadata accepted for unclassified POM')
    path.write_text(metadata.format(classifier=''))
    assert inspect(root, snapshot_manifest)['publicationCount'] == 1
    print('Snapshot classifier mismatch rejection passed')
