#!/bin/sh
# =====================================================================
#  JinX | Super JinX  -  3x-ui v2.9.4 zero-touch bootstrap for Railway
#  - auto domain (RAILWAY_PUBLIC_DOMAIN), single public port 8080
#  - auto VLESS/WS/TLS inbound + auto subscription link
#  - protected inbound: cannot be deleted, renamed or disabled
# =====================================================================
set -u

# ---------- fixed identity (NOT configurable on purpose) --------------
REMARK='جینکس | 𝙎𝙪𝙥𝙚𝙧 𝗝𝗶𝗻𝗫'
EMAIL='SuperJinX'

# ---------- configurable via Railway variables (all optional) ---------
UUID="${JINX_UUID:-df70a084-8d46-50bd-dec8-3a0f41903f3a}"
SUB_ID="${JINX_SUB_ID:-jinx}"
PANEL_USER="${PANEL_USERNAME:-admin}"
PANEL_PASS="${PANEL_PASSWORD:-admin}"
PUBLIC_PORT=8080
RW_PORT="${PORT:-8080}"
DOMAIN="${DOMAIN:-${RAILWAY_PUBLIC_DOMAIN:-}}"

# ---------- internals -------------------------------------------------
PANEL_PORT=2053
SUB_PORT=2096
XRAY_PORT=10000
WS_PATH="/ws/${UUID}"
DB=/etc/x-ui/x-ui.db
API="http://127.0.0.1:${PANEL_PORT}"
JAR=/tmp/jinx.cookie
NGX_CONF=/jinx/nginx.conf
NGX_PROTECT=/jinx/protect.conf
WWW=/jinx/www

log()  { echo "[JinX] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
sq()   { sqlite3 -cmd ".timeout 8000" "$DB" "$@"; }
esc()  { printf '%s' "$1" | sed "s/'/''/g"; }
uri()  { jq -rn --arg s "$1" '$s|@uri'; }
REMARK_SQL=$(esc "$REMARK")

if [ -z "$DOMAIN" ]; then
  log "!!! No domain yet. In Railway: Settings > Networking > Generate Domain, then Redeploy."
  DOMAIN="example.up.railway.app"
fi
log "Domain: $DOMAIN | public port: $PUBLIC_PORT"

# ---------------------------------------------------------------------
# 1) init DB + credentials (env always wins on each boot)
# ---------------------------------------------------------------------
mkdir -p /etc/x-ui /run/nginx "$WWW/sub"
cd /app || exit 1
./x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" -port "$PANEL_PORT" -webBasePath / >/dev/null 2>&1 \
  || log "warn: x-ui setting returned non-zero"

set_kv() {
  _k=$1; _v=$(esc "$2")
  _cur=$(sq "SELECT value FROM settings WHERE key='$_k' LIMIT 1;" 2>/dev/null)
  if [ "$_cur" != "$2" ]; then
    sq "DELETE FROM settings WHERE key='$_k'; INSERT INTO settings(key,value) VALUES('$_k','$_v');"
    CHANGED=1
  fi
}

enforce_settings() {
  CHANGED=0
  set_kv webListen   "127.0.0.1"
  set_kv webPort     "$PANEL_PORT"
  set_kv webBasePath "/"
  set_kv webCertFile ""
  set_kv webKeyFile  ""
  set_kv webDomain   ""
  set_kv subEnable   "true"
  set_kv subListen   "127.0.0.1"
  set_kv subPort     "$SUB_PORT"
  set_kv subPath     "/sub/"
  set_kv subDomain   ""
  set_kv subCertFile ""
  set_kv subKeyFile  ""
  set_kv subURI      "https://${DOMAIN}/sub/"
  set_kv subJsonEnable "false"
}

enforce_settings
# cosmetic defaults, only on boot (user may change them later)
set_kv subTitle     "$REMARK"
set_kv subUpdates   "12"
set_kv subEncrypt   "true"
set_kv subShowInfo  "false"
set_kv timeLocation "Asia/Tehran"

# ---------------------------------------------------------------------
# 1b) internal cert: inbound runs real TLS so the panel link is complete
# ---------------------------------------------------------------------
CERT=/etc/x-ui/jinx.crt; KEY=/etc/x-ui/jinx.key
if [ ! -s "$CERT" ] || [ ! -s "$KEY" ] || ! openssl x509 -in "$CERT" -noout -subject 2>/dev/null | grep -q "$DOMAIN"; then
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$KEY" -out "$CERT" -days 3650 -subj "/CN=$DOMAIN" >/dev/null 2>&1 \
    && log "internal TLS cert ready" || log "warn: cert generation failed"
fi
chmod 644 "$CERT" "$KEY" 2>/dev/null

# ---------------------------------------------------------------------
# 2) subscription file (exact link, guaranteed format)
# ---------------------------------------------------------------------
build_sub() {
  _p=$(uri "$WS_PATH"); _r=$(uri "$REMARK")
  LINK="vless://${UUID}@${DOMAIN}:443?path=${_p}&security=tls&alpn=http%2F1.1&encryption=none&insecure=0&host=${DOMAIN}&fp=chrome&type=ws&allowInsecure=0&sni=${DOMAIN}#${_r}"
  printf '%s' "$LINK" | base64 -w 0 > "$WWW/sub/$SUB_ID"
  printf '%s\n' "$LINK" > "$WWW/link.txt"
  chmod 644 "$WWW/sub/$SUB_ID" "$WWW/link.txt"
  log "Config: $LINK"
  log "Sub:    https://${DOMAIN}/sub/${SUB_ID}"
}
build_sub
TITLE_B64=$(printf '%s' "$REMARK" | base64 -w 0)

EXTRA_LISTEN=""
[ "$RW_PORT" != "$PUBLIC_PORT" ] && EXTRA_LISTEN="    listen ${RW_PORT};"
# ---------------------------------------------------------------------
# 3) nginx: one public port -> panel / ws / sub
# ---------------------------------------------------------------------
: > "$NGX_PROTECT"
cat > "$NGX_CONF" <<NGX
worker_processes auto;
pid /run/nginx/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 8192; multi_accept on; }
http {
  access_log off;
  server_tokens off;
  sendfile on;
  tcp_nodelay on;
  keepalive_timeout 75s;
  client_max_body_size 64m;
  map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

  server {
    listen ${PUBLIC_PORT} default_server;
${EXTRA_LISTEN}

    include ${NGX_PROTECT};

    location = /jinx-health { root ${WWW}; default_type text/plain; try_files /health.txt =503; }

    # VLESS over WebSocket (Railway terminates TLS on 443)
    location ^~ ${WS_PATH} {
      proxy_pass https://127.0.0.1:${XRAY_PORT};
      proxy_ssl_server_name on;
      proxy_ssl_name ${DOMAIN};
      proxy_ssl_verify off;
      proxy_ssl_protocols TLSv1.2 TLSv1.3;
      proxy_ssl_session_reuse on;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_buffering off;
      proxy_request_buffering off;
      proxy_read_timeout 1d;
      proxy_send_timeout 1d;
    }

    # main subscription (exact, protected link)
    location = /sub/${SUB_ID} {
      root ${WWW};
      default_type text/plain;
      add_header profile-title "base64:${TITLE_B64}" always;
      add_header profile-update-interval "12" always;
      add_header subscription-userinfo "upload=0; download=0; total=0; expire=0" always;
      add_header Cache-Control "no-store" always;
    }

    # other clients' subscriptions -> built-in 3x-ui sub server
    location ^~ /sub/ {
      proxy_pass http://127.0.0.1:${SUB_PORT};
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    }

    # panel
    location / {
      proxy_pass http://127.0.0.1:${PANEL_PORT};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_read_timeout 300s;
    }
  }
}
NGX

rm -f "$WWW/health.txt"
nginx -c "$NGX_CONF" -g 'daemon off;' &
log "nginx started on :$PUBLIC_PORT"

# ---------------------------------------------------------------------
# 4) panel (supervised)
# ---------------------------------------------------------------------
( while true; do cd /app && ./x-ui; log "panel exited ($?), restarting..."; sleep 3; done ) &

wait_panel() {
  _i=0
  while [ $_i -lt 180 ]; do
    _c=$(curl -s -o /dev/null -w '%{http_code}' "$API/" 2>/dev/null)
    [ "$_c" != "000" ] && return 0
    _i=$((_i+1)); sleep 1
  done
  return 1
}

api_login() {
  curl -s -c "$JAR" -X POST "$API/login" \
    --data-urlencode "username=$PANEL_USER" --data-urlencode "password=$PANEL_PASS" \
    | jq -e '.success == true' >/dev/null 2>&1 && return 0
  # user changed password inside panel -> restore env credentials
  ./x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" >/dev/null 2>&1
  sleep 2
  curl -s -c "$JAR" -X POST "$API/login" \
    --data-urlencode "username=$PANEL_USER" --data-urlencode "password=$PANEL_PASS" \
    | jq -e '.success == true' >/dev/null 2>&1
}

api_post() { curl -s -b "$JAR" -X POST "$API$1" 2>/dev/null; }

restart_xray() {
  for _p in /panel/api/server/restartXrayService /panel/server/restartXrayService /server/restartXrayService; do
    api_post "$_p" | jq -e '.success == true' >/dev/null 2>&1 && { log "xray restarted"; return 0; }
  done
}

restart_panel() { api_post /panel/setting/restartPanel >/dev/null 2>&1 || true; sleep 3; pkill -x x-ui 2>/dev/null; log "panel restarted to apply settings"; }

# ---------------------------------------------------------------------
# 5) the protected inbound
# ---------------------------------------------------------------------
inbound_id() { sq "SELECT id FROM inbounds WHERE remark='$REMARK_SQL' ORDER BY id LIMIT 1;" 2>/dev/null; }

client_json() {
  jq -cn --arg id "$UUID" --arg e "$EMAIL" --arg s "$SUB_ID" \
    '{id:$id,flow:"",email:$e,limitIp:0,totalGB:0,expiryTime:0,enable:true,tgId:"",subId:$s,comment:"JinX main (protected)",reset:0}'
}

settings_json() {
  _old=${1:-}
  _c=$(client_json)
  if [ -n "$_old" ] && printf '%s' "$_old" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$_old" | jq -c --argjson c "$_c" --arg id "$UUID" \
      '.decryption="none" | .clients = ((.clients // []) | if any(.[]; .id==$id) then map(if .id==$id then (.enable=true|.email=$c.email|.subId=$c.subId) else . end) else [$c] + . end)'
  else
    jq -cn --argjson c "$_c" '{clients:[$c],decryption:"none",fallbacks:[]}'
  fi
}

stream_json() {
  jq -cn --arg d "$DOMAIN" --arg p "$WS_PATH" --arg c "$CERT" --arg k "$KEY" \
    '{network:"ws",security:"tls",
      externalProxy:[{forceTls:"same",dest:$d,port:443,remark:""}],
      tlsSettings:{serverName:$d,minVersion:"1.2",maxVersion:"1.3",cipherSuites:"",
        rejectUnknownSni:false,disableSystemRoot:false,enableSessionResumption:true,
        certificates:[{certificateFile:$c,keyFile:$k,ocspStapling:3600,oneTimeLoading:false,usage:"encipherment",buildChain:false}],
        alpn:["http/1.1"],echServerKeys:"",echForceQuery:"none",
        settings:{allowInsecure:false,fingerprint:"chrome",echConfigList:""}},
      wsSettings:{acceptProxyProtocol:false,path:$p,host:$d,headers:{},heartbeatPeriod:0}}'
}

sniff_json() { echo '{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'; }

push_inbound() {   # $1 = add | update ; $2 = id
  if [ "$1" = update ]; then
    _url="/panel/api/inbounds/update/$2"
    _old=$(sq "SELECT settings FROM inbounds WHERE id=$2;")
  else
    _url="/panel/api/inbounds/add"; _old=""
  fi
  curl -s -b "$JAR" -X POST "$API$_url" \
    --data-urlencode "up=0" --data-urlencode "down=0" --data-urlencode "total=0" \
    --data-urlencode "remark=$REMARK" --data-urlencode "enable=true" \
    --data-urlencode "expiryTime=0" --data-urlencode "trafficReset=never" \
    --data-urlencode "listen=127.0.0.1" --data-urlencode "port=$XRAY_PORT" \
    --data-urlencode "protocol=vless" \
    --data-urlencode "settings=$(settings_json "$_old")" \
    --data-urlencode "streamSettings=$(stream_json)" \
    --data-urlencode "sniffing=$(sniff_json)" \
    --data-urlencode 'allocate={"strategy":"always","refresh":5,"concurrency":3}'
}

install_triggers() {
  _u=$(esc "$UUID")
  sq "
  DROP TRIGGER IF EXISTS jinx_no_delete;
  DROP TRIGGER IF EXISTS jinx_no_edit;
  DROP TRIGGER IF EXISTS jinx_no_client_delete;
  CREATE TRIGGER jinx_no_delete BEFORE DELETE ON inbounds
    WHEN OLD.remark='$REMARK_SQL'
    BEGIN SELECT RAISE(ABORT,'JinX inbound is protected'); END;
  CREATE TRIGGER jinx_no_edit BEFORE UPDATE ON inbounds
    WHEN OLD.remark='$REMARK_SQL' AND (NEW.remark<>OLD.remark OR NEW.port<>OLD.port
      OR NEW.protocol<>OLD.protocol OR NEW.enable<>OLD.enable OR instr(NEW.settings,'$_u')=0)
    BEGIN SELECT RAISE(ABORT,'JinX inbound is protected'); END;
  CREATE TRIGGER jinx_no_client_delete BEFORE DELETE ON client_traffics
    WHEN OLD.email='$EMAIL'
    BEGIN SELECT RAISE(ABORT,'JinX client is protected'); END;"
}

write_protect() {   # block destructive panel API calls for our inbound only
  _id=$1
  MSG='{"success":false,"msg":"⛔ این اینباند محافظت‌شده است و قابل حذف یا ویرایش نیست | This inbound is protected"}'
  : > "$NGX_PROTECT.tmp"
  for _p in \
    "/panel/api/inbounds/del/$_id" "/panel/inbound/del/$_id" \
    "/panel/api/inbounds/update/$_id" "/panel/inbound/update/$_id" \
    "/panel/api/inbounds/$_id/delClient/$UUID" "/panel/inbound/$_id/delClient/$UUID" \
    "/panel/api/inbounds/$_id/delClientByEmail/$EMAIL" \
    "/panel/api/inbounds/updateClient/$UUID" "/panel/inbound/updateClient/$UUID"; do
    printf "location = %s { default_type application/json; return 200 '%s'; }\n" "$_p" "$MSG" >> "$NGX_PROTECT.tmp"
  done
  mv "$NGX_PROTECT.tmp" "$NGX_PROTECT"
  nginx -c "$NGX_CONF" -s reload 2>/dev/null
}

ensure_inbound() {
  _id=$(inbound_id)
  if [ -z "$_id" ]; then
    log "creating protected inbound..."
    push_inbound add >/tmp/jinx.resp
  else
    log "syncing protected inbound #$_id ..."
    push_inbound update "$_id" >/tmp/jinx.resp
  fi
  jq -e '.success == true' /tmp/jinx.resp >/dev/null 2>&1 || log "panel said: $(cat /tmp/jinx.resp 2>/dev/null)"
  _id=$(inbound_id)
  if [ -n "$_id" ]; then
    install_triggers
    write_protect "$_id"
    CUR_ID=$_id
    log "inbound #$_id ready and locked"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------
# 6) bootstrap
# ---------------------------------------------------------------------
CUR_ID=""
if wait_panel; then
  sleep 2
  n=0
  until api_login && ensure_inbound; do
    n=$((n+1)); [ $n -ge 10 ] && { log "bootstrap failed, watchdog will retry"; break; }
    sleep 3
  done
  restart_xray
else
  log "panel did not start in time; watchdog will retry"
fi
echo ok > "$WWW/health.txt"; chmod 644 "$WWW/health.txt"
log "================================================="
log " Panel : https://${DOMAIN}/   (user: ${PANEL_USER})"
log " Sub   : https://${DOMAIN}/sub/${SUB_ID}"
log "================================================="

# ---------------------------------------------------------------------
# 7) watchdog
# ---------------------------------------------------------------------
(
  FAILS=0
  while true; do
    sleep 20
    # panel alive?
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "$API/" 2>/dev/null)" = "000" ]; then
      FAILS=$((FAILS+1))
      [ $FAILS -ge 3 ] && { log "panel unresponsive, restarting"; pkill -x x-ui 2>/dev/null; FAILS=0; }
      continue
    fi
    FAILS=0
    # critical settings
    enforce_settings
    if [ "$CHANGED" = 1 ]; then api_login; restart_panel; sleep 8; fi
    # inbound present + locked
    ID=$(inbound_id)
    if [ -z "$ID" ]; then
      log "protected inbound missing -> restoring"
      api_login && ensure_inbound && restart_xray
    else
      [ "$ID" != "$CUR_ID" ] && { write_protect "$ID"; CUR_ID=$ID; }
      T=$(sq "SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'jinx_%';" 2>/dev/null)
      [ "${T:-0}" -lt 3 ] && install_triggers
    fi
    [ -s "$WWW/sub/$SUB_ID" ] || build_sub
  done
) &

wait
