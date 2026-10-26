# homelab — 一键部署

Docker Compose 服务集，部署在 jarvis，只经 Tailscale 访问。

## 用法

    ./deploy.sh up            # 部署/更新全部服务（幂等）
    ./deploy.sh up <名字>      # 只部署某个
    ./deploy.sh update <名字>  # 拉最新镜像再起
    ./deploy.sh ps            # 看全部状态
    ./deploy.sh logs <名字>
    ./deploy.sh down <名字>

## 已有服务

网页服务都能按名字打开：`http://<名字>.jarvis`，首页 `http://jarvis/` 列出全部（见下一节）；原来的 `http://jarvis:<端口>` 照常可用。

- `uptime-kuma`：监控，`http://kuma.jarvis`（端口 3001）。
- `syncthing`：Mac ↔ jarvis 双向同步 Obsidian 知识库 vault（Project 已并入其子文件夹），GUI `http://sync.jarvis`（端口 8384）。首次 `up` 后在 jarvis 上跑一次
  `./services/syncthing/configure.sh`（幂等）配置文件夹 / 版本控制 / 只走 tailnet / GUI 密码；参数见 `.env.example`。
- `free-llm`：免费 LLM 网关（OpenAI 兼容，`/v1` 与后台 `/admin`），`http://llm.jarvis`（端口 8090）。代码在私有仓库，jarvis 本地构建镜像；说明见 compose 文件开头。
- `security-hot`：信息安全热点网站，`http://news.jarvis`（端口 3002），后台只认 tailnet 来源。代码在私有仓库，jarvis 本地构建镜像；站点配置与密钥放在 `${DATA_ROOT}/security-hot/`，说明见 compose 文件开头。
- `notification`：统一通知 API（Lark 群自定义机器人与自建应用机器人），`http://notify.jarvis`（端口 8787），接口文档 `/docs`。代码在私有仓库，jarvis 本地构建镜像；`ADMIN_TOKEN` 等密钥与两个 SQLite 数据库在 `${DATA_ROOT}/notification/`，push 前要先在 jarvis 上准备好，说明见 compose 文件开头。
- `nitter`：X（Twitter）的只读前端，`http://nitter.jarvis`（端口 8085）。配置写在 compose 里；X 账号在 jarvis 上跑 `./services/nitter/add-session.sh` 添加（存在 `${DATA_ROOT}/nitter/`，不进仓库），说明见 compose 文件开头。
- `caddy`：按名字分流的反向代理，只听 Tailscale IP 的 80 端口。路由在 `services/caddy/Caddyfile`，首页在 `services/caddy/site/index.html`。
- `dns`：CoreDNS，只听 Tailscale IP 的 53 端口，把 `jarvis` 和它下面的任意名字都解析到 jarvis。

不在 Docker 里的 Maestro（systemd，端口 4317）也有名字：`http://maestro.jarvis`。

## 按名字访问

- 解析：Tailscale 后台的 split DNS 把后缀 `jarvis` 交给 jarvis 的 Tailscale IP，tailnet 里每台设备（含手机）都会来问 `dns`，它把 `jarvis` 和任意 `*.jarvis` 都答成 jarvis。后缀来自 `.env` 的 `PROXY_ZONE`。
- 分流：`caddy` 按名字转到对应端口。只用 http，流量走 Tailscale，本身是加密的。Caddy 和 `dns` 都只接受 tailnet 来源（`100.64.0.0/10`）。
- 例外：free-llm 的免密码后台和信息安全热点整站都只认直连、不能经过代理。所以 `llm.jarvis` 的首页和 `/admin` 会跳到 `http://jarvis:8090/admin`，`news.jarvis` 会跳到 `http://jarvis:3002`。free-llm 的 `/v1` 照常走名字。
- 服务之间仍按端口互相调用（比如 security-hot 调 `http://<Tailscale IP>:8090`），不经过 Caddy。
- 浏览器里第一次输入时带上 `http://` 或结尾的 `/`（如 `news.jarvis/`），否则可能被当成搜索词；打开过一次之后地址栏会自动补全。
- 改 `Caddyfile` / `Corefile` 后 push 即可，Caddy 每秒检查一次，CoreDNS 30 秒内自动重载，不用重启容器。
- 一次性设置（换后缀时重做）：Tailscale 后台 → DNS → Nameservers → Add nameserver → Custom，填 jarvis 的 Tailscale IP，打开「Restrict to domain」，填 `jarvis`，再打开「Use with exit node」（不开的话，用 exit node 的设备解析不了这些名字）。

## 加一个新服务

1. 建目录 `services/<名字>/compose.yml`（照着 `services/_template/compose.yml` 抄）。
2. 端口写成 `"${BIND_ADDR}:<host端口>:<容器端口>"`，数据卷用 `"${DATA_ROOT}/<名字>:..."`。
3. 起名字：在 `services/caddy/Caddyfile` 加一段 `http://<名字>.{$PROXY_ZONE} { import proxy {$BIND_ADDR}:<host端口> }`，并在 `services/caddy/site/index.html` 的列表里加一行。
4. push（或在 jarvis 上 `./deploy.sh up <名字>`），然后浏览器开 `http://<名字>.jarvis`（在 tailnet 内）。

## 约定

- 机密和数据都不进 git：`.env` 和 `data/` 已在 `.gitignore`。
- 端口默认绑定 `BIND_ADDR`（Tailscale IP），所以只有你的 tailnet 能访问。
- 每个服务独立 compose project，互不影响。

## 自动部署（GitOps）

push 到 `main` → 本机 self-hosted runner 自动执行 `deploy.sh up`。不用 SSH。

## 自己的项目构建成镜像

把 `templates/build-image.yml` 复制到项目仓库的 `.github/workflows/`，push 后自动产出
`ghcr.io/<owner>/<repo>:latest`；在 `services/<名字>/compose.yml` 里直接引用该镜像即可。
