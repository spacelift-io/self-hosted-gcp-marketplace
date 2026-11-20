#!/usr/bin/env python3
"""Temporary: lets the spacelift-self-hosted chart work as a dependency.

Helm passes a `global` key to every subchart. The values schema of
spacelift-self-hosted 7.2.0 does not allow keys it doesn't know, so Helm
rejects the values with "additional properties 'global' not allowed". This adds
`global` to the schema inside the downloaded chart archive.

Remove this script, and the calls to it in the Makefile and the Dockerfile,
once a chart release allows `global` in its values schema.

Usage: allow-global-in-chart-schema.py <chart-dir>/charts/spacelift-self-hosted-*.tgz
"""

import io
import json
import sys
import tarfile


def patch(path):
    with tarfile.open(path) as src:
        members = [(m, src.extractfile(m).read() if m.isfile() else None) for m in src.getmembers()]

    changed = False
    for i, (member, data) in enumerate(members):
        # Only the chart's own schema: "<chart>/values.schema.json".
        if not (member.isfile() and member.name.count("/") == 1 and member.name.endswith("/values.schema.json")):
            continue
        schema = json.loads(data)
        properties = schema.setdefault("properties", {})
        if "global" in properties:
            continue
        properties["global"] = {"type": "object"}
        data = (json.dumps(schema, indent=2) + "\n").encode()
        member.size = len(data)
        members[i] = (member, data)
        changed = True

    if not changed:
        print(f"{path}: the schema already allows global")
        return

    with tarfile.open(path, "w:gz") as dst:
        for member, data in members:
            dst.addfile(member, io.BytesIO(data) if data is not None else None)
    print(f"{path}: allowed global in the values schema")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for archive in sys.argv[1:]:
        patch(archive)
