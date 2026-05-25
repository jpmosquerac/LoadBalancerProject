#!/bin/bash
set -e

echo "=== Starting NGINX Setup ==="

# Update system
apt-get update
apt-get install -y nginx aws-cli curl

# Backup original nginx.conf
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Replace with custom configuration
# Assuming nginx.conf is provided via S3 or directly copied
if [ -f "/tmp/nginx.conf" ]; then
    cp /tmp/nginx.conf /etc/nginx/nginx.conf
    echo "NGINX configuration loaded from /tmp/nginx.conf"
else
    echo "WARNING: Custom nginx.conf not found. Using default configuration."
    echo "Please update /etc/nginx/nginx.conf manually or via CloudFormation User Data."
fi

# Test NGINX configuration
nginx -t

# Enable and start NGINX service
systemctl enable nginx
systemctl start nginx

# Verify NGINX is running
if systemctl is-active --quiet nginx; then
    echo "NGINX service is running successfully"
else
    echo "ERROR: NGINX failed to start"
    systemctl status nginx
    exit 1
fi

echo "=== NGINX Setup Complete ==="
echo "NGINX logs: /var/log/nginx/access.log and /var/log/nginx/error.log"
