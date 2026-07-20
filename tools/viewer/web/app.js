(function () {
  "use strict";

  const SOF = 0xA5;
  const VERSION = 0x01;
  const MAX_PAYLOAD = 32;
  const BRIDGE_TYPES = { HELLO: 1, DATA: 2, STATUS: 3, SESSION: 4, ERROR: 5 };
  const BRIDGE_MAX_RECORD = 16 * 1024 * 1024;

  const TYPES = {
    0x01: "HEARTBEAT",
    0x02: "DEBUG_PRINT",
    0x03: "EVENT",
    0x04: "WATCH",
    0x05: "STATUS",
    0x10: "TRACE_SPAN_BEGIN",
    0x11: "TRACE_SPAN_END",
    0x12: "TRACE_MARK",
    0x13: "TRACE_VALUE",
    0x14: "TRACE_DROP",
    0x20: "MONITOR_READ_REQ",
    0x21: "MONITOR_READ_RESP",
    0x22: "MONITOR_WRITE_REQ",
    0x23: "MONITOR_WRITE_RESP",
    0x24: "MONITOR_BURST_READ_REQ",
    0x25: "MONITOR_BURST_READ_RESP",
    0x26: "MONITOR_POLL_CFG",
    0x27: "MONITOR_EVENT",
    0x28: "MONITOR_DISCOVER_REQ",
    0x29: "MONITOR_DISCOVER_RESP",
    0x30: "PROFILER_SNAPSHOT",
    0x31: "PROFILER_ALERT",
    0x32: "PROFILER_COUNTER",
    0x33: "PROFILER_LATENCY",
    0x34: "PROFILER_DISCOVER",
    0x35: "PROFILER_CFG_REQ",
    0x36: "PROFILER_CFG_RESP",
    0x40: "LA_CAPTURE_HEADER",
    0x41: "LA_SAMPLE_DATA",
    0x42: "LA_CAPTURE_STATUS",
    0x43: "LA_TRIGGER_EVENT",
    0x44: "LA_CHANNEL_MANIFEST",
    0x45: "LA_CFG_REQ",
    0x46: "LA_CFG_RESP",
  };

  const LEVELS = ["Debug", "Info", "Warning", "Error"];
  const TRACE_STATUS = ["OK", "WARN", "ERROR", "TIMEOUT"];
  const MONITOR_STATUS = ["OK", "BAD_ADDR", "DENIED", "BUSY", "BAD_LEN", "BAD_VALUE", "TIMEOUT"];
  const MONITOR_TIMEOUT_MS = 1000;
  const MAX_TRACE_RENDER_ITEMS = 1200;
  const MAX_TRACE_SPANS = 20000;
  const MAX_TRACE_MARKS = 20000;
  const MAX_TRACE_VALUES = 10000;
  const MAX_TRACE_DROPS = 2000;
  const TRACE_NAMES = {
    0x0001: "DMA",
    0x0002: "Frame",
    0x0003: "FIFO",
    0x0004: "Interrupt",
  };
  const PROFILER_FLAGS = {
    VALID: 1 << 0,
    SATURATED: 1 << 1,
    WINDOW_RESET: 1 << 2,
    PARTIAL: 1 << 3,
    ALERT: 1 << 4,
  };
  const PROFILER_ALERT_CODES = {
    1: "THRESHOLD_HIGH",
    2: "THRESHOLD_LOW",
    3: "OVERFLOW",
    4: "UNDERFLOW",
    5: "TIMEOUT",
    6: "DROP",
  };
  const LA_FLAGS = {
    VALID: 1 << 0,
    TRIGGERED: 1 << 1,
    FORCED: 1 << 2,
    OVERFLOW: 1 << 3,
    PARTIAL: 1 << 4,
  };
  const LA_STATES = ["IDLE", "ARMED", "CAPTURING", "DONE", "READOUT", "ERROR"];
  const LA_TRIGGER_MODES = ["Disabled", "Level", "Rising", "Falling", "Mask"];
  const LA_COMMANDS = {
    arm: 1 << 0,
    stop: 1 << 1,
    clear: 1 << 2,
    force: 1 << 3,
    readout: 1 << 4,
  };
  const LA_CHANNELS = [
    { bit: 0, width: 1, name: "uart_tx_busy", color: "#1769aa", visible: true },
    { bit: 1, width: 1, name: "uart_rx_valid", color: "#0f8a5f", visible: true },
    { bit: 2, width: 1, name: "debug_tx_valid", color: "#b15c00", visible: true },
    { bit: 3, width: 1, name: "debug_tx_ready", color: "#7c3aed", visible: true },
    { bit: 4, width: 1, name: "trace_valid", color: "#c2410c", visible: true },
    { bit: 5, width: 1, name: "monitor_resp_valid", color: "#0369a1", visible: true },
    { bit: 6, width: 1, name: "profiler_snapshot_valid", color: "#be123c", visible: true },
    { bit: 7, width: 1, name: "demo_frame_tick", color: "#4d7c0f", visible: true },
    { bit: 8, width: 8, name: "debug_buffer_used_lsb", color: "#475569", visible: true },
    { bit: 16, width: 8, name: "demo_fifo_level_lsb", color: "#854d0e", visible: true },
    { bit: 24, width: 8, name: "la_state_debug", color: "#155e75", visible: true },
  ];
  const PROFILER_METRICS = [
    { id: 0x0001, name: "AXIS_DEMO_THROUGHPUT", type: "Throughput", unit: "bytes/window", fields: ["bytes", "beats", "active_cycles", "stall_cycles"] },
    { id: 0x0101, name: "FIFO_DEMO_LEVEL", type: "FIFO", unit: "level", fields: ["current_level", "max_level", "min_level", "overflow_underflow"] },
    { id: 0x0201, name: "DEMO_LATENCY", type: "Latency", unit: "cycles", fields: ["count", "min", "max", "avg"] },
    { id: 0x0301, name: "FRAME_RATE", type: "Frame Rate", unit: "frames/window", fields: ["frame_count", "dropped_frames", "min_interval", "max_interval"] },
  ];
  const MAX_PROFILER_HISTORY_PER_METRIC = 600;
  const MAX_PROFILER_ALERTS = 200;
  const MONITOR_REGISTERS = [
    { addr: 0x0000, name: "MONITOR_ID", access: "RO", width: 4 },
    { addr: 0x0004, name: "MONITOR_VERSION", access: "RO", width: 4 },
    { addr: 0x0008, name: "CONTROL", access: "RW", width: 4 },
    { addr: 0x000C, name: "LED_CONTROL", access: "RW", width: 4 },
    { addr: 0x0010, name: "DEMO_PERIOD", access: "RW", width: 4 },
    { addr: 0x0014, name: "COUNTER0", access: "RO", width: 4 },
    { addr: 0x0018, name: "CLEAR_COUNTERS", access: "TRIGGER", width: 4 },
    { addr: 0x001C, name: "ERROR_STATUS", access: "W1C", width: 4 },
    { addr: 0x0040, name: "PROFILER_ID", access: "RO", width: 4 },
    { addr: 0x0044, name: "PROFILER_VERSION", access: "RO", width: 4 },
    { addr: 0x0048, name: "PROFILER_CONTROL", access: "RW", width: 4 },
    { addr: 0x004C, name: "PROFILER_SAMPLE_PERIOD", access: "RW", width: 4 },
    { addr: 0x0050, name: "PROFILER_CLEAR", access: "TRIGGER", width: 4 },
    { addr: 0x0054, name: "PROFILER_STATUS", access: "RW", width: 4 },
    { addr: 0x0058, name: "PROFILER_METRIC_MASK0", access: "RW", width: 4 },
    { addr: 0x005C, name: "PROFILER_ALERT_THRESHOLD0", access: "RW", width: 4 },
    { addr: 0x0060, name: "LA_ID", access: "RO", width: 4 },
    { addr: 0x0064, name: "LA_VERSION", access: "RO", width: 4 },
    { addr: 0x0068, name: "LA_CONTROL", access: "RW", width: 4 },
    { addr: 0x006C, name: "LA_STATUS", access: "RW", width: 4 },
    { addr: 0x0070, name: "LA_SAMPLE_DIVISOR", access: "RW", width: 4 },
    { addr: 0x0074, name: "LA_CAPTURE_DEPTH", access: "RW", width: 4 },
    { addr: 0x0078, name: "LA_PRETRIGGER_DEPTH", access: "RW", width: 4 },
    { addr: 0x007C, name: "LA_TRIGGER_MODE", access: "RW", width: 4 },
    { addr: 0x0080, name: "LA_TRIGGER_CHANNEL", access: "RW", width: 4 },
    { addr: 0x0084, name: "LA_TRIGGER_VALUE", access: "RW", width: 4 },
    { addr: 0x0088, name: "LA_TRIGGER_MASK", access: "RW", width: 4 },
    { addr: 0x008C, name: "LA_COMMAND", access: "TRIGGER", width: 4 },
    { addr: 0x0090, name: "LA_CAPTURE_ID", access: "RO", width: 4 },
    { addr: 0x0094, name: "LA_CHANNEL_MASK", access: "RW", width: 4 },
  ];

  const state = {
    port: null,
    reader: null,
    socket: null,
    sourceType: "serial",
    readLoopActive: false,
    rx: [],
    frames: 0,
    checksumErrors: 0,
    syncDrops: 0,
    unknownFrames: 0,
    paused: false,
    transport: {
      hello: null, status: null, sessionId: null, connection: "disconnected",
      recordRx: new Uint8Array(0), currentBps: 0, lastStatusBytes: 0,
      lastStatusAt: 0, viewerDroppedBytes: 0,
    },
    logs: [],
    watches: new Map(),
    events: new Map(),
    status: {
      bufferUsed: "-",
      dropCount: "-",
      packetCount: "-",
      lastTimestamp: "-",
    },
    trace: {
      spans: [],
      openSpans: new Map(),
      marks: [],
      values: [],
      latestValues: new Map(),
      drops: [],
      selected: null,
    },
    monitor: createMonitorState(),
    profiler: createProfilerState(),
    logicAnalyzer: createLogicAnalyzerState(),
    render: {
      scheduled: false,
      pending: new Set(),
    },
  };
  let aiDebug = null;

  const el = {
    serialSupport: document.getElementById("serialSupport"),
    connectionState: document.getElementById("connectionState"),
    sourceType: document.getElementById("sourceType"),
    bridgeHost: document.getElementById("bridgeHost"),
    bridgePort: document.getElementById("bridgePort"),
    rawReplayInput: document.getElementById("rawReplayInput"),
    bridgeVersion: document.getElementById("bridgeVersion"),
    bridgeTarget: document.getElementById("bridgeTarget"),
    bridgeSession: document.getElementById("bridgeSession"),
    bridgeThroughput: document.getElementById("bridgeThroughput"),
    bridgeBuffer: document.getElementById("bridgeBuffer"),
    bridgeReconnect: document.getElementById("bridgeReconnect"),
    transportSummary: document.getElementById("transportSummary"),
    baudRate: document.getElementById("baudRate"),
    connectButton: document.getElementById("connectButton"),
    disconnectButton: document.getElementById("disconnectButton"),
    sampleButton: document.getElementById("sampleButton"),
    pauseButton: document.getElementById("pauseButton"),
    clearButton: document.getElementById("clearButton"),
    exportCsvButton: document.getElementById("exportCsvButton"),
    exportJsonlButton: document.getElementById("exportJsonlButton"),
    frameCount: document.getElementById("frameCount"),
    checksumErrors: document.getElementById("checksumErrors"),
    syncDrops: document.getElementById("syncDrops"),
    unknownFrames: document.getElementById("unknownFrames"),
    logBody: document.getElementById("logBody"),
    watchBody: document.getElementById("watchBody"),
    eventBody: document.getElementById("eventBody"),
    logCount: document.getElementById("logCount"),
    watchCount: document.getElementById("watchCount"),
    eventCount: document.getElementById("eventCount"),
    bufferUsed: document.getElementById("bufferUsed"),
    dropCount: document.getElementById("dropCount"),
    packetCount: document.getElementById("packetCount"),
    lastTimestamp: document.getElementById("lastTimestamp"),
    traceSummary: document.getElementById("traceSummary"),
    traceLaneFilter: document.getElementById("traceLaneFilter"),
    traceStatusFilter: document.getElementById("traceStatusFilter"),
    traceFrom: document.getElementById("traceFrom"),
    traceTo: document.getElementById("traceTo"),
    traceSpanCount: document.getElementById("traceSpanCount"),
    traceAverageDuration: document.getElementById("traceAverageDuration"),
    traceMaxDuration: document.getElementById("traceMaxDuration"),
    traceProblemCount: document.getElementById("traceProblemCount"),
    traceTimeline: document.getElementById("traceTimeline"),
    traceDetail: document.getElementById("traceDetail"),
    traceValueBody: document.getElementById("traceValueBody"),
    monitorSummary: document.getElementById("monitorSummary"),
    monitorPollEnabled: document.getElementById("monitorPollEnabled"),
    monitorPollInterval: document.getElementById("monitorPollInterval"),
    monitorReadAllButton: document.getElementById("monitorReadAllButton"),
    monitorBody: document.getElementById("monitorBody"),
    monitorErrors: document.getElementById("monitorErrors"),
    profilerSummary: document.getElementById("profilerSummary"),
    profilerMetricSelect: document.getElementById("profilerMetricSelect"),
    profilerValueSelect: document.getElementById("profilerValueSelect"),
    profilerAlertFilter: document.getElementById("profilerAlertFilter"),
    profilerPeriodInput: document.getElementById("profilerPeriodInput"),
    profilerEnableButton: document.getElementById("profilerEnableButton"),
    profilerDisableButton: document.getElementById("profilerDisableButton"),
    profilerApplyPeriodButton: document.getElementById("profilerApplyPeriodButton"),
    profilerClearButton: document.getElementById("profilerClearButton"),
    profilerReadStatusButton: document.getElementById("profilerReadStatusButton"),
    profilerCards: document.getElementById("profilerCards"),
    profilerTrendCanvas: document.getElementById("profilerTrendCanvas"),
    profilerAlerts: document.getElementById("profilerAlerts"),
    profilerTableBody: document.getElementById("profilerTableBody"),
    laSummary: document.getElementById("laSummary"),
    laArmButton: document.getElementById("laArmButton"),
    laStopButton: document.getElementById("laStopButton"),
    laForceButton: document.getElementById("laForceButton"),
    laClearButton: document.getElementById("laClearButton"),
    laReadoutButton: document.getElementById("laReadoutButton"),
    laExportVcdButton: document.getElementById("laExportVcdButton"),
    laSampleDivisor: document.getElementById("laSampleDivisor"),
    laCaptureDepth: document.getElementById("laCaptureDepth"),
    laPretriggerDepth: document.getElementById("laPretriggerDepth"),
    laTriggerMode: document.getElementById("laTriggerMode"),
    laTriggerChannel: document.getElementById("laTriggerChannel"),
    laTriggerValue: document.getElementById("laTriggerValue"),
    laTriggerMask: document.getElementById("laTriggerMask"),
    laApplyConfigButton: document.getElementById("laApplyConfigButton"),
    laCaptureId: document.getElementById("laCaptureId"),
    laState: document.getElementById("laState"),
    laSamples: document.getElementById("laSamples"),
    laChunks: document.getElementById("laChunks"),
    laParserHealth: document.getElementById("laParserHealth"),
    laViewportStart: document.getElementById("laViewportStart"),
    laSamplesPerPixel: document.getElementById("laSamplesPerPixel"),
    laZoomInButton: document.getElementById("laZoomInButton"),
    laZoomOutButton: document.getElementById("laZoomOutButton"),
    laCursorA: document.getElementById("laCursorA"),
    laCursorB: document.getElementById("laCursorB"),
    laCursorDelta: document.getElementById("laCursorDelta"),
    laChannelList: document.getElementById("laChannelList"),
    laWaveCanvas: document.getElementById("laWaveCanvas"),
    laErrors: document.getElementById("laErrors"),
    aiDebugStatus: document.getElementById("aiDebugStatus"),
    aiDebugScope: document.getElementById("aiDebugScope"),
    aiDebugLocalButton: document.getElementById("aiDebugLocalButton"),
    aiDebugConsent: document.getElementById("aiDebugConsent"),
    aiDebugAskButton: document.getElementById("aiDebugAskButton"),
    aiDebugCancelButton: document.getElementById("aiDebugCancelButton"),
    aiDebugPreview: document.getElementById("aiDebugPreview"),
    aiDebugFindings: document.getElementById("aiDebugFindings"),
    aiDebugHypotheses: document.getElementById("aiDebugHypotheses"),
    aiDebugActions: document.getElementById("aiDebugActions"),
    aiDebugFeedbackRating: document.getElementById("aiDebugFeedbackRating"),
    aiDebugFeedbackRoot: document.getElementById("aiDebugFeedbackRoot"),
    aiDebugFeedbackNote: document.getElementById("aiDebugFeedbackNote"),
    aiDebugHistory: document.getElementById("aiDebugHistory"),
    aiDebugExportSnapshot: document.getElementById("aiDebugExportSnapshot"),
    aiDebugExportDiagnosis: document.getElementById("aiDebugExportDiagnosis"),
    aiDebugExportMarkdown: document.getElementById("aiDebugExportMarkdown"),
  };

  function hasSerial() {
    return "serial" in navigator;
  }

  function setConnected(connected, detail) {
    state.transport.connection = connected ? "connected" : "disconnected";
    el.connectionState.textContent = connected ? `${state.sourceType.toUpperCase()} Connected` : "Disconnected";
    el.connectionState.classList.toggle("ok", connected);
    el.connectButton.disabled = connected;
    el.disconnectButton.disabled = !connected;
    if (detail) state.transport.status = { ...(state.transport.status || {}), last_error: detail };
    renderTransport();
  }

  function formatRate(value) {
    if (!Number.isFinite(value)) return "-";
    if (value >= 1024 * 1024) return `${(value / 1024 / 1024).toFixed(2)} MB/s`;
    return `${(value / 1024).toFixed(1)} KB/s`;
  }

  function renderTransport() {
    const hello = state.transport.hello || {};
    const status = state.transport.status || {};
    const target = hello.target || {};
    el.transportSummary.textContent = `${state.sourceType.toUpperCase()} ${state.transport.connection}`;
    el.bridgeVersion.textContent = hello.bridge_version == null ? "-" :
      `bridge v${hello.bridge_version} / transport v${hello.transport_version}`;
    el.bridgeTarget.textContent = hello.stable_id || [target.cable, target.device, target.user_chain].filter(Boolean).join(" / ") || "-";
    el.bridgeSession.textContent = state.transport.sessionId == null ? "-" :
      `${state.transport.sessionId} / ${target.build_id == null ? "-" : target.build_id}`;
    el.bridgeThroughput.textContent = `${formatRate(state.transport.currentBps)} current / ${formatRate(status.bytes_per_second)} average`;
    el.bridgeBuffer.textContent = `${status.buffer_used == null ? "-" : status.buffer_used} used / ${status.overflow_count || 0} overflow / ${status.dropped_bytes || 0} dropped`;
    el.bridgeReconnect.textContent = `${status.reconnects || 0} reconnect / ${status.last_error || "-"}`;
  }

  function checksum(bytes) {
    return bytes.reduce((acc, value) => acc ^ value, 0) & 0xFF;
  }

  function u16(payload, offset) {
    return payload[offset] | (payload[offset + 1] << 8);
  }

  function u32(payload, offset) {
    return (
      payload[offset] |
      (payload[offset + 1] << 8) |
      (payload[offset + 2] << 16) |
      (payload[offset + 3] << 24)
    ) >>> 0;
  }

  function hex(value, width) {
    return "0x" + value.toString(16).toUpperCase().padStart(width, "0");
  }

  function frame(type, payload) {
    const headerAndPayload = [VERSION, type, payload.length, ...payload];
    return [SOF, ...headerAndPayload, checksum(headerAndPayload)];
  }

  function createMonitorState() {
    return {
      registers: MONITOR_REGISTERS.map((reg) => ({ ...reg })),
      values: new Map(),
      pending: new Map(),
      seq: 1,
      pollEnabled: false,
      pollIntervalMs: 500,
      lastPollAt: 0,
      errors: [],
      history: [],
    };
  }

  function createProfilerState() {
    return {
      metrics: new Map(PROFILER_METRICS.map((metric) => [metric.id, { ...metric }])),
      latest: new Map(),
      history: new Map(),
      alerts: [],
      counters: {
        snapshots: 0,
        alerts: 0,
        overflowSnapshots: 0,
        malformed: 0,
      },
      selectedMetricId: PROFILER_METRICS[0].id,
      selectedValueIndex: 0,
      alertFilter: "all",
    };
  }

  function createLogicAnalyzerState() {
    return {
      captures: new Map(),
      latestCaptureId: null,
      manifest: LA_CHANNELS.map((channel) => ({ ...channel })),
      viewport: {
        startSample: 0,
        samplesPerPixel: 1,
        cursorA: 0,
        cursorB: 0,
      },
      config: {
        sampleDivisor: 4,
        captureDepth: 128,
        pretriggerDepth: 32,
        triggerMode: 4,
        triggerChannel: 3,
        triggerValue: 0x00000008,
        triggerMask: 0x00000008,
        channelMask: 0xFFFFFFFF,
      },
      counters: {
        headers: 0,
        samples: 0,
        statuses: 0,
        triggerEvents: 0,
        malformed: 0,
        missingChunks: 0,
        outOfOrderChunks: 0,
        droppedFrames: 0,
      },
    };
  }

  function pushU16(target, value) {
    target.push(value & 0xFF, (value >>> 8) & 0xFF);
  }

  function pushU32(target, value) {
    target.push(value & 0xFF, (value >>> 8) & 0xFF, (value >>> 16) & 0xFF, (value >>> 24) & 0xFF);
  }

  function parseAvailableFrames() {
    while (state.rx.length >= 5) {
      if (state.rx[0] !== SOF) {
        state.rx.shift();
        state.syncDrops += 1;
        continue;
      }

      const len = state.rx[3];
      if (len > MAX_PAYLOAD) {
        state.rx.shift();
        state.syncDrops += 1;
        continue;
      }

      const total = 5 + len;
      if (state.rx.length < total) {
        break;
      }

      const raw = state.rx.splice(0, total);
      const expected = raw[total - 1];
      const actual = checksum(raw.slice(1, total - 1));
      if (actual !== expected) {
        state.checksumErrors += 1;
        continue;
      }

      decodeFrame(raw[1], raw[2], raw.slice(4, total - 1), raw);
    }

    requestRender(renderCounters);
  }

  function appendRxBytes(bytes) {
    for (const byte of bytes) {
      state.rx.push(byte);
    }
  }

  function decodeFrame(version, type, payload, raw) {
    state.frames += 1;

    if (version !== VERSION || !TYPES[type]) {
      state.unknownFrames += 1;
      addLog({
        timestamp: "-",
        type: "UNKNOWN",
        id: hex(type, 2),
        value: raw.map((v) => hex(v, 2)).join(" "),
        text: "Unsupported version or type",
      });
      return;
    }

    if (type === 0x01 && payload.length >= 4) {
      const timestamp = u32(payload, 0);
      addLog({ timestamp, type: TYPES[type], id: "-", value: "-", text: "Heartbeat" });
      state.status.lastTimestamp = timestamp;
      requestRender(renderStatus);
      return;
    }

    if (type === 0x02 && payload.length >= 14) {
      const timestamp = u32(payload, 0);
      const printId = u16(payload, 4);
      const arg0 = u32(payload, 6);
      const arg1 = u32(payload, 10);
      addLog({
        timestamp,
        type: TYPES[type],
        id: hex(printId, 4),
        value: `${hex(arg0, 8)}, ${hex(arg1, 8)}`,
        text: `print ${hex(printId, 4)}`,
      });
      return;
    }

    if (type === 0x03 && payload.length >= 11) {
      const timestamp = u32(payload, 0);
      const eventId = u16(payload, 4);
      const level = payload[6];
      const arg0 = u32(payload, 7);
      updateEvent(eventId, level, arg0);
      addLog({
        timestamp,
        type: TYPES[type],
        id: hex(eventId, 4),
        value: hex(arg0, 8),
        text: LEVELS[level] || `Level ${level}`,
      });
      return;
    }

    if (type === 0x04 && payload.length >= 10) {
      const timestamp = u32(payload, 0);
      const watchId = u16(payload, 4);
      const value = u32(payload, 6);
      updateWatch(watchId, value, timestamp);
      addLog({
        timestamp,
        type: TYPES[type],
        id: hex(watchId, 4),
        value: hex(value, 8),
        text: "watch update",
      });
      return;
    }

    if (type === 0x05 && payload.length >= 10) {
      const timestamp = u32(payload, 0);
      state.status.bufferUsed = u16(payload, 4);
      state.status.dropCount = u16(payload, 6);
      state.status.packetCount = u16(payload, 8);
      state.status.lastTimestamp = timestamp;
      addLog({ timestamp, type: TYPES[type], id: "-", value: "-", text: "status update" });
      requestRender(renderStatus);
      return;
    }

    if (type === 0x10 && payload.length >= 12) {
      const timestamp = u32(payload, 0);
      const traceId = u16(payload, 4);
      const instanceId = u16(payload, 6);
      const arg0 = u32(payload, 8);
      beginTraceSpan(timestamp, traceId, instanceId, arg0);
      addLog({
        timestamp,
        type: TYPES[type],
        id: traceKey(traceId, instanceId),
        value: hex(arg0, 8),
        text: "trace span begin",
      });
      requestRender(renderTrace);
      return;
    }

    if (type === 0x11 && payload.length >= 13) {
      const timestamp = u32(payload, 0);
      const traceId = u16(payload, 4);
      const instanceId = u16(payload, 6);
      const status = payload[8];
      const arg0 = u32(payload, 9);
      const span = endTraceSpan(timestamp, traceId, instanceId, status, arg0);
      addLog({
        timestamp,
        type: TYPES[type],
        id: traceKey(traceId, instanceId),
        value: hex(arg0, 8),
        text: span.orphan ? `orphan end ${traceStatus(status)}` : `trace span end ${traceStatus(status)}`,
      });
      requestRender(renderTrace);
      return;
    }

    if (type === 0x12 && payload.length >= 11) {
      const timestamp = u32(payload, 0);
      const traceId = u16(payload, 4);
      const level = payload[6];
      const arg0 = u32(payload, 7);
      state.trace.marks.push({ timestamp, traceId, level, arg0 });
      pruneTraceHistory();
      addLog({
        timestamp,
        type: TYPES[type],
        id: hex(traceId, 4),
        value: hex(arg0, 8),
        text: LEVELS[level] || `Level ${level}`,
      });
      requestRender(renderTrace);
      return;
    }

    if (type === 0x13 && payload.length >= 12) {
      const timestamp = u32(payload, 0);
      const traceId = u16(payload, 4);
      const valueId = u16(payload, 6);
      const value = u32(payload, 8);
      updateTraceValue(timestamp, traceId, valueId, value);
      addLog({
        timestamp,
        type: TYPES[type],
        id: `${hex(traceId, 4)}/${hex(valueId, 4)}`,
        value: hex(value, 8),
        text: "trace value",
      });
      requestRender(renderTrace);
      return;
    }

    if (type === 0x14 && payload.length >= 10) {
      const timestamp = u32(payload, 0);
      const traceId = u16(payload, 4);
      const dropCount = u32(payload, 6);
      state.trace.drops.push({ timestamp, traceId, dropCount });
      pruneTraceHistory();
      addLog({
        timestamp,
        type: TYPES[type],
        id: hex(traceId, 4),
        value: dropCount,
        text: "trace drop",
      });
      requestRender(renderTrace);
      return;
    }

    if (type === 0x21 && payload.length >= 14) {
      decodeMonitorReadResponse(payload);
      return;
    }

    if (type === 0x23 && payload.length >= 17) {
      decodeMonitorWriteResponse(payload);
      return;
    }

    if (type === 0x30) {
      decodeProfilerSnapshot(payload);
      return;
    }

    if (type === 0x31) {
      decodeProfilerAlert(payload);
      return;
    }

    if (type >= 0x40 && type <= 0x4F) {
      decodeLogicAnalyzerFrame(type, payload);
      return;
    }

    if (type >= 0x20 && type <= 0x2F) {
      state.unknownFrames += 1;
      addMonitorError({
        kind: "unsupported",
        type,
        status: null,
        text: `${TYPES[type]} is reserved for a later Monitor milestone`,
      });
      return;
    }

    if (type >= 0x30 && type <= 0x3F) {
      state.unknownFrames += 1;
      recordProfilerMalformed(type, payload.length, "reserved profiler type");
      return;
    }

    state.unknownFrames += 1;
  }

  function profilerMetric(metricId) {
    return state.profiler.metrics.get(metricId) || {
      id: metricId,
      name: `metric_${hex(metricId, 4)}`,
      type: "Unknown",
      unit: "raw",
      fields: ["value0", "value1", "value2", "value3"],
    };
  }

  function profilerFlagNames(flags) {
    const names = [];
    for (const [name, bit] of Object.entries(PROFILER_FLAGS)) {
      if ((flags & bit) !== 0) {
        names.push(name);
      }
    }
    return names;
  }

  function profilerAlertCode(code) {
    return PROFILER_ALERT_CODES[code] || `CODE_${code}`;
  }

  function decodeProfilerSnapshot(payload) {
    if (payload.length !== 32) {
      recordProfilerMalformed(0x30, payload.length, "bad snapshot length");
      return;
    }

    const timestamp = u32(payload, 0);
    const metricId = u16(payload, 4);
    const flags = u16(payload, 6);
    const sampleCycles = u32(payload, 8);
    const value0 = u32(payload, 12);
    const value1 = u32(payload, 16);
    const value2 = u32(payload, 20);
    const value3 = u32(payload, 24);
    const overflowCount = u16(payload, 28);
    const reserved = u16(payload, 30);
    const metric = profilerMetric(metricId);
    const record = {
      kind: "profiler_snapshot",
      timestamp,
      metricId,
      metricName: metric.name,
      metricType: metric.type,
      unit: metric.unit,
      flags,
      flagNames: profilerFlagNames(flags),
      sampleCycles,
      value0,
      value1,
      value2,
      value3,
      overflowCount,
      reserved,
    };

    state.profiler.counters.snapshots += 1;
    if ((flags & PROFILER_FLAGS.SATURATED) !== 0 || overflowCount > 0) {
      state.profiler.counters.overflowSnapshots += 1;
    }
    state.profiler.latest.set(metricId, record);
    const history = state.profiler.history.get(metricId) || [];
    history.push(record);
    if (history.length > MAX_PROFILER_HISTORY_PER_METRIC) {
      history.splice(0, history.length - MAX_PROFILER_HISTORY_PER_METRIC);
    }
    state.profiler.history.set(metricId, history);

    addLog({
      timestamp,
      type: TYPES[0x30],
      id: hex(metricId, 4),
      value: `${value0}, ${value1}, ${value2}, ${value3}`,
      text: metric.name,
    });
    requestRender(renderProfiler);
  }

  function laCapture(captureId) {
    let capture = state.logicAnalyzer.captures.get(captureId);
    if (!capture) {
      capture = {
        header: null,
        status: null,
        triggerEvent: null,
        chunks: new Map(),
        samples: [],
        missingRanges: [],
        complete: false,
        errors: [],
      };
      state.logicAnalyzer.captures.set(captureId, capture);
    }
    return capture;
  }

  function laFlagNames(flags) {
    const names = [];
    for (const [name, bit] of Object.entries(LA_FLAGS)) {
      if ((flags & bit) !== 0) {
        names.push(name);
      }
    }
    return names;
  }

  function decodeLogicAnalyzerFrame(type, payload) {
    if (type === 0x40) {
      decodeLogicAnalyzerHeader(payload);
    } else if (type === 0x41) {
      decodeLogicAnalyzerSampleData(payload);
    } else if (type === 0x42) {
      decodeLogicAnalyzerStatus(payload);
    } else if (type === 0x43) {
      decodeLogicAnalyzerTriggerEvent(payload);
    } else {
      recordLogicAnalyzerMalformed(type, payload.length, "reserved LA type");
    }
  }

  function decodeLogicAnalyzerHeader(payload) {
    if (payload.length !== 24) {
      recordLogicAnalyzerMalformed(0x40, payload.length, "bad header length");
      return;
    }

    const captureId = u32(payload, 0);
    const header = {
      kind: "la_capture_header",
      captureId,
      timestamp: u32(payload, 4),
      sampleWidthBits: u16(payload, 8),
      sampleCount: u16(payload, 10),
      triggerIndex: u16(payload, 12),
      flags: u16(payload, 14),
      flagNames: laFlagNames(u16(payload, 14)),
      samplePeriodCycles: u32(payload, 16),
      channelCount: u16(payload, 20),
      reserved: u16(payload, 22),
    };
    const capture = laCapture(captureId);
    capture.header = header;
    capture.samples = new Array(header.sampleCount).fill(null);
    capture.complete = false;
    state.logicAnalyzer.latestCaptureId = captureId;
    state.logicAnalyzer.counters.headers += 1;
    addLog({
      timestamp: header.timestamp,
      type: TYPES[0x40],
      id: hex(captureId, 8),
      value: `${header.sampleWidthBits}b x ${header.sampleCount}`,
      text: `trigger @ ${header.triggerIndex}`,
    });
    requestRender(renderCounters);
  }

  function decodeLogicAnalyzerSampleData(payload) {
    if (payload.length !== 32) {
      recordLogicAnalyzerMalformed(0x41, payload.length, "bad sample data length");
      return;
    }

    const captureId = u32(payload, 0);
    const chunkIndex = u16(payload, 4);
    const firstSampleIndex = u16(payload, 6);
    const sampleBytes = payload[8];
    const sampleCount = payload[9];
    const flags = u16(payload, 10);
    if (![1, 2, 4].includes(sampleBytes) || sampleCount * sampleBytes > 20) {
      recordLogicAnalyzerMalformed(0x41, payload.length, "invalid sample packing");
      return;
    }

    const capture = laCapture(captureId);
    if (!capture.header) {
      capture.errors.push("missing_header");
    }
    if (capture.chunks.has(chunkIndex)) {
      capture.errors.push("overlap");
      state.logicAnalyzer.counters.droppedFrames += 1;
      requestRender(renderCounters);
      requestRender(renderLogicAnalyzer);
      return;
    }

    const previousIndexes = Array.from(capture.chunks.keys()).sort((a, b) => a - b);
    if (previousIndexes.length && chunkIndex < previousIndexes[previousIndexes.length - 1]) {
      state.logicAnalyzer.counters.outOfOrderChunks += 1;
    }
    if (previousIndexes.length && chunkIndex > previousIndexes[previousIndexes.length - 1] + 1) {
      const start = previousIndexes[previousIndexes.length - 1] + 1;
      const end = chunkIndex - 1;
      state.logicAnalyzer.counters.missingChunks += end - start + 1;
      capture.missingRanges.push([start, end]);
    }
    if (!previousIndexes.length && chunkIndex > 0) {
      state.logicAnalyzer.counters.missingChunks += chunkIndex;
      capture.missingRanges.push([0, chunkIndex - 1]);
    }

    const values = [];
    for (let index = 0; index < sampleCount; index += 1) {
      const offset = 12 + index * sampleBytes;
      let value = 0;
      for (let byteIndex = 0; byteIndex < sampleBytes; byteIndex += 1) {
        value |= payload[offset + byteIndex] << (8 * byteIndex);
      }
      value >>>= 0;
      values.push(value);
      const sampleIndex = firstSampleIndex + index;
      while (capture.samples.length <= sampleIndex) {
        capture.samples.push(null);
      }
      if (capture.samples[sampleIndex] !== null) {
        capture.errors.push("overlap");
        state.logicAnalyzer.counters.droppedFrames += 1;
      } else {
        capture.samples[sampleIndex] = value;
      }
    }

    const chunk = {
      kind: "la_sample",
      captureId,
      chunkIndex,
      firstSampleIndex,
      sampleBytes,
      sampleCount,
      flags,
      flagNames: laFlagNames(flags),
      values,
    };
    capture.chunks.set(chunkIndex, chunk);
    if (capture.header && capture.samples.slice(0, capture.header.sampleCount).every((sample) => sample !== null)) {
      capture.complete = true;
    }
    state.logicAnalyzer.latestCaptureId = captureId;
    state.logicAnalyzer.counters.samples += 1;
    addLog({
      timestamp: "-",
      type: TYPES[0x41],
      id: `${hex(captureId, 8)}#${chunkIndex}`,
      value: `${sampleCount} samples`,
      text: `first sample ${firstSampleIndex}`,
    });
    requestRender(renderCounters);
    requestRender(renderLogicAnalyzer);
  }

  function decodeLogicAnalyzerStatus(payload) {
    if (payload.length !== 20) {
      recordLogicAnalyzerMalformed(0x42, payload.length, "bad status length");
      return;
    }

    const captureId = u32(payload, 4);
    const status = {
      kind: "la_status",
      timestamp: u32(payload, 0),
      captureId,
      state: payload[8],
      error: payload[9],
      samplesWritten: u16(payload, 10),
      chunksSent: u16(payload, 12),
      chunksTotal: u16(payload, 14),
      statusFlags: u32(payload, 16),
    };
    laCapture(captureId).status = status;
    state.logicAnalyzer.latestCaptureId = captureId;
    state.logicAnalyzer.counters.statuses += 1;
    addLog({
      timestamp: status.timestamp,
      type: TYPES[0x42],
      id: hex(captureId, 8),
      value: `${status.chunksSent}/${status.chunksTotal}`,
      text: `state ${status.state} error ${status.error}`,
    });
    requestRender(renderCounters);
    requestRender(renderLogicAnalyzer);
  }

  function decodeLogicAnalyzerTriggerEvent(payload) {
    if (payload.length !== 20) {
      recordLogicAnalyzerMalformed(0x43, payload.length, "bad trigger event length");
      return;
    }

    const captureId = u32(payload, 4);
    const event = {
      kind: "la_trigger_event",
      timestamp: u32(payload, 0),
      captureId,
      triggerIndex: u16(payload, 8),
      triggerChannel: u16(payload, 10),
      sampleValue: u32(payload, 12),
      triggerValue: u32(payload, 16),
    };
    laCapture(captureId).triggerEvent = event;
    state.logicAnalyzer.latestCaptureId = captureId;
    state.logicAnalyzer.counters.triggerEvents += 1;
    addLog({
      timestamp: event.timestamp,
      type: TYPES[0x43],
      id: hex(captureId, 8),
      value: `${hex(event.sampleValue, 8)} vs ${hex(event.triggerValue, 8)}`,
      text: `trigger channel ${event.triggerChannel} @ ${event.triggerIndex}`,
    });
    requestRender(renderCounters);
    requestRender(renderLogicAnalyzer);
  }

  function recordLogicAnalyzerMalformed(type, length, reason) {
    state.logicAnalyzer.counters.malformed += 1;
    addLog({
      timestamp: "-",
      type: TYPES[type] || hex(type, 2),
      id: "-",
      value: length,
      text: `Malformed LA frame: ${reason}`,
    });
    requestRender(renderCounters);
    requestRender(renderLogicAnalyzer);
  }

  function decodeProfilerAlert(payload) {
    if (payload.length !== 16) {
      recordProfilerMalformed(0x31, payload.length, "bad alert length");
      return;
    }

    const timestamp = u32(payload, 0);
    const metricId = u16(payload, 4);
    const level = payload[6];
    const code = payload[7];
    const arg0 = u32(payload, 8);
    const arg1 = u32(payload, 12);
    const metric = profilerMetric(metricId);
    const record = {
      kind: "profiler_alert",
      timestamp,
      metricId,
      metricName: metric.name,
      metricType: metric.type,
      level,
      levelText: LEVELS[level] || `Level ${level}`,
      code,
      codeText: profilerAlertCode(code),
      arg0,
      arg1,
    };

    state.profiler.counters.alerts += 1;
    state.profiler.alerts.unshift(record);
    if (state.profiler.alerts.length > MAX_PROFILER_ALERTS) {
      state.profiler.alerts.pop();
    }

    addLog({
      timestamp,
      type: TYPES[0x31],
      id: hex(metricId, 4),
      value: `${hex(arg0, 8)}, ${hex(arg1, 8)}`,
      text: `${record.levelText} ${record.codeText} ${metric.name}`,
    });
    requestRender(renderProfiler);
  }

  function recordProfilerMalformed(type, length, reason) {
    state.profiler.counters.malformed += 1;
    addLog({
      timestamp: "-",
      type: TYPES[type] || hex(type, 2),
      id: "-",
      value: length,
      text: `Malformed profiler frame: ${reason}`,
    });
    requestRender(renderProfiler);
  }

  function monitorStatus(status) {
    return MONITOR_STATUS[status] || `STATUS_${status}`;
  }

  function monitorRegister(addr) {
    return state.monitor.registers.find((reg) => reg.addr === addr) || {
      addr,
      name: hex(addr, 4),
      access: "-",
      width: 4,
    };
  }

  function nextMonitorSeq() {
    const seq = state.monitor.seq;
    state.monitor.seq = seq === 0xFFFF ? 1 : seq + 1;
    return seq;
  }

  function encodeMonitorRead(addr, width = 4) {
    const seq = nextMonitorSeq();
    const payload = [];
    pushU16(payload, seq);
    pushU16(payload, addr);
    payload.push(width);
    const bytes = frame(0x20, payload);
    trackMonitorPending(seq, { op: "read", addr, width, bytes });
    return { seq, bytes };
  }

  function encodeMonitorWrite(addr, value, mask = 0xFFFFFFFF, width = 4) {
    const seq = nextMonitorSeq();
    const payload = [];
    pushU16(payload, seq);
    pushU16(payload, addr);
    payload.push(width);
    pushU32(payload, value >>> 0);
    pushU32(payload, mask >>> 0);
    const bytes = frame(0x22, payload);
    trackMonitorPending(seq, { op: "write", addr, width, value: value >>> 0, mask: mask >>> 0, bytes });
    return { seq, bytes };
  }

  function trackMonitorPending(seq, entry) {
    state.monitor.pending.set(seq, {
      seq,
      createdAt: Date.now(),
      timeoutAt: Date.now() + MONITOR_TIMEOUT_MS,
      ...entry,
    });
  }

  function decodeMonitorReadResponse(payload) {
    const timestamp = u32(payload, 0);
    const seq = u16(payload, 4);
    const addr = u16(payload, 6);
    const status = payload[8];
    const width = payload[9];
    const value = u32(payload, 10);
    const pending = state.monitor.pending.get(seq);
    state.monitor.pending.delete(seq);

    const record = {
      kind: "monitor_read",
      timestamp,
      seq,
      addr,
      status,
      statusText: monitorStatus(status),
      width,
      value,
      unknownSeq: !pending,
    };
    state.monitor.history.push(record);

    if (status === 0) {
      updateMonitorValue(addr, value, timestamp, status, width);
    }
    if (!pending || status !== 0) {
      addMonitorError(record);
    }
    addLog({
      timestamp,
      type: TYPES[0x21],
      id: `${hex(addr, 4)}#${seq}`,
      value: hex(value, 8),
      text: record.unknownSeq ? "read response with unknown seq" : `read ${monitorStatus(status)}`,
    });
    requestRender(renderMonitor);
  }

  function decodeMonitorWriteResponse(payload) {
    const timestamp = u32(payload, 0);
    const seq = u16(payload, 4);
    const addr = u16(payload, 6);
    const status = payload[8];
    const oldValue = u32(payload, 9);
    const newValue = u32(payload, 13);
    const pending = state.monitor.pending.get(seq);
    state.monitor.pending.delete(seq);

    const record = {
      kind: "monitor_write",
      timestamp,
      seq,
      addr,
      status,
      statusText: monitorStatus(status),
      oldValue,
      newValue,
      unknownSeq: !pending,
    };
    state.monitor.history.push(record);

    if (status === 0) {
      updateMonitorValue(addr, newValue, timestamp, status, pending ? pending.width : 4);
    }
    if (!pending || status !== 0) {
      addMonitorError(record);
    }
    addLog({
      timestamp,
      type: TYPES[0x23],
      id: `${hex(addr, 4)}#${seq}`,
      value: `${hex(oldValue, 8)} -> ${hex(newValue, 8)}`,
      text: record.unknownSeq ? "write response with unknown seq" : `write ${monitorStatus(status)}`,
    });
    requestRender(renderMonitor);
  }

  function updateMonitorValue(addr, value, timestamp, status, width) {
    const reg = monitorRegister(addr);
    state.monitor.values.set(addr, {
      ...reg,
      value,
      timestamp,
      status,
      statusText: monitorStatus(status),
      width,
    });
  }

  function addMonitorError(record) {
    state.monitor.errors.unshift({
      ...record,
      createdAt: Date.now(),
    });
    if (state.monitor.errors.length > 100) {
      state.monitor.errors.pop();
    }
    requestRender(renderMonitor);
  }

  function expireMonitorPending(now = Date.now()) {
    const expired = [];
    for (const [seq, pending] of state.monitor.pending.entries()) {
      if (pending.timeoutAt <= now) {
        state.monitor.pending.delete(seq);
        const record = {
          kind: "monitor_timeout",
          seq,
          addr: pending.addr,
          status: 6,
          statusText: monitorStatus(6),
          op: pending.op,
        };
        state.monitor.history.push(record);
        addMonitorError(record);
        expired.push(record);
      }
    }
    return expired;
  }

  function traceKey(traceId, instanceId) {
    return `${hex(traceId, 4)}:${hex(instanceId, 4)}`;
  }

  function traceStatus(status) {
    return TRACE_STATUS[status] || `STATUS_${status}`;
  }

  function traceName(traceId) {
    return TRACE_NAMES[traceId] || hex(traceId, 4);
  }

  function traceLaneValue(traceId) {
    return String(traceId);
  }

  function traceItemTime(item) {
    if (item.kind === "span") {
      return item.startTimestamp ?? item.endTimestamp;
    }
    return item.timestamp;
  }

  function traceItemEndTime(item) {
    if (item.kind === "span") {
      return item.endTimestamp ?? item.startTimestamp;
    }
    return item.timestamp;
  }

  function getTraceFilter() {
    const from = el.traceFrom.value === "" ? null : Number(el.traceFrom.value);
    const to = el.traceTo.value === "" ? null : Number(el.traceTo.value);
    return {
      lane: el.traceLaneFilter.value,
      status: el.traceStatusFilter.value,
      from: Number.isFinite(from) ? from : null,
      to: Number.isFinite(to) ? to : null,
    };
  }

  function traceMatchesFilter(item, filter) {
    if (filter.lane !== "all" && traceLaneValue(item.traceId) !== filter.lane) {
      return false;
    }
    if (item.kind === "span") {
      if (filter.status === "problem" && !isTraceProblem(item)) {
        return false;
      }
      if (/^\d+$/.test(filter.status) && String(item.status) !== filter.status) {
        return false;
      }
    } else if (item.kind === "drop" && filter.status === "problem") {
      // Keep trace drops in the problem filter, then apply the time window below.
    } else if (filter.status !== "all") {
      return false;
    }

    const start = traceItemTime(item);
    const end = traceItemEndTime(item);
    if (filter.from !== null && end < filter.from) {
      return false;
    }
    if (filter.to !== null && start > filter.to) {
      return false;
    }
    return true;
  }

  function isTraceProblem(span) {
    return span.orphan || span.status === 1 || span.status === 2 || span.status === 3;
  }

  function buildTraceItems() {
    const openSpans = Array.from(state.trace.openSpans.values()).map((span) => ({
      ...span,
      kind: "span",
      endTimestamp: span.startTimestamp,
      duration: null,
      status: null,
      endArg0: null,
      open: true,
      orphan: false,
    }));
    return [
      ...state.trace.spans.map((span) => ({ ...span, kind: "span" })),
      ...openSpans,
      ...state.trace.marks.map((mark) => ({ ...mark, kind: "mark" })),
      ...state.trace.drops.map((drop) => ({ ...drop, kind: "drop" })),
    ];
  }

  function updateTraceLaneOptions(items) {
    const lanes = Array.from(new Set(items.map((item) => item.traceId))).sort((a, b) => a - b);
    const current = el.traceLaneFilter.value;
    el.traceLaneFilter.innerHTML = [
      '<option value="all">All</option>',
      ...lanes.map((traceId) => `<option value="${traceLaneValue(traceId)}">${traceName(traceId)}</option>`),
    ].join("");
    el.traceLaneFilter.value = lanes.some((traceId) => traceLaneValue(traceId) === current) ? current : "all";
  }

  function renderTrace() {
    const allItems = buildTraceItems();
    updateTraceLaneOptions(allItems);

    const filter = getTraceFilter();
    let visibleItems = allItems.filter((item) => traceMatchesFilter(item, filter));
    const fullVisibleCount = visibleItems.length;
    if (filter.from === null && filter.to === null && visibleItems.length > MAX_TRACE_RENDER_ITEMS) {
      visibleItems = visibleItems
        .sort((a, b) => traceItemTime(a) - traceItemTime(b))
        .slice(-MAX_TRACE_RENDER_ITEMS);
    }
    const visibleSpans = visibleItems.filter((item) => item.kind === "span" && !item.open);
    const durations = visibleSpans.map((span) => span.duration).filter((duration) => duration !== null);
    const totalDuration = durations.reduce((sum, duration) => sum + duration, 0);
    const maxDuration = durations.length ? Math.max(...durations) : null;
    const problemCount = visibleSpans.filter(isTraceProblem).length + visibleItems.filter((item) => item.kind === "drop").length;

    const windowNote = fullVisibleCount > visibleItems.length ? `, showing latest ${visibleItems.length}` : "";
    el.traceSummary.textContent = `${state.trace.spans.length} spans, ${state.trace.marks.length} marks, ${state.trace.values.length} values${windowNote}`;
    el.traceSpanCount.textContent = visibleSpans.length;
    el.traceAverageDuration.textContent = durations.length ? Math.round(totalDuration / durations.length) : "-";
    el.traceMaxDuration.textContent = maxDuration === null ? "-" : maxDuration;
    el.traceProblemCount.textContent = problemCount;

    const timeBounds = visibleItems.reduce((bounds, item) => {
      const start = traceItemTime(item);
      const end = traceItemEndTime(item);
      return {
        min: Math.min(bounds.min, start),
        max: Math.max(bounds.max, end),
      };
    }, { min: Number.POSITIVE_INFINITY, max: Number.NEGATIVE_INFINITY });

    if (!visibleItems.length) {
      el.traceTimeline.innerHTML = '<div class="empty">No trace data matches the current filters.</div>';
      renderTraceValues();
      renderTraceDetail();
      return;
    }

    const minTime = timeBounds.min;
    const range = Math.max(1, timeBounds.max - minTime);
    const lanes = Array.from(new Set(visibleItems.map((item) => item.traceId))).sort((a, b) => a - b);
    el.traceTimeline.innerHTML = lanes.map((traceId) => {
      const laneItems = visibleItems
        .filter((item) => item.traceId === traceId)
        .sort((a, b) => traceItemTime(a) - traceItemTime(b));
      const itemHtml = laneItems.map((item) => traceItemHtml(item, minTime, range)).join("");
      return `
        <div class="trace-lane" role="listitem">
          <div class="trace-lane-name">${traceName(traceId)}</div>
          <div class="trace-lane-track">${itemHtml}</div>
        </div>
      `;
    }).join("");

    renderTraceValues();
    renderTraceDetail();
  }

  function traceItemHtml(item, minTime, range) {
    const start = traceItemTime(item);
    const end = traceItemEndTime(item);
    const left = ((start - minTime) / range) * 100;
    const width = item.kind === "span" ? Math.max(1.5, ((end - start) / range) * 100) : 0;
    const encoded = encodeURIComponent(JSON.stringify(traceSelectionPayload(item)));

    if (item.kind === "span") {
      const classes = ["trace-span"];
      if (item.open) classes.push("is-open");
      if (item.orphan) classes.push("is-orphan");
      if (isTraceProblem(item)) classes.push("is-problem");
      return `
        <button class="${classes.join(" ")}" type="button" data-trace="${encoded}"
          style="left:${left}%; width:${width}%"
          title="${traceName(item.traceId)} ${item.open ? "OPEN" : traceStatus(item.status)}">
          ${item.open ? "OPEN" : traceStatus(item.status)}
        </button>
      `;
    }

    if (item.kind === "drop") {
      return `
        <button class="trace-mark is-drop" type="button" data-trace="${encoded}"
          style="left:${left}%"
          title="${traceName(item.traceId)} drop ${item.dropCount}"></button>
      `;
    }

    return `
      <button class="trace-mark level-${item.level}" type="button" data-trace="${encoded}"
        style="left:${left}%"
        title="${traceName(item.traceId)} ${LEVELS[item.level] || item.level}"></button>
    `;
  }

  function traceSelectionPayload(item) {
    return {
      kind: item.kind,
      traceId: item.traceId,
      instanceId: item.instanceId,
      timestamp: item.timestamp,
      startTimestamp: item.startTimestamp,
      endTimestamp: item.endTimestamp,
      duration: item.duration,
      status: item.status,
      level: item.level,
      startArg0: item.startArg0,
      endArg0: item.endArg0,
      arg0: item.arg0,
      dropCount: item.dropCount,
      open: item.open,
      orphan: item.orphan,
    };
  }

  function renderTraceDetail() {
    const item = state.trace.selected;
    if (!item) {
      el.traceDetail.innerHTML = "<dt>Item</dt><dd>-</dd>";
      return;
    }

    const rows = [
      ["Kind", item.kind],
      ["Trace", traceName(item.traceId)],
    ];
    if (item.kind === "span") {
      rows.push(
        ["Instance", item.instanceId === undefined ? "-" : hex(item.instanceId, 4)],
        ["Start", item.startTimestamp ?? "-"],
        ["End", item.open ? "open" : item.endTimestamp ?? "-"],
        ["Duration", item.duration ?? "-"],
        ["Status", item.open ? "OPEN" : traceStatus(item.status)],
        ["Start Arg0", item.startArg0 === null || item.startArg0 === undefined ? "-" : hex(item.startArg0, 8)],
        ["End Arg0", item.endArg0 === null || item.endArg0 === undefined ? "-" : hex(item.endArg0, 8)],
        ["Orphan", item.orphan ? "yes" : "no"]
      );
    } else if (item.kind === "mark") {
      rows.push(
        ["Timestamp", item.timestamp],
        ["Level", LEVELS[item.level] || item.level],
        ["Arg0", hex(item.arg0, 8)]
      );
    } else if (item.kind === "drop") {
      rows.push(
        ["Timestamp", item.timestamp],
        ["Drop Count", item.dropCount]
      );
    }

    el.traceDetail.innerHTML = rows.map(([key, value]) => `<dt>${key}</dt><dd>${value}</dd>`).join("");
  }

  function renderTraceValues() {
    const rows = Array.from(state.trace.latestValues.values())
      .sort((a, b) => a.traceId - b.traceId || a.valueId - b.valueId);
    el.traceValueBody.innerHTML = rows.map((row) => `
      <tr>
        <td>${traceName(row.traceId)} / ${hex(row.valueId, 4)}</td>
        <td>${hex(row.value, 8)}</td>
        <td>${row.timestamp}</td>
      </tr>
    `).join("");
  }

  function beginTraceSpan(timestamp, traceId, instanceId, arg0) {
    state.trace.openSpans.set(traceKey(traceId, instanceId), {
      traceId,
      instanceId,
      startTimestamp: timestamp,
      startArg0: arg0,
    });
  }

  function endTraceSpan(timestamp, traceId, instanceId, status, arg0) {
    const key = traceKey(traceId, instanceId);
    const begin = state.trace.openSpans.get(key);
    const span = begin ? {
      traceId,
      instanceId,
      startTimestamp: begin.startTimestamp,
      endTimestamp: timestamp,
      // Protocol timestamps are unsigned 32-bit ticks and may wrap while a
      // span is open. Unsigned subtraction preserves the elapsed interval.
      duration: (timestamp - begin.startTimestamp) >>> 0,
      status,
      startArg0: begin.startArg0,
      endArg0: arg0,
      orphan: false,
    } : {
      traceId,
      instanceId,
      startTimestamp: null,
      endTimestamp: timestamp,
      duration: null,
      status,
      startArg0: null,
      endArg0: arg0,
      orphan: true,
    };

    if (begin) {
      state.trace.openSpans.delete(key);
    }
    state.trace.spans.push(span);
    pruneTraceHistory();
    return span;
  }

  function updateTraceValue(timestamp, traceId, valueId, value) {
    const row = { timestamp, traceId, valueId, value };
    state.trace.values.push(row);
    state.trace.latestValues.set(`${hex(traceId, 4)}:${hex(valueId, 4)}`, row);
    pruneTraceHistory();
  }

  function pruneTraceHistory() {
    if (state.trace.spans.length > MAX_TRACE_SPANS) {
      state.trace.spans.splice(0, state.trace.spans.length - MAX_TRACE_SPANS);
    }
    if (state.trace.marks.length > MAX_TRACE_MARKS) {
      state.trace.marks.splice(0, state.trace.marks.length - MAX_TRACE_MARKS);
    }
    if (state.trace.values.length > MAX_TRACE_VALUES) {
      state.trace.values.splice(0, state.trace.values.length - MAX_TRACE_VALUES);
    }
    if (state.trace.drops.length > MAX_TRACE_DROPS) {
      state.trace.drops.splice(0, state.trace.drops.length - MAX_TRACE_DROPS);
    }
  }

  function addLog(row) {
    state.logs.unshift(row);
    if (state.logs.length > 300) {
      state.logs.pop();
    }
    requestRender(renderLog);
  }

  function updateWatch(id, value, timestamp) {
    const prev = state.watches.get(id);
    state.watches.set(id, {
      id,
      value,
      timestamp,
      updates: prev ? prev.updates + 1 : 1,
    });
    requestRender(renderWatch);
  }

  function updateEvent(id, level, arg0) {
    const prev = state.events.get(id);
    state.events.set(id, {
      id,
      level,
      arg0,
      count: prev ? prev.count + 1 : 1,
    });
    requestRender(renderEvents);
  }

  function requestRender(renderFn) {
    if (!state.paused) {
      state.render.pending.add(renderFn);
      if (!state.render.scheduled) {
        state.render.scheduled = true;
        window.requestAnimationFrame(flushRender);
      }
    }
  }

  function flushRender() {
    const pending = Array.from(state.render.pending);
    state.render.pending.clear();
    state.render.scheduled = false;
    pending.forEach((renderFn) => renderFn());
  }

  function renderAll() {
    renderCounters();
    renderLog();
    renderWatch();
    renderEvents();
    renderStatus();
    renderTrace();
    renderMonitor();
    renderProfiler();
    renderLogicAnalyzer();
  }

  function renderCounters() {
    el.frameCount.textContent = state.frames;
    el.checksumErrors.textContent = state.checksumErrors;
    el.syncDrops.textContent = state.syncDrops;
    el.unknownFrames.textContent = state.unknownFrames;
  }

  function renderLog() {
    el.logCount.textContent = state.logs.length;
    el.logBody.innerHTML = state.logs.map((row) => `
      <tr>
        <td>${row.timestamp}</td>
        <td>${row.type}</td>
        <td>${row.id}</td>
        <td>${row.value}</td>
        <td>${row.text}</td>
      </tr>
    `).join("");
  }

  function renderWatch() {
    const rows = Array.from(state.watches.values()).sort((a, b) => a.id - b.id);
    el.watchCount.textContent = rows.length;
    el.watchBody.innerHTML = rows.map((row) => `
      <tr>
        <td>${hex(row.id, 4)}</td>
        <td>${hex(row.value, 8)}</td>
        <td>${row.timestamp}</td>
        <td>${row.updates}</td>
      </tr>
    `).join("");
  }

  function renderEvents() {
    const rows = Array.from(state.events.values()).sort((a, b) => a.id - b.id);
    el.eventCount.textContent = rows.length;
    el.eventBody.innerHTML = rows.map((row) => `
      <tr>
        <td>${hex(row.id, 4)}</td>
        <td class="level-${row.level}">${LEVELS[row.level] || row.level}</td>
        <td>${hex(row.arg0, 8)}</td>
        <td>${row.count}</td>
      </tr>
    `).join("");
  }

  function renderStatus() {
    el.bufferUsed.textContent = state.status.bufferUsed;
    el.dropCount.textContent = state.status.dropCount;
    el.packetCount.textContent = state.status.packetCount;
    el.lastTimestamp.textContent = state.status.lastTimestamp;
    const dropCount = Number(state.status.dropCount);
    el.dropCount.classList.toggle("status-warn", Number.isFinite(dropCount) && dropCount > 0);
  }

  function profilerMetricRows() {
    const ids = new Set([...state.profiler.metrics.keys(), ...state.profiler.latest.keys()]);
    return Array.from(ids).map((id) => ({
      metric: profilerMetric(id),
      latest: state.profiler.latest.get(id),
      history: state.profiler.history.get(id) || [],
    })).sort((a, b) => a.metric.id - b.metric.id);
  }

  function profilerValue(record, index) {
    return record ? record[`value${index}`] : "-";
  }

  function profilerMainValue(row) {
    if (!row.latest) {
      return "-";
    }
    return profilerValue(row.latest, 0);
  }

  function profilerStatsText(row) {
    if (!row.latest) {
      return "-";
    }
    if (row.metric.type === "Latency") {
      return `${row.latest.value1}/${row.latest.value2}/${row.latest.value3}`;
    }
    if (row.metric.type === "FIFO") {
      return `${row.latest.value2}/${row.latest.value1}/-`;
    }
    if (row.metric.type === "Frame Rate") {
      return `${row.latest.value2}/${row.latest.value3}/-`;
    }
    return `-/-/-`;
  }

  function renderProfiler() {
    const rows = profilerMetricRows();
    const counters = state.profiler.counters;
    el.profilerSummary.textContent =
      `${counters.snapshots} snapshots, ${counters.alerts} alerts, ${counters.malformed} malformed`;

    const selectedExists = rows.some((row) => row.metric.id === state.profiler.selectedMetricId);
    if (!selectedExists && rows.length) {
      state.profiler.selectedMetricId = rows[0].metric.id;
    }

    el.profilerMetricSelect.innerHTML = rows.map((row) => {
      const selected = row.metric.id === state.profiler.selectedMetricId ? " selected" : "";
      return `<option value="${row.metric.id}"${selected}>${row.metric.name} (${hex(row.metric.id, 4)})</option>`;
    }).join("");

    const selectedMetric = profilerMetric(state.profiler.selectedMetricId);
    el.profilerValueSelect.innerHTML = selectedMetric.fields.map((field, index) => {
      const selected = index === state.profiler.selectedValueIndex ? " selected" : "";
      return `<option value="${index}"${selected}>${field}</option>`;
    }).join("");

    el.profilerCards.innerHTML = rows.map((row) => {
      const latest = row.latest;
      const flags = latest ? latest.flagNames.join(", ") || "-" : "-";
      const isAlert = latest && ((latest.flags & PROFILER_FLAGS.ALERT) !== 0 || latest.overflowCount > 0);
      const isBad = latest && ((latest.flags & PROFILER_FLAGS.SATURATED) !== 0 || latest.overflowCount > 0);
      return `
        <div class="profiler-card ${isAlert ? "is-alert" : ""} ${isBad ? "is-bad" : ""}">
          <strong title="${row.metric.name}">${row.metric.name}</strong>
          <span class="profiler-primary">${profilerMainValue(row)}</span>
          <dl>
            <dt>Type</dt><dd>${row.metric.type}</dd>
            <dt>Window</dt><dd>${latest ? latest.sampleCycles : "-"}</dd>
            <dt>Flags</dt><dd title="${flags}">${flags}</dd>
            <dt>History</dt><dd>${row.history.length}</dd>
          </dl>
        </div>
      `;
    }).join("");

    el.profilerTableBody.innerHTML = rows.map((row) => {
      const latest = row.latest;
      const flags = latest ? latest.flagNames.join("|") || "-" : "-";
      const latestText = latest ? `${row.metric.fields[0]}=${latest.value0}` : "-";
      return `
        <tr>
          <td>${row.metric.name} ${hex(row.metric.id, 4)}</td>
          <td>${row.metric.type}</td>
          <td>${latestText}</td>
          <td>${latest ? latest.sampleCycles : "-"}</td>
          <td>${profilerStatsText(row)}</td>
          <td>${flags}</td>
          <td>${latest ? latest.timestamp : "-"}</td>
        </tr>
      `;
    }).join("");

    const alertFilter = state.profiler.alertFilter;
    const alerts = state.profiler.alerts.filter((row) => alertFilter === "all" || String(row.level) === alertFilter);
    el.profilerAlerts.innerHTML = alerts.length ? alerts.slice(0, 12).map((row) => `
      <div>
        <strong class="level-${row.level}">${row.levelText} ${row.codeText}</strong>
        <span>${row.metricName} ${hex(row.metricId, 4)} @ ${row.timestamp}</span>
        <span>${hex(row.arg0, 8)} / ${hex(row.arg1, 8)}</span>
      </div>
    `).join("") : '<div class="empty">No Profiler alerts.</div>';

    drawProfilerTrend();
  }

  function drawProfilerTrend() {
    const canvas = el.profilerTrendCanvas;
    const context = canvas.getContext("2d");
    const ratio = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(320, Math.floor(rect.width));
    const height = Math.max(180, Math.floor(rect.height));
    if (canvas.width !== width * ratio || canvas.height !== height * ratio) {
      canvas.width = width * ratio;
      canvas.height = height * ratio;
    }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);
    context.fillStyle = "#fbfcfe";
    context.fillRect(0, 0, width, height);

    const metricId = state.profiler.selectedMetricId;
    const history = (state.profiler.history.get(metricId) || []).slice(-120);
    const metric = profilerMetric(metricId);
    const valueIndex = state.profiler.selectedValueIndex;
    context.strokeStyle = "#d9dee7";
    context.lineWidth = 1;
    for (let i = 0; i < 5; i += 1) {
      const y = 28 + ((height - 56) * i) / 4;
      context.beginPath();
      context.moveTo(16, y);
      context.lineTo(width - 16, y);
      context.stroke();
    }
    context.fillStyle = "#667085";
    context.font = "12px Segoe UI, Arial, sans-serif";
    context.fillText(`${metric.name} ${metric.fields[valueIndex] || `value${valueIndex}`}`, 16, 18);
    if (!history.length) {
      context.fillText("No snapshot history.", 16, height / 2);
      return;
    }

    const values = history.map((row) => Number(profilerValue(row, valueIndex)));
    const min = Math.min(...values);
    const max = Math.max(...values);
    const span = Math.max(1, max - min);
    context.fillText(`min ${min} / max ${max}`, width - 150, 18);
    context.strokeStyle = "#1769aa";
    context.lineWidth = 2;
    context.beginPath();
    values.forEach((value, index) => {
      const x = 16 + ((width - 32) * index) / Math.max(1, values.length - 1);
      const y = height - 28 - ((height - 56) * (value - min)) / span;
      if (index === 0) {
        context.moveTo(x, y);
      } else {
        context.lineTo(x, y);
      }
    });
    context.stroke();
  }

  function renderMonitor() {
    el.monitorSummary.textContent =
      `${state.monitor.registers.length} registers, ${state.monitor.pending.size} pending`;
    const pendingByAddr = new Map();
    for (const pending of state.monitor.pending.values()) {
      pendingByAddr.set(pending.addr, pending);
    }

    el.monitorBody.innerHTML = state.monitor.registers.map((reg) => {
      const row = state.monitor.values.get(reg.addr);
      const pending = pendingByAddr.get(reg.addr);
      const canWrite = reg.access === "RW" || reg.access === "W1C";
      const canTrigger = reg.access === "TRIGGER";
      const valueText = row ? hex(row.value, 8) : "-";
      const updatedText = row ? row.timestamp : "-";
      const statusText = pending ? "PENDING" : row ? row.statusText : "-";
      const writeControls = canWrite ? `
        <input class="monitor-value" data-monitor-value="${reg.addr}" value="${valueText === "-" ? "0x00000000" : valueText}" aria-label="${reg.name} value">
        <input class="monitor-mask" data-monitor-mask="${reg.addr}" value="0xFFFFFFFF" aria-label="${reg.name} mask">
        <button type="button" data-monitor-write="${reg.addr}">Write</button>
      ` : "";
      const triggerControl = canTrigger ? `<button type="button" data-monitor-trigger="${reg.addr}">Trigger</button>` : "";
      return `
        <tr class="${pending ? "is-pending" : ""}">
          <td>${hex(reg.addr, 4)}</td>
          <td>${reg.name}</td>
          <td>${reg.access}</td>
          <td>${valueText}</td>
          <td>${updatedText}</td>
          <td>${statusText}</td>
          <td class="monitor-actions">
            <button type="button" data-monitor-read="${reg.addr}">Read</button>
            ${writeControls}
            ${triggerControl}
          </td>
        </tr>
      `;
    }).join("");

    el.monitorErrors.innerHTML = state.monitor.errors.length ? state.monitor.errors.slice(0, 8).map((row) => {
      const addr = row.addr === undefined ? "-" : hex(row.addr, 4);
      const seq = row.seq === undefined ? "-" : row.seq;
      return `<div><strong>${row.statusText || row.kind}</strong><span>${addr} #${seq}</span></div>`;
    }).join("") : '<div class="empty">No Monitor errors.</div>';
  }

  function latestLogicAnalyzerCapture() {
    if (state.logicAnalyzer.latestCaptureId === null) {
      return null;
    }
    return state.logicAnalyzer.captures.get(state.logicAnalyzer.latestCaptureId) || null;
  }

  function laSampleCount(capture) {
    return capture && capture.header ? capture.header.sampleCount : capture ? capture.samples.length : 0;
  }

  function laStatusText(status) {
    if (!status) {
      return "-";
    }
    return LA_STATES[status.state] || `STATE_${status.state}`;
  }

  function laChannelValue(channel, sample) {
    if (sample === null || sample === undefined) {
      return null;
    }
    if (channel.width === 1) {
      return (sample >>> channel.bit) & 1;
    }
    const mask = channel.width >= 32 ? 0xFFFFFFFF : (1 << channel.width) - 1;
    return (sample >>> channel.bit) & mask;
  }

  function renderLogicAnalyzer() {
    const capture = latestLogicAnalyzerCapture();
    const counters = state.logicAnalyzer.counters;
    const sampleCount = laSampleCount(capture);
    const header = capture ? capture.header : null;
    const status = capture ? capture.status : null;
    const triggerIndex = capture && capture.triggerEvent ? capture.triggerEvent.triggerIndex : header ? header.triggerIndex : 0;
    const chunksSent = status ? status.chunksSent : capture ? capture.chunks.size : 0;
    const chunksTotal = status ? status.chunksTotal : capture ? capture.chunks.size : 0;

    el.laSummary.textContent = capture
      ? `${hex(state.logicAnalyzer.latestCaptureId, 8)} ${sampleCount} samples, trigger ${triggerIndex}`
      : "No capture";
    el.laCaptureId.textContent = capture ? hex(state.logicAnalyzer.latestCaptureId, 8) : "-";
    el.laState.textContent = laStatusText(status);
    el.laSamples.textContent = sampleCount;
    el.laChunks.textContent = `${chunksSent}/${chunksTotal}`;
    el.laParserHealth.textContent = counters.malformed;
    el.laParserHealth.classList.toggle("status-warn", counters.malformed > 0 || counters.missingChunks > 0 || counters.droppedFrames > 0);

    const viewport = state.logicAnalyzer.viewport;
    viewport.startSample = Math.max(0, Math.min(viewport.startSample, Math.max(0, sampleCount - 1)));
    viewport.samplesPerPixel = Math.max(1, viewport.samplesPerPixel);
    viewport.cursorA = Math.max(0, Math.min(viewport.cursorA, Math.max(0, sampleCount - 1)));
    viewport.cursorB = Math.max(0, Math.min(viewport.cursorB, Math.max(0, sampleCount - 1)));
    el.laViewportStart.value = viewport.startSample;
    el.laSamplesPerPixel.value = viewport.samplesPerPixel;
    el.laCursorA.value = viewport.cursorA;
    el.laCursorB.value = viewport.cursorB;
    const deltaSamples = Math.abs(viewport.cursorB - viewport.cursorA);
    const period = header ? header.samplePeriodCycles : state.logicAnalyzer.config.sampleDivisor;
    el.laCursorDelta.textContent = `Delta ${deltaSamples} samples / ${deltaSamples * period} cycles`;

    el.laChannelList.innerHTML = state.logicAnalyzer.manifest.map((channel, index) => {
      const latestSample = capture ? capture.samples[Math.min(viewport.cursorA, Math.max(0, sampleCount - 1))] : null;
      const value = laChannelValue(channel, latestSample);
      const valueText = value === null ? "-" : channel.width === 1 ? value : hex(value, Math.ceil(channel.width / 4));
      const checked = channel.visible ? " checked" : "";
      return `
        <label class="la-channel">
          <input type="checkbox" data-la-channel="${index}"${checked}>
          <span class="la-swatch" style="background:${channel.color}"></span>
          <span class="la-channel-name">${channel.name}</span>
          <span class="la-channel-bit">${channel.width === 1 ? channel.bit : `${channel.bit + channel.width - 1}:${channel.bit}`}</span>
          <strong>${valueText}</strong>
        </label>
      `;
    }).join("");

    const errors = [];
    if (capture) {
      errors.push(...capture.errors);
      errors.push(...capture.missingRanges.map((range) => `missing chunk ${range[0]}..${range[1]}`));
      if (header && (header.flags & LA_FLAGS.OVERFLOW) !== 0) {
        errors.push("header overflow");
      }
      if (header && (header.flags & LA_FLAGS.PARTIAL) !== 0) {
        errors.push("partial capture");
      }
      if (status && (status.statusFlags & LA_FLAGS.OVERFLOW) !== 0) {
        errors.push("status overflow");
      }
    }
    if (counters.malformed > 0) {
      errors.push(`${counters.malformed} malformed frame(s)`);
    }
    el.laErrors.innerHTML = errors.length ? errors.map((error) => `<span>${error}</span>`).join("") : "<span>OK</span>";

    drawLogicAnalyzerWaveform(capture);
  }

  function drawLogicAnalyzerWaveform(capture) {
    const canvas = el.laWaveCanvas;
    const context = canvas.getContext("2d");
    const ratio = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(420, Math.floor(rect.width));
    const height = Math.max(260, Math.floor(rect.height));
    if (canvas.width !== width * ratio || canvas.height !== height * ratio) {
      canvas.width = width * ratio;
      canvas.height = height * ratio;
    }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);
    context.fillStyle = "#fbfcfe";
    context.fillRect(0, 0, width, height);
    context.font = "12px Segoe UI, Arial, sans-serif";

    const channels = state.logicAnalyzer.manifest.filter((channel) => channel.visible);
    if (!capture || !capture.samples.length || !channels.length) {
      context.fillStyle = "#667085";
      context.fillText("No Logic Analyzer capture.", 16, 28);
      return;
    }

    const header = capture.header;
    const viewport = state.logicAnalyzer.viewport;
    const sampleCount = laSampleCount(capture);
    const left = 16;
    const right = width - 16;
    const top = 20;
    const laneHeight = 34;
    const visibleWidth = right - left;
    const visibleSamples = Math.max(1, Math.floor(visibleWidth * viewport.samplesPerPixel));
    const endSample = Math.min(sampleCount, viewport.startSample + visibleSamples);
    const triggerIndex = capture.triggerEvent ? capture.triggerEvent.triggerIndex : header ? header.triggerIndex : -1;

    context.strokeStyle = "#edf0f4";
    context.lineWidth = 1;
    for (let x = left; x <= right; x += Math.max(40, visibleWidth / 8)) {
      context.beginPath();
      context.moveTo(x, top - 8);
      context.lineTo(x, height - 18);
      context.stroke();
    }
    context.fillStyle = "#667085";
    context.fillText(`${viewport.startSample}`, left, height - 6);
    context.fillText(`${Math.max(viewport.startSample, endSample - 1)}`, right - 54, height - 6);

    channels.forEach((channel, laneIndex) => {
      const y = top + laneIndex * laneHeight;
      if (y + laneHeight > height - 18) {
        return;
      }
      context.strokeStyle = "#e5e9f0";
      context.beginPath();
      context.moveTo(left, y + laneHeight - 6);
      context.lineTo(right, y + laneHeight - 6);
      context.stroke();

      context.strokeStyle = channel.color;
      context.fillStyle = channel.color;
      context.lineWidth = 2;
      if (channel.width === 1) {
        context.beginPath();
        let started = false;
        let previousY = null;
        for (let sampleIndex = viewport.startSample; sampleIndex < endSample; sampleIndex += 1) {
          const x = left + (sampleIndex - viewport.startSample) / viewport.samplesPerPixel;
          const value = laChannelValue(channel, capture.samples[sampleIndex]);
          const sampleY = value ? y + 6 : y + laneHeight - 10;
          if (value === null) {
            continue;
          }
          if (!started) {
            context.moveTo(x, sampleY);
            started = true;
          } else {
            context.lineTo(x, previousY);
            context.lineTo(x, sampleY);
          }
          previousY = sampleY;
        }
        if (started) {
          context.lineTo(left + Math.max(0, endSample - viewport.startSample - 1) / viewport.samplesPerPixel, previousY);
          context.stroke();
        }
      } else {
        let lastText = null;
        for (let sampleIndex = viewport.startSample; sampleIndex < endSample; sampleIndex += Math.max(1, Math.floor(18 * viewport.samplesPerPixel))) {
          const value = laChannelValue(channel, capture.samples[sampleIndex]);
          if (value === null) {
            continue;
          }
          const text = hex(value, Math.ceil(channel.width / 4));
          const x = left + (sampleIndex - viewport.startSample) / viewport.samplesPerPixel;
          if (text !== lastText) {
            context.fillText(text, x, y + 20);
            lastText = text;
          }
        }
      }
    });

    function marker(sample, color, label) {
      if (sample < viewport.startSample || sample >= endSample) {
        return;
      }
      const x = left + (sample - viewport.startSample) / viewport.samplesPerPixel;
      context.strokeStyle = color;
      context.lineWidth = 1.5;
      context.beginPath();
      context.moveTo(x, top - 10);
      context.lineTo(x, height - 18);
      context.stroke();
      context.fillStyle = color;
      context.fillText(label, x + 4, top + 10);
    }

    marker(triggerIndex, "#b42318", "T");
    marker(viewport.cursorA, "#111827", "A");
    marker(viewport.cursorB, "#7c3aed", "B");
  }

  function parseNumber(text) {
    const value = String(text).trim();
    if (/^0x/i.test(value)) {
      return Number.parseInt(value, 16) >>> 0;
    }
    return Number.parseInt(value, 10) >>> 0;
  }

  let monitorWriteQueue = Promise.resolve();

  async function sendMonitorBytesNow(bytes) {
    if (state.sourceType === "jtag") {
      addMonitorError({ kind: "monitor_error", statusText: "UNSUPPORTED", text: "JTAG Transport v1 is receive-only; use Serial for Monitor commands" });
      return false;
    }
    if (!state.port || !state.port.writable) {
      addMonitorError({ kind: "monitor_error", statusText: "DISCONNECTED", text: "Serial port is not writable" });
      return false;
    }
    const writer = state.port.writable.getWriter();
    try {
      await writer.write(new Uint8Array(bytes));
      return true;
    } catch (error) {
      addMonitorError({ kind: "monitor_error", statusText: "WRITE_FAILED", text: error.message });
      return false;
    } finally {
      writer.releaseLock();
    }
  }

  function sendMonitorBytes(bytes) {
    const write = monitorWriteQueue.then(() => sendMonitorBytesNow(bytes));
    monitorWriteQueue = write.catch(() => false);
    return write;
  }

  async function monitorRead(addr) {
    const reg = monitorRegister(addr);
    const request = encodeMonitorRead(addr, reg.width || 4);
    if (await sendMonitorBytes(request.bytes)) {
      addLog({ timestamp: "-", type: "MONITOR_READ_REQ", id: `${hex(addr, 4)}#${request.seq}`, value: "-", text: "read request" });
    }
    requestRender(renderMonitor);
  }

  async function monitorWrite(addr, value, mask) {
    const reg = monitorRegister(addr);
    const request = encodeMonitorWrite(addr, value, mask, reg.width || 4);
    if (await sendMonitorBytes(request.bytes)) {
      addLog({ timestamp: "-", type: "MONITOR_WRITE_REQ", id: `${hex(addr, 4)}#${request.seq}`, value: `${hex(value, 8)} mask ${hex(mask, 8)}`, text: "write request" });
    }
    requestRender(renderMonitor);
  }

  function monitorReadAll() {
    state.monitor.registers.forEach((reg) => monitorRead(reg.addr));
  }

  function profilerSetEnabled(enabled) {
    monitorWrite(0x0048, enabled ? 1 : 0, 0x00000001);
  }

  function profilerApplyPeriod() {
    const period = Math.max(1, parseNumber(el.profilerPeriodInput.value));
    el.profilerPeriodInput.value = period;
    monitorWrite(0x004C, period, 0xFFFFFFFF);
  }

  function profilerClearHardware() {
    monitorWrite(0x0050, 1, 0xFFFFFFFF);
  }

  async function applyLogicAnalyzerConfig() {
    const config = state.logicAnalyzer.config;
    config.sampleDivisor = Math.max(1, Math.min(0xFFFF, parseNumber(el.laSampleDivisor.value)));
    config.captureDepth = Math.max(1, parseNumber(el.laCaptureDepth.value));
    config.pretriggerDepth = Math.max(0, parseNumber(el.laPretriggerDepth.value));
    config.triggerMode = Math.max(0, Math.min(4, parseNumber(el.laTriggerMode.value)));
    config.triggerChannel = Math.max(0, Math.min(31, parseNumber(el.laTriggerChannel.value)));
    config.triggerValue = parseNumber(el.laTriggerValue.value);
    config.triggerMask = parseNumber(el.laTriggerMask.value);
    config.channelMask = state.logicAnalyzer.manifest.reduce((mask, channel) => (
      channel.visible ? (mask | (((channel.width >= 32 ? 0xFFFFFFFF : (1 << channel.width) - 1) << channel.bit) >>> 0)) : mask
    ), 0) >>> 0;

    el.laSampleDivisor.value = config.sampleDivisor;
    el.laCaptureDepth.value = config.captureDepth;
    el.laPretriggerDepth.value = config.pretriggerDepth;
    el.laTriggerMode.value = config.triggerMode;
    el.laTriggerChannel.value = config.triggerChannel;
    el.laTriggerValue.value = hex(config.triggerValue, 8);
    el.laTriggerMask.value = hex(config.triggerMask, 8);

    const control = 0x1 | (config.triggerMode === 0 ? 0 : 0x4);
    await monitorWrite(0x0068, control, 0xFFFFFFFF);
    await monitorWrite(0x0070, config.sampleDivisor, 0xFFFFFFFF);
    await monitorWrite(0x0074, config.captureDepth, 0xFFFFFFFF);
    await monitorWrite(0x0078, config.pretriggerDepth, 0xFFFFFFFF);
    await monitorWrite(0x007C, config.triggerMode, 0xFFFFFFFF);
    await monitorWrite(0x0080, config.triggerChannel, 0xFFFFFFFF);
    await monitorWrite(0x0084, config.triggerValue, 0xFFFFFFFF);
    await monitorWrite(0x0088, config.triggerMask, 0xFFFFFFFF);
    await monitorWrite(0x0094, config.channelMask, 0xFFFFFFFF);
    requestRender(renderLogicAnalyzer);
  }

  function logicAnalyzerCommand(command) {
    monitorWrite(0x008C, command, 0xFFFFFFFF);
  }

  function setLogicAnalyzerViewportFromInputs() {
    const viewport = state.logicAnalyzer.viewport;
    viewport.startSample = Math.max(0, parseNumber(el.laViewportStart.value));
    viewport.samplesPerPixel = Math.max(1, parseNumber(el.laSamplesPerPixel.value));
    viewport.cursorA = Math.max(0, parseNumber(el.laCursorA.value));
    viewport.cursorB = Math.max(0, parseNumber(el.laCursorB.value));
    requestRender(renderLogicAnalyzer);
  }

  function zoomLogicAnalyzer(factor) {
    const viewport = state.logicAnalyzer.viewport;
    viewport.samplesPerPixel = Math.max(1, Math.round(viewport.samplesPerPixel * factor));
    requestRender(renderLogicAnalyzer);
  }

  function exportLogicAnalyzerVcd() {
    const capture = latestLogicAnalyzerCapture();
    if (!capture || !capture.samples.length) {
      downloadText(`yifpga-la-empty-${Date.now()}.vcd`, "text/plain;charset=utf-8", "$date\n  no capture\n$end\n");
      return;
    }
    const symbols = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()[]{}";
    const channels = state.logicAnalyzer.manifest.filter((channel) => channel.visible);
    const header = capture.header;
    const triggerIndex = capture.triggerEvent ? capture.triggerEvent.triggerIndex : header ? header.triggerIndex : -1;
    const lines = [
      "$date",
      `  ${new Date().toISOString()}`,
      "$end",
      "$version",
      "  YiFPGA Studio Web Viewer Logic Analyzer",
      "$end",
      "$timescale 1ns $end",
      "$scope module yifpga_la $end",
    ];
    channels.forEach((channel, index) => {
      const symbol = symbols[index] || `s${index}`;
      channel.vcdSymbol = symbol;
      lines.push(`$var wire ${channel.width} ${symbol} ${channel.name} $end`);
    });
    lines.push("$var wire 1 ~ trigger_marker $end", "$upscope $end", "$enddefinitions $end", "#0", "0~");
    for (let sampleIndex = 0; sampleIndex < capture.samples.length; sampleIndex += 1) {
      const sample = capture.samples[sampleIndex];
      if (sample === null || sample === undefined) {
        continue;
      }
      lines.push(`#${sampleIndex}`);
      channels.forEach((channel) => {
        const value = laChannelValue(channel, sample);
        if (channel.width === 1) {
          lines.push(`${value ? 1 : 0}${channel.vcdSymbol}`);
        } else {
          lines.push(`b${value.toString(2).padStart(channel.width, "0")} ${channel.vcdSymbol}`);
        }
      });
      if (sampleIndex === triggerIndex) {
        lines.push("1~");
      } else if (sampleIndex === triggerIndex + 1) {
        lines.push("0~");
      }
    }
    channels.forEach((channel) => {
      delete channel.vcdSymbol;
    });
    downloadText(`yifpga-la-${header ? hex(header.captureId, 8) : "capture"}-${Date.now()}.vcd`, "text/plain;charset=utf-8", lines.join("\n") + "\n");
  }

  async function connect() {
    state.sourceType = el.sourceType.value;
    if (state.sourceType === "jtag") {
      connectJtag();
      return;
    }
    if (!hasSerial()) {
      alert("This browser does not support Web Serial. Use Chrome or Edge.");
      return;
    }

    state.port = await navigator.serial.requestPort();
    await state.port.open({ baudRate: Number(el.baudRate.value) });
    state.reader = state.port.readable.getReader();
    state.readLoopActive = true;
    setConnected(true);
    readLoop();
  }

  function mergeBytes(first, second) {
    const merged = new Uint8Array(first.length + second.length);
    merged.set(first);
    merged.set(second, first.length);
    return merged;
  }

  function consumeBridgeBytes(bytes) {
    state.transport.recordRx = mergeBytes(state.transport.recordRx, bytes);
    let offset = 0;
    const view = new DataView(state.transport.recordRx.buffer, state.transport.recordRx.byteOffset);
    while (state.transport.recordRx.length - offset >= 5) {
      const kind = state.transport.recordRx[offset];
      const length = view.getUint32(offset + 1, true);
      if (length > BRIDGE_MAX_RECORD) {
        throw new Error("Bridge record exceeds maximum size");
      }
      if (state.transport.recordRx.length - offset < 5 + length) break;
      const payload = state.transport.recordRx.slice(offset + 5, offset + 5 + length);
      consumeBridgeRecord(kind, payload);
      offset += 5 + length;
    }
    state.transport.recordRx = state.transport.recordRx.slice(offset);
  }

  function bridgeJson(payload) {
    return JSON.parse(new TextDecoder().decode(payload));
  }

  function consumeBridgeRecord(kind, payload) {
    if (kind === BRIDGE_TYPES.DATA) {
      appendRxBytes(payload);
      parseAvailableFrames();
      return;
    }
    if (kind === BRIDGE_TYPES.HELLO) {
      const value = bridgeJson(payload);
      state.transport.hello = value;
      if (state.transport.sessionId !== null && state.transport.sessionId !== value.session_id) state.rx = [];
      state.transport.sessionId = value.session_id;
    } else if (kind === BRIDGE_TYPES.STATUS) {
      const value = bridgeJson(payload);
      const now = performance.now();
      if (state.transport.lastStatusAt) {
        const elapsed = (now - state.transport.lastStatusAt) / 1000;
        state.transport.currentBps = Math.max(0, value.payload_bytes - state.transport.lastStatusBytes) / Math.max(elapsed, 0.001);
      }
      state.transport.lastStatusAt = now;
      state.transport.lastStatusBytes = value.payload_bytes || 0;
      state.transport.status = value;
    } else if (kind === BRIDGE_TYPES.SESSION) {
      const value = bridgeJson(payload);
      state.rx = [];
      state.transport.sessionId = value.new;
      addLog({ timestamp: "-", type: "SESSION", id: String(value.new), value: "-", text: "Parser resynchronized at next SOF" });
    } else if (kind === BRIDGE_TYPES.ERROR) {
      const value = bridgeJson(payload);
      state.transport.status = { ...(state.transport.status || {}), last_error: value.message || JSON.stringify(value) };
    }
    renderTransport();
  }

  function connectJtag() {
    const host = el.bridgeHost.value.trim() || "127.0.0.1";
    const port = Number(el.bridgePort.value);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      alert("Bridge port must be in 1..65535.");
      return;
    }
    state.transport.recordRx = new Uint8Array(0);
    state.socket = new WebSocket(`ws://${host}:${port}/yifpga`);
    state.socket.binaryType = "arraybuffer";
    state.transport.connection = "connecting";
    renderTransport();
    state.socket.onopen = () => setConnected(true);
    state.socket.onmessage = (event) => {
      try { consumeBridgeBytes(new Uint8Array(event.data)); }
      catch (error) { state.socket.close(1002, "protocol error"); setConnected(false, error.message); }
    };
    state.socket.onerror = () => setConnected(false, "WebSocket connection failed");
    state.socket.onclose = () => { state.socket = null; setConnected(false); };
  }

  async function readLoop() {
    try {
      while (state.readLoopActive && state.reader) {
        const result = await state.reader.read();
        if (result.done) {
          break;
        }
        if (result.value) {
          appendRxBytes(result.value);
          parseAvailableFrames();
        }
      }
    } catch (error) {
      addLog({ timestamp: "-", type: "ERROR", id: "-", value: "-", text: error.message });
    } finally {
      setConnected(false);
    }
  }

  async function disconnect() {
    state.readLoopActive = false;
    if (state.socket) {
      const socket = state.socket;
      state.socket = null;
      socket.close(1000, "viewer disconnect");
    }
    if (state.reader) {
      await state.reader.cancel();
      state.reader.releaseLock();
      state.reader = null;
    }
    if (state.port) {
      await state.port.close();
      state.port = null;
    }
    setConnected(false);
  }

  async function replayRawCapture(file) {
    if (!file) return;
    const bytes = new Uint8Array(await file.arrayBuffer());
    appendRxBytes(bytes);
    parseAvailableFrames();
    addLog({ timestamp: "-", type: "REPLAY", id: "-", value: `${bytes.length} bytes`, text: file.name });
  }

  function injectSample() {
    const bytes = [];
    let payload = [];

    pushU32(payload, 0x12345678);
    bytes.push(...frame(0x01, payload));

    payload = [];
    pushU32(payload, 0x12345690);
    pushU16(payload, 0x1001);
    payload.push(1);
    pushU32(payload, 0x0000002A);
    bytes.push(...frame(0x03, payload));

    payload = [];
    pushU32(payload, 0x123456A0);
    pushU16(payload, 0x2001);
    pushU32(payload, 0x0000ABCD);
    bytes.push(...frame(0x04, payload));

    payload = [];
    pushU32(payload, 0x123456B0);
    pushU16(payload, 0x3001);
    pushU32(payload, 0x11111111);
    pushU32(payload, 0x22222222);
    bytes.push(...frame(0x02, payload));

    payload = [];
    pushU32(payload, 0x123456C0);
    pushU16(payload, 12);
    pushU16(payload, 0);
    pushU16(payload, 4);
    bytes.push(...frame(0x05, payload));

    // Frame 0x0042 opens, starts DMA, hits FIFO pressure, raises IRQ, and closes cleanly.
    payload = [];
    pushU32(payload, 0x123456D0);
    pushU16(payload, 0x0002);
    pushU16(payload, 0x0042);
    pushU32(payload, 0x00000042);
    bytes.push(...frame(0x10, payload));

    payload = [];
    pushU32(payload, 0x123456D4);
    pushU16(payload, 0x0001);
    pushU16(payload, 0x0042);
    pushU32(payload, 0x00000010);
    bytes.push(...frame(0x10, payload));

    payload = [];
    pushU32(payload, 0x123456D8);
    pushU16(payload, 0x0003);
    payload.push(2);
    pushU32(payload, 0x00000080);
    bytes.push(...frame(0x12, payload));

    payload = [];
    pushU32(payload, 0x123456E0);
    pushU16(payload, 0x0003);
    pushU16(payload, 0x0001);
    pushU32(payload, 0x0000007C);
    bytes.push(...frame(0x13, payload));

    payload = [];
    pushU32(payload, 0x123456E4);
    pushU16(payload, 0x0004);
    payload.push(1);
    pushU32(payload, 0x00000001);
    bytes.push(...frame(0x12, payload));

    payload = [];
    pushU32(payload, 0x123456F0);
    pushU16(payload, 0x0001);
    pushU16(payload, 0x0042);
    payload.push(0);
    pushU32(payload, 0x00000020);
    bytes.push(...frame(0x11, payload));

    payload = [];
    pushU32(payload, 0x123456F8);
    pushU16(payload, 0x0002);
    pushU16(payload, 0x0042);
    payload.push(0);
    pushU32(payload, 0x00000043);
    bytes.push(...frame(0x11, payload));

    // A second DMA descriptor times out so the Trace view has an obvious problem span.
    payload = [];
    pushU32(payload, 0x12345710);
    pushU16(payload, 0x0001);
    pushU16(payload, 0x0043);
    pushU32(payload, 0x00000011);
    bytes.push(...frame(0x10, payload));

    payload = [];
    pushU32(payload, 0x12345730);
    pushU16(payload, 0x0001);
    pushU16(payload, 0x0043);
    payload.push(3);
    pushU32(payload, 0x0000DEAD);
    bytes.push(...frame(0x11, payload));

    payload = [];
    pushU32(payload, 0x12345734);
    pushU16(payload, 0x0000);
    pushU32(payload, 2);
    bytes.push(...frame(0x14, payload));

    state.monitor.pending.set(0x501, {
      seq: 0x501,
      op: "read",
      addr: 0x000C,
      width: 4,
      createdAt: Date.now(),
      timeoutAt: Date.now() + MONITOR_TIMEOUT_MS,
    });
    payload = [];
    pushU32(payload, 0x12345740);
    pushU16(payload, 0x0501);
    pushU16(payload, 0x000C);
    payload.push(0, 4);
    pushU32(payload, 0x00000003);
    bytes.push(...frame(0x21, payload));

    state.monitor.pending.set(0x502, {
      seq: 0x502,
      op: "write",
      addr: 0x0010,
      width: 4,
      value: 1000,
      mask: 0xFFFFFFFF,
      createdAt: Date.now(),
      timeoutAt: Date.now() + MONITOR_TIMEOUT_MS,
    });
    payload = [];
    pushU32(payload, 0x12345748);
    pushU16(payload, 0x0502);
    pushU16(payload, 0x0010);
    payload.push(0);
    pushU32(payload, 500);
    pushU32(payload, 1000);
    bytes.push(...frame(0x23, payload));

    bytes.push(...profilerSampleBytes());
    bytes.push(...logicAnalyzerSampleBytes());

    appendRxBytes(bytes);
    parseAvailableFrames();
  }

  function profilerSnapshotFrame(timestamp, metricId, flags, sampleCycles, value0, value1, value2, value3, overflowCount = 0) {
    const payload = [];
    pushU32(payload, timestamp);
    pushU16(payload, metricId);
    pushU16(payload, flags);
    pushU32(payload, sampleCycles);
    pushU32(payload, value0);
    pushU32(payload, value1);
    pushU32(payload, value2);
    pushU32(payload, value3);
    pushU16(payload, overflowCount);
    pushU16(payload, 0);
    return frame(0x30, payload);
  }

  function profilerAlertFrame(timestamp, metricId, level, code, arg0, arg1) {
    const payload = [];
    pushU32(payload, timestamp);
    pushU16(payload, metricId);
    payload.push(level, code);
    pushU32(payload, arg0);
    pushU32(payload, arg1);
    return frame(0x31, payload);
  }

  function profilerSampleBytes() {
    return [
      ...profilerSnapshotFrame(0x12345760, 0x0001, PROFILER_FLAGS.VALID, 100000, 8192, 1024, 1200, 12),
      ...profilerSnapshotFrame(0x12345770, 0x0101, PROFILER_FLAGS.VALID | PROFILER_FLAGS.SATURATED, 100000, 48, 60, 8, 1, 1),
      ...profilerSnapshotFrame(0x12345780, 0x0201, PROFILER_FLAGS.VALID, 100000, 16, 23, 91, 44),
      ...profilerSnapshotFrame(0x12345790, 0x0301, PROFILER_FLAGS.VALID, 100000, 30, 1, 3100, 3500),
      ...profilerAlertFrame(0x12345794, 0x0101, 2, 3, 60, 1),
    ];
  }

  function injectProfilerSample() {
    appendRxBytes(profilerSampleBytes());
    parseAvailableFrames();
  }

  function logicAnalyzerHeaderFrame(captureId, timestamp, sampleWidthBits, sampleCount, triggerIndex, flags, samplePeriodCycles, channelCount) {
    const payload = [];
    pushU32(payload, captureId);
    pushU32(payload, timestamp);
    pushU16(payload, sampleWidthBits);
    pushU16(payload, sampleCount);
    pushU16(payload, triggerIndex);
    pushU16(payload, flags);
    pushU32(payload, samplePeriodCycles);
    pushU16(payload, channelCount);
    pushU16(payload, 0);
    return frame(0x40, payload);
  }

  function logicAnalyzerSampleFrame(captureId, chunkIndex, firstSampleIndex, sampleBytes, values, flags = 0) {
    const payload = [];
    pushU32(payload, captureId);
    pushU16(payload, chunkIndex);
    pushU16(payload, firstSampleIndex);
    payload.push(sampleBytes, values.length);
    pushU16(payload, flags);
    for (const value of values) {
      for (let byteIndex = 0; byteIndex < sampleBytes; byteIndex += 1) {
        payload.push((value >>> (8 * byteIndex)) & 0xFF);
      }
    }
    while (payload.length < 32) {
      payload.push(0);
    }
    return frame(0x41, payload.slice(0, 32));
  }

  function logicAnalyzerStatusFrame(timestamp, captureId, captureState, error, samplesWritten, chunksSent, chunksTotal, statusFlags) {
    const payload = [];
    pushU32(payload, timestamp);
    pushU32(payload, captureId);
    payload.push(captureState, error);
    pushU16(payload, samplesWritten);
    pushU16(payload, chunksSent);
    pushU16(payload, chunksTotal);
    pushU32(payload, statusFlags);
    return frame(0x42, payload);
  }

  function logicAnalyzerTriggerFrame(timestamp, captureId, triggerIndex, triggerChannel, sampleValue, triggerValue) {
    const payload = [];
    pushU32(payload, timestamp);
    pushU32(payload, captureId);
    pushU16(payload, triggerIndex);
    pushU16(payload, triggerChannel);
    pushU32(payload, sampleValue);
    pushU32(payload, triggerValue);
    return frame(0x43, payload);
  }

  function logicAnalyzerSampleBytes() {
    const captureId = 0x0000A501;
    return [
      ...logicAnalyzerHeaderFrame(captureId, 0x12345800, 32, 8, 3, LA_FLAGS.VALID | LA_FLAGS.TRIGGERED, 4, 11),
      ...logicAnalyzerTriggerFrame(0x12345804, captureId, 3, 2, 0x0000000F, 0x00000008),
      ...logicAnalyzerSampleFrame(captureId, 0, 0, 4, [1, 2, 4, 8, 16]),
      ...logicAnalyzerSampleFrame(captureId, 1, 5, 4, [32, 64, 128]),
      ...logicAnalyzerStatusFrame(0x12345820, captureId, 3, 0, 8, 2, 2, LA_FLAGS.VALID),
      ...frame(0x41, [0, 1, 2, 3]),
    ];
  }

  function injectLogicAnalyzerSample() {
    appendRxBytes(logicAnalyzerSampleBytes());
    parseAvailableFrames();
  }

  function clearAll() {
    state.rx = [];
    state.frames = 0;
    state.checksumErrors = 0;
    state.syncDrops = 0;
    state.unknownFrames = 0;
    state.logs = [];
    state.watches.clear();
    state.events.clear();
    state.status = {
      bufferUsed: "-",
      dropCount: "-",
      packetCount: "-",
      lastTimestamp: "-",
    };
    state.trace = {
      spans: [],
      openSpans: new Map(),
      marks: [],
      values: [],
      latestValues: new Map(),
      drops: [],
      selected: null,
    };
    state.monitor = createMonitorState();
    state.profiler = createProfilerState();
    state.logicAnalyzer = createLogicAnalyzerState();
    state.render.pending.clear();
    state.render.scheduled = false;
    if (aiDebug) aiDebug.reset();
    renderAll();
  }

  function setPaused(paused) {
    state.paused = paused;
    el.pauseButton.textContent = paused ? "Resume" : "Pause";
    el.pauseButton.setAttribute("aria-pressed", paused ? "true" : "false");
    el.pauseButton.classList.toggle("active", paused);
    if (!paused) {
      renderAll();
    }
  }

  function csvCell(value) {
    const text = String(value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  }

  function downloadText(filename, mimeType, text) {
    const blob = new Blob([text], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function exportCsv() {
    const profilerHistory = state.profiler.history.get(state.profiler.selectedMetricId) || [];
    const rows = profilerHistory.length ? [
      ["timestamp", "metric_id", "metric_name", "metric_type", "sample_cycles", "value0", "value1", "value2", "value3", "flags", "overflow_count"],
      ...profilerHistory.map((row) => [
        row.timestamp,
        hex(row.metricId, 4),
        row.metricName,
        row.metricType,
        row.sampleCycles,
        row.value0,
        row.value1,
        row.value2,
        row.value3,
        row.flagNames.join("|"),
        row.overflowCount,
      ]),
    ] : [
      ["timestamp", "type", "id", "value", "text"],
      ...state.logs.slice().reverse().map((row) => [
        row.timestamp,
        row.type,
        row.id,
        row.value,
        row.text,
      ]),
    ];
    const name = profilerHistory.length ? `yifpga-profiler-${hex(state.profiler.selectedMetricId, 4)}-${Date.now()}.csv` : `yifpga-debug-${Date.now()}.csv`;
    downloadText(
      name,
      "text/csv;charset=utf-8",
      rows.map((row) => row.map(csvCell).join(",")).join("\n") + "\n"
    );
  }

  function exportJsonl() {
    const records = [
      ...state.logs.slice().reverse().map((row) => ({ kind: "log", ...row })),
      ...Array.from(state.events.values()).map((row) => ({ kind: "event", ...row })),
      ...Array.from(state.watches.values()).map((row) => ({ kind: "watch", ...row })),
      ...state.trace.spans.map((row) => ({ kind: "trace_span", ...row, statusText: traceStatus(row.status) })),
      ...Array.from(state.trace.openSpans.values()).map((row) => ({ kind: "trace_open_span", ...row })),
      ...state.trace.marks.map((row) => ({ kind: "trace_mark", ...row })),
      ...state.trace.values.map((row) => ({ kind: "trace_value", ...row })),
      ...state.trace.drops.map((row) => ({ kind: "trace_drop", ...row })),
      ...state.monitor.history,
      ...state.monitor.errors.map((row) => ({ kind: "monitor_error", ...row })),
      ...Array.from(state.profiler.history.values()).flat(),
      ...state.profiler.alerts,
      { kind: "profiler_counters", ...state.profiler.counters },
      ...Array.from(state.logicAnalyzer.captures.values()).flatMap((capture) => [
        capture.header,
        capture.triggerEvent,
        ...Array.from(capture.chunks.values()),
        capture.status,
      ].filter(Boolean)),
      { kind: "la_parser_counters", ...state.logicAnalyzer.counters },
      { kind: "status", ...state.status },
      {
        kind: "counters",
        frames: state.frames,
        checksumErrors: state.checksumErrors,
        syncDrops: state.syncDrops,
        unknownFrames: state.unknownFrames,
      },
    ];
    downloadText(
      `yifpga-debug-${Date.now()}.jsonl`,
      "application/x-ndjson;charset=utf-8",
      records.map((record) => JSON.stringify(record)).join("\n") + "\n"
    );
  }

  el.connectButton.addEventListener("click", connect);
  el.disconnectButton.addEventListener("click", disconnect);
  el.sourceType.addEventListener("change", () => {
    state.sourceType = el.sourceType.value;
    const jtag = state.sourceType === "jtag";
    document.querySelectorAll("[data-jtag-control]").forEach((item) => { item.hidden = !jtag; });
    document.querySelectorAll("[data-serial-control]").forEach((item) => { item.disabled = jtag; });
    renderTransport();
  });
  el.rawReplayInput.addEventListener("change", () => replayRawCapture(el.rawReplayInput.files[0]));
  el.sampleButton.addEventListener("click", injectSample);
  el.pauseButton.addEventListener("click", () => setPaused(!state.paused));
  el.clearButton.addEventListener("click", clearAll);
  el.exportCsvButton.addEventListener("click", exportCsv);
  el.exportJsonlButton.addEventListener("click", exportJsonl);
  el.monitorReadAllButton.addEventListener("click", monitorReadAll);
  el.profilerEnableButton.addEventListener("click", () => profilerSetEnabled(true));
  el.profilerDisableButton.addEventListener("click", () => profilerSetEnabled(false));
  el.profilerApplyPeriodButton.addEventListener("click", profilerApplyPeriod);
  el.profilerClearButton.addEventListener("click", profilerClearHardware);
  el.profilerReadStatusButton.addEventListener("click", () => monitorRead(0x0054));
  el.laArmButton.addEventListener("click", () => logicAnalyzerCommand(LA_COMMANDS.arm));
  el.laStopButton.addEventListener("click", () => logicAnalyzerCommand(LA_COMMANDS.stop));
  el.laForceButton.addEventListener("click", () => logicAnalyzerCommand(LA_COMMANDS.force));
  el.laClearButton.addEventListener("click", () => logicAnalyzerCommand(LA_COMMANDS.clear));
  el.laReadoutButton.addEventListener("click", () => logicAnalyzerCommand(LA_COMMANDS.readout));
  el.laExportVcdButton.addEventListener("click", exportLogicAnalyzerVcd);
  el.laApplyConfigButton.addEventListener("click", applyLogicAnalyzerConfig);
  el.laZoomInButton.addEventListener("click", () => zoomLogicAnalyzer(0.5));
  el.laZoomOutButton.addEventListener("click", () => zoomLogicAnalyzer(2));
  [el.laViewportStart, el.laSamplesPerPixel, el.laCursorA, el.laCursorB].forEach((input) => {
    input.addEventListener("input", setLogicAnalyzerViewportFromInputs);
    input.addEventListener("change", setLogicAnalyzerViewportFromInputs);
  });
  el.laChannelList.addEventListener("change", (event) => {
    const checkbox = event.target.closest("[data-la-channel]");
    if (!checkbox) {
      return;
    }
    const channel = state.logicAnalyzer.manifest[Number(checkbox.dataset.laChannel)];
    if (channel) {
      channel.visible = checkbox.checked;
      requestRender(renderLogicAnalyzer);
    }
  });
  el.profilerMetricSelect.addEventListener("change", () => {
    state.profiler.selectedMetricId = Number(el.profilerMetricSelect.value);
    state.profiler.selectedValueIndex = 0;
    renderProfiler();
  });
  el.profilerValueSelect.addEventListener("change", () => {
    state.profiler.selectedValueIndex = Number(el.profilerValueSelect.value);
    renderProfiler();
  });
  el.profilerAlertFilter.addEventListener("change", () => {
    state.profiler.alertFilter = el.profilerAlertFilter.value;
    renderProfiler();
  });
  el.monitorPollEnabled.addEventListener("change", () => {
    state.monitor.pollEnabled = el.monitorPollEnabled.checked;
  });
  el.monitorPollInterval.addEventListener("change", () => {
    const interval = Number(el.monitorPollInterval.value);
    state.monitor.pollIntervalMs = Number.isFinite(interval) ? Math.max(100, interval) : 500;
    el.monitorPollInterval.value = state.monitor.pollIntervalMs;
  });
  el.monitorBody.addEventListener("click", (event) => {
    const readButton = event.target.closest("[data-monitor-read]");
    const writeButton = event.target.closest("[data-monitor-write]");
    const triggerButton = event.target.closest("[data-monitor-trigger]");
    if (readButton) {
      monitorRead(Number(readButton.dataset.monitorRead));
    } else if (writeButton) {
      const addr = Number(writeButton.dataset.monitorWrite);
      const valueInput = el.monitorBody.querySelector(`[data-monitor-value="${addr}"]`);
      const maskInput = el.monitorBody.querySelector(`[data-monitor-mask="${addr}"]`);
      const value = parseNumber(valueInput.value);
      const mask = parseNumber(maskInput.value);
      if (window.confirm(`Write ${hex(value, 8)} to ${monitorRegister(addr).name}?`)) {
        monitorWrite(addr, value, mask);
      }
    } else if (triggerButton) {
      const addr = Number(triggerButton.dataset.monitorTrigger);
      if (window.confirm(`Trigger ${monitorRegister(addr).name}?`)) {
        monitorWrite(addr, 1, 0xFFFFFFFF);
      }
    }
  });
  [el.traceLaneFilter, el.traceStatusFilter, el.traceFrom, el.traceTo].forEach((input) => {
    input.addEventListener("input", renderTrace);
    input.addEventListener("change", renderTrace);
  });
  el.traceTimeline.addEventListener("click", (event) => {
    const button = event.target.closest("[data-trace]");
    if (!button) {
      return;
    }
    state.trace.selected = JSON.parse(decodeURIComponent(button.dataset.trace));
    el.traceTimeline.querySelectorAll(".is-selected").forEach((item) => item.classList.remove("is-selected"));
    button.classList.add("is-selected");
    renderTraceDetail();
  });

  function locateDiagnosticEvidence(sourceRef) {
    const selectors = { trace: ".trace-panel", monitor: ".monitor-panel", profiler: ".profiler-panel", logic_analyzer: ".la-panel", viewer: ".transport-panel", debug: ".log-panel" };
    const target = document.querySelector(selectors[sourceRef.view]);
    if (!target) return false;
    target.scrollIntoView({ behavior: "smooth", block: "center" }); target.classList.add("diagnostic-highlight");
    window.setTimeout(() => target.classList.remove("diagnostic-highlight"), 1600); return true;
  }

  aiDebug = new window.YiFPGAAIDebugModel.AIDebugModel({
    stateSource: () => state,
    download: downloadText,
    onLocate: locateDiagnosticEvidence,
    elements: {
      status: el.aiDebugStatus, scope: el.aiDebugScope, local: el.aiDebugLocalButton, consent: el.aiDebugConsent,
      ask: el.aiDebugAskButton, cancel: el.aiDebugCancelButton, preview: el.aiDebugPreview, findings: el.aiDebugFindings,
      hypotheses: el.aiDebugHypotheses, actions: el.aiDebugActions, feedbackRating: el.aiDebugFeedbackRating,
      feedbackRoot: el.aiDebugFeedbackRoot, feedbackNote: el.aiDebugFeedbackNote, history: el.aiDebugHistory,
      exportSnapshot: el.aiDebugExportSnapshot, exportDiagnosis: el.aiDebugExportDiagnosis, exportMarkdown: el.aiDebugExportMarkdown,
    },
  });
  document.querySelectorAll("[data-diagnose-scope]").forEach((button) => button.addEventListener("click", () => {
    el.aiDebugScope.value = button.dataset.diagnoseScope; el.aiDebugScope.dispatchEvent(new Event("change"));
    document.getElementById("aiDebugPanel").scrollIntoView({ behavior: "smooth", block: "start" });
  }));

  if (hasSerial()) {
    el.serialSupport.textContent = "Web Serial supported";
    el.serialSupport.classList.add("ok");
  } else {
    el.serialSupport.textContent = "Web Serial unavailable";
  }

  el.laTriggerMode.innerHTML = LA_TRIGGER_MODES.map((mode, index) => {
    const selected = index === state.logicAnalyzer.config.triggerMode ? " selected" : "";
    return `<option value="${index}"${selected}>${mode}</option>`;
  }).join("");
  setConnected(false);
  clearAll();
  window.setInterval(() => {
    const now = Date.now();
    expireMonitorPending();
    if (
      state.monitor.pollEnabled &&
      state.monitor.pending.size === 0 &&
      now - state.monitor.lastPollAt >= state.monitor.pollIntervalMs
    ) {
      state.monitor.lastPollAt = now;
      monitorReadAll();
    }
  }, 100);

  window.yifpgaViewerTest = {
    clearAll,
    injectSample,
    injectProfilerSample,
    injectLogicAnalyzerSample,
    state,
    renderAll,
    frame,
    pushU16,
    pushU32,
    encodeMonitorRead,
    encodeMonitorWrite,
    expireMonitorPending,
    monitorStatus,
    profilerSnapshotFrame,
    profilerAlertFrame,
    profilerMetric,
    parseBytes(bytes) {
      appendRxBytes(bytes);
      parseAvailableFrames();
    },
    consumeBridgeBytes,
    consumeBridgeRecord,
    diagnosticSnapshot: {
      createSession(options = {}) {
        return window.YiFPGADiagnosticSnapshot.build(state, options);
      },
      createTimeWindow(from, to, options = {}) {
        return window.YiFPGADiagnosticSnapshot.build(state, { ...options, scope: { type: "time_window", from, to } });
      },
      createLogicAnalyzerCapture(captureId = state.logicAnalyzer.latestCaptureId, options = {}) {
        return window.YiFPGADiagnosticSnapshot.build(state, { ...options, captureId, scope: { type: "la_capture", capture_id: captureId } });
      },
      import(json) {
        return window.YiFPGADiagnosticSnapshot.importSnapshot(json);
      },
      export(snapshot) {
        return window.YiFPGADiagnosticSnapshot.canonicalize(snapshot);
      },
      locate(snapshot, evidenceId, callback) {
        return window.YiFPGADiagnosticSnapshot.locate(snapshot, evidenceId, callback);
      },
    },
    aiDebug,
  };
})();
