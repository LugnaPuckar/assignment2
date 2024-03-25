#!/bin/bash

# Written on Windows 11. Unsure about compatibility with other OS.

# Global variables

# 1. Resource group and deployment name
rg_name="assignment2_$(date +'%Y%m%d_%H%M%S')"      # Creates RG name: "assignment2_CurrentDate_CurrentTime"
deployment_name="armdeployment"

# 2. File paths for cloud-init scripts, ARM template.
rp_init=cloud-init-rpserver.sh
as_init=cloud-init-appserver.sh
arm_template=arm_template_bh_rp_as.json

#####################################################################################################
######################!YOU MUST DO BELOW FOR THIS SCRIPT TO WORK!####################################
# 3. Github variables. Set them accordingly to your github username, app name (repo) and workflow name. ####
#####################################################################################################
gh_user=""
app_name=""
workflow_name="cicd.yaml"

# 4. Location and admin user.
location="swedencentral"
admin_user="azureuser"

# Creates a temporary copy of cloud-init script for the application server. 
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

# Starts a Github workflow action to then deploy the app to the provisioned application server.
gh_run_workflow(){
    gh workflow run $workflow_name --repo $gh_user/$app_name --ref main
    rpIP=$(az deployment group show --resource-group $rg_name --name $deployment_name --query "properties.outputs.reverseproxyVM.value" --output tsv)
    echo "Github workflow started. Should soon be available at $rpIP"
}

# Provision the ARM deployment
provision_arm_deployment
gh_run_workflow