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
  if (n < 1000) return Math.round(n) + " B"
  if (n < 1000000) return Math.round(n / 1000) + " KB"
  var mega = n / 1000000
  return (mega >= 10 ? String(Math.round(mega)) : mega.toFixed(1).replace(/\.0$/, "")) + " MB"
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

function placeLabel(klass) {
  if (klass === "internet") return "on the internet"
  if (klass === "private") return "on this network"
  if (klass === "tailscale") return "over Tailscale"
  if (klass === "loopback") return "on this computer"
  if (klass === "docker") return "in Docker"
  if (klass === "multicast") return "to nearby devices"
  if (klass === "linklocal") return "on this link"
  return ""
}

function classLabel(klass) {
  return placeLabel(klass)
}

function stateLabel(state) {
  var value = String(state || "")
  if (value === "estab") return "Talking"
  if (value === "listen") return "Waiting"
  if (value === "syn-sent" || value === "syn-recv") return "Connecting"
  if (value === "unconn") return "Idle"
  if (value === "time-wait" || value === "fin-wait-1" || value === "fin-wait-2"
    || value === "close-wait" || value === "last-ack" || value === "closing" || value === "close")
    return "Finishing"
  return value ? value.charAt(0).toUpperCase() + value.slice(1) : ""
}

function protocolLabel(protocol) {
  var value = String(protocol || "")
  if (value === "udp") return "UDP"
  if (value === "unix") return "local"
  return ""
}

function connectionTone(conn) {
  if (!conn) return "idle"
  var state = String(conn.state || "")
  if (state === "listen") return listenIsPublic(conn) ? "open" : "waiting"
  if (state === "estab")
    return (conn.class === "internet" || conn.internetFacing === true) ? "talking" : "local"
  if (state === "syn-sent" || state === "syn-recv") return "connecting"
  if (state === "time-wait" || state === "fin-wait-1" || state === "fin-wait-2"
    || state === "close-wait" || state === "last-ack" || state === "closing" || state === "close")
    return "finishing"
  return "idle"
}

function processTone(proc) {
  var connections = proc && proc.connections ? proc.connections : []
  var talking = false
  var open = false
  var connecting = false
  for (var i = 0; i < connections.length; i++) {
    var tone = connectionTone(connections[i])
    if (tone === "talking") talking = true
    else if (tone === "open") open = true
    else if (tone === "connecting") connecting = true
  }
  if (talking) return "talking"
  if (open) return "open"
  if (connecting) return "connecting"
  return "local"
}

function snapshotTone(snapshot) {
  if (internetEstab(snapshot) > 0) return "talking"
  var processes = snapshot && snapshot.processes ? snapshot.processes : []
  for (var i = 0; i < processes.length; i++) {
    var connections = processes[i].connections || []
    for (var j = 0; j < connections.length; j++) {
      if (connectionTone(connections[j]) === "open") return "open"
    }
  }
  if (talkingAppCount(snapshot) > 0) return "local"
  if (listenCount(snapshot) > 0) return "waiting"
  return "idle"
}

function listenIsPublic(conn) {
  if (!conn || conn.state !== "listen") return false
  if (conn.internetFacing === true) return true
  var klass = String(conn.class || "")
  return klass !== "loopback" && klass !== ""
}

function destinationText(conn) {
  if (!conn) return ""
  if (conn.state === "listen") return "port " + formatPort(conn.localPort)
  return formatHost(conn.remoteAddress)
}

function formatHost(addr) {
  var host = String(addr || "")
  if (host === "" || host === "*" || host === "0.0.0.0" || host === "::") return ""
  if (host.indexOf(":") >= 0 && host.charAt(0) !== "[") return "[" + host + "]"
  return host
}

function connectionHeadline(conn) {
  if (!conn) return ""
  var service = String(conn.service || "")
  var state = String(conn.state || "")
  if (state === "listen") {
    var port = formatPort(conn.localPort)
    var label = listenIsPublic(conn) ? "Open to the world on port " + port : "Waiting on port " + port
    if (service) label += " (" + service + ")"
    return label
  }
  var dest = formatHost(conn.remoteAddress)
  if (state === "syn-sent" || state === "syn-recv")
    return dest ? "Connecting to " + dest : "Connecting"
  if (state === "time-wait" || state === "fin-wait-1" || state === "fin-wait-2"
    || state === "close-wait" || state === "last-ack" || state === "closing")
    return dest ? "Finishing with " + dest : "Finishing"
  if (service && dest) return service + " → " + dest
  if (dest) return "Talking to " + dest
  return stateLabel(state)
}

function connectionDetail(conn) {
  if (!conn) return ""
  var bits = []
  var proto = protocolLabel(conn.protocol)
  if (proto) bits.push(proto)
  var place = placeLabel(conn.class)
  if (place) bits.push(place)
  var sent = formatBytes(conn.bytesSent)
  var recv = formatBytes(conn.bytesReceived)
  if (sent) bits.push(sent + " sent")
  if (recv) bits.push(recv + " received")
  return bits.join(" · ")
}

function plural(count, word) {
  var value = Number(count) || 0
  return value + " " + word + (value === 1 ? "" : "s")
}

function talkingAppCount(snapshot) {
  var processes = snapshot && snapshot.processes ? snapshot.processes : []
  var n = 0
  for (var i = 0; i < processes.length; i++) {
    var connections = processes[i].connections || []
    for (var j = 0; j < connections.length; j++) {
      if (connections[j].state === "estab") { n++; break }
    }
  }
  return n
}

function tooltip(snapshot) {
  if (!snapshot) return "Who is talking"
  return heroMeta(snapshot) || "Who is talking"
}

function heroMeta(snapshot) {
  var talking = talkingAppCount(snapshot)
  var waiting = listenCount(snapshot)
  var talkingBit = talking === 1 ? "1 app talking" : talking + " apps talking"
  var waitingBit = waiting === 1 ? "1 waiting for a connection" : waiting + " waiting for connections"
  if (talking > 0 && waiting > 0) return talkingBit + " · " + waitingBit
  if (talking > 0) return talkingBit
  if (waiting > 0) return waitingBit
  if (socketCount(snapshot) > 0) return "Nothing is talking right now"
  return "Who is talking"
}

function processTitle(proc) {
  var name = String(proc && proc.displayName || "")
  if (name === "lingering" || name === "Closed connections") return "Closed connections"
  if (name === "" || name === "unknown") return "Unknown app"
  return name
}

function processCountLabel(count) {
  return plural(Number(count) || 0, "connection")
}

function trafficLabel(proc) {
  if (!proc) return ""
  var up = formatBytes(proc.bytesSent)
  var down = formatBytes(proc.bytesReceived)
  var bits = []
  if (up) bits.push(up + " sent")
  if (down) bits.push(down + " received")
  return bits.join(" · ")
}

function missingToolMessage(raw) {
  var text = String(raw || "")
  if (text.indexOf("ss") >= 0 || text === "") return "Can't see connections (ss missing)"
  return "Can't see connections"
}

function healthyStatus() {
  return ""
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
  return trafficLabel(proc)
}

function snapshotJson(snapshot) {
  try {
    return JSON.stringify(snapshot || emptySnapshot(), null, 2)
  } catch (error) {
    return ""
  }
}
