#!/usr/bin/env python3
"""Helpers for deploy.sh.

values         Reads the install form (a values file made by Google's
               print_config.py) and prints the values for the
               spacelift-self-hosted chart that depend on the form.
check-upgrade  Fails when the new version is lower than the installed one.
               Spacelift's database migrations only go forward, so a
               downgrade is not allowed.
"""

import argparse
import re
import sys

import yaml

STATIC_IP_ANNOTATION = "kubernetes.io/ingress.global-static-ip-name"
CLUSTER_ISSUER_ANNOTATION = "cert-manager.io/cluster-issuer"
EDIT_IN_PLACE_ANNOTATION = "acme.cert-manager.io/http01-edit-in-place"

# 7.2.0, or 7.2.0-gcp.1 for a change to the deployer alone.
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-gcp\.(\d+))?$")


def get(form, path, default=""):
    value = form
    for key in path.split("."):
        if not isinstance(value, dict) or key not in value:
            return default
        value = value[key]
    return default if value is None else value


def chart_values(form):
    """Chart values that depend on the form."""
    if not get(form, "license.token"):
        # No license: install only the placeholder.
        return {"installSpacelift": False}

    service_account = get(form, "serviceAccount")
    if not service_account:
        raise ValueError("the form field 'serviceAccount' is empty")

    ingress_v4 = {STATIC_IP_ANNOTATION: get(form, "ingress.ipv4AddressName")}
    ingress_v6 = {STATIC_IP_ANNOTATION: get(form, "ingress.ipv6AddressName")}
    cluster_issuer = get(form, "ingress.clusterIssuer")
    if cluster_issuer:
        ingress_v6[CLUSTER_ISSUER_ANNOTATION] = cluster_issuer
    else:
        # No cert-manager: drop the annotation the chart values set by default.
        ingress_v6[EDIT_IN_PLACE_ANNOTATION] = None

    return {
        "installSpacelift": True,
        "spacelift": {
            "serviceAccount": {"name": service_account},
            "shared": {"serverHostname": get(form, "domain")},
            "cloudSqlProxy": {"dbConnectionName": get(form, "database.connectionName")},
            "ingress": {"annotations": ingress_v4},
            "ingressV6": {"annotations": ingress_v6},
        }
    }


def parse_version(version):
    match = VERSION_RE.match(version)
    if not match:
        raise ValueError(f"unexpected version {version!r}, want X.Y.Z or X.Y.Z-gcp.N")
    return tuple(int(part or 0) for part in match.groups())


def check_upgrade(installed, new):
    """Returns an error message, or None when the upgrade is allowed."""
    if not installed:
        return None
    if parse_version(new) < parse_version(installed):
        return (
            f"version {installed} is installed, and {new} is lower. "
            "Downgrades are not supported, because database migrations only go forward."
        )
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    values = sub.add_parser("values")
    values.add_argument("--form", required=True, help="the form as a values file")

    upgrade = sub.add_parser("check-upgrade")
    upgrade.add_argument("--installed", default="", help="installed version, empty if none")
    upgrade.add_argument("--new", required=True, help="version being installed")

    args = parser.parse_args(argv)
    try:
        if args.command == "values":
            with open(args.form) as f:
                form = yaml.safe_load(f) or {}
            yaml.safe_dump(chart_values(form), sys.stdout, sort_keys=False)
        elif args.command == "check-upgrade":
            error = check_upgrade(args.installed, args.new)
            if error:
                print(f"ERROR: {error}", file=sys.stderr)
                return 1
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
