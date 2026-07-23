# AceFox 构建与发布准备清单

本文定义 AceFox 从源码到可供 `ai2apps-desktop` 使用的 runtime 产物的准备工作。runner 的安装命令见 [自托管 Runner 部署指南](acefox-self-hosted-runners.md)，分支和版本规则见 [分支与发布模型](acefox-branching.md)。

## 1. 目标与职责

AceFox 的职责是构建版本固定、可校验的浏览器 runtime；`ai2apps-desktop` 的职责是将该 runtime 嵌入桌面应用并发布最终的 AI2Apps 安装包。

```text
AceFox 固定 tag
  -> 原生构建、测试、生成 runtime
  -> 校验和与版本清单
  -> （可选）AceFox GitHub Release
  -> ai2apps-desktop 下载指定版本并校验
  -> 生成并签名最终 AI2Apps 分发包
```

当前 AceFox 只计划构建一次，因此第一阶段只需要 `native-build` 执行无签名 POC。不要在 AceFox 公开仓库中配置 Apple、Windows 或 GitHub Release 凭据。

## 2. 当前基线与产物矩阵

- 产品分支：`acefox/143`。
- Mozilla 基线：`upstream/firefox-143.0a1`，指向 `830f9c413c22ae6db8e7b6419329f11418bd1620`。
- 当前构建骨架：`.github/workflows/acefox-build.yml`，只支持手动触发、原生构建、上传 7 天未签名 artifact。

第一阶段按现有桌面端资源格式准备下列 runtime；每个产物必须带版本、架构、Git commit 和 SHA-256。

| 目标 | 构建主机 | 供桌面端使用的 runtime | 最终 Release 资产 |
| --- | --- | --- | --- |
| macOS ARM64 | Apple Silicon Mac | `AceFox.app` | `AceFox-<version>-macos-arm64.dmg`、`AceFox-<version>-macos-arm64.app.zip` |
| Ubuntu ARM64 | 原生 Ubuntu ARM64 | `AceFox-aarch64.AppImage` | `AceFox-<version>-linux-arm64.AppImage`、`AceFox-<version>-linux-arm64-portable.zip` |
| Windows x64 | 原生 Windows x64 | 包含 `firefox.exe` 的目录 ZIP | `AceFox-<version>-windows-x64-setup.exe`、`AceFox-<version>-windows-x64-portable.zip` |

所有平台同时发布“安装包”和“便携包”。便携包解压后必须包含一个单独的顶层目录并可直接启动，不能要求用户再执行安装步骤。Windows runtime 不能让 Electron 调用安装器；桌面端需要的是可解压、可直接启动的目录。若未来覆盖普通 Intel Ubuntu 用户，应额外增加 `linux-x64`；若覆盖 Intel Mac，则增加 `macos-x64` 或 universal 构建。

便携包的归档规则：

- macOS：对已签名并完成 staple 的 `AceFox.app` 使用 `ditto -c -k --keepParent --sequesterRsrc` 生成 ZIP，以保留 app bundle、资源叉和 macOS 元数据；不要用 Finder 或普通 `zip` 代替。
- Ubuntu：将原生 Firefox 安装目录（而非 AppImage 本身）以单一顶层目录归档为 ZIP；保留符号链接与可执行权限，并在干净 Ubuntu 上解压后验证启动。
- Windows：将包含 `firefox.exe` 的完整目录归档为 ZIP；在干净 Windows 上解压并直接启动 `firefox.exe`。
- 每个安装包与便携包均写入 `runtime-manifest.json` / `SHA256SUMS`，并使用不同的文件名、SHA-256 条目和 Release asset。

## 3. Runner 与机器安排

使用组织级 `native-build` group，初期只放无凭据的构建 runner：

```text
native-build
├─ continue-ai-company/acefox（公开；仅手动构建）
├─ continue-ai-company/ai2apps-desktop（高频无签名 CI）
└─ Mac ARM64 / Ubuntu ARM64 / Windows x64 runner
```

AceFox 当前 workflow 仍按 `acefox` 标签路由；因此共享 runner 需要同时拥有 `acefox,native-build` 和对应平台标签。

同一物理机可暂时同时服务构建和桌面端发布，但必须注册两个独立 runner 实例、两个 OS 账号和两个工作目录：

```text
nativebuild 用户       -> native-build runner -> 无密钥
desktoprelease 用户    -> desktop-release runner -> 仅桌面端受保护发布
```

这是权限隔离，不是完整虚拟化隔离。AceFox 公开代码只能使用无密钥的 `native-build`；不允许 PR 触发 self-hosted job。长期方案是 AceFox 脱离 fork network 并迁移为私有独立仓库。

## 4. POC 构建步骤

在三台已 bootstrap 的原生机器上依次触发 `.github/workflows/acefox-build.yml`：

1. 手动选择单一 target，而不是一次选择 `all`。
2. workflow 使用 `actions/checkout`、`./mach build`、`./mach package`。
3. 下载 `obj-*/dist/**` artifact，记录最终文件名、大小、架构和 `git rev-parse HEAD`。
4. 在干净测试环境分别启动安装包和便携包：Mac 解压 `.app.zip` 并启动 `.app`，Ubuntu 启动 AppImage 且解压 portable ZIP 后启动目录内二进制，Windows 解压 portable ZIP 后启动 `firefox.exe`。
5. 对每个通过的产物生成 SHA-256，并写入运行时清单。

POC 的通过标准是“能在目标平台启动”，不是“已可公开分发”。未签名 macOS 包可能需右键打开，Windows SmartScreen 可能警告；这是 POC 的预期行为。

## 5. 在 CI 中必须补齐的实现

POC 通过后再实现以下内容：

1. 为每个平台新增版本化的 release `mozconfig`，启用优化、关闭 debug，并固定 `browser/branding/ai2apps`。
2. 将 `obj-*` 名称固定为可预测的 `MOZ_OBJDIR`，避免 artifact glob 混入旧构建。
3. Linux：在 `./mach package` 后将 Firefox 包装为 AppImage，并在干净 Ubuntu ARM64 上验证。
4. 三端：从同一已验证 staging 目录额外生成 portable ZIP；Mac 使用 `ditto`，Linux/Windows ZIP 保留单一顶层目录、符号链接和可执行权限。
5. Windows：将签名发生在应用 EXE/DLL 和最终 NSIS 安装器的正确阶段；不能只签最终 `Setup.exe`。
6. 生成 `runtime-manifest.json`，至少包含版本、tag、commit、目标、文件名、SHA-256、构建时间。
7. 将 runtime 发布为不可变 tag，例如 `acefox-v143.0a1-ai2apps.1`；消费者只允许按 tag 和 SHA-256 获取，不能追踪分支或 `latest`。

## 6. 签名、商标与发布门槛

现在不要为 AceFox 发布机导入凭据。决定独立对外分发 AceFox 前，必须完成：

- macOS：Developer ID 签名、notarization、staple；
- Windows：公司代码签名方案，并签署应用二进制和安装器；
- Linux：SHA-256 与 GPG/minisign 签名；
- Mozilla 商标与产品命名审查。修改后的 Firefox 不能继续使用 Mozilla/Firefox 商标；`AceFox` 名称也需要公司法务确认。

在这些门槛完成前，AceFox artifact 仅作为 AI2Apps 内部 runtime 使用，不对外标记为正式 AceFox 下载包。

## 7. 开始构建前检查

- [ ] `native-build` group 仅授权 AceFox 与桌面端，且不含任何 release secret。
- [ ] 三台 runner 显示 `Idle`，标签与 workflow 匹配。
- [ ] 每台 runner 均完成 `mach bootstrap`，并有 150GB+ 可用本地空间。
- [ ] `acefox/143` 受保护；只有维护者能手动触发 workflow。
- [ ] 当前 tag、commit、产物命名规范和 SHA-256 清单格式已确定。
- [ ] 三端安装包与便携 ZIP 均已生成、SHA-256 已记录，并分别在干净系统中验证启动。
