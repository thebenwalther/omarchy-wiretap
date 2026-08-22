.pragma library

var SCOPE_ORDER = ["all", "established", "listening", "internet", "local"]

function emptySnapshot() {
  return {
    version: 1,
    generatedAt: 0,
    elapsedMs: 0,
    partial: false,
    error: "",
    warnings: [],
    totals: {
      processes: 0,
      sockets: 0,
      established: 0,
      listen: 0,
      internet: 0,
      internetEstab: 0,
      udp: 0,
      tcp: 0,
      unowned: 0
    },
    processes: []
  }
}

function isSnapshot(value) {
  return !!(value && typeof value === "object" && !Array.isArray(value)
    && value.version === 1 && value.totals && Array.isArray(value.processes))
}

function parseSnapshot(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    var value = JSON.parse(text)
    return isSnapshot(value) ? value : null
  } catch (error) {
    return null
  }
}

function totalsOf(snapshot) {
  return snapshot && snapshot.totals ? snapshot.totals : emptySnapshot().totals
}

function internetEstab(snapshot) {
  return Number(totalsOf(snapshot).internetEstab) || 0
}

function listenCount(snapshot) {
  return Number(totalsOf(snapshot).listen) || 0
}

function processCount(snapshot) {
  return Number(totalsOf(snapshot).processes) || 0
}

function socketCount(snapshot) {
  return Number(totalsOf(snapshot).sockets) || 0
}

function establishedCount(snapshot) {
  return Number(totalsOf(snapshot).established) || 0
}

function connectionInScope(conn, scope) {
  if (!conn) return false
  var value = String(scope || "all")
  if (value === "all" || value === "") return true
  if (value === "established") return conn.state === "estab"
  if (value === "listening") return conn.state === "listen"
  if (value === "internet") return conn.class === "internet" || conn.internetFacing === true
  if (value === "local") return !(conn.class === "internet" || conn.internetFacing === true)
  return true
}

function connectionSearchText(conn) {
  if (!conn) return ""
  return [
    conn.protocol, conn.state, conn.localAddress, conn.localPort,
    conn.remoteAddress, conn.remotePort, conn.interface, conn.class,
    conn.service, conn.internetFacing ? "internet" : "", conn.id
  ].join(" ").toLowerCase()
}

function processSearchText(proc) {
  if (!proc) return ""
  return [
    proc.displayName, proc.comm, proc.exe, proc.cmdline,
    proc.pid, proc.uid, proc.user, proc.cgroup,
    proc.system ? "system" : "", proc.key
  ].join(" ").toLowerCase()
}

function matchesQuery(haystack, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return true
  return String(haystack || "").indexOf(needle) !== -1
}

function isExpanded(expandedKeys, key) {
  var keys = expandedKeys || []
  var value = String(key || "")
  for (var i = 0; i < keys.length; i++) if (String(keys[i]) === value) return true
  return false
}

function withExpanded(expandedKeys, key, on) {
  var keys = (expandedKeys || []).slice()
  var value = String(key || "")
  var found = -1
  for (var i = 0; i < keys.length; i++) if (String(keys[i]) === value) { found = i; break }
  if (on && found === -1) keys.push(value)
  if (!on && found !== -1) keys.splice(found, 1)
  return keys
}

function toggleExpanded(expandedKeys, key) {
  return withExpanded(expandedKeys, key, !isExpanded(expandedKeys, key))
}

function allProcessKeys(snapshot) {
  var processes = snapshot && snapshot.processes ? snapshot.processes : []
  var keys = []
  for (var i = 0; i < processes.length; i++) keys.push(String(processes[i].key || ""))
  return keys
}

function visibleRows(snapshot, query, scope, expandedKeys, appearedIds, newProcessKeys) {
  var processes = snapshot && snapshot.processes ? snapshot.processes : []
  var rows = []
  var appeared = appearedIds || []
  var newKeys = newProcessKeys || []
  for (var i = 0; i < processes.length; i++) {
    var proc = processes[i]
    var connections = proc.connections || []
    var scoped = []
    var j
    for (j = 0; j < connections.length; j++) {
      if (connectionInScope(connections[j], scope)) scoped.push(connections[j])
    }
    var procHit = matchesQuery(processSearchText(proc), query)
    var shown = []
    for (j = 0; j < scoped.length; j++) {
      var conn = scoped[j]
      if (procHit || matchesQuery(connectionSearchText(conn), query)) shown.push(conn)
    }
    if (shown.length === 0 && !(procHit && scoped.length > 0 && String(query || "").trim() === "")) continue
    if (shown.length === 0 && !procHit) continue
    if (shown.length === 0 && procHit && scoped.length === 0) continue
    if (!procHit && shown.length === 0) continue
    var visibleConnections = shown
    if (visibleConnections.length === 0) continue
    var appearedProc = false
    var k
    for (k = 0; k < newKeys.length; k++) if (String(newKeys[k]) === String(proc.key)) appearedProc = true
    rows.push({
      kind: "process",
      process: proc,
      connection: null,
      appeared: appearedProc,
      count: visibleConnections.length
    })
    if (isExpanded(expandedKeys, proc.key)) {
      for (j = 0; j < visibleConnections.length; j++) {
        var appearedConn = false
        var id = String(visibleConnections[j].id || "")
        for (k = 0; k < appeared.length; k++) if (String(appeared[k]) === id) { appearedConn = true; break }
        rows.push({
          kind: "connection",
          process: proc,
          connection: visibleConnections[j],
          appeared: appearedConn,
          count: 0
        })
      }
    }
  }
  return rows
}

function collectIds(snapshot) {
  var ids = {}
  var processes = snapshot && snapshot.processes ? snapshot.processes : []
  for (var i = 0; i < processes.length; i++) {
    var connections = processes[i].connections || []
    for (var j = 0; j < connections.length; j++) {
      var id = String(connections[j].id || "")
      if (id) ids[id] = connections[j]
    }
  }
  return ids
}

function collectKeys(snapshot) {
  var keys = {}
  var processes = snapshot && snapshot.processes ? snapshot.processes : []
  for (var i = 0; i < processes.length; i++) keys[String(processes[i].key || "")] = true
  return keys
}

function diff(prev, next) {
  var previous = collectIds(prev)
  var current = collectIds(next)
  var prevKeys = collectKeys(prev)
  var appearedIds = []
  var departedIds = []
  var newProcessKeys = []
  var appearedInternetEstab = false
  var id
  for (id in current) {
    if (!previous[id]) {
      appearedIds.push(id)
      var conn = current[id]
      if (conn && conn.state === "estab" && conn.class === "internet") appearedInternetEstab = true
    }
  }
  for (id in previous) if (!current[id]) departedIds.push(id)
  var key
  for (key in collectKeys(next)) if (key && !prevKeys[key]) newProcessKeys.push(key)
  return {
    appearedIds: appearedIds,
    departedIds: departedIds,
    newProcessKeys: newProcessKeys,
    appearedInternetEstab: appearedInternetEstab
  }
}

function formatBytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return ""
  if (n < 1000) return String(Math.round(n))
  if (n < 1000000) {
    var kilo = n / 1000
    return (kilo >= 10 ? String(Math.round(kilo)) : kilo.toFixed(1).replace(/\.0$/, "")) + "K"
  }
  var mega = n / 1000000
  return (mega >= 10 ? String(Math.round(mega)) : mega.toFixed(1).replace(/\.0$/, "")) + "M"
}

function formatPort(port) {
  var n = Number(port)
  if (!isFinite(n) || n <= 0) return "*"
  return String(n)
}

function formatEndpoint(addr, port) {
  var host = String(addr || "*")
  if (host.indexOf(":") >= 0 && host.charAt(0) !== "[") host = "[" + host + "]"
  return host + ":" + formatPort(port)
}

function connectionCopyText(conn) {
  if (!conn) return ""
  return String(conn.protocol || "tcp") + " "
    + formatEndpoint(conn.localAddress, conn.localPort)
    + " → "
    + formatEndpoint(conn.remoteAddress, conn.remotePort)
}

function processCopyText(proc) {
  if (!proc) return ""
  var name = String(proc.displayName || proc.comm || "process")
  var pid = Number(proc.pid) || 0
  return pid > 0 ? name + " pid " + pid : name
}

function classLabel(klass) {
  if (klass === "internet") return "net"
  if (klass === "private") return "lan"
  if (klass === "tailscale") return "ts"
  if (klass === "loopback") return "lo"
  if (klass === "docker") return "dk"
  if (klass === "multicast") return "mc"
  if (klass === "linklocal") return "ll"
  if (klass === "unspecified") return "*"
  return ""
}

function stateLabel(state) {
  var value = String(state || "").toUpperCase()
  return value || "?"
}

function protocolLabel(protocol) {
  return String(protocol || "").toUpperCase()
}

function plural(count, word) {
  var value = Number(count) || 0
  return value + " " + word + (value === 1 ? "" : "s")
}

function tooltip(snapshot) {
  if (!snapshot) return "Wiretap"
  var t = totalsOf(snapshot)
  return (Number(t.established) || 0) + " established · "
    + (Number(t.listen) || 0) + " listening · "
    + (Number(t.processes) || 0) + " processes"
}

function heroMeta(snapshot) {
  var t = totalsOf(snapshot)
  return plural(t.established, "established") + " · "
    + plural(t.listen, "listening") + " · "
    + plural(t.processes, "process")
}

function relativeAge(generatedAt, nowMs) {
  var then = Number(generatedAt) * 1000
  if (!isFinite(then) || then <= 0) return ""
  var delta = Math.max(0, (Number(nowMs) || Date.now()) - then)
  if (delta < 3000) return "LIVE"
  var seconds = Math.round(delta / 1000)
  if (seconds < 60) return seconds + "s ago"
  var minutes = Math.round(seconds / 60)
  return minutes + "m ago"
}

function nextScope(current) {
  var value = String(current || "all")
  var idx = SCOPE_ORDER.indexOf(value)
  if (idx < 0) return SCOPE_ORDER[0]
  return SCOPE_ORDER[(idx + 1) % SCOPE_ORDER.length]
}

function scopeAt(index) {
  var i = Number(index) || 0
  if (i < 1 || i > SCOPE_ORDER.length) return ""
  return SCOPE_ORDER[i - 1]
}

function formatElapsedMs(ms) {
  var n = Number(ms)
  if (!isFinite(n) || n < 0) return ""
  return Math.round(n) + " ms"
}

function bytePair(proc) {
  if (!proc) return ""
  var up = formatBytes(proc.bytesSent)
  var down = formatBytes(proc.bytesReceived)
  if (!up && !down) return ""
  return "↑" + (up || "0") + " ↓" + (down || "0")
}

function snapshotJson(snapshot) {
  try {
    return JSON.stringify(snapshot || emptySnapshot(), null, 2)
  } catch (error) {
    return ""
  }
}
