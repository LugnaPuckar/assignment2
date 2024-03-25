#!/bin/bash

# Written on Windows 11. Unsure about compatibility with other OS.

app_name=$1
gh_user=$2
workflow_name=$3


make_new_app(){
  # create new dotnet webapp
  dotnet new webapp -o $app_name

  # change directory to the new app
  cd $app_name

  # create new dotnet gitignore
  dotnet new gitignore
}

create_workflow(){
    # create path for the .github workflows
    mkdir -p .github/workflows

    # cat a new yaml file for the github actions
    cat > .github/workflows/$workflow_name <<EOF
name: $app_name

on:
  push:
    branches:
      - "main"
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Install .NET SDK
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Check out this repo
        uses: actions/checkout@v4

      - name: Restore dependencies (install Nuget packages)
        run: dotnet restore

      - name: Build and publish the app
        run: |
          dotnet build --no-restore
          dotnet publish -c Release -o ./publish        

      - name: Upload app artifacts to Github
        uses: actions/upload-artifact@v4
        with:
          name: app-artifacts
          path: ./publish

  deploy:
    runs-on: self-hosted
    needs: build

    steps:
      - name: Download the artifacts from Github
        uses: actions/download-artifact@v4
        with:
          name: app-artifacts
      
      - name: Stop the app service
        run: |
          sudo systemctl stop $app_name.service
      
      - name: Deploy the application
        run: |
          sudo rm -Rf /opt/$app_name || true
          sudo cp -r /home/azureuser/actions-runner/_work/$app_name/$app_name/ /opt/$app_name

      - name: Start the app service
        run: |
          sudo systemctl start $app_name.service
EOF
}


git_actions(){
	# Create a new repository on Github using the Github CLI
	gh repo create $app_name --public -y

	# initialize a new git repository
	git init

	# add all files to the git repository
	git add .

	# Commit the changes
	git commit -m "Initial commit"

	# Retrieve the HTML URL of the repository using the Github CLI and jq
	repo_url="https://github.com/$gh_user/$app_name.git"

	# Add the remote repository
	git remote add origin "$repo_url"

	# Push the changes to the remote repository
	git push -u origin main
}

main(){
  make_new_app
  create_workflow
  git_actions
}

main