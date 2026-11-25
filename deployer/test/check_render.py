#!/usr/bin/env python3
"""Checks the chart rendered for a full install (make template).

Usage: check_render.py --form <form.yaml> --rendered <helm template output>

The form is the install form the chart was rendered with. Each check prints
what it found; the script exits 1 if any check fails.
"""

import argparse
import sys
import urllib.parse

import yaml

STATIC_IP_ANNOTATION = "kubernetes.io/ingress.global-static-ip-name"
CLUSTER_ISSUER_ANNOTATION = "cert-manager.io/cluster-issuer"
EDIT_IN_PLACE_ANNOTATION = "acme.cert-manager.io/http01-edit-in-place"


def get(data, path):
    for key in path.split("."):
        data = (data or {}).get(key)
    return data


class Render:
    def __init__(self, path):
        with open(path) as f:
            self.objects = [o for o in yaml.safe_load_all(f) if o]

    def of_kind(self, kind):
        return [o for o in self.objects if o["kind"] == kind]

    def get(self, kind, name):
        for o in self.of_kind(kind):
            if o["metadata"]["name"] == name:
                return o
        return None


def check(form, render):
    """Yields (ok, message) for each check."""
    name, namespace = form["name"], form["namespace"]
    shared = render.get("Secret", "spacelift-shared")["stringData"]

    # The MQTT address in spacelift-shared points to the chart's MQTT Service.
    mqtt = render.get("Service", f"{name}-mqtt")
    if mqtt is None:
        yield False, f"no Service {name}-mqtt"
    else:
        port = mqtt["spec"]["ports"][0]["port"]
        want = f"tls://{name}-mqtt.{namespace}.svc.cluster.local:{port}"
        got = shared["MQTT_BROKER_ENDPOINT"]
        yield got == want, f"MQTT_BROKER_ENDPOINT is {got}, the Service is at {want}"

    # The Application selects every Deployment, Service and Ingress.
    app = render.of_kind("Application")[0]
    policy = app["metadata"]["annotations"].get("helm.sh/resource-policy")
    yield policy == "keep", f"the Application has helm.sh/resource-policy {policy}, Helm never deletes it"
    [expression] = app["spec"]["selector"]["matchExpressions"]
    selected = set(expression["values"])
    for kind in ["Deployment", "Service", "Ingress"]:
        for o in render.of_kind(kind):
            instance = get(o, "metadata.labels").get("app.kubernetes.io/instance")
            yield instance in selected, f"the Application selects {kind} {o['metadata']['name']} (instance {instance})"

    # Every Ingress sends traffic to a Service from the render.
    services = {o["metadata"]["name"] for o in render.of_kind("Service")}
    for o in render.of_kind("Ingress"):
        for rule in o["spec"]["rules"]:
            for p in rule["http"]["paths"]:
                backend = p["backend"]["service"]["name"]
                yield backend in services, f"Ingress {o['metadata']['name']} sends traffic to Service {backend}"

    # The pods run as the service account from the form, with the pull secret.
    yield not render.of_kind("ServiceAccount"), "the chart creates no ServiceAccount"
    pull_secret = render.get("Secret", "spacelift-registry")
    yield pull_secret is not None and pull_secret["type"] == "kubernetes.io/dockerconfigjson", "the pull secret spacelift-registry exists"
    service_account = get(form, "spacelift.serviceAccount.name")
    for o in render.of_kind("Deployment"):
        pod = o["spec"]["template"]["spec"]
        yield pod.get("serviceAccountName") == service_account, f"Deployment {o['metadata']['name']} runs as {pod.get('serviceAccountName')}"
        pull_secrets = [s["name"] for s in pod.get("imagePullSecrets", [])]
        yield "spacelift-registry" in pull_secrets, f"Deployment {o['metadata']['name']} pulls with {pull_secrets}"

    # The form values reach spacelift-shared.
    yield shared["LICENSE_TOKEN"] == form["license"]["token"], "LICENSE_TOKEN is the license from the form"
    # Cloud SQL's IAM user is the service account email without ".gserviceaccount.com".
    user = form["database"]["user"].removesuffix(".gserviceaccount.com")
    user = urllib.parse.quote(user, safe="")
    want = f"postgres://{user}@127.0.0.1/{form['database']['name']}"
    yield shared["DATABASE_URL"] == want, f"DATABASE_URL is {shared['DATABASE_URL']}"
    yield "gserviceaccount.com" not in shared["DATABASE_URL"], "DATABASE_URL has no .gserviceaccount.com in the user"
    domain = get(form, "spacelift.shared.serverHostname")
    yield shared["SERVER_DOMAIN"] == domain, f"SERVER_DOMAIN is {shared['SERVER_DOMAIN']}"
    connection = get(form, "spacelift.cloudSqlProxy.dbConnectionName")
    for o in render.of_kind("Deployment"):
        pod = o["spec"]["template"]["spec"]
        for c in pod.get("initContainers", []) + pod["containers"]:
            if c["name"] == "cloud-sql-proxy":
                yield connection in c.get("args", []), f"Deployment {o['metadata']['name']} connects to Cloud SQL {connection}"

    # One Ingress per static IP; the IPv6 one gets the ClusterIssuer.
    ingresses = {get(o, "metadata.annotations").get(STATIC_IP_ANNOTATION): o for o in render.of_kind("Ingress")}
    want = {form["ingress"]["ipv4AddressName"], form["ingress"]["ipv6AddressName"]}
    yield set(ingresses) == want, f"the Ingresses use the static IPs {sorted(ingresses)}"
    v6 = ingresses.get(form["ingress"]["ipv6AddressName"])
    issuer = get(v6, "metadata.annotations").get(CLUSTER_ISSUER_ANNOTATION) if v6 else None
    yield issuer == form["ingress"]["clusterIssuer"], f"the IPv6 Ingress uses the ClusterIssuer {issuer}"
    edit_in_place = get(v6, "metadata.annotations").get(EDIT_IN_PLACE_ANNOTATION) if v6 else None
    yield edit_in_place == "true", "cert-manager solves the HTTP-01 challenge on the IPv6 Ingress itself"
    for o in render.of_kind("Ingress"):
        hosts = [rule["host"] for rule in o["spec"]["rules"]]
        yield hosts == [domain], f"Ingress {o['metadata']['name']} serves {hosts}"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--form", required=True)
    parser.add_argument("--rendered", required=True)
    args = parser.parse_args()

    with open(args.form) as f:
        form = yaml.safe_load(f)
    failed = 0
    for ok, message in check(form, Render(args.rendered)):
        print(f"  {'ok  ' if ok else 'FAIL'} {message}")
        failed += not ok
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
