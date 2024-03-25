#!/bin/bash



# variables gets made in the provision script. Change values at the top of the provision script.
registration_token="{{REGISTRATION_TOKEN}}"
app_name="{{APP_NAME}}"
gh_user="{{GH_USER}}"
runner_name="{{RUNNER_NAME}}"

# Get Ubuntu version, install the Microsoft package repo and update packages
declare repo_version=$(if command -v lsb_release &> /dev/null; then lsb_release -r -s; else grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"'; fi)
wget https://packages.microsoft.com/config/ubuntu/$repo_version/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
apt update -y

# Install the .NET Runtime and SDK
# sudo apt-get update && sudo apt-get install -y aspnetcore-runtime-8.0
apt-get update -y
apt-get install -y aspnetcore-runtime-8.0

# Write unit file
cat << EOF > /etc/systemd/system/$app_name.service
[Unit]
Description=Configures and runs the $app_name web application

[Service]
WorkingDirectory=/opt/$app_name
ExecStart=/usr/bin/dotnet /opt/$app_name/$app_name.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=$app_name
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false
Environment="ASPNETCORE_URLS=http://*:5000"

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable the service
systemctl daemon-reload
systemctl enable $app_name.service

# Add self-hosted runner
mkdir /home/azureuser/actions-runner; cd /home/azureuser/actions-runner
curl -o actions-runner-linux-x64-2.314.1.tar.gz -L https://github.com/actions/runner/releases/download/v2.314.1/actions-runner-linux-x64-2.314.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.314.1.tar.gz
chown -R azureuser:azureuser ../actions-runner
su -c "./config.sh --unattended --url https://github.com/$gh_user/$app_name --token $registration_token --name $runner_name" azureuser
./svc.sh install azureuser
./svc.sh start
