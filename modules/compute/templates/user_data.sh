#!/bin/bash
set -e  # exit immediately if any command fails

# =============================================================================
# USER DATA SCRIPT — AutoServe Pro
# Runs automatically when EC2 first starts up.
# set -e means if any command fails, script stops immediately.
# Logs everything to /var/log/user-data.log for debugging.
# =============================================================================

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== AutoServe Pro startup script beginning ==="

# =============================================================================
# STEP 1 — Update OS and install dependencies
# =============================================================================
echo "=== Installing system dependencies ==="
dnf update -y
dnf install -y python3 python3-pip git

# =============================================================================
# STEP 2 — Install and start SSM Agent
# Enables GitHub Actions to deploy without SSH keys (Day 7)
# Amazon Linux 2023 has SSM agent pre-installed but we ensure it's running
# =============================================================================
echo "=== Starting SSM Agent ==="
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# =============================================================================
# STEP 3 — Clone application code from GitHub
# =============================================================================
echo "=== Cloning application code ==="
cd /home/ec2-user
git clone https://github.com/dhruvs-git/autopro_booking_app.git app
cd app/app

# =============================================================================
# STEP 4 — Install Python dependencies
# =============================================================================
echo "=== Installing Python dependencies ==="
pip3 install -r requirements.txt

# =============================================================================
# STEP 5 — Fetch DB credentials from Secrets Manager
# Writes them to /etc/autoserve/db.env as environment variables
# Flask reads these at startup — no credentials in code ever
# secret_arn and region are injected by Terraform templatefile()
# =============================================================================
echo "=== Fetching DB credentials from Secrets Manager ==="
mkdir -p /etc/autoserve

aws secretsmanager get-secret-value \
  --secret-id ${secret_arn} \
  --region ${region} \
  --query SecretString \
  --output text > /tmp/db_secret.json

# Parse JSON and write as environment variables
python3 -c "
import json
with open('/tmp/db_secret.json') as f:
    s = json.load(f)
with open('/etc/autoserve/db.env', 'w') as f:
    f.write(f'DB_HOST={s[\"host\"]}\n')
    f.write(f'DB_PORT={s[\"port\"]}\n')
    f.write(f'DB_NAME={s[\"dbname\"]}\n')
    f.write(f'DB_USER={s[\"username\"]}\n')
    f.write(f'DB_PASSWORD={s[\"password\"]}\n')
"

# Secure the file — only root can read it
chmod 600 /etc/autoserve/db.env
rm /tmp/db_secret.json

# =============================================================================
# STEP 6 — Create systemd service
# systemd keeps Flask running permanently.
# If Flask crashes, systemd restarts it automatically.
# EnvironmentFile loads the DB credentials we just wrote.
# =============================================================================
echo "=== Creating systemd service ==="
cat > /etc/systemd/system/autoserve.service << 'EOF'
[Unit]
Description=AutoServe Pro Flask Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app/app
EnvironmentFile=/etc/autoserve/db.env
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# STEP 7 — Start Flask
# =============================================================================
echo "=== Starting AutoServe Flask application ==="
systemctl daemon-reload
systemctl enable autoserve
systemctl start autoserve

echo "=== Startup complete ==="