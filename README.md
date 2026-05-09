# Hermes Agent 中文在线安装版

面向中文用户的 Hermes Agent 在线安装项目。

它会自动获取官方 Hermes Agent，并安装适配当前版本的中文汉化内容，帮助你更顺手地完成安装、配置和开始使用。

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/install-zh.sh | bash
```

安装完成后，重新加载 shell：

```bash
source ~/.bashrc
```

如果你使用的是 zsh：

```bash
source ~/.zshrc
```

然后执行：

```bash
hermes setup
```

按提示完成模型、API Key 和常用功能配置。配置完成后，直接运行：

```bash
hermes
```

就可以开始使用。

## 适用环境

- Linux
- macOS
- WSL2

不支持原生 Windows。Windows 用户请先安装 WSL2，再进入 Linux 环境执行安装命令。

## 这个安装版会做什么

安装脚本会尽量帮你自动完成这些事情：

- 下载或更新 Hermes Agent
- 选择匹配版本的中文汉化内容
- 执行官方安装流程
- 在检测到旧版本时提示你如何继续
- 在有旧配置时提示你是否导入

如果你之前安装过旧版本，脚本会尽量帮你平滑升级，而不是要求你从头重来。

## 常用命令

```bash
hermes
```

启动 Hermes 交互界面。

```bash
hermes setup
```

重新打开配置向导。

```bash
hermes model
```

重新选择或切换模型。

```bash
hermes gateway install
```

安装消息网关，用于接入 Telegram、Discord 等平台。

```bash
hermes doctor
```

检查常见环境和配置问题。

## 更新方式

如果你想重新执行最新的在线安装流程，直接再次运行：

```bash
curl -fsSL https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/install-zh.sh | bash
```

安装器会根据你当前的安装状态继续处理。

如果检测到你之前使用的是官方旧版本，或者是官方 `main` 分支版本，脚本会提示你是否切换到当前汉化版匹配的官方发布版本后继续安装。

## 常见问题

### 提示 `hermes: command not found`

先执行：

```bash
source ~/.bashrc
```

如果你使用 zsh，就执行：

```bash
source ~/.zshrc
```

然后再试：

```bash
hermes
```

### 已经装过旧版本，还能继续安装吗

可以。

安装器会先检测你当前的版本。如果旧版本和当前汉化包不匹配，会提示你：

- 自动切换到匹配版本后继续安装
- 或先停止，手动处理

如果检测到已有配置，安装完成后还会提示你是否导入旧配置。

### Windows 能直接安装吗

不能。请先安装 WSL2，再在 Linux 环境中运行安装命令。

### 安装完之后还有部分内容是英文

先重新运行一次安装命令。

如果仍有少量内容未汉化，通常是因为官方版本刚更新，对应汉化内容还在同步中。

## 项目地址

- 中文在线安装版：<https://github.com/David8lang/hermes-agent-zh>
- 官方 Hermes Agent：<https://github.com/NousResearch/hermes-agent>
