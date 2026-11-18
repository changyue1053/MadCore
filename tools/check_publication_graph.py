"""Check staged POM graph, not full Gradle metadata resolution, SBOM or licensing."""
import hashlib
import json
import re
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def inspect(repository, manifest):
    group, version = manifest['group'], manifest['version']
    modules = manifest['production'] + manifest['optInTestOnly'] + [manifest['umbrella']]
    allowed_external = set(manifest['allowedExternal'])
    def module_of(artifact):
        candidates = [m for m in modules if artifact == m or artifact.startswith(m + '-')]
        if len(candidates) != 1:
            raise ValueError('Unexpected or ambiguous internal artifact: ' + artifact)
        return candidates[0]
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    graph, fingerprints, external = {}, {}, set()
    for path in sorted(Path(repository).rglob('*.pom')):
        tree = ET.parse(path).getroot()
        def text(node, key):
            return node.findtext('m:' + key, namespaces=ns)
        coord = tuple(text(tree, k) for k in ('groupId', 'artifactId', 'version'))
        if coord[0] != group:
            raise ValueError('Unexpected staged publication group')
        if coord[2] != version:
            raise ValueError('Mismatched staged publication version')
        module_of(coord[1])
        expected_dir = Path(repository) / group.replace('.', '/') / coord[1] / version
        if path.parent != expected_dir:
            raise ValueError('Publication is not at its canonical Maven repository path')
        if path.name != coord[1] + '-' + version + '.pom':
            prefix = version.removesuffix('SNAPSHOT')
            pattern = re.escape(coord[1] + '-' + prefix) + r'[0-9]{8}\.[0-9]{6}-[0-9]+\.pom'
            metadata = expected_dir / 'maven-metadata.xml'
            if not version.endswith('-SNAPSHOT') or not re.fullmatch(pattern, path.name) or not metadata.is_file():
                raise ValueError('Unresolvable publication filename/snapshot metadata')
            snapshot = path.name[len(coord[1]) + 1:-4]
            records = ET.parse(metadata).getroot().findall('./versioning/snapshotVersions/snapshotVersion')
            if not any(n.findtext('extension') == 'pom' and n.findtext('value') == snapshot for n in records):
                raise ValueError('Snapshot POM not indexed in Maven metadata')
        dependencies = []
        for dep in tree.findall('m:dependencies/m:dependency', ns):
            if text(dep, 'scope') not in (None, 'compile', 'runtime') or text(dep, 'optional') not in (None, 'false'):
                raise ValueError('Unsupported non-production or optional dependency edge')
            if text(dep, 'classifier') or text(dep, 'type') not in (None, 'jar', 'aar', 'pom', 'klib'):
                raise ValueError('Unsupported classified dependency edge')
            target = tuple(text(dep, k) for k in ('groupId', 'artifactId', 'version'))
            if not all(target):
                raise ValueError('Unresolved dependency coordinate')
            if target[0] == group:
                module_of(target[1])
                if target[2] != version:
                    raise ValueError('Internal dependency version drift')
                dependencies.append(target)
            else:
                if ':'.join(target[:2]) not in allowed_external:
                    raise ValueError('Unreviewed external runtime dependency')
                external.add(target)
        if coord in graph and graph[coord] != dependencies:
            raise ValueError('Conflicting duplicate publication metadata')
        graph[coord] = dependencies
        fingerprints[str(path.relative_to(repository))] = hashlib.sha256(path.read_bytes()).hexdigest()
    if not graph:
        raise ValueError('No published POMs; empty validation is not a pass')
    found = {module_of(c[1]) for c in graph}
    if found != set(modules):
        raise ValueError('Missing declared module publications')
    for targets in graph.values():
        if any(target not in graph for target in targets):
            raise ValueError('Internal dependency missing from standalone staging repository')
    roots = [c for c in graph if module_of(c[1]) == manifest['umbrella']]
    expected = set(manifest['production']) | {manifest['umbrella']}
    closures = {}
    for root in roots:
        reached = set()
        def visit(coord):
            if coord in reached: return
            reached.add(coord)
            for dep in graph[coord]: visit(dep)
        visit(root)
        reached_modules = {module_of(c[1]) for c in reached}
        if reached_modules != expected:
            raise ValueError('Umbrella variant closure missing production or includes test-only modules: ' + root[1])
        closures[':'.join(root)] = sorted(reached_modules)
    return {'scope': 'staged Maven POM graph only; not SBOM/license or Gradle-metadata certification',
            'group': group, 'version': version, 'productionClosure': sorted(expected), 'variantClosures': closures,
            'optInTestOnly': manifest['optInTestOnly'], 'publicationCount': len(graph),
            'externalDependencies': [':'.join(c) for c in sorted(external)],
            'pomSha256': fingerprints}

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    report = inspect(Path(sys.argv[1]), json.loads((root / 'SDK-MODULES.json').read_text()))
    output = root / 'build/validation/publication-graph.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"Publication POM graph passed: {report['publicationCount']} coordinates; testkit excluded from production closure")
