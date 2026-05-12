# KH-ImmortalWrt-x86_64

GitHub Actions 用 **[ImmortalWrt 官方 ImageBuilder](https://downloads.immortalwrt.org/releases/)** 自动拼装 x86_64 软路由固件，集成常用应用：

- **代理 / 翻墙**：PassWall + PassWall 2 + OpenClash + xray-core / sing-box / hysteria / shadowsocks-rust 等核心
- **远程组网**：Tailscale、ZeroTier、Cloudflare Tunnel (cloudflared)
- **服务**：KMS 服务器 (vlmcsd) — 局域网内激活 Windows / Office；SNMP daemon — Prometheus / Zabbix / LibreNMS 监控
- **界面**：Argon 主题（带配置面板，可换背景/调透明度）

> 单次 build 约 **10–15 分钟**（不再 from-source 编译）。所有 .ipk 包都来自 ImmortalWrt 官方源 + kenzok8 社区维护的 .ipk 镜像。

---

## 目录结构

```
.
├── .github/workflows/build.yml    # ImageBuilder 流水线
├── packages.list                  # 想装的包列表（一行一个）
├── scripts/
│   └── test-firmware.ps1          # Windows 上 QEMU 一键测试脚本
├── files/                         # （可选）打包进固件 rootfs 的额外文件
└── README.md
```

---

## 工作原理

`make image PROFILE=generic PACKAGES="..."` 是 OpenWrt / ImmortalWrt 官方的标准 **ImageBuilder** 命令。它不编译源码 —— 而是：

1. 拉 ImmortalWrt **已经编译好、测试过**的 `.ipk` 包（来自 ImmortalWrt 官方 + 第三方 .ipk 镜像）
2. 把这些 `.ipk` 装进一个 squashfs rootfs
3. 跟内核打包成 `*-combined-efi.img.gz` / `*-combined.img.gz`

整个过程**没有 cross-compile**，所以也就不可能撞 source build 那些坑（lyaml/libyaml 缺失、sing-box 的 broken vendored fork、kernel build_dir 跨节点路径……我们都见识过了）。

### 跟以前 source build 的对比

| 维度 | 老的 source-build | 现在 ImageBuilder |
| --- | --- | --- |
| 编译时间 | 1–3 小时 | **10–15 分钟** |
| 失败率 | ~50%（上游 break 一个包 = build 整体 fail） | 几乎 0（.ipk 都是上游已成功 build 的） |
| 自定义自由度 | 高（任何 source patch） | 中（只能选官方编好的 .ipk） |
| 缓存复杂度 | ccache + dl + Go + Cargo 多层 | 不需要 |
| 上游 broken 时影响 | 整个流水线挂 | 不受影响（.ipk 是稳定快照） |

### 自动触发

- `push` 到 `main` 分支（除 `README.md` / `.gitignore` / `*.md` / `scripts/*.ps1` 之外）—— 主要是改 `packages.list` 会触发
- 手动 `workflow_dispatch`（可选改 ImageBuilder 版本）

---

## 怎么改装的包

**只编辑 [packages.list](packages.list)**，每行一个包名。push 后约 15 分钟出新 release。

```
# 加 SQM 流控
luci-app-sqm

# 加 Docker 支持
docker docker-compose dockerd
luci-app-dockerman
```

不需要懂 OpenWrt build system，不需要本地编译，不需要 `.config` 几千行配置。

**包名查询**：

- ImmortalWrt 官方包：[downloads.immortalwrt.org/releases/24.10.2/packages/x86_64/](https://downloads.immortalwrt.org/releases/24.10.2/packages/x86_64/)
- kenzok8 .ipk 镜像（PassWall / OpenClash 等）：[op.supes.top/packages/x86_64/](https://op.supes.top/packages/x86_64/)

包名跟 source 名一致，去掉 `CONFIG_PACKAGE_` 前缀。

---

## 直接下载固件

到 [Releases](../../releases) 找最新 tag，按需下载：

| 文件 | 用途 |
| --- | --- |
| `immortalwrt-*-x86-64-generic-squashfs-combined-efi.img.gz` | **UEFI 主板首选**（PVE / 现代主板） |
| `immortalwrt-*-x86-64-generic-squashfs-combined.img.gz` | 传统 BIOS 启动 |
| `immortalwrt-*-x86-64-generic-ext4-combined-efi.img.gz` | UEFI + ext4（可在 OpenWrt 内 resize 分区） |
| `immortalwrt-*-x86-64-generic-ext4-combined.img.gz` | BIOS + ext4 |
| `immortalwrt-*-x86-64-generic-rootfs.tar.gz` | LXC / Docker / 自建系统 |
| `sha256sums`、`*.manifest`、`profiles.json`、`*.buildinfo` | 校验 + 元数据 |

写盘工具推荐 [balenaEtcher](https://etcher.balena.io/) 或 PVE 内 `qm importdisk`。

默认 LAN IP **192.168.1.1**，首次访问会强制设 root 密码。

---

## 在 Windows 上快速试跑（QEMU）

仓库自带一个一键脚本 [scripts/test-firmware.ps1](scripts/test-firmware.ps1)：

```powershell
# 一次性安装依赖
winget install QEMU.QEMU
winget install GitHub.cli ; gh auth login

# 启动测试虚拟机（默认拉最新 release 的 x86_64 BIOS 镜像）
.\scripts\test-firmware.ps1
```

脚本会自动：

1. 拉最新 Release 的 `*-squashfs-combined.img.gz`
2. 解压
3. 启动 QEMU，把宿主机 `localhost:8080` 转发到 VM `:80`
4. 约 30 秒后自动打开浏览器到 `http://localhost:8080`

退出：PowerShell 里按 `Ctrl-A` 然后 `X`。

---

## 配置示例

### Tailscale（编译进固件但无 LuCI 前端）

SSH 进路由器：

```sh
ssh root@192.168.1.1
tailscale up
# 跟着输出的 URL 浏览器认证，回车继续
```

### SNMP（编译进固件，无 LuCI 前端）

```sh
ssh root@192.168.1.1
uci set snmpd.public.community='your_secret'
uci set snmpd.public.source='lan'
uci commit snmpd
/etc/init.d/snmpd restart
```

### PassWall / OpenClash

LuCI 里 **服务** → **PassWall**（或 OpenClash） → 添加节点 → 启动。

---

## 工作流可选输入

| 输入参数 | 默认值 | 说明 |
| --- | --- | --- |
| `ibuilder_version` | `24.10.2` | 要用的 ImmortalWrt release（如 `24.10.0`、`SNAPSHOT`） |
| `upload_release` | `true` | 编译完成后自动创建 GitHub Release |

---

## 常见问题

**Q: ImageBuilder 拼装时有 .ipk 找不到怎么办？**
A: 看 build log 里 `Unknown package '...'`。原因可能是：
- 包名拼错 — 去 [op.supes.top/packages/x86_64/](https://op.supes.top/packages/x86_64/) 或官方索引核对
- 该包未在当前 ImmortalWrt 版本发布 — 试 `workflow_dispatch` 切到 `24.10.1` 或 `SNAPSHOT`
- 该包是 ImmortalWrt source 才有、没有 .ipk —— 此时只能等社区编一份 .ipk，或换包

**Q: 跨大版本升级（如 24.10 → 25.x）**
A: ImageBuilder 切版本 = 改 workflow_dispatch 输入 `ibuilder_version`，重 build 出新 release，sysupgrade 升级。建议**不保留旧配置**（`sysupgrade -n`），手动从备份导入 PassWall 节点等。

**Q: 想换 SNAPSHOT (滚动版)？**
A: 手动触发时 `ibuilder_version: SNAPSHOT`。注意 SNAPSHOT 没有 LuCI 默认装，要在 packages.list 加 `luci`、`luci-ssl-openssl` 等。

**Q: 公开仓库 GitHub Actions 是免费的吗？**
A: 是。标准 `ubuntu-*` runner 对公开仓库**完全免费且无限**。Release 附件存储也无限免费。

---

## License

工作流与脚本：MIT。  ImmortalWrt 本身按 GPL-2.0 分发。
