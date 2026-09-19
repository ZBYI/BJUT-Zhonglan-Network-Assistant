@echo off
chcp 65001 >nul
setlocal EnableExtensions
title 北工大校园网助手
cls

REM ============================================================
REM 北工大校园网助手 - v2.0.0
REM
REM 功能：
REM 1. 自动扫描中蓝校区校园 Wi-Fi
REM 2. 仅匹配 CMCC-BJUT-SUSHE-H数字-5G
REM 3. 自动选择信号最强的校园 Wi-Fi
REM 4. 首次连接开放 Wi-Fi 时自动创建 WLAN 配置
REM 5. 自动连接目标 Wi-Fi
REM 6. 自动获取当前 IPv4
REM 7. 自动执行校园网 Portal 认证
REM 8. 登录完成后自动退出
REM ============================================================

REM -------- 用户设置 --------
set "account=YOUR_ACCOUNT@campus"
set "password=YOUR_PASSWORD"

REM -------- Portal --------
set "server=http://10.21.221.98:801/eportal/portal/login"


echo ============================================================
echo.
echo                  北工大校园网助手
echo.
echo ============================================================
echo.


REM ============================================================
REM 1. 检查基本组件
REM ============================================================

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [失败] 未找到 Windows PowerShell
    pause
    exit /b 1
)

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo [失败] 未找到 curl.exe
    pause
    exit /b 1
)


REM ============================================================
REM 2. 扫描中蓝校园 Wi-Fi
REM
REM 只匹配：
REM CMCC-BJUT-SUSHE-H数字-5G
REM ============================================================

echo [扫描] 正在搜索附近的中蓝校园 Wi-Fi...
echo.

set "best_ssid="
set "best_signal="

for /f "tokens=1-3 delims=|" %%A in ('powershell.exe -NoProfile -Command "$bestSsid='';$bestSignal=-1;$current='';foreach($line in (netsh wlan show networks mode=bssid)){$m=[regex]::Match($line,'^s*SSIDs+d+s*:s*(.+)$');if($m.Success){$current=$m.Groups[1].Value.Trim();continue};if([regex]::IsMatch($current,'^CMCC-BJUT-SUSHE-Hd+-5G$') -and $line.TrimEnd().EndsWith([char]37)){$s=[regex]::Match($line,':s*(d+)');if($s.Success){$v=[int]$s.Groups[1].Value;if($v -gt $bestSignal){$bestSignal=$v;$bestSsid=$current}}}};if($bestSignal -ge 0){Write-Output ('BEST|' + $bestSsid + '|' + $bestSignal)}"') do (
    if /i "%%A"=="BEST" (
        set "best_ssid=%%B"
        set "best_signal=%%C"
    )
)


REM ============================================================
REM 3. 判断有没有扫描到符合规则的 Wi-Fi
REM ============================================================

if not defined best_ssid (
    echo [信息] 未发现符合规则的中蓝校园 Wi-Fi
    echo [信息] 保持当前网络连接
    echo.
    goto PORTAL_START
)


echo [选择] 信号最强的校园 Wi-Fi：
echo.
echo        %best_ssid%
echo        信号强度：%best_signal%%%
echo.


REM ============================================================
REM 4. 获取当前正在连接的 Wi-Fi
REM ============================================================

call :GET_CURRENT_SSID

if defined current_ssid (
    echo [信息] 当前 Wi-Fi：%current_ssid%
) else (
    echo [信息] 当前未连接 Wi-Fi
)

echo.


REM ============================================================
REM 5. 如果已经连接最强 Wi-Fi，就不切换
REM ============================================================

if /i "%current_ssid%"=="%best_ssid%" (
    echo [信息] 当前已经连接信号最强的校园 Wi-Fi
    echo.
    goto WAIT_NETWORK
)


REM ============================================================
REM 6. 检查 Windows 是否已经保存该 Wi-Fi
REM ============================================================

echo [连接] 准备连接：
echo        %best_ssid%
echo.

netsh wlan show profile name="%best_ssid%" >nul 2>&1

if not errorlevel 1 (
    goto CONNECT_WIFI
)


REM ============================================================
REM 7. 第一次遇到这个开放 Wi-Fi
REM    自动创建 WLAN Profile
REM ============================================================

echo [配置] 首次连接该 Wi-Fi，正在创建网络配置...

set "profileFile=%TEMP%BJUT_WLAN_%RANDOM%_%RANDOM%.xml"

> "%profileFile%" (
    echo ^<?xml version="1.0"?^>
    echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^>
    echo ^<name^>%best_ssid%^</name^>
    echo ^<SSIDConfig^>
    echo ^<SSID^>
    echo ^<name^>%best_ssid%^</name^>
    echo ^</SSID^>
    echo ^<nonBroadcast^>false^</nonBroadcast^>
    echo ^</SSIDConfig^>
    echo ^<connectionType^>ESS^</connectionType^>
    echo ^<connectionMode^>manual^</connectionMode^>
    echo ^<MSM^>
    echo ^<security^>
    echo ^<authEncryption^>
    echo ^<authentication^>open^</authentication^>
    echo ^<encryption^>none^</encryption^>
    echo ^<useOneX^>false^</useOneX^>
    echo ^</authEncryption^>
    echo ^</security^>
    echo ^</MSM^>
    echo ^</WLANProfile^>
)

netsh wlan add profile filename="%profileFile%" user=current >nul 2>&1

if errorlevel 1 (
    del /q "%profileFile%" >nul 2>&1
    echo [失败] Wi-Fi 配置创建失败
    echo.
    pause
    exit /b 1
)

del /q "%profileFile%" >nul 2>&1

echo [配置] Wi-Fi 配置创建成功
echo.


REM ============================================================
REM 8. 连接信号最强 Wi-Fi
REM ============================================================

:CONNECT_WIFI

echo [连接] 正在连接：
echo        %best_ssid%

netsh wlan connect name="%best_ssid%" ssid="%best_ssid%" >nul 2>&1

if errorlevel 1 (
    echo.
    echo [失败] Windows 无法发起 Wi-Fi 连接
    pause
    exit /b 1
)


REM ============================================================
REM 9. 最多等待 15 秒确认 Wi-Fi 已切换
REM ============================================================

set /a wifi_try=0

:WAIT_WIFI

timeout /t 1 /nobreak >nul

call :GET_CURRENT_SSID

if /i "%current_ssid%"=="%best_ssid%" goto WIFI_CONNECTED

set /a wifi_try+=1

if %wifi_try% GEQ 15 (
    echo.
    echo [失败] Wi-Fi 连接超时
    echo [目标] %best_ssid%
    echo [当前] %current_ssid%
    echo.
    pause
    exit /b 1
)

goto WAIT_WIFI


:WIFI_CONNECTED

echo.
echo [成功] Wi-Fi 已连接
echo [信息] %best_ssid%
echo.


REM ============================================================
REM 10. 等待 DHCP
REM ============================================================

:WAIT_NETWORK

echo [等待] 正在初始化网络...
timeout /t 3 /nobreak >nul


REM ============================================================
REM 11. Portal 流程
REM ============================================================

:PORTAL_START

echo [检测] 正在检查 Internet...

curl.exe -fsS ^
    --connect-timeout 3 ^
    --max-time 6 ^
    "https://www.baidu.com/favicon.ico" ^
    -o NUL >nul 2>&1

if not errorlevel 1 (
    echo [成功] 当前已经可以正常访问 Internet
    echo.
    timeout /t 3 /nobreak >nul
    exit /b
)


REM ============================================================
REM 12. 检查 Portal
REM ============================================================

echo [检测] 正在检测校园网认证服务...

curl.exe -sS ^
    --connect-timeout 2 ^
    --max-time 4 ^
    "%server%" ^
    -o NUL >nul 2>&1

if errorlevel 1 (
    echo [失败] 当前无法连接校园网认证服务器
    echo.
    pause
    exit /b 1
)


REM ============================================================
REM 13. 获取 IPv4
REM ============================================================

echo [检测] 正在获取当前 IPv4...

set /a ip_try=0

:GET_IP

set "ip="

for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "$c=Get-NetIPConfiguration ^| Where-Object {$_.IPv4DefaultGateway -and $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' -and $_.NetAdapter.HardwareInterface} ^| Sort-Object {$_.NetIPv4Interface.InterfaceMetric} ^| Select-Object -First 1;if($c){$c.IPv4Address.IPAddress}"`) do (
    set "ip=%%I"
)

if defined ip goto IP_READY

set /a ip_try+=1

if %ip_try% GEQ 10 (
    echo [失败] 未获取到有效 IPv4 地址
    echo.
    pause
    exit /b 1
)

timeout /t 1 /nobreak >nul
goto GET_IP


:IP_READY

echo [信息] 当前 IPv4：%ip%
echo [认证] 正在登录校园网...


REM ============================================================
REM 14. Portal 登录
REM ============================================================

curl.exe -sS -G "%server%" ^
    --connect-timeout 5 ^
    --max-time 10 ^
    --data-urlencode "callback=dr1003" ^
    --data-urlencode "login_method=1" ^
    --data-urlencode "user_account=%account%" ^
    --data-urlencode "user_password=%password%" ^
    --data-urlencode "wlan_user_ip=%ip%" ^
    --data-urlencode "wlan_user_ipv6=" ^
    --data-urlencode "wlan_user_mac=000000000000" ^
    --data-urlencode "wlan_ac_ip=" ^
    --data-urlencode "wlan_ac_name=" ^
    --data-urlencode "jsVersion=4.2.1" ^
    --data-urlencode "terminal_type=1" ^
    --data-urlencode "lang=zh-cn" ^
    --data-urlencode "v=7103" ^
    --data-urlencode "lang=zh" ^
    -o NUL >nul 2>&1

timeout /t 3 /nobreak >nul


REM ============================================================
REM 15. 验证最终结果
REM ============================================================

echo [检测] 正在验证网络连接...

curl.exe -fsS ^
    --connect-timeout 3 ^
    --max-time 8 ^
    "https://www.baidu.com/favicon.ico" ^
    -o NUL >nul 2>&1

if not errorlevel 1 (
    echo.
    echo [成功] 校园网认证成功，网络已连接
) else (
    echo.
    echo [失败] 校园网认证未成功
)

echo.
echo 窗口将在 5 秒后关闭...
timeout /t 5 /nobreak >nul
exit /b


REM ============================================================
REM 子程序：读取当前连接的 Wi-Fi SSID
REM ============================================================

:GET_CURRENT_SSID

set "current_ssid="

for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "$lines=netsh wlan show interfaces;foreach($line in $lines){$m=[regex]::Match($line,'^s*SSIDs*:s*(.+)$');if($m.Success){$m.Groups[1].Value.Trim();break}}"`) do (
    set "current_ssid=%%I"
)

exit /b
