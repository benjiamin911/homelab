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

- `uptime-kuma`：监控，`http://jarvis:3001`。
- `syncthing`：Mac ↔ jarvis 双向同步 Obsidian 知识库 vault（Project 已并入其子文件夹），GUI `http://jarvis:8384`。首次 `up` 后在 jarvis 上跑一次
  `./services/syncthing/configure.sh`（幂等）配置文件夹 / 版本控制 / 只走 tailnet / GUI 密码；参数见 `.env.example`。
- `free-llm`：免费 LLM 网关（OpenAI 兼容，`/v1` 与后台 `/admin`），`http://jarvis:8090`。代码在私有仓库，jarvis 本地构建镜像；说明见 compose 文件开头。
- `security-hot`：信息安全热点网站，`http://jarvis:3002`，后台只认 tailnet 来源。代码在私有仓库，jarvis 本地构建镜像；站点配置与密钥放在 `${DATA_ROOT}/security-hot/`，说明见 compose 文件开头。

## 加一个新服务

1. 建目录 `services/<名字>/compose.yml`（照着 `services/_template/compose.yml` 抄）。
2. 端口写成 `"${BIND_ADDR}:<host端口>:<容器端口>"`，数据卷用 `"${DATA_ROOT}/<名字>:..."`。
3. `./deploy.sh up <名字>`。
4. 浏览器 `http://jarvis:<host端口>`（在 tailnet 内）。

## 约定

- 机密和数据都不进 git：`.env` 和 `data/` 已在 `.gitignore`。
- 端口默认绑定 `BIND_ADDR`（Tailscale IP），所以只有你的 tailnet 能访问。
- 每个服务独立 compose project，互不影响。

## 自动部署（GitOps）

push 到 `main` → 本机 self-hosted runner 自动执行 `deploy.sh up`。不用 SSH。

## 自己的项目构建成镜像

把 `templates/build-image.yml` 复制到项目仓库的 `.github/workflows/`，push 后自动产出
`ghcr.io/<owner>/<repo>:latest`；在 `services/<名字>/compose.yml` 里直接引用该镜像即可。
