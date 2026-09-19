@echo off
chcp 65001 >nul
setlocal EnableExtensions
title 北工大校园网助手
cls

REM ============================================================
REM 北工大校园网助手
REM 双击运行一次，完成校园网认证后自动退出
REM ============================================================

set "account=YOUR_ACCOUNT@campus"
set "password=YOUR_PASSWORD"

set "server=http://10.21.221.98:801/eportal/portal/login"


echo ============================================================
echo.
echo                  北工大校园网助手
echo.
echo ============================================================
echo.


REM ============================================================
REM 1. 检查当前是否已经联网
REM ============================================================

echo [检测] 正在检查网络状态...

curl.exe -fsS ^
    --connect-timeout 3 ^
    --max-time 6 ^
    "https://www.baidu.com/favicon.ico" ^
    -o NUL >nul 2>&1

if not errorlevel 1 (
    echo [信息] 当前网络已经可以正常访问 Internet
    echo.
    timeout /t 3 /nobreak >nul
    exit /b
)


REM ============================================================
REM 2. 检测校园网认证服务器
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
    timeout /t 5 /nobreak >nul
    exit /b
)


REM ============================================================
REM 3. 自动获取当前物理网卡 IPv4
REM ============================================================

set "ip="

for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -Command "$c=Get-NetIPConfiguration ^| Where-Object {$_.IPv4DefaultGateway -and $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' -and $_.NetAdapter.HardwareInterface} ^| Sort-Object {$_.NetIPv4Interface.InterfaceMetric} ^| Select-Object -First 1; if($c){$c.IPv4Address.IPAddress}"`) do (
    set "ip=%%I"
)

if not defined ip (
    echo [失败] 未获取到有效 IPv4 地址
    echo.
    timeout /t 5 /nobreak >nul
    exit /b
)


echo [信息] 当前 IPv4：%ip%
echo [认证] 正在登录校园网...


REM ============================================================
REM 4. 提交校园网认证
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


REM 等待认证生效
timeout /t 3 /nobreak >nul


REM ============================================================
REM 5. 验证登录结果
REM ============================================================

curl.exe -fsS ^
    --connect-timeout 3 ^
    --max-time 8 ^
    "https://www.baidu.com/favicon.ico" ^
    -o NUL >nul 2>&1

if not errorlevel 1 (
    echo [成功] 校园网认证成功，网络已连接
) else (
    echo [失败] 校园网认证未成功
)

echo.
echo 窗口将在 5 秒后关闭...
timeout /t 5 /nobreak >nul
exit /b
