# 北工大校园网助手

一个面向北京工业大学校园网的 Windows 批处理登录脚本。

## 功能

- 手动双击运行，不常驻后台
- 已经联网时直接退出，不重复认证
- 自动检测校园网认证服务器
- 自动获取当前正在使用的物理网卡 IPv4 地址
- 自动提交 ePortal 登录请求
- 登录后自动验证 Internet 连接
- 使用 UTF-8 中文控制台提示

## 使用方法

1. 下载 `BJUT-Network-Assistant.bat`。
2. 用记事本或其他文本编辑器打开文件。
3. 修改下面两行：

```bat
set "account=YOUR_ACCOUNT@campus"
set "password=YOUR_PASSWORD"
```

4. 以 UTF-8 编码保存。
5. 连接校园网 Wi-Fi 或有线网络后，双击运行脚本。
6. 认证完成后窗口会自动关闭。

## 注意事项

- 请勿把填写了真实账号和密码的版本提交到公开仓库或发送给他人。
- 脚本当前使用的认证地址为 `http://10.21.221.98:801/eportal/portal/login`。如果学校后续调整认证服务器，需要同步修改脚本中的 `server`。
- 不同校区只要使用同一认证服务器和账号域，脚本无需依赖 Wi-Fi 名称。
- 本项目为个人学习与便捷登录用途，与北京工业大学及校园网服务提供商无官方关联。

## 系统要求

- Windows 10 / Windows 11
- 系统自带 `curl.exe`
- Windows PowerShell

## 工作流程

```text
双击运行
  ↓
检测 Internet
  ├─ 已联网 → 直接退出
  └─ 未联网
       ↓
检测校园网 Portal
       ↓
自动获取 IPv4
       ↓
提交认证
       ↓
验证 Internet
       ↓
自动退出
```
