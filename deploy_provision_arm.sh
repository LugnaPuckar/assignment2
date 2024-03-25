#!/bin/bash

# Written on Windows 11. Unsure about compatibility with other OS.

############################################################################################################
# Global variables #
####################

# 1. Resource group and deployment name
rg_name="assignment2_$(date +'%Y%m%d_%H%M%S')"      # Creates RG name: "assignment2_CurrentDate_CurrentTime"
deployment_name="armdeployment"

# 2. File paths for cloud-init scripts, ARM template.
rp_init=cloud-init-rpserver.sh
as_init=cloud-init-appserver.sh
arm_template=arm_template_bh_rp_as.json

# 3. Github variables. Set the global variables here if you want to skip the prompts. Else, leave them as is.
gh_user=""
workflow_name="cicd.yaml"

# 4. Location and admin user.
location="swedencentral"
admin_user="azureuser"

############################################################################################################

# Verify that jq is installed - Exit if not.
jq_check_installation(){
    if command -v jq &> /dev/null; then
        echo "jq is installed."
    else
        echo "jq is not installed. Please install jq to proceed."
        exit 1
    fi
}

# Verify that GH CLI is authenticated - Exit if not.
gh_check_auth_status(){
    if gh auth status &> /dev/null; then
    echo "Github CLI - Authentication successful."
    else
    echo "Github CLI - Authentication failed. Exiting. For more info: https://docs.github.com/en/enterprise-cloud@latest/github-cli/github-cli/quickstart"
    exit 1
    fi

}

# Checks if gh_user is empty. If empty, it will prompt the user to enter a Github username, otherwise it will check if the username exists/valid and continue.
gh_user_check_the_global_variable(){

    # Check if gh_user is not empty
    if [ -n "$gh_user" ]; then
        # Check if gh_user exists and is valid
        gh_user_check_if_username_is_valid "$gh_user"
    else
        # if gh_user is empty or not valid, prompt the user to enter a Github username
        gh_user_set_username_if_empty
    fi
}

# Function that checks if the Github username exists.
gh_user_check_if_username_is_valid(){
    local username="$1"
    local response=$(curl -s "https://api.github.com/users/$username")
    if [[ "$response" == *"message"*"Not Found"* ]]; then
        echo "Error: GitHub username '$username' not found."
        exit 1
    else
        echo "GitHub username '$username' is valid."
    fi
}

# Function to choose the Github username if the global variable is empty.
gh_user_set_username_if_empty(){
    local github_username=""
    read -p "Enter the Github username: " github_username
    # Validate not empty
    if [ -z "$github_username" ]; then
        echo "Error: Github username cannot be empty."
        exit 1
    else
        # Check if the username exists
        gh_user_check_if_username_is_valid "$github_username"

        # if it exists, set the global variable gh_user to the entered username
        gh_user="$github_username"
    fi
}

# Start a Github workflow to deploy the app if app already exists on Github.
gh_run_workflow(){
    gh workflow run $workflow_name --repo $gh_user/$app_name --ref main
    local rpIP=$(get_vm_ip "reverseproxyVM")
    echo "Github workflow started. Should soon be available at $rpIP"
}

# Creates a temporary copy of cloud-init script. 
# Replaces placeholders with actual values for the run.
create_temp_appserver_init(){
    local registration_token=$(gh api -X POST "repos/$gh_user/$app_name/actions/runners/registration-token" | jq -r '.token')
    local runner_name="${app_name}_runner_$(date +'%Y%m%d_%H%M%S')"
    local tmp_as_init=$(mktemp)
    trap 'rm -f "$tmp_as_init"' EXIT
    cp "$as_init" "$tmp_as_init"

    sed -i " \
    s/{{REGISTRATION_TOKEN}}/$registration_token/; \
    s/{{APP_NAME}}/$app_name/; \
    s/{{GH_USER}}/$gh_user/; \
    s/{{RUNNER_NAME}}/$runner_name/ \
    " "$tmp_as_init"
    
    echo "$tmp_as_init"
}

# Creates a resource group.
# Provisions the ARM deployment. 
# Exits if the deployment fails.
provision_arm_deployment(){
    az group create --name $rg_name --location $location
    az deployment group create --resource-group $rg_name --name $deployment_name \
    --template-file $arm_template \
    --parameters \
    customDataReverseProxyServer=@$rp_init \
    customDataAppServer=@$(create_temp_appserver_init) \
    adminUsername=$admin_user \
    sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"

    # Exit if the deployment failed - Check the exit code of the deployment command
    if [ $? -ne 0 ]; then
    echo "Deployment failed. Exiting script."
    exit 1
    fi

}

# Function to get the public IP of VMs directly using deployment output name
get_vm_ip(){
    local name=$(az deployment group show --resource-group $rg_name --name $deployment_name --query "properties.outputs.$1.value" --output tsv)
    az vm show --resource-group $rg_name --name "$name" --show-details --query publicIps --output tsv
}

# Function to get the private IP of VMs directly using deployment output name
get_vm_private_ip(){
    local name=$(az deployment group show --resource-group $rg_name --name $deployment_name --query "properties.outputs.$1.value" --output tsv)
    az vm show --resource-group $rg_name --name "$name" --show-details --query privateIps --output tsv
}

# Get all VM names and public IPs and echo them in the terminal.
echo_all_vm_ip(){
    # Get the public IPs for each VM. "" value is the output name from the ARM template.
    local bhIP=$(get_vm_ip "bastionhostVM")
    local rpIP=$(get_vm_ip "reverseproxyVM")
    local asIP=$(get_vm_ip "appserverVM")

    local bhPrivateIP=$(get_vm_private_ip "bastionhostVM")
    local rpPrivateIP=$(get_vm_private_ip "reverseproxyVM")
    local asPrivateIP=$(get_vm_private_ip "appserverVM")

    # Echo the outputs to connect to the VMs.
    echo "########################################################################"
    echo "#### Use below to connect to VM ########################################"
    echo 'eval $(ssh-agent)' # For easy copy-paste
    echo 'ssh-add'           # For easy copy-paste
    echo "BastionHost:   ssh -A $admin_user@$bhIP         $bhIP"
    echo "ReverseProxy:   ssh $admin_user@$rpPrivateIP"
    echo "AppServer:    ssh $admin_user@$asPrivateIP"
    echo "Browse the webapp at:           $rpIP"

    # Can't SSH to RP or AS via public IP. Connect to Bastion Host first, then to RP or AS via private IP.
    # echo "ReverseProxy:   ssh $admin_user@$rpIP         $rpIP"
    # echo "AppServer:    ssh $admin_user@$asIP        $asIP"

}

# Echo the command to delete the resource group.
echo_delete_rg(){
    echo "########################################################################"
    echo "# Are you done testing? ################################################"
    echo "# Delete the resource group by copy pasting below command in terminal. #"
    echo "az group delete --name $rg_name --yes --no-wait"
}

# Run this if you want to create a new app on Github.
main_app_new(){
    # $1 = app_name, $2 = gh_user, $3 = workflow_name
    ./createapp.sh $app_name $gh_user $workflow_name
    provision_arm_deployment
    echo_all_vm_ip
    echo_delete_rg
}

# Run this if app already exists on Github.
main_app_exists(){
    gh_run_workflow
    provision_arm_deployment
    echo_all_vm_ip
    echo_delete_rg
}

# Function to choose the app name if app_name="" or invalid.
choose_app_name(){

    echo "########################################################################"
    echo "### Choose an option for what application to provision:              ###"
    echo "### If you want to create a new app on Github, choose #1 or #2.      ###"
    echo "### If you want to deploy an existing app on Github, choose  #3.     ###"
    echo "########################################################################"
    echo "1. Create a new basic webapp with unique name: assignment2_$(date +'%Y%m%d_%H%M%S')"
    echo "2. Create a new basic webapp with a custom name of your choice"
    echo "3. Enter the name of an existing app on GitHub"
    read -p "Enter your choice (1, 2, or 3): " choice

    if [ "$choice" == "1" ]; then
        app_name="assignment2_$(date +'%Y%m%d_%H%M%S')"
        chosen_app_type="new"
    elif [ "$choice" == "2" ]; then
        read -p "Enter the custom app name for the new app: " custom_name
        app_name="$custom_name"
        chosen_app_type="new"
    elif [ "$choice" == "3" ]; then
        read -p "Enter the name of the existing app on GitHub: " existing_name
        # Check if existing_name exists
        if ! gh repo view "$gh_user/$existing_name" &> /dev/null ; then
            echo "Error: The repository '$gh_user/$existing_name' does not exist."
            exit 1
        fi

        # Set the app_name if repository exists
        app_name="$existing_name"
        chosen_app_type="existing"
    else
        echo "Invalid choice. Exiting script."
        exit 1
    fi
}

# Call the function to choose the app name
main(){
    gh_check_auth_status
    jq_check_installation
    gh_user_check_the_global_variable
    choose_app_name
    if [ "$chosen_app_type" == "new" ]; then
        main_app_new
    elif [ "$chosen_app_type" == "existing" ]; then
        main_app_exists
    fi
}

main
