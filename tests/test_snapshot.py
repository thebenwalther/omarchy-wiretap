#!/usr/bin/env python3
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
BIN = ROOT / "bin" / "wiretap"


def load_wiretap():
    loader = importlib.machinery.SourceFileLoader("wiretap_cli", str(BIN))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


wt = load_wiretap()


def fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


class ParseEndpointTests(unittest.TestCase):
    def test_ipv4(self):
        addr, port, iface, family = wt.parse_endpoint("10.10.5.90:443")
        self.assertEqual((addr, port, iface, family), ("10.10.5.90", 443, "", "inet"))

    def test_ipv4_iface(self):
        addr, port, iface, family = wt.parse_endpoint("127.0.0.53%lo:53")
        self.assertEqual((addr, port, iface, family), ("127.0.0.53", 53, "lo", "inet"))

    def test_ipv6_bracket(self):
        addr, port, iface, family = wt.parse_endpoint("[2001:db8::1]:443")
        self.assertEqual((addr, port, iface, family), ("2001:db8::1", 443, "", "inet6"))

    def test_ipv6_unspecified_listen(self):
        addr, port, iface, family = wt.parse_endpoint("[::]:22")
        self.assertEqual((addr, port, family), ("::", 22, "inet6"))

    def test_unbracketed_unspecified(self):
        addr, port, iface, family = wt.parse_endpoint(":::80")
        self.assertEqual((addr, port, family), ("::", 80, "inet6"))

    def test_star(self):
        addr, port, iface, family = wt.parse_endpoint("*")
        self.assertEqual((addr, port), ("*", "*"))


class ClassifyTests(unittest.TestCase):
    def test_classes(self):
        self.assertEqual(wt.classify_address("127.0.0.1"), "loopback")
        self.assertEqual(wt.classify_address("::1"), "loopback")
        self.assertEqual(wt.classify_address("10.10.5.90"), "private")
        self.assertEqual(wt.classify_address("100.118.171.4"), "tailscale")
        self.assertEqual(wt.classify_address("172.17.0.1"), "docker")
        self.assertEqual(wt.classify_address("224.0.0.251"), "multicast")
        self.assertEqual(wt.classify_address("0.0.0.0"), "unspecified")
        self.assertEqual(wt.classify_address("140.82.113.25"), "internet")
        self.assertEqual(wt.classify_address("1.1.1.1"), "internet")


class ParseSsTests(unittest.TestCase):
    def test_tunep_counts_and_fields(self):
        sockets = wt.parse_ss_output(fixture("ss-tunep.txt"))
        self.assertEqual(len(sockets), 15)
        listen = [s for s in sockets if s["state"] == "listen"]
        self.assertGreaterEqual(len(listen), 4)
        ssh = next(s for s in sockets if s["localPort"] == 22 and s["family"] == "inet")
        self.assertEqual(ssh["pid"], None)
        self.assertTrue(ssh["system"])
        self.assertEqual(wt.cgroup_unit(ssh["cgroup"]), "sshd")
        chrome = next(s for s in sockets if s["inode"] == 864218)
        self.assertEqual(chrome["comm"], "chromium")
        self.assertEqual(chrome["pid"], 37143)
        self.assertEqual(chrome["class"], "internet")
        self.assertTrue(chrome["internetFacing"])
        lo = next(s for s in sockets if s["interface"] == "lo")
        self.assertEqual(lo["localAddress"], "127.0.0.53")
        v6 = next(s for s in sockets if s["localPort"] == 22 and s["family"] == "inet6")
        self.assertEqual(v6["localAddress"], "::")
        unb = next(s for s in sockets if s["localPort"] == 80)
        self.assertEqual(unb["localAddress"], "::")
        cups = next(s for s in sockets if s["localPort"] == 631)
        self.assertEqual(cups["localAddress"], "::1")
        self.assertFalse(cups["internetFacing"])
        mdns = next(s for s in sockets if s["remoteAddress"] == "0.0.0.0" and s["localPort"] == 5353)
        self.assertEqual(mdns["class"], "unspecified")

    def test_tcp_info_join(self):
        base = wt.parse_ss_output(fixture("ss-tunep.txt"))
        info = wt.parse_ss_output(fixture("ss-tnep-i.txt"), default_netid="tcp")
        joined = wt.join_info(base, info)
        chrome = next(s for s in joined if s["inode"] == 864218)
        self.assertEqual(chrome["bytesSent"], 22131)
        self.assertEqual(chrome["bytesReceived"], 7939)
        tail = next(s for s in joined if s["inode"] == 34840)
        self.assertEqual(tail["bytesSent"], 78894)

    def test_cgroup_only(self):
        sockets = wt.parse_ss_output(fixture("ss-cgroup-only.txt"))
        self.assertEqual(len(sockets), 3)
        self.assertTrue(all(s["pid"] is None for s in sockets))
        self.assertTrue(all(s["system"] for s in sockets))

    def test_empty(self):
        self.assertEqual(wt.parse_ss_output(fixture("ss-empty.txt")), [])
        self.assertEqual(wt.parse_ss_output(""), [])

    def test_ipv6_fixture(self):
        sockets = wt.parse_ss_output(fixture("ss-ipv6-listen.txt"))
        curl = next(s for s in sockets if s["comm"] == "curl")
        self.assertEqual(curl["remoteAddress"], "2001:db8::1")
        self.assertEqual(curl["family"], "inet6")

    def test_weird_comm_does_not_execute(self):
        line = (
            'tcp ESTAB 0 0 10.0.0.1:1 8.8.8.8:53 '
            'users:(("`rm -rf /`",pid=1,fd=3)) uid:1000 ino:1 sk:1 '
            "cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/app-x.scope <->\n"
        )
        sockets = wt.parse_ss_output(line)
        self.assertEqual(sockets[0]["comm"], "`rm -rf /`")


class SnapshotFilterTests(unittest.TestCase):
    def snapshot(self, **kwargs):
        defaults = {
            "tunep_text": fixture("ss-tunep.txt"),
            "info_text": fixture("ss-tnep-i.txt"),
            "enrich": False,
            "include_system": True,
            "include_unconnected_udp": True,
        }
        defaults.update(kwargs)
        return wt.snapshot_from_sources(**defaults)

    def test_default_hides_system_and_unconn(self):
        snap = self.snapshot(include_system=False, include_unconnected_udp=False)
        names = {p["displayName"] for p in snap["processes"]}
        self.assertIn("chromium", names)
        self.assertIn("dropbox", names)
        self.assertNotIn("sshd", names)
        self.assertTrue(all(c["state"] != "unconn" or c["protocol"] != "udp" for p in snap["processes"] for c in p["connections"]))

    def test_include_system_groups_cgroup(self):
        snap = self.snapshot(include_system=True, include_unconnected_udp=True)
        names = {p["displayName"] for p in snap["processes"]}
        self.assertIn("sshd", names)
        self.assertIn("systemd-resolved", names)
        resolved = next(p for p in snap["processes"] if p["displayName"] == "systemd-resolved")
        self.assertGreaterEqual(len(resolved["connections"]), 2)
        self.assertTrue(resolved["system"])

    def test_service_and_json_roundtrip(self):
        snap = self.snapshot()
        chrome = next(p for p in snap["processes"] if p["displayName"] == "chromium")
        https = next(c for c in chrome["connections"] if c["remotePort"] == 443)
        self.assertEqual(https["service"], "https")
        payload = json.dumps(snap)
        json.loads(payload)
        self.assertEqual(snap["totals"]["sockets"], sum(len(p["connections"]) for p in snap["processes"]))

    def test_unix_hidden_by_default(self):
        snap = self.snapshot(
            unix_text=fixture("ss-unix.txt"),
            include_unix=False,
            include_system=True,
            include_unconnected_udp=True,
        )
        protos = {c["protocol"] for p in snap["processes"] for c in p["connections"]}
        self.assertNotIn("unix", protos)

    def test_unix_included(self):
        snap = self.snapshot(
            unix_text=fixture("ss-unix.txt"),
            include_unix=True,
            include_system=True,
            include_unconnected_udp=True,
        )
        protos = {c["protocol"] for p in snap["processes"] for c in p["connections"]}
        self.assertIn("unix", protos)


class MissingSsTests(unittest.TestCase):
    def test_missing_ss_returns_json_error(self):
        snap = wt.snapshot_from_sources(ss_bin="/definitely/not/ss-binary", enrich=False)
        self.assertEqual(snap["error"], "iproute2 ss is not on PATH")
        self.assertEqual(snap["processes"], [])
        self.assertTrue(snap["partial"])


class VersionTests(unittest.TestCase):
    def test_version_constant(self):
        self.assertEqual(wt.VERSION, "1.0.0")

    def test_main_version(self):
        self.assertEqual(wt.main(["--version"]), 0)


class EnrichTests(unittest.TestCase):
    def test_proc_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = Path(tmp) / "42"
            proc.mkdir()
            (proc / "comm").write_text("myapp\n")
            (proc / "cmdline").write_bytes(b"/usr/bin/myapp\x00--flag\x00")
            (proc / "status").write_text("Name:\tmyapp\nUid:\t1000\t1000\t1000\t1000\n")
            # pid (comm) then 20 remainder fields before starttime at index 19
            stat_rest = " ".join(["S", "1"] + ["0"] * 17 + ["9999"] + ["0"] * 5)
            (proc / "stat").write_text(f"42 (myapp) {stat_rest}\n")
            os.symlink("/usr/bin/myapp", proc / "exe")
            extra = wt.enrich_pid(42, tmp)
            self.assertEqual(extra["comm"], "myapp")
            self.assertEqual(extra["exe"], "/usr/bin/myapp")
            self.assertEqual(extra["uid"], 1000)
            self.assertEqual(extra["startTime"], 9999)


if __name__ == "__main__":
    unittest.main()
