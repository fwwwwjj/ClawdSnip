#!/bin/zsh
# 一次性：生成一个只在本机用的固定签名证书，放进单独的钥匙串文件（不碰登录钥匙串）。
# 有了它，每次重新编译 ClawdSnip 的签名都不变，macOS 的录屏 / 辅助功能授权就不会失效。
set -euo pipefail

DIR="$HOME/Library/Application Support/ClawdSnip"
KC="$DIR/signing.keychain-db"
PASSF="$DIR/signing.pass"
NAME="ClawdSnip Local Signing"
SSL=/usr/bin/openssl

if [[ -f "$KC" ]]; then
  echo "signing keychain already exists: $KC"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
PASS="$($SSL rand -hex 16)"
print -r -- "$PASS" > "$PASSF"
chmod 600 "$PASSF"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
$SSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
$SSL pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/id.p12" -passout pass:"$PASS"

# create-keychain 会把新钥匙串加进搜索列表；记下原列表，建完后恢复
ORIG=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')}")
security create-keychain -p "$PASS" "$KC"
security list-keychains -d user -s "${ORIG[@]}"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null

echo "created signing identity \"$NAME\" in $KC"
