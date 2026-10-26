#!/usr/bin/env bash
# 给 Nitter 加一个 X 账号 session（cookie 方式），追加到 ${DATA_ROOT}/nitter/sessions.jsonl，然后重启 nitter 生效。
# 在 jarvis 上以 stark 运行：./services/nitter/add-session.sh
# 准备：用浏览器隐私窗口登录一个专门给 Nitter 用的 X 小号（别用主号，可能被封），开发者工具 →
#   存储（Firefox）/ Application（Chrome）→ Cookies → https://x.com，复制 auth_token 和 ct0，然后直接关掉窗口。
#   别点「退出登录」：退出会让这个 auth_token 当场作废。
# auth_token、ct0 不回显，输入都不进 shell 历史。要删 session：直接编辑 sessions.jsonl（一行一个），再 ./deploy.sh restart nitter。
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "ERROR: 别用 sudo / root 运行：写出的文件属主会是 root，nitter 读不了"; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a; . "$ROOT/.env"; set +a
: "${DATA_ROOT:=$ROOT/data}"
: "${BIND_ADDR:?BIND_ADDR 未在 .env 设置}"
FILE="$DATA_ROOT/nitter/sessions.jsonl"

read -rp  "X 用户名（日志里靠它认出是哪个账号）: " user
read -rsp "auth_token: " token; echo
read -rsp "ct0: " ct0; echo
user="${user#@}"
# 只收字母、数字（用户名另加下划线）：挡住粘错的内容，也保证写进 JSON 不用转义
[[ "$user"  =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERROR: 用户名为空或含有字母、数字、下划线以外的字符"; exit 1; }
[[ "$token" =~ ^[A-Za-z0-9]+$ ]]  || { echo "ERROR: auth_token 为空或含有字母数字以外的字符"; exit 1; }
[[ "$ct0"   =~ ^[A-Za-z0-9]+$ ]]  || { echo "ERROR: ct0 为空或含有字母数字以外的字符"; exit 1; }

umask 077
mkdir -p "$(dirname "$FILE")"
touch "$FILE"; chmod 600 "$FILE"                                              # 先收紧权限再写 token（手工建的文件可能是 644）
if [ -s "$FILE" ] && [ -n "$(tail -c1 "$FILE")" ]; then echo >> "$FILE"; fi   # 末尾没换行先补上，免得两行粘成一行
printf '{"kind":"cookie","username":"%s","auth_token":"%s","ct0":"%s"}\n' "$user" "$token" "$ct0" >> "$FILE"
echo "已写入 $FILE，重启 nitter 生效……"
"$ROOT/deploy.sh" restart nitter
for _ in $(seq 1 20); do health="$(curl -fsS -m 2 "http://${BIND_ADDR}:8085/.health" 2>/dev/null)" && break; sleep 1; done
if [ -n "$health" ]; then
  echo "nitter 已加载 $(printf '%s' "$health" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2) 个 session。打开 http://nitter.jarvis/jack 试试。"
else
  echo "nitter 还没起来，稍后看 curl http://${BIND_ADDR}:8085/.health 和 ./deploy.sh logs nitter"
fi
