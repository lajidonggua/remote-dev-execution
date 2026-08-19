# remote-dev-execution

这是一个用于“AI 编辑环境”和“权威开发环境”分离场景的 Agent Skill。

```text
VM / 容器 / 其他 AI 编辑环境
        |
        | 在本地检查和修改源码
        v
dev-exec / SSH / 独立 checkout 推荐使用 Mutagen
        |
        v
Mac / 工作站 / 真实开发机（权威环境）
        |
        | 真实工具链、依赖、服务、容器和运行时
        v
权威构建、测试、调试和运行结果
```

Skill 的核心原则是：轻量的源码检查和编辑留在 AI 所在环境；依赖真实
平台、SDK、服务、Docker、运行时或凭据的命令，交给权威开发环境执行。

英文文档：[README.md](README.md)

## 最短路径：Relay 一键部署，独立 checkout 再配置同步

对于“非管理员 Mac + Claude Code 运行在 VM”的场景，`dev-relay setup`
可以一次完成 relay、VM 命令 wrapper、Claude Skill 安装和项目本地配置。

执行前只需要确认两个前置条件：

1. Mac 已经可以免交互执行 `ssh VM_ALIAS true`。
2. 已经明确两个项目 checkout 的路径。两个 checkout 分离时，必须先完成
   下文的 Mutagen 步骤，再运行任何项目测试。

然后在 Mac 的 canonical checkout 中执行：

```sh
~/code/remote-dev-execution/scripts/dev-relay setup VM_ALIAS \
  --client claude \
  --project /absolute/path/to/project/in/agent-environment \
            /absolute/path/to/project/in/authoritative-environment \
  --shell /bin/zsh
```

### 参数和值的含义

| 值或参数 | 是否必需 | 应该填写什么 |
| --- | --- | --- |
| `VM_ALIAS` | 首次 setup 必需 | Mac 上已经存在、用于连接 Agent 环境的 SSH alias。必须先能免交互执行 `ssh VM_ALIAS true`。 |
| `--project` 第一个值 | 使用 `--project` 时必需 | Agent 环境中的项目 checkout 绝对路径，目录必须已经存在。 |
| `--project` 第二个值 | 使用 `--project` 时必需 | 权威环境中的项目 checkout 绝对路径，构建、测试、服务和调试会在这里运行。 |
| `--client CLIENT` | 可选，首次 setup 推荐填写 | 只能填写 `claude`、`codex` 或 `both`，用于在 Agent 环境安装对应 Skill。安装后重启 Agent。 |
| `--shell SHELL` | 可选 | 权威环境中实际存在的 shell，通常是 `/bin/zsh` 或 `/bin/sh`。省略时优先使用当前用户 shell，否则 `dev-exec` 默认使用 `/bin/sh`。 |
| `--mutagen SESSION` | 可选 | 已存在的 Mutagen session 名称。默认由 `dev-exec` 所在环境控制；如果 daemon/session 在其他获准环境中，和 `--mutagen-host` 一起填写。必须和 `--project` 一起使用。 |
| `--mutagen-host HOST` | 可选 | Agent 环境可以非交互连接的 SSH alias，指向实际拥有该 Mutagen daemon/session 的环境。必须和 `--project`、`--mutagen` 一起使用。 |
| `--mutagen-bin BIN` | 可选 | 选定控制环境中的 Mutagen 可执行文件名或绝对路径。必须和 `--project`、`--mutagen` 一起使用；非交互 SSH 的 `PATH` 不包含 `mutagen` 时填写。 |
| `--clear-mutagen` | 可选 | 显式移除已有生成配置中的 Mutagen session、可执行文件和控制主机设置。必须和 `--project` 一起使用，不能与 `--mutagen` 同时使用。 |

`--client` 只决定安装哪个 Agent Skill，不决定命令去哪里执行。Claude Code
运行在 Agent 环境时填写 `claude`，Codex 填写 `codex`，两个客户端都运行时
填写 `both`。如果正确的 Skill 软链接已经安装，或者本次只配置 relay 和
wrapper，可以省略；之后也可以使用 `dev-relay install-skill` 单独补装。

`--mutagen` 只选择已经存在的 session，不会安装 Mutagen 或创建 session。
首次还没有 session 时，relay setup 先省略该参数，然后进入生成好配置的
Agent 项目执行：

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
```

它会按需安装用户级 Mutagen、基于已有项目映射创建 `two-way-safe` session、
更新被忽略的 `.dev-exec.env`，并立即运行 doctor。以后每次 `dev-exec` 都会
先 flush，再检查结构化健康状态；端点断开、冲突、文件系统问题或 flush 失败
都会在 SSH 之前阻止项目命令。

如果已经有审核过的 session，在 relay setup 中填写
`--mutagen EXISTING_SESSION`。如果它由其他获准环境中的 Mutagen daemon 控制，
再填写 `--mutagen-host MUTAGEN_CONTROL_HOST`；如果非交互 SSH 的 `PATH` 中没有
`mutagen`，再填写 `--mutagen-bin MUTAGEN_BIN`。wrapper 会在那里执行
`version`、`sync list` 和 `sync flush` 前置检查。只有真正共享 checkout，
或者其他同步工具具有可阻塞的完成检查时，才完全省略 Mutagen。两个独立
checkout 没有可靠同步时不得运行测试。

重复 setup 时，如果项目配置是已有的生成配置，当前 Mutagen session 和可执行
文件设置会默认保留；只有传入 `--mutagen` 才会替换 session，传入
`--clear-mutagen` 才会显式移除。这样普通的 relay 刷新不会意外关闭源码新鲜度
检查。只有确认项目改为共享 checkout 或其他独立可验证的同步方式时，才使用
`--clear-mutagen`。

| 场景 | `--client` | `--mutagen` |
| --- | --- | --- |
| Claude 首次 setup，两个 checkout 分离且还没有 session | `claude` | 先省略，然后在 Agent 项目运行 `setup-mutagen.sh --install` |
| 首次 setup，但已有本地控制的审核过 Mutagen session | `claude` | 已存在的 session 名称 |
| 已有由其他环境控制的 Mutagen session | `claude` | session 名称、`--mutagen-host`，必要时加 `--mutagen-bin` |
| Claude 首次 setup，双方使用同一个共享 checkout | `claude` | 省略 |
| Skill 已安装，只更新当前项目映射 | 省略 | 仅当该项目使用 Mutagen 时填写 |
| Agent 环境同时运行 Claude 和 Codex | `both` | 根据 checkout 同步方式决定 |

团队内部仓库或固定 release 可以增加 `--repo REPOSITORY` 和
`--ref BRANCH_OR_TAG_OR_COMMIT`。在 `setup` 中使用这两个参数时必须同时提供
`--client`，并确保指定 ref 已经包含需要安装的版本。

两条项目路径和源码新鲜度策略是仅有的项目级必选项。setup 不会猜测它们，
因为猜错会让测试看似成功，实际却使用旧源码或无关 checkout。

setup 完成后重启 Claude/Codex。在 Agent 环境的项目目录中执行：

```sh
~/.local/share/remote-dev-execution/dev-exec doctor
```

只有源码新鲜度已经确认，并且 doctor 输出
`authoritative execution: ready`，才能开始测试。如果看到
`source freshness: not verified`，说明执行通道已可用，但尚不能证明权威
checkout 包含当前修改；先确认共享 checkout 或外部同步，再运行测试。

随后用不暴露底层拓扑的提示词调用 Skill：

```text
Use $remote-dev-execution to validate delegated execution and run the smallest relevant project check without exposing infrastructure details.
```

如果旧版本 setup 只安装了 wrapper，可以在 Mac 上补装 VM 中的 Skill，
然后重启 Agent：

```sh
~/code/remote-dev-execution/scripts/dev-relay install-skill --client claude
```

完整英文提示词和可观察验收标准见
[Agent 执行验证](references/agent-validation.md)。

## 仓库内容

- `SKILL.md`：Codex 或 Claude 激活 Skill 后读取的核心规则。
- `scripts/dev-exec`：提供脱敏 doctor、查找项目配置、Mutagen flush 和健康
  检查、通过 SSH 执行命令，并保留 stdout、stderr 和退出码。
- `scripts/dev-relay`：macOS 非管理员用户态 `sshd` 和由 Mac 发起的反向
  SSH 隧道。
- `scripts/install-skill.sh`：安全维护 canonical Git checkout，并为 Claude
  Code 或 Codex 建立用户级软链接。
- `scripts/install-mutagen.sh`：校验 checksum、无需管理员权限的 macOS/Linux
  Mutagen 安装器。
- `scripts/setup-mutagen.sh`：根据项目配置创建 session、更新配置并集成运行
  doctor。
- `references/configuration.md`：`.dev-exec.env`、变量优先级和源码新鲜度。
- `references/mutagen.md`：Mutagen 安装、session、ignore、健康检查、运行和恢复。
- `references/reverse-relay.md`：反向 relay 的安全模型、手动配置和排错。
- `references/agent-validation.md`：隐私安全的 Agent 提示词和委派执行验收标准。
- `assets/*.example`：只包含占位符的配置模板。

本仓库是 Skill 的 canonical copy。不要把项目绝对路径、真实主机名、用户
名、IP、私钥、密码、Token 或其他秘密写入仓库。

## 先选择部署方式

| 场景 | 推荐方式 | 是否必须 Mutagen |
| --- | --- | --- |
| VM 可以直接 SSH 到权威开发机，双方使用同一个共享 checkout | 直接 SSH + `.dev-exec.env` | 不需要 |
| VM 和权威开发机是两个 checkout | 直接 SSH + Mutagen | 推荐；其他工具必须提供可信、可阻塞的完成检查 |
| 权威环境是 Mac，VM 无法主动连入 Mac | `dev-relay setup` 反向 relay | 只有两个 checkout 分离时需要 |
| 需要交互式 shell 或终端调试器 | 直接 `ssh -t` 或 relay SSH | 不需要，但仍必须确认源码是最新的 |

Mutagen 是同步工具，不是 SSH 替代品。两个 checkout 分离时，本 Skill 会把
它作为强制前置检查：`dev-exec` 先 flush，再读取结构化 session 状态；发现
冲突或文件系统问题时不会启动 SSH。wrapper 不会替你决定冲突哪一侧优先。

## 前置条件

### AI 环境 / VM

- POSIX shell：`sh`、Bash、Zsh、Dash 或 Ksh。
- 安装或更新 Skill 需要 Git。
- SSH 客户端，以及指向权威环境的可用 SSH alias。
- 项目目录中有 `.dev-exec.env`，或者进程环境中已经导出必需的
  `DEV_EXEC_*` 变量。

### 权威开发环境

- 真实项目 checkout、工具链、依赖、服务、Docker、SDK 和运行时。
- 可以通过 SSH alias 访问的 SSH server；使用反向 relay 时例外。
- 两个 checkout 分离并采用推荐同步方式时，Mutagen 必须安装在
  `dev-exec` 所在环境；内置安装器不需要管理员权限。

### 反向 relay 额外条件

- macOS 存在 `/usr/sbin/sshd`、`/usr/bin/ssh` 和 `/usr/bin/ssh-keygen`。
- Mac 可以先以非交互方式 SSH 到 VM。
- VM 的 SSH server 允许 remote forwarding，登录 shell 是 POSIX 兼容 shell。
- relay 使用的高位 loopback 端口没有被占用。

反向 relay 不会开启 macOS Remote Login，不会绑定 22 端口，不会修改防火墙，
不会监听公网地址，也不需要 `sudo`。

## 安装 Skill

Skill 必须安装在运行 Agent 的那台环境中。如果 Claude Code 在 VM 中运行，
Mac 的 `~/.claude/skills` 对 VM 不可见；必须在 VM 中单独 clone 并建立链接。

### 使用公开仓库

在 VM（或其他运行 Agent 的环境）执行：

```sh
git clone https://github.com/lajidonggua/remote-dev-execution.git \
  ~/code/remote-dev-execution

~/code/remote-dev-execution/scripts/install-skill.sh \
  --repo https://github.com/lajidonggua/remote-dev-execution.git \
  --ref main \
  --client claude
```

如果同一个用户环境同时运行 Claude 和 Codex：

```sh
~/code/remote-dev-execution/scripts/install-skill.sh --client both
```

默认目标分别是 Claude Code 的 `~/.claude/skills/remote-dev-execution` 和
Codex 的 `~/.agents/skills/remote-dev-execution`，两者都会指向同一个
canonical checkout。

安装器的行为是保守且可重复的：

- 只更新 `origin` 与 `--repo` 匹配且没有本地修改的 checkout。
- `--ref` 可以指定分支、tag 或 commit。
- 发现已有真实目录、断开的软链接或指向其他位置的链接时直接停止。
- 不使用 `sudo`，不覆盖无关的用户文件。
- `--no-update` 使用当前 checkout，不执行 fetch。
- `--dry-run` 只预览动作。
- `--root DIR` 指定 canonical checkout；`--target DIR` 指定单个客户端的链接位置。

安装或更新软链接后，重新启动 Claude Code/Codex 或开启新会话，让 Agent 重新
加载 Skill 元数据和指令。

### 团队内部使用

内部阶段使用团队私有仓库，并固定到经过审核的 ref：

```sh
~/code/remote-dev-execution/scripts/install-skill.sh \
  --repo git@github.com:your-org/remote-dev-execution.git \
  --ref team-stable \
  --client claude
```

不要把私有 deploy key、访问 Token 或私有项目路径写入 Skill；让 Git/SSH
自己的 credential helper 处理认证。测试阶段可以使用分支，稳定分发应使用
commit SHA 或 release tag。

### Claude Code 的触发与提示词

Claude Code 会根据 Skill 的描述和当前任务语义，判断是否需要加载 Skill。
这是按需的语义触发，不是命令拦截器。安装 Skill 不会自动安装 Mutagen、创建
`.dev-exec.env`、运行 `doctor`，也不能阻止 Claude 直接在当前工作区执行命令。

如果不写明确的工作流提示词，任务中明确提到远程验证时，Claude 仍可能自动
触发 Skill，但没有绝对保证。比如“修好后运行测试”这种模糊请求，可能被直接
当作当前工作区的本地测试。即使本地测试成功，也不能证明使用了权威开发环境。

为了让团队行为稳定，建议在 Agent 工作区的项目根目录加入并提交一份
`CLAUDE.md`（或 `AGENTS.md`）：

```markdown
For this workspace:

- Treat the current workspace as the editing environment.
- Run tests, builds, linters, services, and runtime checks only through the project's dev-exec wrapper.
- Run `dev-exec doctor` before authoritative validation.
- If execution or source freshness cannot be verified, stop and report the issue.
- Never run environment-dependent commands directly in the current workspace.
```

`.dev-exec.env` 和其他机器特定值仍应只保留在本地并加入忽略规则；上面的
项目规则没有主机名、用户名、路径、操作系统或传输方式信息。安装或更新 Skill，
或者修改项目规则后，请重启 Claude Code 或新建会话，让它重新加载元数据和指令。

日常任务使用下面这一句即可：

```text
Use the project's remote-dev-execution workflow for validation.
```

需要验证 Agent 是否正确委派测试时，使用
[references/agent-validation.md](references/agent-validation.md) 中的完整英文
提示词。它要求先运行脱敏的 `dev-exec doctor`，再选择最小相关测试，并且只报告
项目结果。不要为了触发 Skill 而在提示词中写入基础设施详情。

## 配置项目

在 VM 项目 checkout 中执行：

```sh
cp ~/code/remote-dev-execution/assets/.dev-exec.env.example .dev-exec.env
chmod 600 .dev-exec.env
```

编辑 `.dev-exec.env`，填写权威环境的 SSH alias 和项目路径：

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
```

`DEV_EXEC_DIR` 是权威开发机上的路径，不是 VM 上的路径，必须是绝对路径。
`.dev-exec.env` 是业务项目的本地配置，不是 Skill 配置。把它加入业务仓库
的 `.gitignore`，或者写入业务仓库的 `.git/info/exclude`。

`dev-exec` 从当前工作目录向上查找最近的 `.dev-exec.env`。进程环境变量会
覆盖配置文件值，适合临时切换 shell：

```sh
DEV_EXEC_SHELL=/bin/sh \
  ~/code/remote-dev-execution/scripts/dev-exec doctor
```

变量完整说明见 [references/configuration.md](references/configuration.md)。

## 直接 SSH：完整教程

当 VM 可以直接访问权威开发机时，这是最简单的方案。

### 1. 配置并测试 SSH alias

在 VM 的 `~/.ssh/config` 中配置 alias。以下只是结构示例，必须替换为你的
真实主机、用户和密钥：

```sshconfig
Host dev-machine
  HostName your-development-host
  User devuser
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

先测试普通 SSH，不要一开始就排查 Skill：

```sh
ssh dev-machine true
```

如果出现密码提示、host-key 错误或 alias 不存在，先修复普通 SSH。不要通过
关闭 host-key 检查来“解决”问题。

### 2. 指向权威 checkout

从 VM 项目目录执行：

```sh
cat > .dev-exec.env <<'EOF'
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
EOF
chmod 600 .dev-exec.env
```

### 3. 执行最小的权威验证

普通命令使用参数形式：

```sh
~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test -- --runInBand
```

doctor 报告执行失败或源码新鲜度尚未确认时，不要运行测试。

需要管道、重定向或 shell 展开的命令，使用一个带引号的字符串：

```sh
~/code/remote-dev-execution/scripts/dev-exec \
  'npm test -- --runInBand | tee /tmp/project-test.log'
```

wrapper 会先进入 `DEV_EXEC_DIR`，再执行 `DEV_EXEC_SHELL -lc`。远程 stdout 和
stderr 原样返回，SSH 成功连接后返回远程命令的退出码。

## Mutagen：可选，但源码新鲜度不可省略

### 不需要 Mutagen 的情况

以下场景不要额外安装 Mutagen：

- VM 和权威环境使用同一个共享或挂载的 checkout；
- VM 当前路径本身就是权威 checkout；
- 已经有其他同步工具，并且它有明确、可验证的完成信号。

此时不要设置 `DEV_EXEC_MUTAGEN_SESSION`，但每次验证前仍要确认权威 checkout
确实包含最新编辑内容。wrapper 无法猜测两个目录是否同步。

### 需要 Mutagen 的情况

当 Agent 和权威环境各自拥有一个 checkout 时，推荐 Mutagen。Claude/Codex
仍在 Agent 本地文件系统中高频扫描和修改，不需要通过高延迟网络挂载读写。

先手动创建 `.dev-exec.env`，或者用 `dev-relay setup --project` 生成。然后在
Agent 项目中执行一次：

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
```

| 参数 | 什么时候使用 | 作用 |
| --- | --- | --- |
| `--install` | `dev-exec` 所在环境还没有 Mutagen | 不用 `sudo`，把固定版本安装到 `~/.local/bin`。 |
| `--name SESSION` | 推荐，用于团队统一命名 | 指定新 session 名；省略时按当前项目生成稳定名称。 |
| `--ignore PATH` | 可重建的依赖、缓存或构建目录只应留在本侧 | 添加一个 ignore；多个目录重复填写该参数。 |
| `--version VERSION` | 团队审核了其他安装版本 | 指定 `--install` 使用的版本。 |
| `--verbose` | 仅限用户批准的 setup 排错 | 显示 Mutagen 原始输出，可能包含端点和路径。 |

helper 会在需要时把固定版本安装到 `~/.local/bin`，不使用 `sudo`；下载安装包
后会核对官方 release 的 `SHA256SUMS`。它从最近的 `.dev-exec.env` 推导两个
端点，创建 `two-way-safe` session，原子写入 session 配置，维护本地 Git
exclude，并执行 doctor。如果 `.dev-exec.env` 已被 Git 跟踪，它会直接停止。

只安装 Mutagen、不创建 session 时，在 `dev-exec` 所在环境运行：

```sh
~/code/remote-dev-execution/scripts/install-mutagen.sh
~/.local/bin/mutagen version
```

该环境已经批准 Homebrew 时，也可以执行
`brew install mutagen-io/mutagen/mutagen`。如果现有 session 由其他获准环境
控制，则应配置 `DEV_EXEC_MUTAGEN_HOST`；只在其他环境安装而不配置该变量，
前置检查仍无法执行。
Mutagen daemon 会按需自动启动，通常不需要单独启动服务。重启或网络变化后
重新运行 doctor 即可。

VCS 元数据和 `.dev-exec.env` 默认不会同步。只为当前项目明确增加可重建的
依赖或构建目录：

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync \
  --ignore node_modules \
  --ignore build
```

不要照搬 ignore；源码、lockfile、migration、fixture 和需要审核的生成文件不能
忽略。被忽略的依赖和产物需要在权威环境独立准备。

已有 session 时，直接配置它的准确名称：

```sh
DEV_EXEC_HOST=dev-machine
DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine
DEV_EXEC_SHELL=/bin/zsh
DEV_EXEC_MUTAGEN_SESSION=project-sync
DEV_EXEC_MUTAGEN_BIN=mutagen
# 只有当 Mutagen daemon/session 由其他环境控制时才填写：
# DEV_EXEC_MUTAGEN_HOST=sync-control
```

以后每次 `dev-exec` 都会先 flush，再查询结构化健康状态，然后才启动 SSH。
session 不存在、端点断开、冲突、session error、扫描问题、写入问题或 flush
失败都会停止执行。这个二次检查很重要，因为 `two-way-safe` 可以在保留冲突的
情况下完成一次 flush。

健康的 doctor 会依次包含 `synchronization tool: available`、
`synchronization session: available`、`synchronization health: healthy`、
`synchronization preflight: passed` 和 `authoritative execution: ready`。

Mutagen 和 session 默认存在于 `dev-exec` 所在环境；如果 session 在其他获准
环境中，设置 `DEV_EXEC_MUTAGEN_HOST` 后 wrapper 会通过该 alias 执行前置检查。
只在其他环境安装、却没有配置这个变量，不能完成 Agent 侧前置检查。

运行 formatter、generator、migration、install 或更新 snapshot 前，先确定
生成文件由哪一侧拥有，以及如何安全回传到编辑环境。Mutagen 不会替你解决
这些所有权问题。

单独安装、版本固定、已有 session、ignore、日常操作、冲突恢复和安全细节见
[Mutagen synchronization](references/mutagen.md)。

## macOS 非管理员反向 Relay

当权威环境是 Mac、Claude 在 VM 中运行，而 VM 因为无法开启 Remote Login 或
没有管理员权限而不能主动连入 Mac 时，使用反向 relay。

```text
VM: dev-exec / ssh rde-mac-dev
        -> VM 127.0.0.1:22022
        -> Mac 发起的反向 SSH forward
        -> Mac 127.0.0.1:22022
        -> 用户自己的 sshd
        -> Mac 项目、工具链、服务和运行时
```

这里有两个方向相反的 alias：

- `dev-vm`：Mac 用它连接 VM，并创建反向隧道。
- `rde-mac-dev`：安装在 VM，经过隧道回到 Mac。

### 在 Mac 上一键 setup

先确认 Mac 已经可以免密码连接 VM：

```sh
ssh dev-vm true
```

然后执行：

```sh
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --client claude \
  --project /absolute/path/to/project/on/vm \
           /absolute/path/to/project/on/mac \
  --shell /bin/zsh
```

所有 alias、路径、shell 和 Mutagen session 都是示例，必须替换。`--project`
是可选的，但提供后会在 VM 项目中生成 `.dev-exec.env`，并尽量写入该项目
checkout 的 `.git/info/exclude`。不提供时，需要在 VM 手动创建配置文件。
`--client` 会把 Skill 安装到 Agent 实际运行的环境中。

setup 会在不使用管理员权限的情况下：

1. 在 VM 生成专用 Ed25519 key（如果还没有）。
2. 只取 VM 公钥，用于授权 Mac 用户态 `sshd`。
3. 创建只监听 loopback 的 Mac `sshd`，并启动反向隧道。
4. 在 VM 安装受管理的 SSH alias 和精确的 relay host-key 信任。
5. 在 VM 安装 `~/.local/share/remote-dev-execution/dev-exec`，只有在
   `~/.local/bin/dev-exec` 未被占用时才创建链接。
6. 为指定 Agent 安装 canonical Git checkout 和用户级 Skill 软链接。
7. 执行一次 VM 到 Mac 的端到端验证。

setup 本身只负责连通性，不会自动同步两个独立 checkout。首次完成后，在 VM
项目中运行 `setup-mutagen.sh --install`；如果已经有审核过的 session，也可以
在 setup 时使用 `--mutagen`；或者采用其他经过验证的同步机制。relay 活跃时，
VM 可以以当前 Mac 用户打开 shell，并不局限于某个项目目录，所以只应连接
可信 VM。

重复 setup 时省略 `--mutagen` 会保留已有的生成配置和 Mutagen session。只有在
明确改用共享 checkout 或其他已验证的新鲜度机制时，才使用 `--clear-mutagen`。

如果 relay 由旧版本创建，可以只补装 Agent Skill，不需要重建 relay：

```sh
~/code/remote-dev-execution/scripts/dev-relay install-skill --client claude
```

团队内部仓库或固定 release 可以在两条命令中增加 `--repo` 和 `--ref`。
安装后重启 Agent，让它重新发现 Skill。

### 启动、查看和停止

`setup` 会自动启动 relay。Mac 休眠、网络变化或 VM 重启后，执行：

```sh
~/code/remote-dev-execution/scripts/dev-relay status
~/code/remote-dev-execution/scripts/dev-relay stop
~/code/remote-dev-execution/scripts/dev-relay start
```

也可以让当前终端持有前台进程：

```sh
~/code/remote-dev-execution/scripts/dev-relay foreground
```

`foreground` 退出时会清理它启动的用户态 `sshd`。后台 relay 正在运行时不要
再启动 foreground。

### 在 VM 验证回程

setup 已经做过底层端到端检查。日常由用户或 Agent 验证时，在 VM 项目中
运行脱敏的 doctor：

```sh
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync

~/.local/share/remote-dev-execution/dev-exec doctor
```

只有两个 checkout 分离时才运行一次 setup helper。已经确认共享 checkout，
或 relay setup 已填写现有 session 时跳过。

doctor 能证明 wrapper 到达了可信项目配置所声明的环境，但不会独立判断该
目标是否真的具备“权威”身份，也无法判断未配置同步的独立 checkout 是否
最新。先审核配置并确认源码新鲜度，再运行项目测试。原始 `ssh` 探针只用于
用户批准的详细排错，因为它可能暴露基础设施信息。

如果 setup 没有使用 `--project`，在 VM 项目中手动写入：

```sh
cat > .dev-exec.env <<'EOF'
DEV_EXEC_HOST=rde-mac-dev
DEV_EXEC_DIR=/absolute/path/to/project/on/mac
DEV_EXEC_SHELL=/bin/zsh
# 两个 checkout 分离时可选：
# DEV_EXEC_MUTAGEN_SESSION=project-sync
EOF
chmod 600 .dev-exec.env
```

### 交互式调试和 debug 端口

`dev-exec` 适合非交互命令。需要 shell、REPL 或终端 debugger 时使用 TTY：

```sh
ssh -t rde-mac-dev \
  'cd /absolute/path/to/project/on/mac && exec /bin/zsh -l'
```

如果需要把 Mac 上的 debug 服务映射到 VM loopback，在 Mac 的
`~/.config/remote-dev-execution/relay.env` 中加入：

```sh
DEV_RELAY_DEBUG_PORTS="3000 5005 9229"
```

重启 relay，并让 Mac 侧服务监听 `127.0.0.1`。端口只在两台机器的 loopback
之间转发，不会暴露到局域网。

手动 relay、生成 VM SSH 配置、安全模型和限制见
[references/reverse-relay.md](references/reverse-relay.md)。

## 端到端 Demo

### Demo A：直接 SSH，共享 checkout

```sh
# 在 VM 项目中执行。
printf '%s\n' \
  'DEV_EXEC_HOST=dev-machine' \
  'DEV_EXEC_DIR=/absolute/path/to/shared/project' \
  'DEV_EXEC_SHELL=/bin/zsh' > .dev-exec.env
chmod 600 .dev-exec.env

ssh dev-machine true
~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

双方使用同一个 checkout，所以不需要 Mutagen。

### Demo B：两个 checkout，使用 Mutagen

```sh
# 在 VM 项目中执行。
printf '%s\n' \
  'DEV_EXEC_HOST=dev-machine' \
  'DEV_EXEC_DIR=/absolute/path/to/project/on/authoritative-machine' > .dev-exec.env
chmod 600 .dev-exec.env

# 一次完成安装、创建 session、更新配置和 doctor。
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync \
  --ignore PROJECT_GENERATED_DIRECTORY

~/code/remote-dev-execution/scripts/dev-exec doctor
~/code/remote-dev-execution/scripts/dev-exec -- npm test
```

没有额外 ignore 时删除 `--ignore PROJECT_GENERATED_DIRECTORY`。wrapper 每次
执行前都会 flush 并检查 session 健康状态。

### Demo C：VM Claude 调试非管理员 Mac

```sh
# Mac 上：建立 relay，并自动生成 VM 项目配置。
ssh dev-vm true
~/code/remote-dev-execution/scripts/dev-relay setup dev-vm \
  --client claude \
  --project /absolute/path/to/project/on/vm \
           /absolute/path/to/project/on/mac \
  --shell /bin/zsh

# VM 项目中：一次配置同步，然后验证并运行测试。
~/code/remote-dev-execution/scripts/setup-mutagen.sh \
  --install \
  --name project-sync
~/.local/share/remote-dev-execution/dev-exec doctor
~/.local/share/remote-dev-execution/dev-exec -- npm test
```

### Demo D：复用由其他环境控制的 Mutagen session

如果 Mutagen 已经在另一个获准环境中创建，不要为同一对 checkout 再创建第二个
session。relay setup 时同时填写现有 session 名称和控制 alias：

```sh
~/code/remote-dev-execution/scripts/dev-relay setup VM_ALIAS \
  --client claude \
  --project /absolute/path/to/project/in/agent-environment \
           /absolute/path/to/project/in/authoritative-environment \
  --shell /bin/zsh \
  --mutagen EXISTING_SESSION \
  --mutagen-host MUTAGEN_CONTROL_HOST \
  --mutagen-bin MUTAGEN_BIN
```

之后 Agent 侧 wrapper 会在每次委托命令前，通过该控制 alias 执行 Mutagen 的
`version`、`sync list` 和 `sync flush` 检查。如果控制环境的非交互 `PATH` 中
没有 `mutagen`，`MUTAGEN_BIN` 可以填写绝对路径。控制 alias 必须能从 Agent
环境非交互连接，且 session 必须显示双方已连接、没有扫描问题或冲突。

## 常见问题

| 现象 | 检查方式 |
| --- | --- |
| `DEV_EXEC_HOST is required` | 在目标项目或父目录创建 `.dev-exec.env`，或导出必需变量。 |
| `configuration not found` | 确认当前目录在目标项目树内。 |
| SSH 要求输入密码 | 先修复普通 SSH alias 和 keychain；wrapper 本身是非交互的。 |
| 远程目录不存在 | 确认 `DEV_EXEC_DIR` 是权威机器上的绝对路径。 |
| Mutagen executable unavailable | 在 `dev-exec` 所在环境运行 `setup-mutagen.sh --install`，或者设置 `DEV_EXEC_MUTAGEN_HOST` 并修正控制环境中的 `DEV_EXEC_MUTAGEN_BIN`。 |
| Mutagen session unavailable | 在 session 所属控制环境中用 `mutagen sync list -- SESSION` 核对 `DEV_EXEC_MUTAGEN_SESSION`，不要换成未审核的 session。 |
| Mutagen health 报告端点断开、冲突或文件系统问题 | 用户运行 `mutagen sync list --long -- SESSION`，恢复 session、处理相关文件后重跑 doctor，不要绕过健康检查。 |
| doctor 显示 `source freshness: not verified` | 先确认共享 checkout 或完成外部同步；仅连通不能证明测试使用了当前源码。 |
| setup 发现未托管的 `.dev-exec.env` | 保留文件并去掉 `--project` 重跑；或者审核后把它移为备份，再让 setup 生成。脚本不会自动覆盖。 |
| Agent 找不到 Skill | 用匹配的 `--client` 运行 `dev-relay install-skill`，然后重启 Agent。 |
| relay 已停止 | Mac 上运行 `dev-relay status`，然后 `stop` 再 `start`。 |
| VM host-key 错误 | 重新运行 setup 或 `print-vm-config`，安装精确生成的 trust 条目，不要关闭严格校验。 |
| debugger 无法连接 | 只配置需要的 `DEV_RELAY_DEBUG_PORTS`，让服务监听 loopback，然后重启 relay。 |
| macOS 日志出现 audit/login 警告 | 非 root `sshd` 可能无法写系统审计数据库；命令和 TTY 会话仍可能正常。 |

## 安全和脱敏清单

以下内容必须留在 Git 之外：

- `.dev-exec.env` 和 `relay.env`；
- SSH 私钥、`known_hosts` 材料和 relay state；
- 用户名、主机名、IP、项目绝对路径、Token 和密码；
- 含凭据或个人数据的日志和命令输出。

推送到团队仓库或公开仓库前执行扫描。`dev-machine`、`dev-vm`、
`rde-mac-dev`、`127.0.0.1` 和 `/absolute/path/...` 都是故意使用的通用示例：

```sh
git status --short --ignored
git grep -n -I -E \
  '(/Users/|/home/|/var/folders|ssh-(rsa|ed25519)|BEGIN .*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]+|Bearer [A-Za-z0-9._-]+)' \
  -- . ':!README.md' ':!README.zh-CN.md' || true
```

如果真实秘密曾经进入 Git，先撤销或轮换，再按团队批准的历史重写流程清理；
只删除最新文件中的一行并不能消除 Git 历史中的秘密。

## 更新、卸载和公开发布

更新到经过审核的 ref：

```sh
~/code/remote-dev-execution/scripts/install-skill.sh \
  --repo https://github.com/lajidonggua/remote-dev-execution.git \
  --ref main \
  --client claude
```

卸载时先确认用户级目标是指向 canonical checkout 的软链接，只删除软链接；
是否删除 checkout 另行决定。

公开发布前，先合并经过审核的变更，等待 `Validate` workflow 通过，再创建
类似 `v0.1.0` 的 annotated tag，让用户安装固定 tag，而不是未经审核的移动
分支。不要使用 `curl | sh`；先 clone 经过审核的仓库，再运行可见的安装脚本。

## 验证改动

运行 CI 使用的检查：

```sh
sh -n scripts/dev-exec scripts/dev-relay scripts/install-skill.sh \
  scripts/install-mutagen.sh scripts/setup-mutagen.sh \
  tests/test-dev-exec.sh tests/test-dev-relay.sh tests/test-install-skill.sh \
  tests/test-install-mutagen.sh tests/test-setup-mutagen.sh \
  tests/test-relay-embedded.sh
tests/test-dev-exec.sh
tests/test-dev-relay.sh
tests/test-install-skill.sh
tests/test-install-mutagen.sh
tests/test-setup-mutagen.sh
tests/test-relay-embedded.sh
```

官方 Skill 元数据校验还需要 Python `PyYAML`。

## 参考和许可证

- [配置参考](references/configuration.md)
- [Mutagen 同步参考](references/mutagen.md)
- [macOS 非管理员反向 relay 参考](references/reverse-relay.md)
- [Agent 执行验证](references/agent-validation.md)
- [MIT License](LICENSE)
