# KH-ImmortalWrt-x86_64

GitHub Actions 自动编译 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10` 分支固件，目标平台 **x86_64 generic**（适合 N100/J4125 等软路由、PVE 虚拟机、ESXi）。

工作流改编自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)（MIT License）。

---

## 目录结构

```
.
├── .github/workflows/build.yml    # GitHub Actions 工作流
├── configs/
│   └── x86_64.config              # 编译配置（.config 种子文件）
├── scripts/
│   ├── diy-part1.sh               # feeds 更新前 自定义脚本
│   └── diy-part2.sh               # feeds 安装后、make defconfig 前 自定义脚本
├── feeds.conf.default             # 自定义 feeds 列表（覆盖源码默认值）
├── files/                         # （可选）打包进固件 rootfs 的文件
└── README.md
```

---

## 使用方法

### 一、首次触发编译

1. Fork 或推送本仓库到自己的 GitHub。
2. 打开仓库 **Actions** 页 → 选择 `Build ImmortalWrt x86_64` → 点击 **Run workflow**。
3. 等待 ~1.5–2.5 小时（首次较慢，后续可借助 ccache 加速）。
4. 编译完成后，固件会出现在仓库 **Releases** 页（tag 形如 `2026.05.10-1430`），同时 Artifacts 也可下载。

### 二、定制配置（推荐流程）

**第一次跑通后**，建议进入 ImmortalWrt 源码目录用 `make menuconfig` 选好需要的包，再把生成的 `.config` 复制回来覆盖 [configs/x86_64.config](configs/x86_64.config)：

```bash
git clone https://github.com/immortalwrt/immortalwrt -b openwrt-24.10
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/this/repo/configs/x86_64.config .config
make menuconfig          # 勾选 LuCI 应用、主题、内核模块等
cp .config /path/to/this/repo/configs/x86_64.config
git add configs/x86_64.config && git commit -m "update x86_64 config"
git push
```

> ImmortalWrt 在 Windows 上无法直接编译，建议用 WSL2 / Linux 虚拟机 / 远程 Linux 主机来跑 `make menuconfig`。

### 三、添加第三方插件源

编辑 [feeds.conf.default](feeds.conf.default) 取消对应行注释，例如启用 [kenzok8/small-package](https://github.com/kenzok8/small-package)：

```
src-git small8 https://github.com/kenzok8/small-package
```

或者在 [scripts/diy-part1.sh](scripts/diy-part1.sh) 里追加：

```bash
echo 'src-git small8 https://github.com/kenzok8/small-package' >> feeds.conf.default
```

### 四、修改默认 LAN IP / 主机名 / 主题

在 [scripts/diy-part2.sh](scripts/diy-part2.sh) 里取消对应行的注释。

### 五、SSH 登录调试 Actions

触发工作流时，把 `ssh` 输入参数设为 `true`，工作流会用 [tmate](https://tmate.io) 建立 SSH 反向连接，连接信息会打印在日志中。

---

## 工作流可选输入

| 输入参数 | 默认值 | 说明 |
| --- | --- | --- |
| `ssh` | `false` | 启用 tmate SSH 调试 |
| `upload_bin_dir` | `false` | 把整个 `bin/` 目录作为 Artifact 上传（包含 .ipk） |
| `upload_release` | `true` | 编译完成后自动创建 GitHub Release |

---

## 编译产物

默认 `configs/x86_64.config` 会生成：

- `*-x86-64-generic-squashfs-combined-efi.img.gz` — UEFI 启动（推荐，适合现代主板/PVE）
- `*-x86-64-generic-squashfs-combined.img.gz` — 传统 BIOS 启动
- `*-x86-64-generic-rootfs.tar.gz` — rootfs（自定义安装用）

写盘工具推荐 [balenaEtcher](https://etcher.balena.io/) 或 PVE 内 `qm importdisk`。

---

## 常见问题

**Q: 编译失败怎么办？**
A: 先看日志最后 ~200 行；多数情况是某个包源失效或磁盘空间不足。可以触发时勾选 `ssh=true` 进入容器排查。

**Q: 为什么选 `ubuntu-22.04` 而不是 `ubuntu-latest`？**
A: ImmortalWrt 24.10 在 22.04 上编译稳定性更好；24.04 偶尔会因为 GLIBC 版本与 host tools 冲突。

**Q: 想换 master 滚动分支？**
A: 编辑 [.github/workflows/build.yml](.github/workflows/build.yml) 中 `REPO_BRANCH: openwrt-24.10` → `master`。

---

## License

工作流脚本沿用 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 的 MIT 协议；ImmortalWrt 本身按 GPL-2.0 协议分发。
