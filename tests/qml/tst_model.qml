import QtQuick
import QtTest
import "../../Model.js" as Model

TestCase {
  name: "WiretapModel"

  function sampleSnapshot() {
    return {
      version: 1,
      generatedAt: 1710000000,
      elapsedMs: 42,
      partial: false,
      error: "",
      warnings: [],
      totals: {
        processes: 2,
        sockets: 3,
        established: 1,
        listen: 1,
        internet: 2,
        internetEstab: 1,
        udp: 0,
        tcp: 3,
        unowned: 0
      },
      processes: [
        {
          key: "pid:10:1",
          displayName: "chromium",
          comm: "chromium",
          exe: "/usr/bin/chromium",
          cmdline: "/usr/bin/chromium",
          pid: 10,
          uid: 1000,
          user: "bmw",
          cgroup: "chromium",
          system: false,
          bytesSent: 22131,
          bytesReceived: 7939,
          connections: [
            {
              id: "tcp|10.10.5.90|55514|140.82.113.25|443|1",
              protocol: "tcp",
              state: "estab",
              localAddress: "10.10.5.90",
              localPort: 55514,
              remoteAddress: "140.82.113.25",
              remotePort: 443,
              class: "internet",
              service: "https",
              internetFacing: true
            }
          ]
        },
        {
          key: "pid:20:1",
          displayName: "dropbox",
          comm: "dropbox",
          exe: "/opt/dropbox/dropbox",
          pid: 20,
          uid: 1000,
          user: "bmw",
          cgroup: "dropbox",
          system: false,
          connections: [
            {
              id: "tcp|0.0.0.0|17500|0.0.0.0|0|2",
              protocol: "tcp",
              state: "listen",
              localAddress: "0.0.0.0",
              localPort: 17500,
              remoteAddress: "0.0.0.0",
              remotePort: 0,
              class: "unspecified",
              service: "dbxsvc",
              internetFacing: true
            },
            {
              id: "tcp|10.10.5.90|40122|10.10.1.9|22|3",
              protocol: "tcp",
              state: "estab",
              localAddress: "10.10.5.90",
              localPort: 40122,
              remoteAddress: "10.10.1.9",
              remotePort: 22,
              class: "private",
              service: "ssh",
              internetFacing: false
            }
          ]
        }
      ]
    }
  }

  function test_emptySnapshotIsSafe() {
    var snap = Model.emptySnapshot()
    compare(snap.version, 1)
    compare(snap.processes.length, 0)
    compare(snap.totals.sockets, 0)
  }

  function test_parseSnapshot() {
    compare(Model.parseSnapshot(""), null)
    compare(Model.parseSnapshot("not json"), null)
    compare(Model.parseSnapshot("[]"), null)
    compare(Model.parseSnapshot("{}"), null)
    var parsed = Model.parseSnapshot('{"version":1,"totals":{},"processes":[]}')
    compare(parsed.version, 1)
  }

  function test_scopeAndFilter() {
    var snap = sampleSnapshot()
    compare(Model.visibleRows(snap, "", "all", [], [], []).length, 2)
    compare(Model.visibleRows(snap, "", "listening", ["pid:20:1"], [], []).length, 2)
    compare(Model.visibleRows(snap, "listen", "all", ["pid:20:1"], [], []).length, 2)
    compare(Model.visibleRows(snap, "chromium", "all", ["pid:10:1"], [], []).length, 2)
    compare(Model.visibleRows(snap, "443", "all", ["pid:10:1"], [], []).length, 2)
    compare(Model.visibleRows(snap, "nope", "all", [], [], []).length, 0)
    compare(Model.visibleRows(snap, "", "internet", [], [], []).length, 2)
    compare(Model.visibleRows(snap, "", "local", ["pid:20:1"], [], []).length, 2)
  }

  function test_diffMarksNewInternetEstab() {
    var prev = Model.emptySnapshot()
    var next = sampleSnapshot()
    var delta = Model.diff(prev, next)
    compare(delta.appearedIds.length, 3)
    compare(delta.appearedInternetEstab, true)
    compare(delta.newProcessKeys.length, 2)
    var none = Model.diff(next, next)
    compare(none.appearedIds.length, 0)
    compare(none.appearedInternetEstab, false)
  }

  function test_formatters() {
    compare(Model.formatBytes(7939), "7.9K")
    compare(Model.formatBytes(22131), "22K")
    compare(Model.formatEndpoint("10.10.5.90", 443), "10.10.5.90:443")
    compare(Model.formatEndpoint("2001:db8::1", 443), "[2001:db8::1]:443")
    compare(Model.classLabel("tailscale"), "ts")
    compare(Model.nextScope("all"), "established")
    compare(Model.nextScope("local"), "all")
    compare(Model.scopeAt(3), "listening")
    compare(Model.connectionCopyText({
      protocol: "tcp",
      localAddress: "10.10.5.90",
      localPort: 443,
      remoteAddress: "1.1.1.1",
      remotePort: 443
    }), "tcp 10.10.5.90:443 → 1.1.1.1:443")
  }

  function test_expandHelpers() {
    var keys = Model.toggleExpanded([], "a")
    compare(Model.isExpanded(keys, "a"), true)
    keys = Model.toggleExpanded(keys, "a")
    compare(Model.isExpanded(keys, "a"), false)
  }
}
