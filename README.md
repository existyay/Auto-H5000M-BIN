# 🚀 ImmortalWrt H5000M 自动编译

[![Build ImmortalWrt MT798x](https://github.com/existyay/Auto-H5000M-BIN/actions/workflows/build.yml/badge.svg)](https://github.com/existyay/Auto-H5000M-BIN/actions/workflows/build.yml)

基于 [padavanonly/immortalwrt-mt798x-24.10](https://github.com/padavanonly/immortalwrt-mt798x-24.10) 源码，分支 [`mt798x-mt799x-6.6-mtwifi`](https://github.com/padavanonly/immortalwrt-mt798x-24.10/tree/mt798x-mt799x-6.6-mtwifi)，自动编译 H5000M 路由器固件。

---

## 📥 下载固件

前往 [Releases](https://github.com/existyay/Auto-H5000M-BIN/releases) 页面下载最新固件。

---

## 🔧 默认配置

| 项目               | 值                                     |
| ------------------ | -------------------------------------- |
| **访问地址** | `192.168.6.1` 或 `immortalwrt.lan` |
| **用户名**   | `root`                               |
| **密码**     | `admin`                              |

---

## 📦 预装插件

### 🌐 网络管理

- **QModem** - 5G/LTE 模组管理（支持 Quectel、Fibocom 等）
- **HomeProxy** - 代理工具
- **MWAN3** - 多 WAN 负载均衡
- **UPnP** - 自动端口映射

### 🛡️ 系统工具

- **AdGuardHome** - 广告过滤 & DNS
- **Argon 主题** - 美化界面
- **TurboACC-MTK** - MTK 硬件加速
- **Vlmcsd** - KMS 激活服务器
- **RamFree** - 内存释放

### 🔌 硬件支持

- **Airpifanctrl** - 风扇控制
- **kmod-tun** - TUN 隧道支持
- **ip-full** - 完整 IP 工具

---

## ⏰ 编译计划

- **自动编译**: 每周一北京时间 00:00
- **手动触发**: Actions → Run workflow

---

## 🔗 相关链接

- [上游源码](https://github.com/padavanonly/immortalwrt-mt798x-24.10)
- [QModem 项目](https://github.com/FUjr/QModem)
- [ImmortalWrt 官网](https://immortalwrt.org/)

---

## 📝 许可证

本项目遵循上游项目许可证。
