# Hermes 中文补丁说明

## 在线一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/install-zh.sh | bash
```

强制 GitHub 官方源：

```bash
curl -fsSL https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/install-zh.sh | HERMES_ZH_REPO_SOURCE=github bash
```

强制 GitCode 镜像源：

```bash
curl -fsSL https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/install-zh.sh | HERMES_ZH_REPO_SOURCE=gitcode bash
```

安装脚本会从同一仓库的 patches/versions/... 路径下载 manifest、补丁和 zh_patch.py。
这个目录提供 Hermes CLI/setup/gateway 的中文补丁。补丁目标是只翻译用户可见文案，不改变原版交互流程、菜单默认项、输入顺序、保存逻辑、二维码/链接流程或命令行行为。
