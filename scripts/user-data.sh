#!/bin/bash
sudo yum update -y

# 1. Install Nginx (Logic for AL2 vs AL2023)
if command -v amazon-linux-extras &> /dev/null; then
    sudo amazon-linux-extras install nginx1 -y
else
    sudo yum install nginx -y
fi

sudo systemctl enable nginx
sudo systemctl start nginx

# 2. IMDSv2 - The Secure Way to get Metadata
# Step A: Get a Session Token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Step B: Use the Token to get the Instance ID
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

# 3. Create the Index Page
echo "<h1>Hello from Achyut's instance: $INSTANCE_ID </h1>" | sudo tee /usr/share/nginx/html/index.html