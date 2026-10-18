#!/usr/bin/env bash
# 把 jarvis 上的 Syncthing 配成：只走 tailnet + 两个 Obsidian vault 文件夹 + Staggered 版本控制 + GUI 密码。
# 幂等，可重复执行。全部参数来自仓库根目录的 .env：
#   BIND_ADDR / DATA_ROOT                       compose 也在用
#   SYNCTHING_GUI_USER / SYNCTHING_GUI_PASSWORD GUI 登录；密码只用 A-Za-z0-9（如 `openssl rand -hex 16`）
#   MAC_DEVICE_ID（可选）                        Mac 的 Syncthing 设备 ID；设置后加入设备并把两个文件夹分享给它
#   MAC_TAILSCALE_IP（可选）                     让 jarvis 也能主动连 Mac
# 用法：./services/syncthing/configure.sh
#       ROTATE_PASSWORD=1 ./services/syncthing/configure.sh   # 用 .env 里的新密码重设 GUI 密码
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a; . "$ROOT/.env"; set +a
: "${DATA_ROOT:=$ROOT/data}"
API="http://${BIND_ADDR}:8384"
CFG="$DATA_ROOT/syncthing/config/config.xml"

wait_api(){ for _ in $(seq 1 60); do curl -fsS -m 2 "$API/rest/noauth/health" >/dev/null 2>&1 && return 0; sleep 2; done; echo "ERROR: Syncthing API 未就绪：$API"; exit 1; }
py(){ python3 -I -c "$@"; }   # JSON 交给 python3（jarvis 不一定有 jq）

wait_api
[ -f "$CFG" ] || { echo "ERROR: 找不到 $CFG"; exit 1; }
KEY="$(sed -n 's|.*<apikey>\(.*\)</apikey>.*|\1|p' "$CFG" | head -1)"
[ -n "$KEY" ] || { echo "ERROR: 读不到 API key：$CFG"; exit 1; }
st(){ curl --fail-with-body -sS -m 20 -H "X-API-Key: $KEY" -H 'Content-Type: application/json' "$@"; }

# 0) 删掉首次启动自动创建的 "Default Folder"（id=default，路径 /var/syncthing/Sync）；不存在则忽略
st -X DELETE "$API/rest/config/folders/default" >/dev/null 2>&1 || true

# 1) 只走 tailnet：关全局发现 / 本地发现 / 中继 / NAT 穿透；不上报使用数据与崩溃（这些都热生效）
st -X PATCH "$API/rest/config/options" -d '{
  "globalAnnounceEnabled": false, "localAnnounceEnabled": false,
  "relaysEnabled": false, "natEnabled": false,
  "urAccepted": -1, "crashReportingEnabled": false, "startBrowser": false
}' >/dev/null

# 2) Mac 设备（可选）。必须先于文件夹：文件夹引用未知设备会被 Syncthing 静默丢弃。
MAC="${MAC_DEVICE_ID:-}"
if [ -n "$MAC" ]; then
  ADDRS="$(py 'import json,sys; a=[f"tcp://{sys.argv[1]}:22000"] if sys.argv[1] else []; a.append("dynamic"); print(json.dumps(a))' "${MAC_TAILSCALE_IP:-}")"
  if st "$API/rest/config/devices/$MAC" >/dev/null 2>&1; then
    st -X PATCH "$API/rest/config/devices/$MAC" -d "{\"addresses\":$ADDRS}" >/dev/null          # 已存在：只更新地址，保留学到的名字等
  else
    st -X POST "$API/rest/config/devices" -d "{\"deviceID\":\"$MAC\",\"addresses\":$ADDRS}" >/dev/null
  fi
fi

# 3) 两个文件夹。已存在 → PATCH（保留现有共享设备，必要时补上 Mac）；不存在 → POST 新建。
#    Staggered 版本控制保留 365 天（maxAge 单位：秒），每小时清理一次。
FOLDER_PY='import json,sys
mode, fid, label, path, mac = sys.argv[1:6]
devs = json.load(sys.stdin).get("devices", []) if mode == "patch" else []
if mac and not any(d.get("deviceID") == mac for d in devs): devs.append({"deviceID": mac})
f = {"label": label, "path": path, "type": "sendreceive", "rescanIntervalS": 3600,
     "fsWatcherEnabled": True, "fsWatcherDelayS": 10, "devices": devs,
     "versioning": {"type": "staggered", "params": {"maxAge": "31536000"}, "cleanupIntervalS": 3600, "fsPath": "", "fsType": "basic"}}
if mode == "post": f["id"] = fid
print(json.dumps(f))'
ensure_folder(){ # id label path
  local existing
  if existing="$(st "$API/rest/config/folders/$1" 2>/dev/null)"; then
    st -X PATCH "$API/rest/config/folders/$1" -d "$(printf '%s' "$existing" | py "$FOLDER_PY" patch "$1" "$2" "$3" "$MAC")" >/dev/null
  else
    st -X POST "$API/rest/config/folders" -d "$(py "$FOLDER_PY" post "$1" "$2" "$3" "$MAC" </dev/null)" >/dev/null
  fi
}
ensure_folder obsidian-vault 'Obsidian Vault' '/vaults/Obsidian Vault'
ensure_folder project        'Project'        '/vaults/Project'

# 4) 忽略规则（POST；.stignore 本身不会被同步，Mac 端要填一样的）
IGNORES='{"ignore":[
  "// Obsidian 每台机器自己的界面状态",
  ".obsidian/workspace.json",
  ".obsidian/workspace-mobile.json",
  ".trash",
  "// 系统 / 工具噪音",
  "(?d).DS_Store",
  "(?d)Thumbs.db",
  "// Claude Code 本机设置",
  ".claude/settings.local.json"
]}'
for f in obsidian-vault project; do st -X POST "$API/rest/db/ignores?folder=$f" -d "$IGNORES" >/dev/null; done

# 5) 需要重启就重启（上面的改动一般都热生效）
if st "$API/rest/config/restart-required" | py 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("requiresRestart") else 1)'; then
  st -X POST "$API/rest/system/restart" >/dev/null || true; sleep 3; wait_api
fi

MYID="$(st "$API/rest/system/status" | py 'import json,sys; print(json.load(sys.stdin)["myID"])')"

# 6) GUI 账号密码，放最后：改密码会让 GUI 监听器软重启。已设置且未要求轮换时跳过。
if [ -n "${SYNCTHING_GUI_PASSWORD:-}" ]; then
  GUI_USER="${SYNCTHING_GUI_USER:-stark}"
  if [ "${ROTATE_PASSWORD:-0}" = "1" ] || ! st "$API/rest/config/gui" | py 'import json,sys; g=json.load(sys.stdin); sys.exit(0 if g.get("user")==sys.argv[1] and g.get("password") else 1)' "$GUI_USER"; then
    st -X PATCH "$API/rest/config/gui" -d "$(py 'import json,sys; print(json.dumps({"user":sys.argv[1],"password":sys.argv[2]}))' "$GUI_USER" "$SYNCTHING_GUI_PASSWORD")" >/dev/null
    sleep 1; wait_api
  fi
fi

echo "jarvis 的 Syncthing 设备 ID：$MYID"
echo "Web GUI：$API（用户 ${SYNCTHING_GUI_USER:-stark}，密码见 .env 的 SYNCTHING_GUI_PASSWORD）"
