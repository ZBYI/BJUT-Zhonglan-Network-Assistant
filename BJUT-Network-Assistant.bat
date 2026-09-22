@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions
cls
title BJUT Network Assistant v3.2 Extreme

REM ============================================================
REM USER CONFIG - only edit the next two lines
REM Keep @campus after your account
REM ============================================================
set "BJUT_ACCOUNT=YOUR_ACCOUNT@campus"
set "BJUT_PASSWORD=YOUR_PASSWORD"
set "BJUT_SERVER=http://10.21.221.98:801/eportal/portal/login"
set "BJUT_SELF=%~f0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText($env:BJUT_SELF,[Text.Encoding]::UTF8);$m='#<BJUT-'+'POWERSHELL>';$i=$f.IndexOf($m);if($i -lt 0){exit 90};& ([ScriptBlock]::Create($f.Substring($i+$m.Length)))"
set "BJUT_RC=%errorlevel%"
exit /b %BJUT_RC%

#<BJUT-POWERSHELL>

# ============================================================
# BJUT Network Assistant v3.2.0 Extreme
# 单 PowerShell 进程 + 高频条件检测 + Portal 返回值直读
# ============================================================

$Account = $env:BJUT_ACCOUNT
$Password = $env:BJUT_PASSWORD
$Server = $env:BJUT_SERVER
$TargetPattern = '^CMCC-BJUT-SUSHE-H\d+-5G$'
$InternetProbe = 'https://www.baidu.com/favicon.ico'

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'SilentlyContinue'

function Write-Status {
    param(
        [string]$Tag,
        [string]$Text,
        [ConsoleColor]$TagColor = [ConsoleColor]::Cyan,
        [ConsoleColor]$TextColor = [ConsoleColor]::Gray
    )

    Write-Host ("[{0}] " -f $Tag) -NoNewline -ForegroundColor $TagColor
    Write-Host $Text -ForegroundColor $TextColor
}

function Exit-Success {
    param([string]$Message)

    Write-Host
    Write-Status '成功' $Message Green Green
    Start-Sleep -Milliseconds 350
    exit 0
}

function Exit-Failure {
    param(
        [string]$Message,
        [int]$Code = 1
    )

    Write-Host
    Write-Status '失败' $Message Red Red
    Write-Host
    Write-Host '按任意键关闭窗口...' -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
    exit $Code
}

function Get-CurrentSsid {
    $lines = & netsh.exe wlan show interfaces 2>$null

    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^\s*SSID\s*:\s*(.+)$')
        if ($m.Success) {
            return $m.Groups[1].Value.Trim()
        }
    }

    return $null
}

function Test-TargetSsid {
    param([string]$Ssid)

    if ([string]::IsNullOrWhiteSpace($Ssid)) {
        return $false
    }

    return [regex]::IsMatch($Ssid, $TargetPattern)
}

function Find-BestCampusWifi {
    $map = @{}
    $current = ''

    $lines = & netsh.exe wlan show networks mode=bssid 2>$null

    foreach ($line in $lines) {
        $ssidMatch = [regex]::Match($line, '^\s*SSID\s+\d+\s*:\s*(.+)$')

        if ($ssidMatch.Success) {
            $current = $ssidMatch.Groups[1].Value.Trim()
            continue
        }

        if (-not [regex]::IsMatch($current, $TargetPattern)) {
            continue
        }

        $signalMatch = [regex]::Match($line, ':\s*(\d+)\s*%\s*$')

        if ($signalMatch.Success) {
            $signal = [int]$signalMatch.Groups[1].Value

            if ((-not $map.ContainsKey($current)) -or ($signal -gt $map[$current])) {
                $map[$current] = $signal
            }
        }
    }

    if ($map.Count -eq 0) {
        return $null
    }

    $best = $map.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First 1

    return [pscustomobject]@{
        Ssid   = [string]$best.Key
        Signal = [int]$best.Value
    }
}

function Get-WifiIPv4 {
    try {
        $interfaces = [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()

        foreach ($nic in $interfaces) {
            if ($nic.OperationalStatus -ne [Net.NetworkInformation.OperationalStatus]::Up) {
                continue
            }

            if ($nic.NetworkInterfaceType -ne [Net.NetworkInformation.NetworkInterfaceType]::Wireless80211) {
                continue
            }

            $props = $nic.GetIPProperties()

            $gateway = $props.GatewayAddresses |
                Where-Object {
                    $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
                    $_.Address.ToString() -ne '0.0.0.0'
                } |
                Select-Object -First 1

            if (-not $gateway) {
                continue
            }

            $addr = $props.UnicastAddresses |
                Where-Object {
                    $_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
                    -not $_.Address.ToString().StartsWith('169.254.')
                } |
                Select-Object -First 1

            if ($addr) {
                return $addr.Address.ToString()
            }
        }
    }
    catch {
    }

    return $null
}

function Test-Internet {
    param([int]$TimeoutMs = 700)

    $response = $null

    try {
        $request = [Net.HttpWebRequest]::Create($InternetProbe)
        $request.Method = 'GET'
        $request.Timeout = $TimeoutMs
        $request.ReadWriteTimeout = $TimeoutMs
        $request.AllowAutoRedirect = $true
        $request.Proxy = $null
        $request.KeepAlive = $false
        $request.UserAgent = 'Mozilla/5.0'

        $response = $request.GetResponse()
        $code = [int]$response.StatusCode

        return ($code -ge 200 -and $code -lt 400)
    }
    catch {
        return $false
    }
    finally {
        if ($response) {
            try { $response.Close() } catch {}
        }
    }
}

function Ensure-WlanProfile {
    param([string]$Ssid)

    & netsh.exe wlan show profile name="$Ssid" *> $null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    Write-Status '配置' '首次连接该开放 Wi-Fi，正在创建 WLAN 配置...' Yellow Yellow

    $profileFile = Join-Path $env:TEMP ("BJUT_WLAN_{0}.xml" -f [guid]::NewGuid().ToString('N'))

    $xml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$Ssid</name>
    <SSIDConfig>
        <SSID>
            <name>$Ssid</name>
        </SSID>
        <nonBroadcast>false</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>manual</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>open</authentication>
                <encryption>none</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
        </security>
    </MSM>
</WLANProfile>
"@

    try {
        [IO.File]::WriteAllText(
            $profileFile,
            $xml,
            (New-Object System.Text.UTF8Encoding($false))
        )

        & netsh.exe wlan add profile filename="$profileFile" user=current *> $null
        $code = $LASTEXITCODE
    }
    catch {
        $code = 1
    }
    finally {
        Remove-Item -LiteralPath $profileFile -Force -ErrorAction SilentlyContinue
    }

    if ($code -eq 0) {
        Write-Status '配置' 'WLAN 配置创建成功' Green Green
        return $true
    }

    return $false
}

function Add-QueryValue {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Key,
        [string]$Value
    )

    $escaped = [Uri]::EscapeDataString([string]$Value)
    $List.Add(("{0}={1}" -f $Key, $escaped))
}

function Invoke-PortalLogin {
    param(
        [string]$Ip
    )

    $parts = New-Object 'System.Collections.Generic.List[string]'

    Add-QueryValue $parts 'callback' 'dr1003'
    Add-QueryValue $parts 'login_method' '1'
    Add-QueryValue $parts 'user_account' $Account
    Add-QueryValue $parts 'user_password' $Password
    Add-QueryValue $parts 'wlan_user_ip' $Ip
    Add-QueryValue $parts 'wlan_user_ipv6' ''
    Add-QueryValue $parts 'wlan_user_mac' '000000000000'
    Add-QueryValue $parts 'wlan_ac_ip' ''
    Add-QueryValue $parts 'wlan_ac_name' ''
    Add-QueryValue $parts 'jsVersion' '4.2.1'
    Add-QueryValue $parts 'terminal_type' '1'
    Add-QueryValue $parts 'lang' 'zh-cn'
    Add-QueryValue $parts 'v' '7103'
    Add-QueryValue $parts 'lang' 'zh'

    $url = $Server + '?' + ($parts -join '&')

    $response = $null
    $reader = $null

    try {
        $request = [Net.HttpWebRequest]::Create($url)
        $request.Method = 'GET'
        $request.Timeout = 2500
        $request.ReadWriteTimeout = 2500
        $request.Proxy = $null
        $request.KeepAlive = $false
        $request.UserAgent = 'Mozilla/5.0'

        $response = $request.GetResponse()
        $reader = New-Object IO.StreamReader(
            $response.GetResponseStream(),
            [Text.Encoding]::UTF8
        )

        $text = $reader.ReadToEnd()

        $result = $null
        $message = $null

        $first = $text.IndexOf('{')
        $last = $text.LastIndexOf('}')

        if ($first -ge 0 -and $last -gt $first) {
            try {
                $json = $text.Substring($first, $last - $first + 1) | ConvertFrom-Json
                $result = [int]$json.result
                $message = [string]$json.msg
            }
            catch {
            }
        }

        return [pscustomobject]@{
            TransportOk = $true
            Success     = ($result -eq 1)
            Result      = $result
            Message     = $message
            Raw         = $text
        }
    }
    catch {
        return [pscustomobject]@{
            TransportOk = $false
            Success     = $false
            Result      = $null
            Message     = $_.Exception.Message
            Raw         = ''
        }
    }
    finally {
        if ($reader) {
            try { $reader.Close() } catch {}
        }

        if ($response) {
            try { $response.Close() } catch {}
        }
    }
}

Clear-Host

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host
Write-Host '                 北工大校园网助手' -ForegroundColor White
Write-Host '                 v3.2.0 EXTREME' -ForegroundColor Cyan
Write-Host
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host

if ($Account -eq 'YOUR_ACCOUNT@campus' -or [string]::IsNullOrWhiteSpace($Account)) {
    Exit-Failure '请先修改 BAT 顶部的校园网账号。'
}

if (-not $Account.EndsWith('@campus', [StringComparison]::OrdinalIgnoreCase)) {
    Exit-Failure '账号格式错误：账号末尾必须保留 @campus。'
}

if ($Password -eq 'YOUR_PASSWORD' -or [string]::IsNullOrWhiteSpace($Password)) {
    Exit-Failure '请先修改 BAT 顶部的校园网密码。'
}

$current = Get-CurrentSsid
$previous = $current
$disconnectedNonTarget = $false

if ([string]::IsNullOrWhiteSpace($current)) {
    Write-Status '信息' '当前未连接 Wi-Fi'
}
else {
    Write-Status '当前' $current Cyan White

    if (Test-TargetSsid $current) {
        Write-Status '判断' '当前已连接中蓝 5G 校园 Wi-Fi，不主动断开' Green Green
    }
    else {
        Write-Status '切换' '当前不是目标校园 Wi-Fi，立即断开...' Yellow Yellow

        & netsh.exe wlan disconnect *> $null
        $disconnectCode = $LASTEXITCODE

        if ($disconnectCode -eq 0) {
            $disconnectedNonTarget = $true
            Write-Status '成功' ("已断开：{0}" -f $current) Green Green
        }
        else {
            Write-Status '警告' 'Windows 未确认断开成功，继续执行扫描' Yellow Yellow
        }
    }
}

Write-Status '扫描' '正在搜索中蓝 5G 校园 Wi-Fi...' Cyan Cyan

$best = $null

for ($scanTry = 0; $scanTry -lt 3; $scanTry++) {
    $best = Find-BestCampusWifi

    if ($best) {
        break
    }

    if ($scanTry -lt 2) {
        Start-Sleep -Milliseconds 120
    }
}

if (-not $best) {
    if ($disconnectedNonTarget -and -not [string]::IsNullOrWhiteSpace($previous)) {
        Write-Status '恢复' ("未发现目标校园 Wi-Fi，尝试重新连接：{0}" -f $previous) Yellow Yellow

        & netsh.exe wlan connect name="$previous" ssid="$previous" *> $null

        if ($LASTEXITCODE -eq 0) {
            Write-Status '恢复' '已发送重新连接请求' Green Green
        }
        else {
            Write-Status '警告' '无法自动恢复原 Wi-Fi' Yellow Yellow
        }

        Exit-Failure '附近没有发现符合规则的中蓝 5G 校园 Wi-Fi。' 2
    }

    if (Test-TargetSsid $current) {
        Write-Status '信息' '扫描暂未返回候选，继续使用当前校园 Wi-Fi' Yellow Yellow
        $best = [pscustomobject]@{
            Ssid   = $current
            Signal = -1
        }
    }
    else {
        Exit-Failure '附近没有发现符合规则的中蓝 5G 校园 Wi-Fi。' 2
    }
}

Write-Status '选择' $best.Ssid Green Yellow

if ($best.Signal -ge 0) {
    Write-Status '信号' ("{0}%" -f $best.Signal) Green Yellow
}

$current = Get-CurrentSsid

if ($current -ne $best.Ssid) {
    if (-not (Ensure-WlanProfile $best.Ssid)) {
        Exit-Failure '无法创建目标 Wi-Fi 的 Windows WLAN 配置。'
    }

    Write-Status '连接' ("正在连接：{0}" -f $best.Ssid) Cyan White

    & netsh.exe wlan connect name="$($best.Ssid)" ssid="$($best.Ssid)" *> $null
    $connectCode = $LASTEXITCODE

    if ($connectCode -ne 0) {
        Exit-Failure 'Windows 无法发起 Wi-Fi 连接。'
    }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $connected = $false

    do {
        $nowSsid = Get-CurrentSsid

        if ($nowSsid -eq $best.Ssid) {
            $connected = $true
            break
        }

        Start-Sleep -Milliseconds 120
    }
    while ($watch.ElapsedMilliseconds -lt 6500)

    if (-not $connected) {
        Exit-Failure ("Wi-Fi 连接超时。目标：{0}" -f $best.Ssid)
    }

    Write-Status '成功' 'Wi-Fi 已连接' Green Green
}
else {
    Write-Status '信息' '当前已经是信号最强的目标校园 Wi-Fi' Green Green
}

Write-Status '检测' '正在获取当前 IPv4...' Cyan Gray

$ipWatch = [Diagnostics.Stopwatch]::StartNew()
$ip = $null

do {
    $ip = Get-WifiIPv4

    if ($ip) {
        break
    }

    Start-Sleep -Milliseconds 100
}
while ($ipWatch.ElapsedMilliseconds -lt 7000)

if (-not $ip) {
    Exit-Failure '未获取到有效的 Wi-Fi IPv4 地址。'
}

Write-Status 'IPv4' $ip Cyan White

Write-Status '检测' '正在极速检查 Internet...' Cyan Gray

if (Test-Internet 700) {
    Exit-Success '当前已经可以正常访问 Internet'
}

Write-Status '认证' '正在登录校园网...' Magenta Magenta

$portal = Invoke-PortalLogin $ip

if (-not $portal.TransportOk) {
    Exit-Failure '无法连接校园网认证服务器。'
}

if ($portal.Success) {
    Write-Status '认证' 'Portal 已返回认证成功' Green Green
}
else {
    if (Test-Internet 700) {
        Exit-Success '当前已经可以正常访问 Internet'
    }

    if (-not [string]::IsNullOrWhiteSpace($portal.Message)) {
        Write-Status '原因' $portal.Message Red Red
        Exit-Failure 'Portal 未通过认证。'
    }

    Exit-Failure 'Portal 未返回认证成功结果。'
}

$verifyWatch = [Diagnostics.Stopwatch]::StartNew()

do {
    if (Test-Internet 700) {
        Exit-Success '校园网认证成功，网络已连接'
    }

    Start-Sleep -Milliseconds 120
}
while ($verifyWatch.ElapsedMilliseconds -lt 4500)

Write-Host
Write-Status '认证' 'Portal 已明确返回成功' Green Green
Write-Status '提示' 'Internet 探测暂未通过，Windows 网络状态可能仍在刷新。' Yellow Yellow
Write-Status '提示' '可直接打开浏览器测试网页；实际网络可能已经可用。' Yellow Yellow
Write-Host
Write-Host '按任意键关闭窗口...' -ForegroundColor DarkGray
[void][Console]::ReadKey($true)
exit 0
