param(
    [string]$Port = "COM6",
    [int]$Baud = 115200,
    [int]$DurationSec = 30
)

$typeNames = @{
    1 = "HEARTBEAT"
    2 = "DEBUG_PRINT"
    3 = "EVENT"
    4 = "WATCH"
    5 = "STATUS"
    16 = "TRACE_SPAN_BEGIN"
    17 = "TRACE_SPAN_END"
    18 = "TRACE_MARK"
    19 = "TRACE_VALUE"
    20 = "TRACE_DROP"
}

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$serial.ReadTimeout = 100

$rx = New-Object System.Collections.Generic.List[byte]
$frames = @{}
$checksumErrors = 0
$syncDrops = 0
$unknownFrames = 0
$statusFrames = 0
$maxBufferUsed = 0
$lastDropCount = $null
$lastPacketCount = $null
$startedAt = Get-Date

try {
    $serial.Open()

    while (((Get-Date) - $startedAt).TotalSeconds -lt $DurationSec) {
        try {
            [void]$rx.Add([byte]$serial.ReadByte())

            while ($rx.Count -ge 5) {
                if ($rx[0] -ne 0xA5) {
                    $rx.RemoveAt(0)
                    $syncDrops += 1
                    continue
                }

                $len = [int]$rx[3]
                if ($len -gt 32) {
                    $rx.RemoveAt(0)
                    $syncDrops += 1
                    continue
                }

                $total = 5 + $len
                if ($rx.Count -lt $total) {
                    break
                }

                $raw = @()
                for ($i = 0; $i -lt $total; $i += 1) {
                    $raw += $rx[$i]
                }
                for ($i = 0; $i -lt $total; $i += 1) {
                    $rx.RemoveAt(0)
                }

                $checksum = 0
                for ($i = 1; $i -lt ($total - 1); $i += 1) {
                    $checksum = $checksum -bxor $raw[$i]
                }

                if ($checksum -ne $raw[$total - 1]) {
                    $checksumErrors += 1
                    continue
                }

                $version = [int]$raw[1]
                $msgType = [int]$raw[2]
                if ($version -ne 1 -or -not $typeNames.ContainsKey($msgType)) {
                    $unknownFrames += 1
                }

                if (-not $frames.ContainsKey($msgType)) {
                    $frames[$msgType] = 0
                }
                $frames[$msgType] += 1

                if ($msgType -eq 5 -and $len -eq 10) {
                    $statusFrames += 1
                    $payload = $raw[4..13]
                    $bufferUsed = [int]($payload[4] -bor ($payload[5] -shl 8))
                    $dropCount = [int]($payload[6] -bor ($payload[7] -shl 8))
                    $packetCount = [int]($payload[8] -bor ($payload[9] -shl 8))
                    if ($bufferUsed -gt $maxBufferUsed) {
                        $maxBufferUsed = $bufferUsed
                    }
                    $lastDropCount = $dropCount
                    $lastPacketCount = $packetCount
                }
            }
        } catch [System.TimeoutException] {
        }
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}

$totalFrames = 0
foreach ($value in $frames.Values) {
    $totalFrames += $value
}

"port=$Port"
"baud=$Baud"
"duration_sec=$DurationSec"
"frames_total=$totalFrames"
foreach ($key in ($frames.Keys | Sort-Object)) {
    $name = $typeNames[[int]$key]
    if (-not $name) {
        $name = "TYPE_$key"
    }
    "$name=$($frames[$key])"
}
"status_frames=$statusFrames"
"checksum_errors=$checksumErrors"
"sync_drops=$syncDrops"
"unknown_frames=$unknownFrames"
"pending_bytes=$($rx.Count)"
"max_buffer_used=$maxBufferUsed"
"last_drop_count=$lastDropCount"
"last_packet_count=$lastPacketCount"
