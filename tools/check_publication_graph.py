"""Check staged POM graph, not full Gradle metadata resolution, SBOM or licensing."""
import hashlib
import json
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
        dependencies = []
        for dep in tree.findall('m:dependencies/m:dependency', ns):
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
    reached = set()
    def visit(coord):
        if coord in reached: return
        reached.add(coord)
        for dep in graph[coord]: visit(dep)
    for root in roots: visit(root)
    reached_modules = {module_of(c[1]) for c in reached}
    expected = set(manifest['production']) | {manifest['umbrella']}
    if reached_modules != expected:
        raise ValueError('Production umbrella closure missing modules or includes test-only modules')
    return {'scope': 'staged Maven POM graph only; not SBOM/license or Gradle-metadata certification',
            'group': group, 'version': version, 'productionClosure': sorted(reached_modules),
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
