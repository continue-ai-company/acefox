# AceFox 自托管 Runner 部署指南

本文用于注册 AceFox 的原生 GitHub Actions 构建机，涵盖 runner 注册、分组、主机准备和验证。它不包含签名证书、公证密钥或发布凭据；这些敏感信息绝不能提交到仓库。

## 1. 安全边界

`continue-ai-company/acefox` 当前是公开仓库。持久运行的 self-hosted runner 可能被来自 fork 或 Pull Request 的不可信代码接管。因此：

- 不要把个人开发机注册为 runner。
- 不要让含签名凭据的机器运行 PR、fork 或任意手动工作流。
- 在 AceFox 迁移到独立私有仓库之前，不要给 self-hosted runner 增加 `pull_request` 触发器。

当前阶段必须遵守以下规则：

1. 原生构建工作流仅使用 `workflow_dispatch`；只有具备写权限的维护者可以触发。
2. 所有构建机使用专用操作系统账号，例如 `acefoxrunner`，不保存签名证书、SSH 私钥、生产服务凭据或无关源码。
3. 未来的发布 runner 只允许执行受保护 tag 触发的发布工作流，并通过 GitHub Environment `acefox-production` 的人工审批获取发布凭据。
4. 只要公开仓库仍在使用，就不要让发布 runner 执行 PR、fork 或自由输入参数的手动工作流。

参考资料：[GitHub runner 安全说明](https://docs.github.com/en/actions/reference/security/secure-use)、[runner group 访问控制](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access)、[注册 self-hosted runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)。

## 2. Runner 清单与标签

现有 `.github/workflows/acefox-build.yml` 使用以下自定义标签。请保持拼写与大小写一致；GitHub 还会自动添加 `self-hosted` 默认标签。

| 主机 | Runner 名称 | 自定义标签 | 工作流目标 |
| --- | --- | --- | --- |
| Apple Silicon macOS | `acefox-macos-arm64-01` | `acefox,native-build,macos,arm64` | `macos-arm64` |
| Ubuntu ARM64 | `acefox-linux-arm64-01` | `acefox,native-build,linux,arm64` | `linux-arm64` |
| Windows x64 | `acefox-windows-x64-01` | `acefox,native-build,windows,x64` | `windows-x64` |

例如 macOS 任务会按下列标签路由：

```yaml
runs-on: [self-hosted, acefox, macos, arm64]
```

## 3. 主机准备

使用专用物理机或虚拟机。每台建议至少 16GB 内存、150GB 可用本地 SSD。Firefox 文档的本机构建最低要求是 30GB 空闲空间；150GB 是为了预留对象目录、编译缓存、产物和重试空间。

| 主机 | 注册前准备 |
| --- | --- |
| macOS ARM64 | 当前 macOS、Xcode、已接受 Xcode license、Homebrew |
| Ubuntu ARM64 | 受支持 Ubuntu、Python 3、`mach bootstrap` 所需的构建工具和系统依赖 |
| Windows x64 | Windows 11 或 Server 2022、MozillaBuild、Visual Studio Build Tools、Windows SDK |

具体操作：

1. 创建专用非个人账号 `acefoxrunner`。
2. 以该账号安装上述平台依赖。
3. 用一个可删除的 AceFox checkout 运行一次 `./mach bootstrap`，确认依赖能在该账号下安装。
4. runner 工作目录必须位于本地 SSD，不能放在网络共享盘、同步盘或 WSL 挂载盘中。

建议安装目录：

```text
macOS:   /Users/acefoxrunner/actions-runner
Ubuntu:  /home/acefoxrunner/actions-runner
Windows: C:\actions-runner
```

## 4. 在 GitHub 创建 Runner Group

需要组织 Owner，或被授予 **Manage organization runners and runner groups** 权限的成员操作。

1. 打开 `continue-ai-company` 组织主页。
2. 进入 **Settings** -> **Actions** -> **Runner groups**。
3. 创建 group：`native-build`。这是 AceFox 和 `ai2apps-desktop` 共用的、
   不带发布凭据的原生构建组。
4. 因为 `continue-ai-company/acefox` 是公开仓库，勾选 **Allow public repositories**。
5. 将 **Repository access** 设为 **Selected repositories**，只选择 `continue-ai-company/acefox`；不要选择组织内全部仓库。
6. `ai2apps-desktop` 需要高频构建时，将其加入 `native-build` 的已选仓库列表。
7. 另创建 `desktop-release`，只授权 `continue-ai-company/ai2apps-desktop`；该组用于桌面端签名、公证和发布，不能授权 AceFox 公开仓库。
8. 若 GitHub 当前套餐和界面提供 **Selected workflows**，将 `desktop-release` 限制为将来的 `desktop-release.yml`，将 `native-build` 限制为构建验证工作流。

**Allow public repositories** 的含义是“允许被已选中的公开仓库使用”，并不等于允许组织中的全部公开仓库访问；真正的范围由 **Selected repositories** 决定。

当前先将三台机器放入 `native-build`。以后再单独部署加固的发布 runner，并把它放入 `desktop-release`；发布 runner 永远不能执行 PR 代码。若短期必须共用物理机，应在不同的 OS 账号、不同 runner 目录中注册两个 runner 实例，详见 `docs/acefox-build-release-plan.md`。

## 5. 下载 Runner 安装包与获取注册 Token

安装包 URL、SHA-256 校验值和注册 token 都由 GitHub 页面即时生成。不要把 URL、token 或校验值硬编码进脚本；注册 token 是短时有效的。

每台机器分别执行：

1. 进入 **Organization settings** -> **Actions** -> **Runners**。
2. 点击 **New self-hosted runner**。
3. 选择实际系统与架构：`macOS / ARM64`、`Linux / ARM64` 或 `Windows / x64`。
4. 将 GitHub 页面给出的“下载、校验、解压”命令复制到对应主机执行。必须使用页面给出的版本化 URL 和 SHA-256 校验命令。
5. 页面最后会给出 `config.sh` 或 `config.cmd` 注册命令；不要直接执行该行，改用本仓库第 6、7 节的脚本，以保证名称、标签和服务安装方式统一。

解压后，macOS/Linux 的 runner 目录会有 `config.sh`、`run.sh`、`svc.sh`；Windows 会有 `config.cmd`、`run.cmd`。这些文件来自 GitHub Actions Runner 安装包，不属于 AceFox 源码。

## 6. 注册 macOS / Ubuntu Runner

以专用非 root runner 账号登录，在已解压的 runner 目录执行。脚本会注册 runner 并安装 launchd/systemd 服务；仅在服务安装和启动阶段请求 `sudo`。

macOS：

```bash
cd /Users/acefoxrunner/actions-runner

/path/to/acefox/ci/runner/register-unix-runner.sh \
  --url https://github.com/continue-ai-company/acefox \
  --token 'TOKEN_FROM_GITHUB_UI' \
  --name acefox-macos-arm64-01 \
  --labels acefox,native-build,macos,arm64
```

Ubuntu：

```bash
cd /home/acefoxrunner/actions-runner

/path/to/acefox/ci/runner/register-unix-runner.sh \
  --url https://github.com/continue-ai-company/acefox \
  --token 'TOKEN_FROM_GITHUB_UI' \
  --name acefox-linux-arm64-01 \
  --labels acefox,native-build,linux,arm64
```

如果只是一次性排错，不想安装系统服务，在命令最后添加 `--no-service`，注册完成后手动执行 `./run.sh` 即可。

## 7. 注册 Windows Runner

以管理员身份打开 PowerShell，然后执行：

```powershell
Set-Location C:\actions-runner

& C:\path\to\acefox\ci\runner\register-windows-runner.ps1 `
  -RunnerUrl 'https://github.com/continue-ai-company/acefox' `
  -RunnerToken 'TOKEN_FROM_GITHUB_UI' `
  -RunnerName 'acefox-windows-x64-01' `
  -RunnerLabels 'acefox,native-build,windows,x64'
```

该脚本使用 `--runasservice`，因此 runner 会作为 Windows 服务启动。运行服务的专用账号必须拥有 `C:\actions-runner`、MozillaBuild 和 Visual Studio Build Tools 的访问权限，不能使用开发者个人账号。

## 8. 分配 Group 并验证

若注册页面未提供 group 选择器，注册后手动分配：

1. 进入 **Organization settings** -> **Actions** -> **Runners**。
2. 选择刚注册的 runner，点击 **Edit**，选择 `native-build`。
3. 确认状态为 **Idle**，标签包含 `self-hosted`、`acefox`、`native-build`、对应系统和架构标签。

在 macOS/Linux 主机以 runner 账号验证网络与基础工具：

```bash
./config.sh --check \
  --url https://github.com/continue-ai-company/acefox \
  --token 'TOKEN_FROM_GITHUB_UI'

df -h .
git --version
python3 --version
```

在 Windows 主机验证服务和磁盘：

```powershell
Get-Service 'actions.runner*'
Get-PSDrive -PSProvider FileSystem
git --version
python --version
```

最后在 GitHub Actions 页面手动运行 **AceFox build validation**，选择与该 runner 对应的目标。注册成功并不代表 `mach`、MozillaBuild、Xcode 或 Firefox 工具链已经正确安装；必须以实际 `./mach build` 和 `./mach package` 结果为准。

## 9. 轮换与安全事件处理

- 更换或删除机器前，先在 GitHub 中禁用 runner。
- 跨 Firefox 大版本时，清理旧的 `obj-*`、runner `_work` 和编译缓存；runner 正在运行时不要删除 `.runner` 配置文件。
- 如果发布机意外执行了公开代码或 PR 代码，立刻禁用 runner、吊销所有发布凭据、检查工作目录，并从干净镜像重新创建该主机。
- 将 AceFox 迁移到独立私有仓库后，从两个 group 中移除 **Allow public repositories**，并重新限制为私有仓库访问。
