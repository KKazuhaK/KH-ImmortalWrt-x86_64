# KH-ImmortalWrt-x86_64

GitHub Actions 自动编译 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10` **x86_64** 固件，开箱集成以下应用：

- **代理 / 翻墙**：PassWall + PassWall 2 + OpenClash + xray-core / sing-box / hysteria / shadowsocks-rust 等核心
- **远程组网**：Tailscale、ZeroTier、Cloudflare Tunnel (cloudflared)
- **服务**：KMS 服务器 (vlmcsd) — 局域网内激活 Windows / Office；SNMP daemon — Prometheus / Zabbix / LibreNMS 监控
- **界面**：Argon 主题（带配置面板，可换背景/调透明度）

| Target | 架构 | 典型设备 |
| --- | --- | --- |
| `x86_64` | x86-64 | N100 / J4125 软路由、PC、PVE / ESXi 虚机 |

自动产出 **UEFI** 和 **legacy BIOS** 两种镜像；x86 不像路由器那样区分 factory/sysupgrade —— **第一次写盘和后续 LuCI 在线升级是同一个文件**。

工作流改编自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)（MIT License）。

---

## 目录结构

```
.
├── .github/workflows/build.yml    # matrix 构建工作流
├── configs/
│   └── x86_64.config              # x86_64 (64-bit, PassWall pre-integrated)
├── scripts/
│   ├── diy-part1.sh               # feeds 更新前 自定义脚本
│   └── diy-part2.sh               # feeds 安装后、make defconfig 前 自定义脚本
├── feeds.conf.default             # 自定义 feeds 列表
├── files/                         # （可选）打包进固件 rootfs 的文件
└── README.md
```

---

## 工作原理

每次 push（或手动触发）后：

```
prep                              # ~5s, 创建空 Release tag
 ├─ build (x86_64)        ─┐  并行跑, 各 ~30min–2h
 └─ build (x86_generic)   ─┘  把产物 append 到同一个 Release
```

总耗时 ≈ 最慢的一个 target，**不是 2 倍**。所有产物挂在同一个 Release tag 下（形如 `2026.05.11-1234`）。

### 缓存策略

每个 target 独立缓存：
- `dl/`（已下载源码 tarball）—— key 含 target 名 + `.config` 哈希
- `.ccache/`（C/C++ 编译产物缓存）—— key 含 target 名 + `.config` 哈希，单实例上限 2 GB
- **Go build cache + module cache** —— 覆盖 xray-core / sing-box / hysteria，首次后命中能省 30+ 分钟
- **Cargo registry + build target** —— 覆盖 shadowsocks-rust，首次后命中能省 20+ 分钟

GitHub 给每个 repo 的 actions/cache 总配额是 10 GB。2 个 x86 target 合计约 12–14 GB，会触发轻微的 LRU 驱逐 —— 常 push 的 target 缓存保留。**永远不会让 build 失败**。

### Release 产物过滤

工作流会自动删除不直接用于刷机的中间产物（独立 kernel.bin、单 rootfs.img.gz、initramfs、recovery、bootloader 部件、dtb、elf 等），Release 页面只列出真正需要的镜像。

### 自动触发条件

- `push` 到 `main` 分支（除 README/LICENSE/.md/.gitignore/.gitattributes 修改外）
- 手动 `workflow_dispatch`（可选 SSH 调试 / 上传 bin 目录）
- `concurrency.cancel-in-progress`：新 push 自动取消正在跑的旧 build

---

## 使用方法

### 直接下载固件

到 [Releases 页面](../../releases) 找最新 tag，按需下载：

| 文件 | 用途 |
| --- | --- |
| `immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz` | **x86_64 UEFI 主板首选**（PVE / 现代主板） |
| `immortalwrt-x86-64-generic-squashfs-combined.img.gz` | x86_64 传统 BIOS 启动 |
| `immortalwrt-x86-64-generic-ext4-combined-efi.img.gz` | UEFI + ext4（可在 OpenWrt 内 resize 分区） |
| `immortalwrt-x86-64-generic-ext4-combined.img.gz` | BIOS + ext4 |
| `immortalwrt-x86-64-generic-rootfs.tar.gz` | LXC / Docker / 自建系统 |
| `immortalwrt-x86-generic-generic-squashfs-combined.img.gz` | 32-bit BIOS 主板 |
| `immortalwrt-x86-generic-generic-squashfs-combined-efi.img.gz` | 32-bit UEFI 主板（罕见） |
| `sha256sums`、`*.manifest`、`profiles.json`、`*.buildinfo` | 校验 + 元数据 |

写盘工具推荐 [balenaEtcher](https://etcher.balena.io/) 或 PVE 内 `qm importdisk`。

### 在 SLURM 集群 / Linux 服务器上手动编译

如果你有 Linux 服务器（家用 PC、自己的 VPS、学校的 SLURM 集群如 [openlab.ics.uci.edu](https://openlab.ics.uci.edu) 等），可以用 [scripts/compile.sbatch](scripts/compile.sbatch) 跳过 GitHub Actions 直接本地编。它会应用本仓库的 `configs/x86_64.config` + `scripts/diy-part2.sh` + `feeds.conf.default`，产出跟 Release 一模一样的镜像。

```bash
# 在目标 Linux 服务器上
git clone https://github.com/KKazuhaK/KH-ImmortalWrt-x86_64.git ~/kh
cd ~/kh

# 方式 A — SLURM 提交（适合 openlab / 集群环境）
sbatch scripts/compile.sbatch
squeue -u $USER                          # 看队列状态
tail -f immortalwrt-x86_64-*.log         # 跟进编译日志

# 方式 B — 直接前台跑（适合家用 Linux 机器 / VPS）
bash scripts/compile.sbatch
```

编译完成后固件在 `$PWD/firmware-output/`。可调参数（环境变量）：

- `REPO_BRANCH`：上游分支（默认 `openwrt-24.10`）
- `WORK_DIR`：build_dir / ccache / dl 的位置，**持久化目录可跨次 build 复用缓存**（默认 `~/immortalwrt-build`）
- `OUTPUT_DIR`：固件输出位置（默认 `$PWD/firmware-output`）

SLURM 资源默认 8 核 / 16 GB / 4 小时上限，按需在文件头的 `#SBATCH` 行改。

### 在 Windows 上快速试跑（QEMU）

不刷物理设备就想看 LuCI 长什么样？仓库自带一个一键脚本 [scripts/test-firmware.ps1](scripts/test-firmware.ps1)：

```powershell
# 一次性安装依赖（QEMU + GitHub CLI）
winget install QEMU.QEMU
winget install GitHub.cli ; gh auth login

# 启动测试虚拟机（默认拉最新 release 的 x86_64 BIOS 镜像）
.\scripts\test-firmware.ps1
```

脚本会自动：

1. 拉最新 Release 的 `*-squashfs-combined.img.gz` 到 `.test-cache/`
2. 用 .NET 解压成 `.img`
3. 启动 QEMU，把宿主机的 `localhost:8080` 转发到虚拟机 `:80`、`localhost:2222` 转发到 `:22`
4. 约 30 秒后自动打开浏览器到 `http://localhost:8080`

退出虚拟机：在 PowerShell 里按 `Ctrl-A` 然后 `X`。

可选参数：`-Target x86_generic`（试 32-bit）、`-HttpPort 9000`（换端口）、`-Force`（强制重新下载）、`-NoBrowser`（不自动开浏览器）。

### 自己定制（推荐流程）

**第一次跑通后**，建议进入 ImmortalWrt 源码用 `make menuconfig` 选好需要的包，再把生成的 `.config` 复制回对应文件：

```bash
git clone https://github.com/immortalwrt/immortalwrt -b openwrt-24.10
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/this/repo/configs/x86_64.config .config
make menuconfig          # 勾选 LuCI 应用、主题、内核模块等
cp .config /path/to/this/repo/configs/x86_64.config
git add configs/x86_64.config && git commit -m "x86_64: add openclash + argon theme"
git push
```

> ImmortalWrt 在 Windows 上无法直接编译，建议用 WSL2 / Linux 虚拟机 / 远程 Linux 主机来跑 `make menuconfig`。

### 将来想加更多 target（如 ARM 路由器 / 树莓派 / 软路由 ARM 设备）

1. 新增 `configs/<target>.config`，最简形式（让 defconfig 自动展开）：
   ```
   CONFIG_TARGET_<target>=y
   CONFIG_TARGET_<target>_<subtarget>=y
   CONFIG_CCACHE=y
   ```
2. 在 [.github/workflows/build.yml](.github/workflows/build.yml) 的 `matrix.target` 列表追加一项：
   ```yaml
   - name: <target_name>
     config: configs/<target>.config
   ```
3. push 即生效。

### 添加第三方插件源

编辑 [feeds.conf.default](feeds.conf.default) 取消对应行注释，或者在 [scripts/diy-part1.sh](scripts/diy-part1.sh) 里 `echo` 追加。

### SSH 登录调试 Actions

手动触发时把 `ssh` 输入参数设为 `true`，工作流会用 [tmate](https://tmate.io) 建立 SSH 反向连接，连接信息打印在日志中。

---

## 工作流可选输入

| 输入参数 | 默认值 | 说明 |
| --- | --- | --- |
| `ssh` | `false` | 启用 tmate SSH 调试 |
| `upload_bin_dir` | `false` | 把整个 `bin/` 目录作为 Artifact 上传（7 天保留期；含 .ipk） |
| `upload_release` | `true` | 编译完成后自动创建 GitHub Release |

---

## 常见问题

**Q: 编译失败怎么办？**
A: 先看日志最后 ~200 行；多数情况是某个包源失效或上游 commit 引入 break。一个 target 失败不影响另一个（`fail-fast: false`）。可以触发时勾选 `ssh=true` 进入容器排查。

**Q: 为什么选 `ubuntu-22.04` 而不是 `ubuntu-latest`？**
A: ImmortalWrt 24.10 在 22.04 上编译稳定性更好；24.04 偶尔会因 GLIBC 版本与 host tools 冲突。

**Q: 想换 master 滚动分支？**
A: 编辑 [.github/workflows/build.yml](.github/workflows/build.yml) 中 `REPO_BRANCH: openwrt-24.10` → `master`。

**Q: 公开仓库 GitHub Actions 是免费的吗？**
A: 是。标准 `ubuntu-*` runner 的分钟数对公开仓库**完全免费且无限**；私有仓库才有月度配额。`actions/cache` 配额 10 GB（满了自动 LRU 驱逐，不会让 build 失败）；Release 附件不计入配额。

---

## License

工作流脚本沿用 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 的 MIT 协议；ImmortalWrt 本身按 GPL-2.0 协议分发。
