#!/bin/bash
set -euxo pipefail

# --- Install web server (AL2023 uses dnf) ---
dnf -y update
dnf -y install nginx

# --- IMDS helper (uses v2 token if available) ---
TOKEN="$(curl -sS -X PUT 'http://169.254.169.254/latest/api/token' \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' || true)"

md() {
  local path="$1"
  if [ -n "$TOKEN" ]; then
    curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254${path}"
  else
    curl -sS "http://169.254.169.254${path}"
  fi
}

INSTANCE_ID="$(md /latest/meta-data/instance-id)"
AZ="$(md /latest/meta-data/placement/availability-zone)"
HOSTNAME_FQDN="$(hostname -f || hostname)"

# --- Simple page that proves which instance served you ---
cat > /usr/share/nginx/html/index.html <<EOF
<!doctype html>
<html>
<head><meta charset="utf-8"><title>ASG Demo</title></head>
<body style="font-family:system-ui;max-width:720px;margin:40px auto;">
  <h1>Hello from $INSTANCE_ID</h1>
  <p>Hostname: $HOSTNAME_FQDN<br>AZ: $AZ</p>
</body>
</html>
EOF

systemctl enable --now nginx
