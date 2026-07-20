param(
    [string]$Port = "COM6",
    [int]$Baud = 115200,
    [int]$TimeoutMs = 2000,
    [switch]$TraceFrames,
    [switch]$SelfTest
)

$SOF = 0xA5
$VERSION = 0x01
$TYPE_READ_REQ = 0x20
$TYPE_READ_RESP = 0x21
$TYPE_WRITE_REQ = 0x22
$TYPE_WRITE_RESP = 0x23

$STATUS = @("OK", "BAD_ADDR", "DENIED", "BUSY", "BAD_LEN", "BAD_VALUE", "TIMEOUT")

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
    return [int](
        ([uint32]$Payload[$Offset]) -bor
        (([uint32]$Payload[($Offset + 1)]) -shl 8)
    )
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
    $body.Add([byte]$VERSION)
    $body.Add([byte]$Type)
    $body.Add([byte]$Payload.Count)
    foreach ($byte in $Payload) {
        $body.Add($byte)
    }

    $checksum = 0
    foreach ($byte in $body) {
        $checksum = $checksum -bxor $byte
    }

    $frame = New-Object System.Collections.Generic.List[byte]
    $frame.Add([byte]$SOF)
    foreach ($byte in $body) {
        $frame.Add($byte)
    }
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

function Status-Name([int]$Code) {
    if ($Code -ge 0 -and $Code -lt $STATUS.Count) {
        return $STATUS[$Code]
    }
    return "STATUS_$Code"
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
    [byte[]]$readPayload = 0x5F, 0xB7, 0x06, 0x6F, 0x00, 0x41, 0x00, 0x00, 0x00, 0x04, 0x30, 0x4D, 0x46, 0x4F
    Assert-Equal (Read-U16 $readPayload 4) 0x4100 "read response seq decode"
    Assert-Equal (Read-U16 $readPayload 6) 0x0000 "read response addr decode"
    Assert-Equal (Read-U32 $readPayload 10) 0x4F464D30 "read response value decode"

    $readRequest = New-ReadRequest 0x4100 0x0000
    Assert-Equal (Format-HexBytes $readRequest) "A5 01 20 05 00 41 00 00 04 61" "read request frame"

    $writeRequest = New-WriteRequest 0x4102 0x000C 0x00000003 ([uint32]::MaxValue)
    Assert-Equal (Format-HexBytes $writeRequest) "A5 01 22 0D 02 41 0C 00 04 03 00 00 00 FF FF FF FF 66" "write request frame"

    [byte[]]$writePayload = 0x01, 0x02, 0x03, 0x04, 0x02, 0x41, 0x0C, 0x00, 0x00, 0x78, 0x56, 0x34, 0x12, 0x03, 0x00, 0x00, 0x00
    Assert-Equal (Read-U16 $writePayload 4) 0x4102 "write response seq decode"
    Assert-Equal (Read-U16 $writePayload 6) 0x000C "write response addr decode"
    Assert-Equal (Read-U32 $writePayload 9) 0x12345678 "write response old value decode"
    Assert-Equal (Read-U32 $writePayload 13) 0x00000003 "write response new value decode"

    if (-not $Quiet) {
        "PASS: monitor_validate self-test passed"
    }
}

function Wait-MonitorResponse(
    [System.IO.Ports.SerialPort]$Serial,
    [int]$Seq,
    [int]$ExpectedType,
    [int]$TimeoutMs
) {
    $rx = New-Object System.Collections.Generic.List[byte]
    $startedAt = Get-Date
    $checksumErrors = 0
    $syncDrops = 0

    while (((Get-Date) - $startedAt).TotalMilliseconds -lt $TimeoutMs) {
        try {
            $rx.Add([byte]$Serial.ReadByte())
        } catch [System.TimeoutException] {
        }

        while ($rx.Count -ge 5) {
            if ($rx[0] -ne $SOF) {
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

            $raw = New-Object byte[] $total
            for ($i = 0; $i -lt $total; $i += 1) {
                $raw[$i] = $rx[$i]
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

            $msgType = [int]$raw[2]
            if ($TraceFrames) {
                Write-Host "TRACE_FRAME type=0x$($msgType.ToString('X2')) len=$len expected=0x$($ExpectedType.ToString('X2'))"
            }
            if ($msgType -ne $ExpectedType) {
                continue
            }

            $payload = New-Object byte[] $len
            for ($i = 0; $i -lt $len; $i += 1) {
                $payload[$i] = $raw[(4 + $i)]
            }

            $respSeq = Read-U16 $payload 4
            if ($TraceFrames) {
                Write-Host "TRACE_EXPECTED_TYPE seq=$respSeq expected_seq=$Seq payload=$((($payload | ForEach-Object { $_.ToString('X2') }) -join ' '))"
            }
            if ($respSeq -ne $Seq) {
                continue
            }

            return @{
                Type = $msgType
                Payload = $payload
                ChecksumErrors = $checksumErrors
                SyncDrops = $syncDrops
            }
        }
    }

    throw "Timed out waiting for Monitor response seq=$Seq type=0x$($ExpectedType.ToString('X2'))"
}

function Invoke-Read([System.IO.Ports.SerialPort]$Serial, [int]$Seq, [int]$Addr) {
    $frame = New-ReadRequest $Seq $Addr
    $Serial.Write($frame, 0, $frame.Length)
    $resp = Wait-MonitorResponse $Serial $Seq $TYPE_READ_RESP $TimeoutMs
    $payload = [byte[]]$resp.Payload
    return @{
        Seq = $Seq
        Addr = Read-U16 $payload 6
        Status = [int]$payload[8]
        Width = [int]$payload[9]
        Value = Read-U32 $payload 10
        ChecksumErrors = $resp.ChecksumErrors
        SyncDrops = $resp.SyncDrops
    }
}

function Invoke-Write([System.IO.Ports.SerialPort]$Serial, [int]$Seq, [int]$Addr, [uint32]$Value, [uint32]$Mask) {
    $frame = New-WriteRequest $Seq $Addr $Value $Mask
    $Serial.Write($frame, 0, $frame.Length)
    $resp = Wait-MonitorResponse $Serial $Seq $TYPE_WRITE_RESP $TimeoutMs
    $payload = [byte[]]$resp.Payload
    return @{
        Seq = $Seq
        Addr = Read-U16 $payload 6
        Status = [int]$payload[8]
        OldValue = Read-U32 $payload 9
        NewValue = Read-U32 $payload 13
        ChecksumErrors = $resp.ChecksumErrors
        SyncDrops = $resp.SyncDrops
    }
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

try {
    $serial.Open()
    $serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()

    $seq = 0x4100
    $id = Invoke-Read $serial $seq 0x0000
    $seq += 1
    $versionRead = Invoke-Read $serial $seq 0x0004
    $seq += 1
    $allOnes = [uint32]::MaxValue

    $ledWrite = Invoke-Write $serial $seq 0x000C 0x00000003 $allOnes
    $seq += 1
    $ledRead = Invoke-Read $serial $seq 0x000C
    $seq += 1
    $periodWrite = Invoke-Write $serial $seq 0x0010 0x000186A0 $allOnes
    $seq += 1
    $clearWrite = Invoke-Write $serial $seq 0x0018 0x00000001 $allOnes
    $seq += 1
    $deniedWrite = Invoke-Write $serial $seq 0x0000 $allOnes $allOnes

    "port=$Port"
    "baud=$Baud"
    "MONITOR_ID=0x$($id.Value.ToString('X8')) status=$(Status-Name $id.Status)"
    "MONITOR_VERSION=0x$($versionRead.Value.ToString('X8')) status=$(Status-Name $versionRead.Status)"
    "LED_CONTROL_WRITE old=0x$($ledWrite.OldValue.ToString('X8')) new=0x$($ledWrite.NewValue.ToString('X8')) status=$(Status-Name $ledWrite.Status)"
    "LED_CONTROL_READ value=0x$($ledRead.Value.ToString('X8')) status=$(Status-Name $ledRead.Status)"
    "DEMO_PERIOD_WRITE old=0x$($periodWrite.OldValue.ToString('X8')) new=0x$($periodWrite.NewValue.ToString('X8')) status=$(Status-Name $periodWrite.Status)"
    "CLEAR_COUNTERS_WRITE status=$(Status-Name $clearWrite.Status)"
    "RO_WRITE_MONITOR_ID status=$(Status-Name $deniedWrite.Status)"

    if ($id.Value -ne 0x4F464D30 -or $id.Status -ne 0) {
        throw "MONITOR_ID validation failed"
    }
    if ($versionRead.Status -ne 0) {
        throw "MONITOR_VERSION validation failed"
    }
    if ($ledWrite.Status -ne 0 -or $ledRead.Status -ne 0 -or $ledRead.Value -ne 0x00000003) {
        throw "LED_CONTROL validation failed"
    }
    if ($periodWrite.Status -ne 0 -or $periodWrite.NewValue -ne 0x000186A0) {
        throw "DEMO_PERIOD validation failed"
    }
    if ($clearWrite.Status -ne 0) {
        throw "CLEAR_COUNTERS validation failed"
    }
    if ($deniedWrite.Status -ne 2) {
        throw "RO write denial validation failed"
    }

    "PASS: YiFPGA Monitor board validation passed"
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
