param(
    [string]$Port = "COM4",
    [int]$Baud = 115200,
    [int]$DurationMs = 3000
)

$SOF = 0xA5
$VERSION = 0x01

function Push-U16([System.Collections.Generic.List[byte]]$Bytes, [int]$Value) {
    $Bytes.Add([byte]($Value -band 0xFF))
    $Bytes.Add([byte](($Value -shr 8) -band 0xFF))
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
    return New-Frame 0x20 $payload
}

function Format-HexBytes([byte[]]$Bytes) {
    return (($Bytes | ForEach-Object { $_.ToString("X2") }) -join " ")
}

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$serial.ReadTimeout = 20
$serial.WriteTimeout = 1000
$serial.DtrEnable = $true
$serial.RtsEnable = $true

$rx = New-Object System.Collections.Generic.List[byte]
$seq = 0x4100
$request = New-ReadRequest $seq 0x0000

try {
    $serial.Open()
    $serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()

    "TX_READ_ID=$(Format-HexBytes $request)"
    $serial.Write($request, 0, $request.Length)

    $startedAt = Get-Date
    while (((Get-Date) - $startedAt).TotalMilliseconds -lt $DurationMs) {
        try {
            $rx.Add([byte]$serial.ReadByte())
        } catch [System.TimeoutException] {
        }

        while ($rx.Count -ge 5) {
            if ($rx[0] -ne $SOF) {
                "DROP_BYTE=0x$($rx[0].ToString('X2'))"
                $rx.RemoveAt(0)
                continue
            }

            $len = [int]$rx[3]
            if ($len -gt 32) {
                "DROP_BAD_LEN=$len"
                $rx.RemoveAt(0)
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

            $payload = @()
            for ($i = 0; $i -lt $len; $i += 1) {
                $payload += $raw[4 + $i]
            }

            $ok = $checksum -eq $raw[$total - 1]
            "FRAME type=0x$($raw[2].ToString('X2')) len=$len checksum_ok=$ok payload=$(Format-HexBytes ([byte[]]$payload)) raw=$(Format-HexBytes $raw)"
        }
    }

    "PENDING_BYTES=$($rx.Count)"
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
