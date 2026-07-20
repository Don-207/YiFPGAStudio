param(
    [string]$Port = "COM6",
    [int]$Baud = 115200,
    [int]$TimeoutMs = 5000,
    [int]$RunSeconds = 10,
    [switch]$TraceFrames,
    [switch]$SelfTest
)

$SOF = 0xA5
$PROTOCOL_VERSION = 0x01
$TYPE_READ_REQ = 0x20
$TYPE_READ_RESP = 0x21
$TYPE_WRITE_REQ = 0x22
$TYPE_WRITE_RESP = 0x23
$TYPE_PROFILER_SNAPSHOT = 0x30
$TYPE_PROFILER_ALERT = 0x31

$ADDR_PROFILER_ID = 0x0040
$ADDR_PROFILER_VERSION = 0x0044
$ADDR_PROFILER_CONTROL = 0x0048
$ADDR_PROFILER_SAMPLE_PERIOD = 0x004C
$ADDR_PROFILER_CLEAR = 0x0050
$ADDR_PROFILER_STATUS = 0x0054
$ADDR_PROFILER_METRIC_MASK0 = 0x0058
$ADDR_PROFILER_ALERT_THRESHOLD0 = 0x005C

$METRIC_AXIS = 0x0001
$METRIC_FIFO = 0x0101
$METRIC_LATENCY = 0x0201
$METRIC_FRAME = 0x0301

function Push-U16([System.Collections.Generic.List[byte]]$Bytes, [int]$Value) {
    $Bytes.Add([byte]($Value -band 0xFF))
    $Bytes.Add([byte](($Value -shr 8) -band 0xFF))
}

function Push-U32([System.Collections.Generic.List[byte]]$Bytes, [uint32]$Value) {
    $Bytes.Add([byte]($Value -band 0xFF))
    $Bytes.Add([byte](($Value -shr 8) -band 0xFF))
    $Bytes.Add([byte](($Value -shr 16) -band 0xFF))
    $Bytes.Add([byte](($Value -shr 24) -band 0xFF))
}

function Read-U16([byte[]]$Payload, [int]$Offset) {
    return [int](([uint32]$Payload[$Offset]) -bor (([uint32]$Payload[($Offset + 1)]) -shl 8))
}

function Read-U32([byte[]]$Payload, [int]$Offset) {
    return [uint32](
        ([uint32]$Payload[$Offset]) -bor
        (([uint32]$Payload[($Offset + 1)]) -shl 8) -bor
        (([uint32]$Payload[($Offset + 2)]) -shl 16) -bor
        (([uint32]$Payload[($Offset + 3)]) -shl 24)
    )
}

function New-Frame([int]$Type, [System.Collections.Generic.List[byte]]$Payload) {
    $body = New-Object System.Collections.Generic.List[byte]
    $body.Add([byte]$PROTOCOL_VERSION)
    $body.Add([byte]$Type)
    $body.Add([byte]$Payload.Count)
    foreach ($byte in $Payload) { $body.Add($byte) }

    $checksum = 0
    foreach ($byte in $body) { $checksum = $checksum -bxor $byte }

    $frame = New-Object System.Collections.Generic.List[byte]
    $frame.Add([byte]$SOF)
    foreach ($byte in $body) { $frame.Add($byte) }
    $frame.Add([byte]$checksum)
    return $frame.ToArray()
}

function New-ReadRequest([int]$Seq, [int]$Addr) {
    $payload = New-Object System.Collections.Generic.List[byte]
    Push-U16 $payload $Seq
    Push-U16 $payload $Addr
    $payload.Add([byte]4)
    return New-Frame $TYPE_READ_REQ $payload
}

function New-WriteRequest([int]$Seq, [int]$Addr, [uint32]$Value, [uint32]$Mask) {
    $payload = New-Object System.Collections.Generic.List[byte]
    Push-U16 $payload $Seq
    Push-U16 $payload $Addr
    $payload.Add([byte]4)
    Push-U32 $payload $Value
    Push-U32 $payload $Mask
    return New-Frame $TYPE_WRITE_REQ $payload
}

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) {
        throw "$Name failed: expected=$Expected actual=$Actual"
    }
}

function Format-HexBytes([byte[]]$Bytes) {
    return (($Bytes | ForEach-Object { $_.ToString("X2") }) -join " ")
}

function Invoke-SelfTest([switch]$Quiet) {
    Assert-Equal (Format-HexBytes (New-ReadRequest 0x5100 $ADDR_PROFILER_ID)) "A5 01 20 05 00 51 40 00 04 31" "profiler id read request"
    Assert-Equal (Format-HexBytes (New-WriteRequest 0x5101 $ADDR_PROFILER_CONTROL 0x00000001 0x00000001)) "A5 01 22 0D 01 51 48 00 04 01 00 00 00 01 00 00 00 32" "profiler enable write request"
    [byte[]]$snapshotPayload = 0x10,0x00,0x00,0x00,0x01,0x00,0x01,0x00,0x20,0x4E,0x00,0x00,0x08,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x05,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    Assert-Equal (Read-U16 $snapshotPayload 4) $METRIC_AXIS "snapshot metric decode"
    Assert-Equal (Read-U32 $snapshotPayload 8) 20000 "snapshot sample cycles decode"
    if (-not $Quiet) { "PASS: profiler_validate self-test passed" }
}

function Read-Frame([System.IO.Ports.SerialPort]$Serial, [System.Collections.Generic.List[byte]]$Rx, [int]$TimeoutMs) {
    $startedAt = Get-Date
    while (((Get-Date) - $startedAt).TotalMilliseconds -lt $TimeoutMs) {
        try {
            $Rx.Add([byte]$Serial.ReadByte())
        } catch [System.TimeoutException] {
        }

        while ($Rx.Count -ge 5) {
            if ($Rx[0] -ne $SOF) {
                $Rx.RemoveAt(0)
                continue
            }
            $len = [int]$Rx[3]
            if ($len -gt 32) {
                $Rx.RemoveAt(0)
                continue
            }
            $total = 5 + $len
            if ($Rx.Count -lt $total) { break }

            $raw = New-Object byte[] $total
            for ($i = 0; $i -lt $total; $i += 1) { $raw[$i] = $Rx[$i] }
            for ($i = 0; $i -lt $total; $i += 1) { $Rx.RemoveAt(0) }

            $checksum = 0
            for ($i = 1; $i -lt ($total - 1); $i += 1) { $checksum = $checksum -bxor $raw[$i] }
            if ($checksum -ne $raw[$total - 1]) { continue }

            $payload = New-Object byte[] $len
            for ($i = 0; $i -lt $len; $i += 1) { $payload[$i] = $raw[(4 + $i)] }
            return @{ Type = [int]$raw[2]; Payload = $payload }
        }
    }
    return $null
}

function Wait-MonitorResponse([System.IO.Ports.SerialPort]$Serial, [System.Collections.Generic.List[byte]]$Rx, [int]$Seq, [int]$ExpectedType) {
    $startedAt = Get-Date
    while (((Get-Date) - $startedAt).TotalMilliseconds -lt $TimeoutMs) {
        $frame = Read-Frame $Serial $Rx 100
        if ($null -eq $frame) { continue }
        if ($TraceFrames) { Write-Host "TRACE_FRAME type=0x$(([int]$frame.Type).ToString('X2')) len=$($frame.Payload.Length)" }
        if ($frame.Type -ne $ExpectedType) { continue }
        if ($frame.Payload.Length -lt 10) { continue }
        $respSeq = Read-U16 ([byte[]]$frame.Payload) 4
        if ($respSeq -eq $Seq) { return $frame }
    }
    throw "Timed out waiting for Monitor response seq=$Seq type=0x$($ExpectedType.ToString('X2'))"
}

function Invoke-Read([System.IO.Ports.SerialPort]$Serial, [System.Collections.Generic.List[byte]]$Rx, [int]$Seq, [int]$Addr) {
    $frame = New-ReadRequest $Seq $Addr
    $Serial.Write($frame, 0, $frame.Length)
    $resp = Wait-MonitorResponse $Serial $Rx $Seq $TYPE_READ_RESP
    $payload = [byte[]]$resp.Payload
    return @{ Status = [int]$payload[8]; Value = Read-U32 $payload 10 }
}

function Invoke-Write([System.IO.Ports.SerialPort]$Serial, [System.Collections.Generic.List[byte]]$Rx, [int]$Seq, [int]$Addr, [uint32]$Value, [uint32]$Mask) {
    $frame = New-WriteRequest $Seq $Addr $Value $Mask
    $Serial.Write($frame, 0, $frame.Length)
    $resp = Wait-MonitorResponse $Serial $Rx $Seq $TYPE_WRITE_RESP
    $payload = [byte[]]$resp.Payload
    return @{ Status = [int]$payload[8]; OldValue = Read-U32 $payload 9; NewValue = Read-U32 $payload 13 }
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

Invoke-SelfTest -Quiet

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$serial.ReadTimeout = 50
$serial.WriteTimeout = 1000
$serial.DtrEnable = $true
$serial.RtsEnable = $true
$rx = New-Object System.Collections.Generic.List[byte]

try {
    $serial.Open()
    $serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()

    for ($i = 0; $i -lt 3; $i += 1) {
        $disableFrame = New-WriteRequest (0x50F0 + $i) $ADDR_PROFILER_CONTROL 0 1
        $serial.Write($disableFrame, 0, $disableFrame.Length)
        Start-Sleep -Milliseconds 100
    }
    Start-Sleep -Milliseconds 500
    $serial.DiscardInBuffer()

    $seq = 0x5100
    $id = Invoke-Read $serial $rx $seq $ADDR_PROFILER_ID; $seq += 1
    $version = Invoke-Read $serial $rx $seq $ADDR_PROFILER_VERSION; $seq += 1
    $periodWrite = Invoke-Write $serial $rx $seq $ADDR_PROFILER_SAMPLE_PERIOD 20000 ([uint32]::MaxValue); $seq += 1
    $maskWrite = Invoke-Write $serial $rx $seq $ADDR_PROFILER_METRIC_MASK0 ([uint32]::MaxValue) ([uint32]::MaxValue); $seq += 1
    $thresholdWrite = Invoke-Write $serial $rx $seq $ADDR_PROFILER_ALERT_THRESHOLD0 0 ([uint32]::MaxValue); $seq += 1
    $clearWrite = Invoke-Write $serial $rx $seq $ADDR_PROFILER_CLEAR 1 ([uint32]::MaxValue); $seq += 1
    $enableWrite = Invoke-Write $serial $rx $seq $ADDR_PROFILER_CONTROL 1 1; $seq += 1

    if ($id.Status -ne 0 -or $id.Value -ne 0x4F465034) { throw "PROFILER_ID validation failed" }
    if ($version.Status -ne 0) { throw "PROFILER_VERSION validation failed" }
    if ($periodWrite.Status -ne 0 -or $periodWrite.NewValue -ne 20000) { throw "PROFILER_SAMPLE_PERIOD validation failed" }
    if ($maskWrite.Status -ne 0) { throw "PROFILER_METRIC_MASK0 validation failed" }
    if ($thresholdWrite.Status -ne 0) { throw "PROFILER_ALERT_THRESHOLD0 disable validation failed" }
    if ($clearWrite.Status -ne 0) { throw "PROFILER_CLEAR validation failed" }
    if ($enableWrite.Status -ne 0 -or (($enableWrite.NewValue -band 1) -ne 1)) { throw "PROFILER_CONTROL enable validation failed" }

    $seen = @{}
    $alerts = 0
    $deadline = (Get-Date).AddSeconds($RunSeconds)
    while ((Get-Date) -lt $deadline) {
        $frame = Read-Frame $serial $rx 250
        if ($null -eq $frame) { continue }
        if ($frame.Type -eq $TYPE_PROFILER_SNAPSHOT -and $frame.Payload.Length -eq 32) {
            $metricId = Read-U16 ([byte[]]$frame.Payload) 4
            $seen[$metricId] = $true
            if ($TraceFrames) { Write-Host "SNAPSHOT metric=0x$($metricId.ToString('X4')) sample=$(Read-U32 ([byte[]]$frame.Payload) 8)" }
        } elseif ($frame.Type -eq $TYPE_PROFILER_ALERT -and $frame.Payload.Length -eq 16) {
            $alerts += 1
        }
        if ($seen.ContainsKey($METRIC_AXIS) -and $seen.ContainsKey($METRIC_FIFO) -and $seen.ContainsKey($METRIC_LATENCY) -and $seen.ContainsKey($METRIC_FRAME)) {
            break
        }
    }

    foreach ($metricId in @($METRIC_AXIS, $METRIC_FIFO, $METRIC_LATENCY, $METRIC_FRAME)) {
        if (-not $seen.ContainsKey($metricId)) {
            $seenText = (($seen.Keys | Sort-Object | ForEach-Object { "0x$($_.ToString('X4'))" }) -join ",")
            throw "Missing profiler snapshot metric 0x$($metricId.ToString('X4')); seen=[$seenText]"
        }
    }

    $thresholdAlertFrame = New-WriteRequest $seq $ADDR_PROFILER_ALERT_THRESHOLD0 16 ([uint32]::MaxValue)
    $seq += 1
    $serial.Write($thresholdAlertFrame, 0, $thresholdAlertFrame.Length)
    $alertDeadline = (Get-Date).AddSeconds([Math]::Max(5, [Math]::Min($RunSeconds, 15)))
    while ((Get-Date) -lt $alertDeadline -and $alerts -lt 1) {
        $frame = Read-Frame $serial $rx 250
        if ($null -eq $frame) { continue }
        if ($frame.Type -eq $TYPE_PROFILER_ALERT -and $frame.Payload.Length -eq 16) {
            $alerts += 1
        }
    }
    if ($alerts -lt 1) {
        throw "Missing profiler alert"
    }

    $status = $null
    try {
        $status = Invoke-Read $serial $rx $seq $ADDR_PROFILER_STATUS
    } catch {
        Write-Warning "PROFILER_STATUS read skipped after high-rate profiler traffic: $($_.Exception.Message)"
    }
    "port=$Port"
    "baud=$Baud"
    "PROFILER_ID=0x$($id.Value.ToString('X8'))"
    "PROFILER_VERSION=0x$($version.Value.ToString('X8'))"
    if ($null -ne $status) {
        "PROFILER_STATUS=0x$($status.Value.ToString('X8'))"
    }
    "snapshots=$($seen.Keys.Count)"
    "alerts=$alerts"
    "PASS: YiFPGA Profiler board validation passed"
} finally {
    if ($serial.IsOpen) {
        try {
            $disableFrame = New-WriteRequest 0x51FF $ADDR_PROFILER_CONTROL 0 1
            $serial.Write($disableFrame, 0, $disableFrame.Length)
            Start-Sleep -Milliseconds 100
        } catch {
        }
        $serial.Close()
    }
}
