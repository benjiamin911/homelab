# homelab — 一键部署

Docker Compose 服务集，部署在 jarvis，只经 Tailscale 访问。

## 用法

    ./deploy.sh up            # 部署/更新全部服务（幂等）
    ./deploy.sh up <名字>      # 只部署某个
    ./deploy.sh update <名字>  # 拉最新镜像再起
    ./deploy.sh ps            # 看全部状态
    ./deploy.sh logs <名字>
    ./deploy.sh down <名字>

## 加一个新服务

1. 建目录 `services/<名字>/compose.yml`（照着 `services/_template/compose.yml` 抄）。
2. 端口写成 `"${BIND_ADDR}:<host端口>:<容器端口>"`，数据卷用 `"${DATA_ROOT}/<名字>:..."`。
3. `./deploy.sh up <名字>`。
4. 浏览器 `http://jarvis:<host端口>`（在 tailnet 内）。

## 约定

- 机密和数据都不进 git：`.env` 和 `data/` 已在 `.gitignore`。
- 端口默认绑定 `BIND_ADDR`（Tailscale IP），所以只有你的 tailnet 能访问。
- 每个服务独立 compose project，互不影响。
