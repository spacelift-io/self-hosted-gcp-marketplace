import unittest

import spacelift_mp as mp

FULL_FORM = {
    "name": "spacelift",
    "namespace": "spacelift",
    "serviceAccount": "spacelift-backend",
    "license": {"token": "test-license"},
    "domain": "spacelift.example.com",
    "database": {"connectionName": "test-project:us-central1:spacelift"},
    "ingress": {
        "ipv4AddressName": "spacelift-v4",
        "ipv6AddressName": "spacelift-v6",
        "clusterIssuer": "letsencrypt-prod",
    },
}


class ChartValuesTest(unittest.TestCase):
    def test_no_license_installs_placeholder(self):
        form = dict(FULL_FORM, license={"token": ""})
        self.assertEqual(mp.chart_values(form), {"installSpacelift": False})

    def test_full_install(self):
        result = mp.chart_values(FULL_FORM)
        self.assertTrue(result["installSpacelift"])
        values = result["spacelift"]
        self.assertEqual(values["serviceAccount"], {"name": "spacelift-backend"})
        self.assertEqual(values["fullnameOverride"], "spacelift")
        self.assertEqual(values["shared"], {"serverHostname": "spacelift.example.com"})
        self.assertEqual(
            values["cloudSqlProxy"], {"dbConnectionName": "test-project:us-central1:spacelift"}
        )
        self.assertEqual(
            values["ingress"]["annotations"], {mp.STATIC_IP_ANNOTATION: "spacelift-v4"}
        )
        self.assertEqual(
            values["ingressV6"]["annotations"],
            {
                mp.STATIC_IP_ANNOTATION: "spacelift-v6",
                mp.CLUSTER_ISSUER_ANNOTATION: "letsencrypt-prod",
            },
        )

    def test_no_cluster_issuer_drops_cert_manager_annotations(self):
        form = dict(FULL_FORM, ingress=dict(FULL_FORM["ingress"], clusterIssuer=""))
        annotations = mp.chart_values(form)["spacelift"]["ingressV6"]["annotations"]
        self.assertNotIn(mp.CLUSTER_ISSUER_ANNOTATION, annotations)
        self.assertIsNone(annotations[mp.EDIT_IN_PLACE_ANNOTATION])

    def test_chart_objects_follow_the_install_name(self):
        form = dict(FULL_FORM, name="sl-prod")
        self.assertEqual(mp.chart_values(form)["spacelift"]["fullnameOverride"], "sl-prod")

    def test_empty_required_fields_fail(self):
        for field in ["name", "serviceAccount"]:
            with self.subTest(field=field):
                form = dict(FULL_FORM, **{field: ""})
                with self.assertRaises(ValueError):
                    mp.chart_values(form)


class CheckUpgradeTest(unittest.TestCase):
    def test_allowed(self):
        for installed, new in [
            ("", "7.2.0"),
            ("7.2.0", "7.2.0"),
            ("7.2.0", "7.2.1"),
            ("7.2.0", "7.2.0-gcp.1"),
            ("7.2.0-gcp.1", "7.2.0-gcp.2"),
            ("7.2.0-gcp.3", "7.2.1"),
            ("7.2.1", "7.3.0"),
        ]:
            with self.subTest(installed=installed, new=new):
                self.assertIsNone(mp.check_upgrade(installed, new))

    def test_downgrade_fails(self):
        for installed, new in [
            ("7.2.1", "7.2.0"),
            ("7.2.0-gcp.1", "7.2.0"),
            ("7.3.0", "7.2.9-gcp.4"),
        ]:
            with self.subTest(installed=installed, new=new):
                self.assertIsNotNone(mp.check_upgrade(installed, new))

    def test_bad_version_fails(self):
        with self.assertRaises(ValueError):
            mp.check_upgrade("7.2.0", "v7.2.1")


if __name__ == "__main__":
    unittest.main()
