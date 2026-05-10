# KH-ImmortalWrt

GitHub Actions 自动并行编译多个 CPU 架构的 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10` 固件。当前 matrix 包含 9 个 target：

| Target | 架构 | 典型设备 |
| --- | --- | --- |
| `x86_64` | x86-64 | N100/J4125 软路由、PC、PVE/ESXi 虚机 |
| `x86_generic` | i686 (32-bit) | 极老 PC / 极低配虚机 |
| `rockchip_armv8` | ARMv8 64-bit | NanoPi R2S/R4S/R5S/R6S、Orange Pi 5、Radxa Rock 5B |
| `bcm2711` | ARMv8 64-bit (A72) | 树莓派 4 / Pi 400 / CM4 |
| `bcm2712` | ARMv8 64-bit (A76) | 树莓派 5 |
| `ramips_mt7621` | MIPS | 红米 AC2100、Newifi3、K2P、小米 4A 千兆等 |
| `mediatek_filogic` | ARMv8 64-bit | 小米 AX3000T、Redmi BE6500、GL-MT6000 等 Wi-Fi 6/7 |
| `mediatek_mt7622` | ARMv8 64-bit (A53) | Redmi AX6S、Linksys MR8300/E8450 |
| `qualcommax_ipq807x` | ARMv8 64-bit | 小米 AX9000、NetGear RAX120、Linksys MX5300 |

> 仓库名带 `x86_64` 是历史遗留 —— 实际产物覆盖以上所有 target。

工作流改编自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)（MIT License）。

---

## 目录结构

```
.
├── .github/workflows/build.yml    # 多 target matrix 构建工作流
├── configs/
│   ├── x86_64.config              # 软路由 / PVE
│   ├── x86_generic.config         # 32-bit PC
│   ├── rockchip_armv8.config      # Rockchip ARM64 SBC
│   ├── bcm2711.config             # 树莓派 4
│   ├── bcm2712.config             # 树莓派 5
│   ├── ramips_mt7621.config       # MTK MIPS 路由（AC2100 / K2P 等）
│   ├── mediatek_filogic.config    # MTK Wi-Fi 6/7 路由（AX3000T 等）
│   ├── mediatek_mt7622.config     # MTK Wi-Fi 6 路由（AX6S 等）
│   └── qualcommax_ipq807x.config  # 高通骁龙路由（AX9000 等）
├── scripts/
│   ├── diy-part1.sh               # feeds 更新前 自定义脚本（所有 target 共用）
│   └── diy-part2.sh               # feeds 安装后、make defconfig 前 自定义脚本
├── feeds.conf.default             # 自定义 feeds 列表（所有 target 共用）
├── files/                         # （可选）打包进固件 rootfs 的文件
└── README.md
```

---

## 工作原理

### 并行 matrix 构建

每次 push（或手动触发）后，workflow 启动 10 个 job：

```
prep                                            # ~5s, 创建空 Release tag
 ├─ build (x86_64)            ─┐
 ├─ build (x86_generic)       ─┤
 ├─ build (rockchip_armv8)    ─┤
 ├─ build (bcm2711)           ─┤
 ├─ build (bcm2712)           ─┼─ 并行跑, 各 ~30min–2h
 ├─ build (ramips_mt7621)     ─┤   每个 job 把产物 append 到同一个 Release
 ├─ build (mediatek_filogic)  ─┤
 ├─ build (mediatek_mt7622)   ─┤
 └─ build (qualcommax_ipq807x)─┘
```

总耗时 ≈ 最慢的那个 target，**不是 9 倍**。GitHub 公开仓库并发 job 上限 20，毫无压力。所有产物挂在同一个 Release tag 下（形如 `2026.05.11-1234`）。

### 缓存策略

每个 target 独立缓存：
- `dl/`（已下载的源码 tarball）—— key 含 target 名 + `.config` 哈希
- `.ccache/`（C 编译产物缓存）—— key 含 target 名 + `.config` 哈希，单实例上限 2 GB

GitHub 给每个 repo 的 actions/cache 总配额是 10 GB。9 个 target 合计可能 30–50 GB，远超配额，GitHub 按 LRU 自动驱逐最久未访问的 entry —— 常 push 的 target 缓存保留，少 push 的过期。**永远不会让 build 失败**，但部分 target 可能每隔几次 push 就掉一次缓存退回到全量编译。

### 自动触发条件

- `push` 到 `main` 分支（除 README/LICENSE/.md/.gitignore/.gitattributes 修改外）
- 手动 `workflow_dispatch`（可选 SSH 调试 / 上传 bin 目录）
- `concurrency.cancel-in-progress`：新 push 自动取消正在跑的旧 build，避免堆积

---

## 使用方法

### 直接下载固件

到 [Releases 页面](../../releases) 找最新 tag，按设备类型下载（文件名包含 target 名 + 设备型号）：

- **x86_64 软路由 / PVE**：`immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz`（UEFI）或 `immortalwrt-x86-64-generic-squashfs-combined.img.gz`（BIOS）
- **32-bit PC**：`immortalwrt-x86-generic-generic-squashfs-combined.img.gz`
- **NanoPi R4S / R5S 等 Rockchip SBC**：`immortalwrt-rockchip-armv8-<vendor>_<model>-squashfs-sysupgrade.img.gz`
- **树莓派 4**：`immortalwrt-bcm27xx-bcm2711-rpi-4-squashfs-factory.img.gz`
- **树莓派 5**：`immortalwrt-bcm27xx-bcm2712-rpi-5-squashfs-factory.img.gz`
- **红米 AC2100 / K2P / Newifi3 等 MIPS 路由**：`immortalwrt-ramips-mt7621-<vendor>_<model>-squashfs-sysupgrade.bin`
- **小米 AX3000T / Redmi BE6500 等新款 Wi-Fi 6/7**：`immortalwrt-mediatek-filogic-<vendor>_<model>-squashfs-sysupgrade.bin`
- **Redmi AX6S / Linksys MR8300**：`immortalwrt-mediatek-mt7622-<vendor>_<model>-squashfs-sysupgrade.bin`
- **小米 AX9000 等高通高端**：`immortalwrt-qualcommax-ipq807x-<vendor>_<model>-squashfs-sysupgrade.bin`

### 自己定制（推荐流程）

**第一次跑通后**，建议进入 ImmortalWrt 源码用 `make menuconfig` 选好需要的包，再把生成的 `.config` 复制回对应文件：

```bash
git clone https://github.com/immortalwrt/immortalwrt -b openwrt-24.10
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/this/repo/configs/x86_64.config .config   # 或其他 target
make menuconfig          # 勾选 LuCI 应用、主题、内核模块等
cp .config /path/to/this/repo/configs/x86_64.config
git add configs/x86_64.config && git commit -m "x86_64: add openclash + argon theme"
git push                  # 仅触发改动的 target —— 还不行，目前所有 target 一起跑
```

> 当前 workflow 任何 .config 改动都会触发所有 target 重编。如果只想编单个 target，可以手动 `workflow_dispatch` + 在 matrix 里 comment 掉其他 target；或者将来按需引入 path-based filter。

### 添加更多 target

复制一份 `configs/*.config`，例如 `configs/mt7621.config`，内容：

```
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_CCACHE=y
```

然后在 [.github/workflows/build.yml](.github/workflows/build.yml) 的 `matrix.target` 列表追加一项：

```yaml
- name: mt7621
  config: configs/mt7621.config
```

push 即生效。

### 添加第三方插件源

编辑 [feeds.conf.default](feeds.conf.default) 取消对应行注释，例如启用 [kenzok8/small-package](https://github.com/kenzok8/small-package)：

```
src-git small8 https://github.com/kenzok8/small-package
```

或者在 [scripts/diy-part1.sh](scripts/diy-part1.sh) 里追加。注意：feeds 对所有 target 共用，加进去后所有 target 都会拉那个源。

### SSH 登录调试 Actions

手动触发时把 `ssh` 输入参数设为 `true`，4 个 matrix job 都会用 [tmate](https://tmate.io) 建立 SSH 反向连接，连接信息在日志中。

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
A: 先看日志最后 ~200 行；多数情况是某个包源失效或上游 commit 引入 break。某个 target 失败不影响其他 target（`fail-fast: false`）。可以触发时勾选 `ssh=true` 进入容器排查。

**Q: 一个 target 在 matrix 中失败了，其他 target 的 Release 怎样？**
A: 失败 target 不会上传产物，但其他成功 target 的产物已挂到 Release。Release 页面会缺少该 target 的镜像。

**Q: 为什么选 `ubuntu-22.04` 而不是 `ubuntu-latest`？**
A: ImmortalWrt 24.10 在 22.04 上编译稳定性更好；24.04 偶尔会因 GLIBC 版本与 host tools 冲突。

**Q: 想换 master 滚动分支？**
A: 编辑 [.github/workflows/build.yml](.github/workflows/build.yml) 中 `REPO_BRANCH: openwrt-24.10` → `master`。

**Q: 公开仓库 GitHub Actions 是免费的吗？**
A: 是。标准 `ubuntu-*` runner 的分钟数对公开仓库**完全免费且无限**；私有仓库才有月度配额。`actions/cache` 配额 10 GB（满了自动 LRU 驱逐，不会让 build 失败）；Release 附件不计入配额。

---

## License

工作流脚本沿用 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 的 MIT 协议；ImmortalWrt 本身按 GPL-2.0 协议分发。
