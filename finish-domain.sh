#!/usr/bin/env bash
# Gan ten mien capi.khoind.dbagencyglobal.com cho GitHub Pages.
# Chay:  bash finish-domain.sh
# Can:   file .cf-token (hoac bien moi truong CLOUDFLARE_API_TOKEN)
set -u

ZONE="dbagencyglobal.com"
SUB="capi.khoind"
FQDN="$SUB.$ZONE"
TARGET="khoi09061997bn-oss.github.io"
REPO="khoi09061997bn-oss/capi-n8n-service"
CFAPI="https://api.cloudflare.com/client/v4"

cd "$(dirname "$0")" || exit 1

CF="${CLOUDFLARE_API_TOKEN:-}"
[ -z "$CF" ] && [ -f .cf-token ] && CF=$(tr -d ' \t\r\n' < .cf-token)
if [ -z "$CF" ]; then
  echo "THIEU TOKEN. Tao token tai dash.cloudflare.com > My Profile > API Tokens"
  echo "Quyen can: Zone / DNS / Edit, gioi han vung $ZONE"
  echo "Roi luu vao file .cf-token trong thu muc nay (da duoc gitignore)."
  exit 1
fi

echo "[1/6] Tim zone $ZONE"
ZID=$(curl -s -H "Authorization: Bearer $CF" "$CFAPI/zones?name=$ZONE" \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const r=JSON.parse(d);process.stdout.write(r.success&&r.result[0]?r.result[0].id:'')})")
if [ -z "$ZID" ]; then echo "  KHONG TIM THAY ZONE. Token co the thieu quyen hoac sai vung."; exit 1; fi
echo "  zone id: ${ZID:0:8}..."

echo "[2/6] Tao ban ghi CNAME $FQDN -> $TARGET (DNS only)"
EXIST=$(curl -s -H "Authorization: Bearer $CF" "$CFAPI/zones/$ZID/dns_records?name=$FQDN" \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const r=JSON.parse(d);process.stdout.write(r.result&&r.result[0]?r.result[0].id:'')})")
BODY="{\"type\":\"CNAME\",\"name\":\"$SUB\",\"content\":\"$TARGET\",\"ttl\":1,\"proxied\":false}"
if [ -n "$EXIST" ]; then
  echo "  ban ghi da ton tai, cap nhat lai"
  OUT=$(curl -s -X PUT -H "Authorization: Bearer $CF" -H "Content-Type: application/json" \
    "$CFAPI/zones/$ZID/dns_records/$EXIST" -d "$BODY")
else
  OUT=$(curl -s -X POST -H "Authorization: Bearer $CF" -H "Content-Type: application/json" \
    "$CFAPI/zones/$ZID/dns_records" -d "$BODY")
fi
echo "$OUT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const r=JSON.parse(d);console.log(r.success?'  OK: '+r.result.name+' -> '+r.result.content+' (proxied='+r.result.proxied+')':'  LOI: '+JSON.stringify(r.errors))})"
echo "$OUT" | grep -q '"success":true' || exit 1

echo "[3/6] Khoi phuc file CNAME va push"
printf '%s' "$FQDN" > CNAME
git add CNAME
git -c user.name="khoi09061997bn-oss" -c user.email="khoi09061997bn@gmail.com" \
  commit -q -m "chore: gan lai ten mien $FQDN" 2>/dev/null || echo "  khong co gi de commit"
git push -q origin main && echo "  da push"

echo "[4/6] Cho DNS lan ra (toi da 5 phut)"
for i in $(seq 1 20); do
  if nslookup "$FQDN" 1.1.1.1 >/dev/null 2>&1; then echo "  DNS da co sau $((i*15))s"; break; fi
  sleep 15
done

echo "[5/6] Bao GitHub Pages dung ten mien nay"
GH=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
curl -s -o /dev/null -w "  PUT pages: HTTP %{http_code}\n" -X PUT \
  -H "Authorization: Bearer $GH" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/pages" \
  -d "{\"cname\":\"$FQDN\",\"source\":{\"branch\":\"main\",\"path\":\"/\"}}"

echo "[6/6] Cho chung chi HTTPS roi bat Enforce HTTPS (toi da 15 phut)"
for i in $(seq 1 30); do
  ST=$(curl -s -H "Authorization: Bearer $GH" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/pages" \
    | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const r=JSON.parse(d);process.stdout.write(String(r.https_certificate&&r.https_certificate.state))})")
  echo "  chung chi: $ST"
  if [ "$ST" = "approved" ]; then
    curl -s -o /dev/null -w "  bat Enforce HTTPS: HTTP %{http_code}\n" -X PUT \
      -H "Authorization: Bearer $GH" -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/pages" -d '{"https_enforced":true}'
    break
  fi
  sleep 30
done

echo ""
echo "XONG. Kiem tra: https://$FQDN/"
curl -s -o /dev/null -w "  trang tra ve HTTP %{http_code}\n" "https://$FQDN/" || true
