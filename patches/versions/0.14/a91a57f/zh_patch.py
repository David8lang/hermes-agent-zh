"""
Chinese localization helpers for Hermes CLI setup menus.

This module is intentionally small and defensive: callers can translate known
menu text while unknown text, provider names, model IDs, URLs, and config keys
remain unchanged.
"""

from __future__ import annotations

import re
from typing import Iterable


_TEXT = {
    # Section labels and headings
    "Model & Provider": "模型与提供商",
    "Text-to-Speech": "文本转语音",
    "Terminal Backend": "终端后端",
    "Messaging Platforms (Gateway)": "消息平台（网关）",
    "Messaging Platforms": "消息平台",
    "Tools": "工具",
    "Agent Settings": "代理设置",
    "Tool Availability Summary": "工具可用性摘要",
    "Inference Provider": "推理提供商",
    "Same-Provider Fallback & Rotation": "同提供商备用凭据与轮换",
    "Vision & Image Analysis (optional)": "视觉与图像分析（可选）",
    "Text-to-Speech Provider (optional)": "文本转语音提供商（可选）",
    "Context Compression": "上下文压缩",
    "Session Reset Policy": "会话重置策略",
    "OpenClaw Installation Detected": "检测到 OpenClaw 安装",
    "Configuration Location": "配置位置",
    "Welcome Back!": "欢迎回来！",
    "Quick Setup - Missing Items Only": "快速设置 - 仅配置缺失项目",
    "Tool API Keys": "工具 API 密钥",
    "API key saved.": "API 密钥已保存。",
    "Cancelled.": "已取消。",
    "No change.": "未更改。",
    "Not logged into Nous Portal. Starting login...": "尚未登录 Nous Portal，正在开始登录...",
    "Login cancelled or failed.": "登录已取消或失败。",
    "Not logged into OpenAI Codex. Starting login...": "尚未登录 OpenAI Codex，正在开始登录...",
    "Not logged into Qwen CLI OAuth.": "尚未登录 Qwen CLI OAuth。",
    "Run: qwen auth qwen-oauth": "请运行：qwen auth qwen-oauth",
    "No curated models available for Nous Portal.": "Nous Portal 当前没有可用的精选模型。",
    "No free models currently available.": "当前没有可用的免费模型。",
    "Custom OpenAI-compatible endpoint configuration:": "自定义 OpenAI 兼容端点配置：",
    "No custom providers configured.": "当前没有配置自定义提供商。",
    "Remove a custom provider:": "删除一个自定义提供商：",
    "Fetching available models...": "正在获取可用模型...",
    "Could not fetch models from endpoint.": "无法从端点获取模型列表。",
    "Could not fetch models from endpoint. Enter model name manually.": "无法从端点获取模型列表，请手动输入模型名称。",
    "No URL provided. Cancelled.": "未提供 URL，已取消。",
    "Endpoint saved. Use `/model` in chat or `hermes model` to set a model.": "端点已保存。可在聊天中使用 `/model`，或运行 `hermes model` 设置模型。",
    "Continue with OAuth login? [y/N]: ": "继续进行 OAuth 登录吗？ [y/N]: ",
    "Select provider to remove:": "选择要删除的提供商：",
    "Cancel": "取消",
    "  Skipped (keeping current)": "  已跳过（保留当前设置）",
    "Skipped (keeping current)": "已跳过（保留当前设置）",
    "Choose how to connect to your main chat model.": "选择如何连接你的主聊天模型。",
    "Provider setup skipped.": "已跳过提供商设置。",
    "You can try again later with: hermes model": "稍后可以运行 hermes model 重试。",
    "Skipping migration. You can run it later with: hermes claw migrate --dry-run": "已跳过迁移。稍后可以运行：hermes claw migrate --dry-run",
    "Current model:": "当前模型：",
    "Active provider:": "当前提供商：",
    "(not set)": "（未设置）",
    "not set": "未设置",
    "none": "无",
    "Guide:": "指南：",
    "Warning:": "警告：",
    "Falling back to auto provider detection.": "正在回退到自动检测提供商。",
    "No inference provider configured. Run 'hermes model' to choose a provider and model, or set an API key (OPENROUTER_API_KEY, OPENAI_API_KEY, etc.) in ~/.hermes/.env.": "未配置推理提供商。请运行 'hermes model' 选择提供商和模型，或在 ~/.hermes/.env 中设置 API 密钥（OPENROUTER_API_KEY、OPENAI_API_KEY 等）。",

    # Main setup menus
    "What would you like to do?": "你想执行什么操作？",
    "Quick Setup - configure missing items only": "快速设置 - 仅配置缺失项目",
    "Full Setup - reconfigure everything": "完整设置 - 重新配置全部内容",
    "Exit": "退出",
    "How would you like to set up Hermes?": "你想如何设置 Hermes？",
    "Quick setup - provider, model & messaging (recommended)": "快速设置 - 提供商、模型和消息平台（推荐）",
    "Full setup - configure everything": "完整设置 - 配置全部内容",

    # Common setup choices and prompts
    "Connect a messaging platform? (Telegram, Discord, etc.)": "要连接消息平台吗？（Telegram、Discord 等）",
    "Set up messaging now (recommended)": "现在设置消息平台（推荐）",
    "Skip - set up later with 'hermes setup gateway'": "跳过 - 稍后用 'hermes setup gateway' 设置",
    "Which tools would you like to configure?": "你想配置哪些工具？",
    "Which platforms would you like to set up?": "你想设置哪些平台？",
    "Select platforms to configure:": "选择要配置的平台：",
    "Configure vision:": "配置视觉能力：",
    "OpenRouter - uses Gemini (free tier at openrouter.ai/keys)": "OpenRouter - 使用 Gemini（openrouter.ai/keys 有免费额度）",
    "OpenAI-compatible endpoint - base URL, API key, and vision model": "OpenAI 兼容端点 - Base URL、API 密钥和视觉模型",
    "Skip for now": "暂时跳过",
    "Select vision model:": "选择视觉模型：",
    "Use default (gpt-4o-mini)": "使用默认值（gpt-4o-mini）",
    "Select same-provider rotation strategy:": "选择同提供商凭据轮换策略：",
    "Fill-first / sticky - keep using the first healthy credential until it is exhausted": "优先填满 / 粘性 - 持续使用第一个可用凭据，直到耗尽",
    "Round robin - rotate to the next healthy credential after each selection": "轮询 - 每次选择后切换到下一个可用凭据",
    "Random - pick a random healthy credential each time": "随机 - 每次随机选择一个可用凭据",
    "Select TTS provider:": "选择文本转语音提供商：",
    "Select terminal backend:": "选择终端后端：",
    "Session reset mode:": "会话重置模式：",
    "Launch hermes chat now?": "现在启动 hermes chat 吗？",

    # Tools setup
    "Select an option:": "选择一个选项：",
    "Configure all platforms (global)": "配置所有平台（全局）",
    "Configure MCP server tools": "配置 MCP 服务器工具",
    "Reconfigure an existing tool's provider or API key": "重新配置已有工具的提供商或 API 密钥",
    "Done": "完成",
    "All platforms": "所有平台",
    "Choose a provider": "选择提供商",
    "Select Search Provider": "选择搜索提供商",
    "Select provider:": "选择提供商：",
    "Nous Portal (Nous Research subscription)": "Nous Portal（Nous Research 订阅）",
    "OpenRouter (100+ models, pay-per-use)": "OpenRouter（100+ 模型，按量付费）",
    "Vercel AI Gateway (200+ models, $5 free credit, no markup)": "Vercel AI Gateway（200+ 模型，$5 免费额度，无加价）",
    "Anthropic (Claude models - API key or Claude Code)": "Anthropic（Claude 模型 - API key 或 Claude Code）",
    "Anthropic (Claude models — API key or Claude Code)": "Anthropic（Claude 模型 - API key 或 Claude Code）",
    "OpenAI Codex": "OpenAI Codex",
    "Xiaomi MiMo (MiMo-V2 models - pro, omni, flash)": "Xiaomi MiMo（MiMo-V2 模型 - pro、omni、flash）",
    "Xiaomi MiMo (MiMo-V2 models — pro, omni, flash)": "Xiaomi MiMo（MiMo-V2 模型 - pro、omni、flash）",
    "NVIDIA NIM (Nemotron models - build.nvidia.com or local NIM)": "NVIDIA NIM（Nemotron 模型 - build.nvidia.com 或本地 NIM）",
    "NVIDIA NIM (Nemotron models — build.nvidia.com or local NIM)": "NVIDIA NIM（Nemotron 模型 - build.nvidia.com 或本地 NIM）",
    "Qwen OAuth (reuses local Qwen CLI login)": "Qwen OAuth（复用本地 Qwen CLI 登录）",
    "GitHub Copilot (uses GITHUB_TOKEN or gh auth token)": "GitHub Copilot（使用 GITHUB_TOKEN 或 gh auth token）",
    "GitHub Copilot ACP (spawns `copilot --acp --stdio`)": "GitHub Copilot ACP（启动 `copilot --acp --stdio`）",
    "Hugging Face Inference Providers (20+ open models)": "Hugging Face Inference Providers（20+ 开放模型）",
    "Google AI Studio (Gemini models - native Gemini API)": "Google AI Studio（Gemini 模型 - 原生 Gemini API）",
    "Google AI Studio (Gemini models — native Gemini API)": "Google AI Studio（Gemini 模型 - 原生 Gemini API）",
    "Google Gemini via OAuth + Code Assist (free tier supported; no API key needed)": "Google Gemini via OAuth + Code Assist（支持免费层；无需 API key）",
    "DeepSeek (DeepSeek-V3, R1, coder - direct API)": "DeepSeek（DeepSeek-V3、R1、coder - 直连 API）",
    "DeepSeek (DeepSeek-V3, R1, coder — direct API)": "DeepSeek（DeepSeek-V3、R1、coder - 直连 API）",
    "xAI (Grok models - direct API)": "xAI（Grok 模型 - 直连 API）",
    "xAI (Grok models — direct API)": "xAI（Grok 模型 - 直连 API）",
    "Z.AI / GLM (Zhipu AI direct API)": "Z.AI / GLM（智谱 AI 直连 API）",
    "Kimi Coding Plan (api.kimi.com) & Moonshot API": "Kimi Coding Plan（api.kimi.com）& Moonshot API",
    "Kimi / Moonshot China (Moonshot CN direct API)": "Kimi / Moonshot China（Moonshot CN 直连 API）",
    "StepFun Step Plan (agent/coding models via Step Plan API)": "StepFun Step Plan（通过 Step Plan API 使用 agent/coding 模型）",
    "MiniMax (global direct API)": "MiniMax（全球直连 API）",
    "MiniMax China (domestic direct API)": "MiniMax China（国内直连 API）",
    "Alibaba Cloud / DashScope Coding (Qwen + multi-provider)": "Alibaba Cloud / DashScope Coding（Qwen + 多提供商）",
    "Ollama Cloud (cloud-hosted open models - ollama.com)": "Ollama Cloud（云端开放模型 - ollama.com）",
    "Ollama Cloud (cloud-hosted open models — ollama.com)": "Ollama Cloud（云端开放模型 - ollama.com）",
    "Arcee AI (Trinity models - direct API)": "Arcee AI（Trinity 模型 - 直连 API）",
    "Arcee AI (Trinity models — direct API)": "Arcee AI（Trinity 模型 - 直连 API）",
    "Kilo Code (Kilo Gateway API)": "Kilo Code（Kilo Gateway API）",
    "OpenCode Zen (35+ curated models, pay-as-you-go)": "OpenCode Zen（35+ 精选模型，按量付费）",
    "OpenCode Go (open models, $10/month subscription)": "OpenCode Go（开放模型，$10/月订阅）",
    "AWS Bedrock (Claude, Nova, Llama, DeepSeek - IAM or API key)": "AWS Bedrock（Claude、Nova、Llama、DeepSeek - IAM 或 API key）",
    "AWS Bedrock (Claude, Nova, Llama, DeepSeek — IAM or API key)": "AWS Bedrock（Claude、Nova、Llama、DeepSeek - IAM 或 API key）",
    "Custom endpoint (enter URL manually)": "自定义端点（手动输入 URL）",
    "Configure auxiliary models...": "配置辅助模型...",
    "Leave unchanged": "保持不变",
    "Configure vision backend": "配置视觉后端",
    "Which tool would you like to reconfigure?": "你想重新配置哪个工具？",
    "Tools for": "工具配置：",
    "Press Enter to continue": "按 Enter 继续",
    "Applied recommended defaults:": "已应用推荐默认值：",
    "Max iterations: 90": "最大迭代次数：90",
    "Tool progress: all": "工具进度：all",
    "Compression threshold: 0.50": "压缩阈值：0.50",
    "Session reset: inactivity (1440 min) + daily (4:00)": "会话重置：空闲 1440 分钟 + 每日 4:00",
    "Run `hermes setup agent` later to customize.": "稍后运行 `hermes setup agent` 可自定义。",
    "Setup complete! You're ready to go.": "设置完成！现在可以开始使用。",
    "Configure all settings:": "配置所有设置：",
    "Connect Telegram/Discord:": "连接 Telegram/Discord：",
    "Tool Availability Summary": "工具可用性摘要",
    "Vision (image analysis)": "视觉（图像分析）",
    "Mixture of Agents": "多模型协作",
    "Web Search & Extract": "网页搜索与提取",
    "Web Search & Extract (Nous subscription)": "网页搜索与提取（Nous 订阅）",
    "Browser Automation": "浏览器自动化",
    "Browser Automation (Nous Browser Use)": "浏览器自动化（Nous Browser Use）",
    "Image Generation": "图像生成",
    "Image Generation (Nous subscription)": "图像生成（Nous 订阅）",
    "Text-to-Speech (OpenAI via Nous subscription)": "文本转语音（通过 Nous 订阅使用 OpenAI）",
    "Text-to-Speech (ElevenLabs)": "文本转语音（ElevenLabs）",
    "Text-to-Speech (OpenAI)": "文本转语音（OpenAI）",
    "Text-to-Speech (MiniMax)": "文本转语音（MiniMax）",
    "Text-to-Speech (Mistral Voxtral)": "文本转语音（Mistral Voxtral）",
    "Text-to-Speech (Google Gemini)": "文本转语音（Google Gemini）",
    "Text-to-Speech (NeuTTS local)": "文本转语音（本地 NeuTTS）",
    "Text-to-Speech (NeuTTS - not installed)": "文本转语音（NeuTTS - 未安装）",
    "Text-to-Speech (KittenTTS local)": "文本转语音（本地 KittenTTS）",
    "Text-to-Speech (KittenTTS - not installed)": "文本转语音（KittenTTS - 未安装）",
    "Text-to-Speech (Edge TTS)": "文本转语音（Edge TTS）",
    "Modal Execution (Nous subscription)": "Modal 执行（Nous 订阅）",
    "Modal Execution (direct Modal)": "Modal 执行（直连 Modal）",
    "Modal Execution": "Modal 执行",
    "Modal Execution (optional via Nous subscription)": "Modal 执行（可通过 Nous 订阅使用）",
    "RL Training (Tinker)": "RL 训练（Tinker）",
    "Smart Home (Home Assistant)": "智能家居（Home Assistant）",
    "Skills Hub (GitHub)": "技能中心（GitHub）",
    "Terminal/Commands": "终端/命令",
    "Task Planning (todo)": "任务规划（todo）",
    "Skills (view, create, edit)": "技能（查看、创建、编辑）",
    "Some tools are disabled. Run 'hermes setup tools' to configure them,": "部分工具已禁用。运行 'hermes setup tools' 进行配置，",
    "Setup Complete!": "设置完成！",
    "Settings:": "设置：",
    "API Keys:": "API 密钥：",
    "Data:": "数据：",
    "To edit your configuration:": "编辑配置：",
    "Re-run the full wizard": "重新运行完整向导",
    "Change model/provider": "更改模型/提供商",
    "Change terminal backend": "更改终端后端",
    "Configure messaging": "配置消息平台",
    "Configure tool providers": "配置工具提供商",
    "View current settings": "查看当前设置",
    "Open config in your editor": "在编辑器中打开配置",
    "Set a specific value": "设置指定值",
    "Or edit the files directly:": "或直接编辑文件：",
    "Ready to go!": "准备就绪！",
    "Start chatting": "开始聊天",
    "Start messaging gateway": "启动消息网关",
    "Check for issues": "检查问题",
    "Hermes Configuration": "Hermes 配置",
    "Paths": "路径",
    "Config:": "配置:",
    "Secrets:": "密钥:",
    "Install:": "安装目录:",
    "API Keys": "API 密钥",
    "Model": "模型",
    "Model:": "模型:",
    "Max turns:": "最大轮次:",
    "Display": "显示",
    "Personality:": "个性:",
    "Reasoning:": "推理:",
    "Bell:": "提示音:",
    "User preview:": "用户消息预览:",
    "Terminal": "终端",
    "Backend:": "后端:",
    "Working dir:": "工作目录:",
    "Timeout:": "超时:",
    "Timezone": "时区",
    "Timezone:": "时区:",
    "(server-local)": "（服务器本地）",
    "Enabled:": "启用:",
    "Threshold:": "阈值:",
    "Target ratio:": "目标比例:",
    "Protect last:": "保护最近:",
    "Provider:": "提供商:",
    "Messaging Platforms": "消息平台",
    "configured": "已配置",
    "not configured": "未配置",
    "on": "开",
    "off": "关",
    "yes": "是",
    "no": "否",
    "Edit config file": "编辑配置文件",
    "Run setup wizard": "运行设置向导",
    "Select default model:": "选择默认模型：",
    "Available free models:": "可用免费模型：",
    "Enter custom model name": "输入自定义模型名称",
    "Skip (keep current)": "跳过（保留当前设置）",
    "Enter model name:": "输入模型名称：",
    "Model name:": "模型名称：",
    "Please enter a number": "请输入数字",

    # Gateway setup
    "Select a platform to configure:": "选择要配置的平台：",
    "Gateway Setup": "网关设置",
    "Telegram": "Telegram",
    "Discord": "Discord",
    "Slack": "Slack",
    "Matrix": "Matrix",
    "Mattermost": "Mattermost",
    "WhatsApp": "WhatsApp",
    "Signal": "Signal",
    "Email": "电子邮件",
    "SMS": "短信",
    "DingTalk": "钉钉",
    "WeCom": "企业微信",
    "Weixin": "微信客服",
    "Feishu / Lark": "飞书 / Lark",
    "How would you like to set up Feishu / Lark?": "你想如何设置飞书 / Lark？",
    "Scan QR code to create a new bot automatically (recommended)": "扫码自动创建新的机器人（推荐）",
    "Enter existing App ID and App Secret manually": "手动输入已有的 App ID 和 App Secret",
    "QQ Bot": "QQ 机器人",
    "BlueBubbles": "BlueBubbles",
    "Bot token": "机器人令牌",
    "Allowed user IDs (comma-separated)": "允许的用户 ID（逗号分隔）",
    "Allowed user IDs or usernames (comma-separated)": "允许的用户 ID 或用户名（逗号分隔）",
    "Home channel ID (for cron/notification delivery, or empty to set later with /set-home)": "主频道 ID（用于 cron/通知发送，或留空，稍后通过 /set-home 设置）",
    "1. Open Telegram and message @BotFather": "1. 打开 Telegram，并向 @BotFather 发送消息",
    "2. Send /newbot and follow the prompts to create your bot": "2. 发送 /newbot，并按提示创建你的机器人",
    "3. Copy the bot token BotFather gives you": "3. 复制 BotFather 提供给你的机器人令牌",
    "4. To find your user ID: message @userinfobot - it replies with your numeric ID": "4. 若要查看你的用户 ID：给 @userinfobot 发消息，它会回复你的数字 ID",
    "4. To find your user ID: message @userinfobot — it replies with your numeric ID": "4. 若要查看你的用户 ID：给 @userinfobot 发消息，它会回复你的数字 ID",
    "Paste the token from @BotFather (step 3 above).": "粘贴上面第 3 步从 @BotFather 获取的令牌。",
    "Paste your user ID from step 4 above.": "粘贴上面第 4 步获取的用户 ID。",
    "For DMs, this is your user ID. You can set it later by typing /set-home in chat.": "如果是私聊，这里填写你的用户 ID。也可以稍后在聊天里输入 /set-home 设置。",
    "1. Go to https://discord.com/developers/applications → New Application": "1. 打开 https://discord.com/developers/applications → New Application",
    "2. Go to Bot → Reset Token → copy the bot token": "2. 进入 Bot → Reset Token → 复制机器人令牌",
    "3. Enable: Bot → Privileged Gateway Intents → Message Content Intent": "3. 启用：Bot → Privileged Gateway Intents → Message Content Intent",
    "4. Invite the bot to your server:": "4. 邀请机器人加入你的服务器：",
    "OAuth2 → URL Generator → check BOTH scopes:": "OAuth2 → URL Generator → 同时勾选这两个 scope：",
    "- applications.commands  (required for slash commands!)": "- applications.commands（斜杠命令必需）",
    "Bot Permissions: Send Messages, Read Message History, Attach Files": "机器人权限：Send Messages、Read Message History、Attach Files",
    "Copy the URL and open it in your browser to invite.": "复制该 URL，并在浏览器中打开完成邀请。",
    "5. Get your user ID: enable Developer Mode in Discord settings,": "5. 获取你的用户 ID：先在 Discord 设置中开启 Developer Mode，",
    "then right-click your name → Copy ID": "然后右键你的名字 → Copy ID",
    "Paste the token from step 2 above.": "粘贴上面第 2 步获取的令牌。",
    "Right-click a channel → Copy Channel ID (requires Developer Mode).": "右键频道 → Copy Channel ID（需要开启 Developer Mode）。",
    "Gateway service is installed and running.": "网关服务已安装并正在运行。",
    "Gateway service is installed but not running.": "网关服务已安装但未运行。",
    "Gateway service is not installed yet.": "尚未安装网关服务。",
    "Start it now?": "现在启动吗？",
    "Restart the gateway to pick up changes?": "重启网关以应用更改吗？",
    "Start the gateway service?": "启动网关服务吗？",
    "Start the service now?": "现在启动服务吗？",
    "Choose how the gateway should run in the background:": "选择网关在后台的运行方式：",
    "User service (no sudo; best for laptops/dev boxes; may need linger after logout)": "用户服务（无需 sudo；适合笔记本/开发机；注销后可能需要 linger）",
    "System service (starts on boot; requires sudo; still runs as your user)": "系统服务（开机启动；需要 sudo；仍以你的用户运行）",
    "Skip service install for now": "暂时跳过服务安装",

    # Yes/no prompts
    "Add another credential for same-provider fallback?": "为同一提供商再添加一个备用凭据吗？",
    "Install espeak-ng now?": "现在安装 espeak-ng 吗？",
    "Install NeuTTS dependencies now?": "现在安装 NeuTTS 依赖吗？",
    "Install KittenTTS now?": "现在安装 KittenTTS 吗？",
    "Reconfigure Telegram?": "重新配置 Telegram 吗？",
    "Reconfigure Discord?": "重新配置 Discord 吗？",
    "Reconfigure Slack?": "重新配置 Slack 吗？",
    "Reconfigure Matrix?": "重新配置 Matrix 吗？",
    "Reconfigure Mattermost?": "重新配置 Mattermost 吗？",
    "Reconfigure BlueBubbles?": "重新配置 BlueBubbles 吗？",
    "Reconfigure webhooks?": "重新配置 Webhooks 吗？",
    "Enable WhatsApp now?": "现在启用 WhatsApp 吗？",
    "Configure webhook listener settings?": "配置 webhook 监听设置吗？",
    "Proceed with migration?": "继续迁移吗？",
    "Would you like to see what can be imported?": "要查看可导入的内容吗？",
    "Test SSH connection?": "测试 SSH 连接吗？",
    "Update API key?": "更新 API 密钥吗？",
    "Update Modal credentials?": "更新 Modal 凭据吗？",
    "It looks like Hermes isn't configured yet -- no API keys or providers found.": "看起来 Hermes 还没有完成配置，未找到 API 密钥或提供商。",
    "Run setup now?": "现在运行配置向导吗？",
    "You can run 'hermes setup' at any time to configure.": "你可以随时运行 'hermes setup' 进行配置。",
}

_FRAGMENTS = (
    ("missing ", "缺少 "),
    ("not configured", "未配置"),
    ("partially configured", "部分已配置"),
    ("configured + paired", "已配置并已配对"),
    ("configured", "已配置"),
    ("enabled, not paired", "已启用，未配对"),
    ("enabled", "已启用"),
    ("active", "当前启用"),
    ("no API key", "无 API 密钥"),
)

_PREFIXES = (
    ("Configure ", "配置 "),
    ("Tools for ", "工具配置："),
)

_DASH_RE = re.compile(r"\s+[—–]\s+")
_NO_API_KEY_RE = re.compile(r"^No (.+) API key configured\.$")
_BASE_URL_RE = re.compile(r"^Base URL \[(.+)\]:\s*$")
_FOUND_MODELS_DEV_RE = re.compile(
    r"^\s*Found (\d+) model\(s\) from models\.dev registry$"
)
_TOOL_CATEGORIES_RE = re.compile(r"^\s*(\d+)/(\d+) tool categories available:$")
_ALL_FILES_RE = re.compile(r"^📁 All your files are in (.+)/:$")
_EDIT_ENV_RE = re.compile(
    r"^or edit (.+)/\.env directly to add the missing API keys\.$"
)
_FOUND_PROVIDER_API_RE = re.compile(r"^\s*Found (\d+) model\(s\) from (.+) API$")
_SHOWING_CURATED_RE = re.compile(
    r'^\s*Showing (\d+) curated models - use "Enter custom model name" for others\.$'
)
_SHOWING_CURATED_SIMPLE_RE = re.compile(r"^\s*Showing (\d+) curated models$")
_INVALID_URL_RE = re.compile(
    r"^\s*Invalid URL - must start with http:// or https://\. Keeping current value\.$"
)
_DEFAULT_MODEL_SET_RE = re.compile(r"^Default model set to: (.+) \(via (.+)\)$")
_FOUND_GENERIC_MODELS_RE = re.compile(r"^\s*Found (\d+) model\(s\) from (.+)$")
_FOUND_TEXT_MODELS_RE = re.compile(
    r"^\s*Found (\d+) text model\(s\) \(filtered from (\d+) total\)$"
)
_EXPECTED_CREDENTIALS_FILE_RE = re.compile(r"^Expected credentials file: (.+)$")
_UPGRADE_AT_RE = re.compile(r"^Upgrade at (.+) to access paid models\.$")
_CURRENT_URL_RE = re.compile(r"^\s*Current URL: (.+)$")
_CURRENT_KEY_RE = re.compile(r"^\s*Current key: (.+)$")
_API_BASE_URL_RE = re.compile(r"^API base URL \[(.+)\]:\s*$")
_DISPLAY_NAME_RE = re.compile(r"^Display name \[(.+)\]:\s*$")
_MODEL_NAME_EXAMPLE_RE = re.compile(r"^Model name \(e\.g\. gpt-4, llama-3-70b\):\s*$")
_MODEL_NAME_RE = re.compile(r"^Model name(?: \[(.+)\])?:\s*$")
_USE_THIS_MODEL_RE = re.compile(r"^\s*Use this model\? \[Y/n\]:\s*$")
_AVAILABLE_MODELS_RE = re.compile(r"^\s*Available models:$")
_SELECT_MODEL_OR_NAME_RE = re.compile(
    r"^\s*Select model \[1-(\d+)\] or type name:\s*$"
)
_CONTEXT_LENGTH_RE = re.compile(
    r"^Context length in tokens \[leave blank for auto-detect\]:\s*$"
)
_FOUND_MODELS_COUNT_RE = re.compile(r"^Found (\d+) model\(s\):$")
_NO_MODEL_SPECIFIED_RE = re.compile(r"^No model specified\. Cancelled\.$")
_MODEL_SET_RE = re.compile(r"^Model set to: (.+)$")
_PROVIDER_LINE_RE = re.compile(r"^Provider: (.+) \((.+)\)$")
_LOGIN_FAILED_RE = re.compile(r"^Login failed: (.+)$")
_SESSION_EXPIRED_RE = re.compile(r"^Session expired: (.+)$")
_VERIFY_CREDENTIALS_RE = re.compile(r"^Could not verify credentials: (.+)$")
_OAUTH_LOGIN_FAILED_RE = re.compile(r"^OAuth login failed: (.+)$")
_USING_GCP_PROJECT_RE = re.compile(r"^\s*Using GCP project: (.+)$")
_FAILED_GEMINI_CREDENTIALS_RE = re.compile(r"^Failed to resolve Gemini credentials: (.+)$")
_CHOICE_RE = re.compile(r"^Choice \[1-(\d+)\] \(default: skip\):\s*$")
_PLEASE_ENTER_RANGE_RE = re.compile(r"^Please enter 1-(\d+)$")
_USER_PREVIEW_RE = re.compile(r"^first (\d+) line\(s\), last (\d+) line\(s\)$")
_TARGET_RATIO_RE = re.compile(r"^(\d+)% of threshold preserved$")
_PROTECT_LAST_RE = re.compile(r"^(\d+) messages$")


def _normalize(text: str) -> str:
    return _DASH_RE.sub(" - ", text).strip()


def zh(text: str | None) -> str | None:
    """Translate known Hermes CLI setup text to Chinese."""
    if text is None:
        return None

    normalized = _normalize(text)
    translated = _TEXT.get(normalized)
    if translated is not None:
        return translated

    match = _FOUND_GENERIC_MODELS_RE.match(normalized)
    if match:
        return f"  找到 {match.group(1)} 个来自 {match.group(2)} 的模型"

    match = _FOUND_TEXT_MODELS_RE.match(normalized)
    if match:
        return f"  找到 {match.group(1)} 个文本模型（总计 {match.group(2)} 个，已筛选）"

    match = _EXPECTED_CREDENTIALS_FILE_RE.match(normalized)
    if match:
        return f"预期的凭据文件：{match.group(1)}"

    match = _UPGRADE_AT_RE.match(normalized)
    if match:
        return f"可前往 {match.group(1)} 升级以访问付费模型。"

    match = _CURRENT_URL_RE.match(normalized)
    if match:
        return f"  当前 URL：{match.group(1)}"

    match = _CURRENT_KEY_RE.match(normalized)
    if match:
        return f"  当前密钥：{match.group(1)}"

    match = _API_BASE_URL_RE.match(normalized)
    if match:
        return f"API 基础 URL [{match.group(1)}]: "

    match = _DISPLAY_NAME_RE.match(normalized)
    if match:
        return f"显示名称 [{match.group(1)}]："

    if _MODEL_NAME_EXAMPLE_RE.match(normalized):
        return "模型名称（例如 gpt-4、llama-3-70b）："

    match = _MODEL_NAME_RE.match(normalized)
    if match:
        if match.group(1):
            return f"模型名称 [{match.group(1)}]："
        return "模型名称："

    if _USE_THIS_MODEL_RE.match(normalized):
        return "  使用这个模型吗？ [Y/n]: "

    if _AVAILABLE_MODELS_RE.match(normalized):
        return "  可用模型："

    match = _SELECT_MODEL_OR_NAME_RE.match(normalized)
    if match:
        return f"  选择模型 [1-{match.group(1)}]，或直接输入名称："

    if _CONTEXT_LENGTH_RE.match(normalized):
        return "上下文长度（tokens）[留空则自动检测]："

    match = _FOUND_MODELS_COUNT_RE.match(normalized)
    if match:
        return f"找到 {match.group(1)} 个模型："

    if _NO_MODEL_SPECIFIED_RE.match(normalized):
        return "未指定模型，已取消。"

    match = _MODEL_SET_RE.match(normalized)
    if match:
        return f"模型已设置为：{match.group(1)}"

    match = _PROVIDER_LINE_RE.match(normalized)
    if match:
        return f"提供商：{match.group(1)}（{match.group(2)}）"

    match = _LOGIN_FAILED_RE.match(normalized)
    if match:
        return f"登录失败：{match.group(1)}"

    match = _SESSION_EXPIRED_RE.match(normalized)
    if match:
        return f"会话已过期：{match.group(1)}"

    match = _VERIFY_CREDENTIALS_RE.match(normalized)
    if match:
        return f"无法验证凭据：{match.group(1)}"

    match = _OAUTH_LOGIN_FAILED_RE.match(normalized)
    if match:
        return f"OAuth 登录失败：{match.group(1)}"

    match = _USING_GCP_PROJECT_RE.match(normalized)
    if match:
        return f"  使用的 GCP 项目：{match.group(1)}"

    match = _FAILED_GEMINI_CREDENTIALS_RE.match(normalized)
    if match:
        return f"解析 Gemini 凭据失败：{match.group(1)}"

    match = _NO_API_KEY_RE.match(normalized)
    if match:
        return f"未配置 {match.group(1)} API 密钥。"

    match = _BASE_URL_RE.match(normalized)
    if match:
        return f"基础 URL [{match.group(1)}]: "

    match = _FOUND_MODELS_DEV_RE.match(normalized)
    if match:
        return f"  找到 {match.group(1)} 个来自 models.dev 注册表的模型"

    match = _TOOL_CATEGORIES_RE.match(normalized)
    if match:
        return f"{match.group(1)}/{match.group(2)} 个工具类别可用："

    match = _ALL_FILES_RE.match(normalized)
    if match:
        return f"📁 所有文件都在 {match.group(1)}/："

    match = _EDIT_ENV_RE.match(normalized)
    if match:
        return f"或直接编辑 {match.group(1)}/.env 来添加缺失的 API 密钥。"

    match = _FOUND_PROVIDER_API_RE.match(normalized)
    if match:
        return f"  找到 {match.group(1)} 个来自 {match.group(2)} API 的模型"

    match = _SHOWING_CURATED_RE.match(normalized)
    if match:
        return f"  显示 {match.group(1)} 个精选模型 - 可用“输入自定义模型名称”选择其他模型。"

    if _INVALID_URL_RE.match(normalized):
        return "  Invalid URL（无效 URL）- 必须以 http:// 或 https:// 开头。保留当前值。"

    match = _DEFAULT_MODEL_SET_RE.match(normalized)
    if match:
        return f"默认模型已设置为：{match.group(1)}（通过 {match.group(2)}）"

    match = _CHOICE_RE.match(normalized)
    if match:
        return f"选择 [1-{match.group(1)}]（默认：跳过）："

    match = _PLEASE_ENTER_RANGE_RE.match(normalized)
    if match:
        return f"请输入 1-{match.group(1)}"

    match = _USER_PREVIEW_RE.match(normalized)
    if match:
        return f"前 {match.group(1)} 行，后 {match.group(2)} 行"

    match = _TARGET_RATIO_RE.match(normalized)
    if match:
        return f"保留阈值的 {match.group(1)}%"

    match = _PROTECT_LAST_RE.match(normalized)
    if match:
        return f"{match.group(1)} 条消息"

    value = text
    for prefix, translated_prefix in _PREFIXES:
        if value.startswith(prefix):
            value = translated_prefix + value[len(prefix):]
            break

    for src, dst in _FRAGMENTS:
        value = value.replace(src, dst)
    return value


def zh_menu(
    question: str,
    choices: Iterable[str],
    description: str | None = None,
) -> tuple[str, list[str], str | None]:
    """Translate a menu title, menu choices, and optional description."""
    return zh(question), [zh(choice) for choice in choices], zh(description)


def yes_no_value(value: str) -> bool | None:
    """Parse English or Chinese yes/no input."""
    normalized = (value or "").strip().lower()
    if normalized in {"y", "yes", "是", "好"}:
        return True
    if normalized in {"n", "no", "否", "不"}:
        return False
    return None
