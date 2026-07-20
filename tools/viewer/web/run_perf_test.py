import base64
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request


ROOT = os.path.dirname(os.path.abspath(__file__))
URL = Path(ROOT, "index.html").resolve().as_uri()
LOCAL_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

BROWSER_COMMANDS = (
    "msedge", "microsoft-edge", "microsoft-edge-stable",
    "google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
)
BROWSER_PATHS = (
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
)

STRESS_EXPRESSION = r"""
(function () {
  const api = window.yifpgaViewerTest;
  api.clearAll();
  const bytes = [];
  let timestamp = 0;
  function payloadFor(type, cycle) {
    const payload = [];
    timestamp += 100;
    if (type === 0x01) {
      api.pushU32(payload, timestamp);
    } else if (type === 0x02) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, 0x3001);
      api.pushU32(payload, cycle);
      api.pushU32(payload, 0xCAFE0000 | (cycle & 0xFFFF));
    } else if (type === 0x03) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, 0x1001);
      payload.push(1);
      api.pushU32(payload, cycle);
    } else if (type === 0x04) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, 0x2001);
      api.pushU32(payload, cycle);
    } else if (type === 0x05) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, 4);
      api.pushU16(payload, 0);
      api.pushU16(payload, cycle & 0xFFFF);
    } else if (type === 0x10) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, cycle % 2 ? 0x0001 : 0x0002);
      api.pushU16(payload, cycle & 0xFFFF);
      api.pushU32(payload, cycle);
    } else if (type === 0x11) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, cycle % 2 ? 0x0001 : 0x0002);
      api.pushU16(payload, cycle & 0xFFFF);
      payload.push(cycle % 41 === 0 ? 3 : 0);
      api.pushU32(payload, cycle);
    } else if (type === 0x12) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, cycle % 2 ? 0x0003 : 0x0004);
      payload.push(cycle % 37 === 0 ? 2 : 1);
      api.pushU32(payload, cycle);
    } else if (type === 0x13) {
      api.pushU32(payload, timestamp);
      api.pushU16(payload, 0x0003);
      api.pushU16(payload, 0x0001);
      api.pushU32(payload, cycle);
    }
    return payload;
  }
  function addFrame(type, cycle) {
    bytes.push.apply(bytes, api.frame(type, payloadFor(type, cycle)));
  }
  for (let cycle = 0; cycle < 2400; cycle += 1) {
    if (cycle % 80 === 0) addFrame(0x01, cycle);
    if (cycle % 16 === 0) addFrame(0x02, cycle);
    if (cycle % 8 === 0) addFrame(0x03, cycle);
    if (cycle % 1 === 0) addFrame(0x04, cycle);
    if (cycle % 8 === 0) addFrame(0x05, cycle);
    addFrame(0x10, cycle);
    addFrame(0x11, cycle);
    addFrame(0x12, cycle);
    if (cycle % 3 === 0) addFrame(0x13, cycle);
  }
  const wrapBegin = [];
  api.pushU32(wrapBegin, 0xfffffff0);
  api.pushU16(wrapBegin, 0x0001);
  api.pushU16(wrapBegin, 0xbeef);
  api.pushU32(wrapBegin, 0);
  bytes.push.apply(bytes, api.frame(0x10, wrapBegin));
  const wrapEnd = [];
  api.pushU32(wrapEnd, 0x00000020);
  api.pushU16(wrapEnd, 0x0001);
  api.pushU16(wrapEnd, 0xbeef);
  wrapEnd.push(0);
  api.pushU32(wrapEnd, 0);
  bytes.push.apply(bytes, api.frame(0x11, wrapEnd));
  const start = performance.now();
  api.parseBytes(bytes);
  api.injectProfilerSample();
  api.injectLogicAnalyzerSample();
  api.parseBytes(api.frame(0x30, [0, 1, 2, 3]));
  api.renderAll();
  const elapsed = Math.round(performance.now() - start);
  return JSON.stringify({
    frames: api.state.frames,
    checksumErrors: api.state.checksumErrors,
    syncDrops: api.state.syncDrops,
    unknownFrames: api.state.unknownFrames,
    spans: api.state.trace.spans.length,
    wrapDuration: api.state.trace.spans.find((span) => span.instanceId === 0xbeef).duration,
    marks: api.state.trace.marks.length,
    values: api.state.trace.values.length,
    profilerSnapshots: api.state.profiler.counters.snapshots,
    profilerAlerts: api.state.profiler.counters.alerts,
    profilerOverflowSnapshots: api.state.profiler.counters.overflowSnapshots,
    profilerMalformed: api.state.profiler.counters.malformed,
    profilerCards: document.querySelectorAll("#profilerCards .profiler-card").length,
    profilerRows: document.querySelectorAll("#profilerTableBody tr").length,
    profilerAlertItems: document.querySelectorAll("#profilerAlerts .error-list div, #profilerAlerts div").length,
    profilerTrendWidth: document.getElementById("profilerTrendCanvas").width,
    laCaptures: api.state.logicAnalyzer.captures.size,
    laMalformed: api.state.logicAnalyzer.counters.malformed,
    laChannels: document.querySelectorAll("#laChannelList .la-channel").length,
    laCanvasWidth: document.getElementById("laWaveCanvas").width,
    laSummary: document.getElementById("laSummary").textContent,
    traceNodes: document.querySelectorAll("#traceTimeline .trace-span, #traceTimeline .trace-mark").length,
    elapsedMs: elapsed,
    summary: document.getElementById("traceSummary").textContent
  });
})()
"""

AI_DEBUG_EXPRESSION = r"""
(async function () {
  const api = window.yifpgaViewerTest;
  const local = await api.aiDebug.runLocal();
  document.getElementById("aiDebugConsent").checked = true;
  document.getElementById("aiDebugConsent").dispatchEvent(new Event("change"));
  const provider = await api.aiDebug.askAI();
  const report = api.aiDebug.report();
  const evidenceIds = new Set(api.aiDebug.state.snapshot.evidence.map((item) => item.evidence_id));
  const references = report.findings.flatMap((item) => item.evidence_ids)
    .concat((report.diagnosis ? report.diagnosis.hypotheses : []).flatMap((item) => item.evidence_ids));
  let cancelCount = 0;
  let cancelledFindingCount = 0;
  for (let index = 0; index < 5; index += 1) {
    const controller = new window.YiFPGAAIProvider.AnalysisController();
    const pending = controller.run(
      new window.YiFPGAAIProvider.MockProvider("valid", 50),
      api.aiDebug.state.snapshot,
      api.aiDebug.state.ruleResult
    );
    window.setTimeout(() => controller.cancel(), 1);
    const cancelled = await pending;
    if (cancelled.status !== "cancelled") throw new Error(`cancel iteration ${index} returned ${cancelled.status}`);
    cancelCount += 1;
    cancelledFindingCount += (cancelled.local_findings || []).length;
  }
  return JSON.stringify({
    localStatus: api.aiDebug.state.status,
    findingCount: local.findings.length,
    providerStatus: provider.status,
    hypothesisCount: report.diagnosis ? report.diagnosis.hypotheses.length : 0,
    danglingReferences: references.filter((id) => !evidenceIds.has(id)),
    previewText: document.getElementById("aiDebugPreview").textContent,
    historyCount: api.aiDebug.state.history.length,
    cancelCount,
    cancelledFindingCount
  });
})()
"""


def http_json(url):
    with LOCAL_OPENER.open(url, timeout=2) as response:
        return json.loads(response.read().decode("utf-8"))


def http_json_request(url, method="GET"):
    request = urllib.request.Request(url, method=method)
    with LOCAL_OPENER.open(request, timeout=2) as response:
        return json.loads(response.read().decode("utf-8"))


def ws_connect(ws_url):
    if not ws_url.startswith("ws://"):
        raise RuntimeError("Only ws:// URLs are supported")
    rest = ws_url[len("ws://"):]
    host_port, path = rest.split("/", 1)
    host, port = host_port.split(":")
    sock = socket.create_connection((host, int(port)), timeout=5)
    sock.settimeout(30)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET /{path} HTTP/1.1\r\n"
        f"Host: {host_port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    sock.sendall(request.encode("ascii"))
    response = sock.recv(4096)
    if b" 101 " not in response:
        raise RuntimeError(response.decode("latin1", errors="replace"))
    return sock


def ws_send(sock, payload):
    data = payload.encode("utf-8")
    header = bytearray([0x81])
    if len(data) < 126:
        header.append(0x80 | len(data))
    elif len(data) < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", len(data)))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", len(data)))
    mask = os.urandom(4)
    header.extend(mask)
    masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(data))
    sock.sendall(bytes(header) + masked)


def recvall(sock, count):
    chunks = []
    remaining = count
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise RuntimeError("WebSocket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def ws_recv(sock):
    first = recvall(sock, 2)
    opcode = first[0] & 0x0F
    masked = bool(first[1] & 0x80)
    length = first[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", recvall(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recvall(sock, 8))[0]
    mask = recvall(sock, 4) if masked else b""
    data = recvall(sock, length)
    if masked:
        data = bytes(byte ^ mask[index % 4] for index, byte in enumerate(data))
    if opcode == 8:
        raise RuntimeError("WebSocket closed")
    if opcode != 1:
        return None
    return json.loads(data.decode("utf-8"))


def cdp_call(sock, counter, method, params=None):
    msg_id = next(counter)
    ws_send(sock, json.dumps({"id": msg_id, "method": method, "params": params or {}}))
    deadline = time.time() + 30
    while time.time() < deadline:
        message = ws_recv(sock)
        if message and message.get("id") == msg_id:
            if "error" in message:
                raise RuntimeError(message["error"])
            return message.get("result")
    raise TimeoutError(method)


def ids():
    value = 0
    while True:
        value += 1
        yield value


def find_browser(explicit=None):
    candidate = explicit or os.environ.get("YIFPGA_VIEWER_BROWSER")
    if candidate:
        resolved = shutil.which(candidate) or candidate
        if os.path.isfile(resolved):
            return resolved
        raise RuntimeError(f"Configured Chromium browser not found: {candidate}")
    for command in BROWSER_COMMANDS:
        resolved = shutil.which(command)
        if resolved:
            return resolved
    for path in BROWSER_PATHS:
        if os.path.isfile(path):
            return path
    raise RuntimeError(
        "No Chromium-compatible browser found. Install Edge/Chrome/Chromium, "
        "or set YIFPGA_VIEWER_BROWSER to its executable path."
    )


def free_local_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def parse_args():
    parser = argparse.ArgumentParser(description="Run the headless YiFPGA Studio Viewer stress test")
    parser.add_argument("--browser", help="Chromium-compatible browser executable")
    parser.add_argument("--debug-port", type=int, help="CDP port; default chooses a free local port")
    return parser.parse_args()


def main():
    args = parse_args()
    browser = find_browser(args.browser)
    port = args.debug_port or free_local_port()

    profile = tempfile.mkdtemp(prefix="yifpga-viewer-cdp-")
    proc = subprocess.Popen([
        browser,
        "--headless=new",
        "--disable-gpu",
        "--disable-gpu-sandbox",
        "--disable-software-rasterizer",
        "--disable-dev-shm-usage",
        "--no-sandbox",
        "--disable-features=VizDisplayCompositor",
        "--no-first-run",
        "--disable-background-networking",
        "--remote-debugging-address=127.0.0.1",
        f"--remote-debugging-port={port}",
        f"--user-data-dir={profile}",
        "about:blank",
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        deadline = time.time() + 15
        tabs = []
        last_error = None
        while time.time() < deadline:
            try:
                http_json(f"http://127.0.0.1:{port}/json/version")
                tab = http_json_request(f"http://127.0.0.1:{port}/json/new?{urllib.parse.quote(URL, safe=':/')}", "PUT")
                tabs = [tab]
                if tab.get("webSocketDebuggerUrl"):
                    break
            except Exception as error:
                last_error = error
                time.sleep(0.2)
        if not tabs:
            stdout, stderr = proc.communicate(timeout=1) if proc.poll() is not None else (b"", b"")
            raise RuntimeError(
                f"No browser CDP tab found using {browser}. "
                f"returncode={proc.poll()} last_error={last_error} "
                f"stderr={stderr.decode('utf-8', errors='replace')[:1000]}"
            )

        sock = ws_connect(tabs[0]["webSocketDebuggerUrl"])
        counter = ids()
        cdp_call(sock, counter, "Runtime.enable")
        heap_before = cdp_call(sock, counter, "Runtime.getHeapUsage")

        hook_ready = None
        deadline = time.time() + 20
        while time.time() < deadline:
            evaluated = cdp_call(sock, counter, "Runtime.evaluate", {
                "expression": "!!window.yifpgaViewerTest",
                "returnByValue": True,
            })
            value = evaluated.get("result", {}).get("value")
            if value:
                hook_ready = True
                break
            time.sleep(0.2)

        if not hook_ready:
            raise RuntimeError("Viewer test hook did not become ready")

        evaluated = cdp_call(sock, counter, "Runtime.evaluate", {
            "expression": STRESS_EXPRESSION,
            "returnByValue": True,
            "timeout": 20000,
        })
        result = evaluated.get("result", {}).get("value")
        if not result:
            raise RuntimeError(f"Perf test returned no result: {evaluated}")
        parsed = json.loads(result)
        if parsed["wrapDuration"] != 0x30:
            raise RuntimeError(f"Trace timestamp wrap handling failed: {result}")
        if parsed["profilerSnapshots"] < 4:
            raise RuntimeError(f"Profiler snapshots missing: {result}")
        if parsed["profilerAlerts"] < 1:
            raise RuntimeError(f"Profiler alerts missing: {result}")
        if parsed["profilerMalformed"] < 1:
            raise RuntimeError(f"Profiler malformed counter missing: {result}")
        if parsed["profilerCards"] < 4 or parsed["profilerRows"] < 4:
            raise RuntimeError(f"Profiler UI did not render metric rows: {result}")
        if parsed["profilerTrendWidth"] <= 0:
            raise RuntimeError(f"Profiler trend canvas did not initialize: {result}")
        if parsed["laCaptures"] < 1:
            raise RuntimeError(f"Logic Analyzer capture missing: {result}")
        if parsed["laMalformed"] < 1:
            raise RuntimeError(f"Logic Analyzer malformed counter missing: {result}")
        if parsed["laChannels"] < 8 or parsed["laCanvasWidth"] <= 0:
            raise RuntimeError(f"Logic Analyzer UI did not render: {result}")
        ai_evaluated = cdp_call(sock, counter, "Runtime.evaluate", {
            "expression": AI_DEBUG_EXPRESSION,
            "returnByValue": True,
            "awaitPromise": True,
            "timeout": 20000,
        })
        ai_result = ai_evaluated.get("result", {}).get("value")
        if not ai_result:
            raise RuntimeError(f"AI Debug workflow returned no result: {ai_evaluated}")
        ai_parsed = json.loads(ai_result)
        if ai_parsed["providerStatus"] != "completed" or ai_parsed["hypothesisCount"] < 1:
            raise RuntimeError(f"AI Debug Mock workflow failed: {ai_result}")
        if ai_parsed["danglingReferences"] or ai_parsed["historyCount"] < 2:
            raise RuntimeError(f"AI Debug report/history integrity failed: {ai_result}")
        if ai_parsed["cancelCount"] != 5:
            raise RuntimeError(f"AI Debug cancellation lifecycle failed: {ai_result}")
        heap_after = cdp_call(sock, counter, "Runtime.getHeapUsage")
        parsed["memory"] = {
            "heapUsedBeforeBytes": heap_before["usedSize"],
            "heapUsedAfterBytes": heap_after["usedSize"],
            "heapDeltaBytes": heap_after["usedSize"] - heap_before["usedSize"],
            "heapTotalAfterBytes": heap_after["totalSize"],
        }
        parsed["aiDebug"] = ai_parsed
        result = json.dumps(parsed, separators=(",", ":"))
        print(result)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    main()
