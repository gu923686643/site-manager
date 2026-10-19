# 站点管家（Site Manager）v0.4

## 功能（第三阶段：本地 API 网关）

- 本机 HTTP 服务：`GET /v1/models`（聚合启用站点的模型）、`POST /v1/chat/completions`（流式/非流式）
- Bearer 鉴权（自动生成密钥，可重新生成/复制）
- 本机回环或局域网监听（可切换），端口可配
- 按模型名路由到首个可用站点；SSE 透传并统计 token 用量
- 请求日志：模型、站点、流式/非流式、状态、耗时、token，本机保留最近 200 条
- 入口：站点列表右上角云图标

## 功能（第二阶段：模型聊天）

- **流式聊天**：`POST /v1/chat/completions`（stream=true），SSE 逐字输出，可随时停止
- **历史会话**：按站点分组的会话列表，新建/删除/重命名（首条消息自动生成标题），本机持久化
- **模型选择**：从站点拉取模型列表，记住每个站点上次用的模型；可单模型测试连通
- **多 Key 管理**：每个站点可存多个 API Key（安全存储），切换默认 Key，聊天/拉模型时选用
- 删除站点时连带清理其聊天记录

## 功能（第一阶段）

独立的 API 站点管理工具。无账号体系、无激活、无自有服务端——
所有数据只保存在本机，只与你自己填写的站点通信。

## 功能（第一阶段）

- **站点管理**：增 / 删 / 改、启停、收藏、隐藏、标签、备注；保存时自动识别重复站点
- **搜索与筛选**：按名称/地址/备注搜索，按标签与收藏筛选，收藏置顶排序
- **测连通**：`GET /v1/models` 验证地址与 Key 是否有效
- **拉模型列表**：展示站点可用模型，支持搜索
- **查余额**：`GET /api/user/self`（NewAPI 系），剩余额度 + 估算美元
- **用量明细**：`GET /api/log/self`（NewAPI 系），最近 20 条消费/充值记录
- **站点公告**：`GET /api/notice`（公开接口），有公告时在概览页展示
- **登录状态检查**：一键验证网页登录态 / API Key 是否有效
- **签到**：`GET/POST /api/user/checkin`（NewAPI 系）；站点若开人机验证会自动提示去网页手动完成；每次结果记在站点上
- **批量操作**：批量刷新余额、批量签到（仅启用的站点），逐站结果汇总展示
- **网页登录**：内置浏览器在站点官网登录，自动捕获 Cookie（只存本机安全存储），用于余额与签到接口
- **多类型站点**：NewAPI（全功能）/ OneAPI（余额 ✓，签到为 NewAPI 独有功能故不支持）/ SUB2API（仅模型列表）/ OpenAI 兼容（仅模型列表）；不支持的功能会明确提示而不是报错

## 隐私设计

| 数据 | 存哪 | 去哪 |
|---|---|---|
| 站点名称/地址/备注 | 本机 SharedPreferences | 不出本机 |
| API Key、网页 Cookie | 本机安全存储（Keystore/Keychain） | 只发往该站点 |
| 所有 API 请求 | — | 只发往你填写的站点地址 |

不收集、不上传、不经过任何中转服务。

## 接口说明（NewAPI / OneAPI 系，源码核实）

| 功能 | 方法与路径 | 认证 |
|---|---|---|
| 测连通 / 拉模型 | `GET /v1/models` | `Authorization: Bearer <apiKey>` |
| 查余额 | `GET /api/user/self` | 网页 Cookie（优先）或 Bearer |
| 签到状态 | `GET /api/user/checkin` | 网页 Cookie |
| 执行签到 | `POST /api/user/checkin` | 网页 Cookie |

- 额度单位：500000 = 1 美元（估算展示）
- `POST /api/user/checkin` 若站点开启 Turnstile，自动签到会被拦截，App 会提示去网页手动完成
- 非 NewAPI 系站点：余额/签到可能不支持，App 会明确提示而不报错崩溃

## 构建

```bash
export PATH="$PWD/flutter-sdk/bin:$PATH"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME=~/Android/sdk
cd app && flutter pub get && flutter build apk --debug
```

产物：`app/build/app/outputs/flutter-apk/app-debug.apk`

## 测试

```bash
cd app && flutter test        # 10 个单测：连接/模型/余额/签到解析与异常分支
cd app && flutter analyze     # 静态分析零问题
```

## 已知限制（v0.1）

- 签到只支持 NewAPI 系站点的官方签到接口；网页签到需手动
- 余额接口需要站点支持 `/api/user/self`（NewAPI/OneAPI 系）
- 暂无：模型聊天、本地网关、定时自动签到（后续阶段）
