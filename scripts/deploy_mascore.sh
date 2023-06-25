#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Trap the SIGINT signal (Ctrl+C)
trap ctrl_c INT

function ctrl_c() {
    echo "Stopping the script..."
    exit 1
}

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 CLUSTER_NAME IBM_ENTITLEMENT_KEY_SECRET_ARN MONGO_HOSTS DOCDB_SECRET_ARN"
    exit
fi
echo `date "+%Y/%m/%d %H:%M:%S"` "Setting up the environment variables for MASCore Deployment"
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
# The MongoDB role in ansible automation requires the AWS_REGION to be set
export AWS_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
# CLUSTER NAME
export CLUSTER_NAME=$1
# Entitlement Key secret ARN
export IBM_ENTITLEMENT_SECRET_ARN=$2
export IBM_ENTITLEMENT_KEY=`aws secretsmanager get-secret-value --secret-id $IBM_ENTITLEMENT_SECRET_ARN --region $AWS_REGION | jq -r ."SecretString"`
# List of Mongo Hosts with Ports
export MONGODB_HOSTS=$3
# Document DB username and password secret ARN
export DOCDB_SECRET_ARN=$4
export MONGODB_ADMIN_USERNAME=`aws secretsmanager get-secret-value --secret-id $DOCDB_SECRET_ARN --region $AWS_REGION | jq -r ."SecretString"|jq -r .username`
export MONGODB_ADMIN_PASSWORD=`aws secretsmanager get-secret-value --secret-id $DOCDB_SECRET_ARN --region $AWS_REGION | jq -r ."SecretString"|jq -r .password`

export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig
export MONGODB_ACTION=install

export SLS_LICENSE_FILE=/root/install-dir/entitlement.lic
export SLS_LICENSE_ID=`head -1 $SLS_LICENSE_FILE| cut -d" " -f3`
[ -z "$SLS_LICENSE_ID" ] && echo "Could not fetch SLS License ID. Check the entitlement.lic file" && exit 1

export PULL_SECRET_FILE=/root/install-dir/pull-secret.txt
[ ! -f "/root/install-dir/pull-secret.txt" ] && echo "pull-secret file not found. Ensure file is present in the pre-requisite s3 bucket" && exit 1

export UDS_CONTACT_EMAIL=`cat $PULL_SECRET_FILE| jq -r '.[]|."cloud.openshift.com"."email"'`
[ -z "$UDS_CONTACT_EMAIL" ] && echo "Could not fetch email ID from pull secret. Check if pull secret is valid" && exit 1
export UDS_CONTACT_FIRSTNAME=$UDS_CONTACT_EMAIL
export UDS_CONTACT_LASTNAME=$UDS_CONTACT_EMAIL
#Default Storage class
export DEFAULT_SC=`oc get sc | grep default | awk '{print $1}'`
#Set the EFS as storage class for Prometheus Storage class, all else would be default
export PROMETHEUS_ALERTMGR_STORAGE_CLASS="efs"
export PROMETHEUS_STORAGE_CLASS=$DEFAULT_SC
export PROMETHEUS_USERWORKLOAD_STORAGE_CLASS=$DEFAULT_SC
export GRAFANA_INSTANCE_STORAGE_CLASS=$DEFAULT_SC
#export MONGODB_STORAGE_CLASS="gp2" # Required if MongoDB Storage class is community
export UDS_STORAGE_CLASS=$DEFAULT_SC

echo `date "+%Y/%m/%d %H:%M:%S"` "Installing the MAS Operator on the OCP Cluster"
# Install the MAS Operator
#ansible-playbook ibm.mas_devops.oneclick_core
export ROLE_NAME=ibm_catalogs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=common_services && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=cert_manager && ansible-playbook ibm.mas_devops.run_role

# Check if the Certificate bundles for specific AWS Region is downloaded
[ ! -f "/root/install-dir/${AWS_REGION}-bundle.pem" ] && echo "DB certificate not present. Please check install-dir folder" && exit 1

export MONGODB_PROVIDER=aws
export SLS_MONGO_RETRYWRITES=false

export MONGODB_CA_PEM_LOCAL_FILE=/root/install-dir/${AWS_REGION}-bundle.pem
export MONGODB_RETRY_WRITES=$SLS_MONGO_RETRYWRITES
export ROLE_NAME=gencfg_mongo && ansible-playbook ibm.mas_devops.run_role

#SLS
[ ! -f "/root/install-dir/masconfig/mongo-mongoce.yml" ] && echo "Mongo mas config file must be present" && exit 1
export SLS_NAMESPACE=ibm-sls
export SLS_MONGODB_CFG_FILE="/root/install-dir/masconfig/mongo-mongoce.yml"

envsubst < /root/ibm-mas-on-aws/config/masocp-products-config-template.yaml > /root/ibm-mas-on-aws/config/masocp-products-config.yaml
envsubst < /root/ibm-mas-on-aws/config/cloudcredentialrequest-config-template.yaml > /root/ibm-mas-on-aws/config/cloudcredentialrequest-config.yaml

oc new-project "$SLS_NAMESPACE"
oc create -f /root/ibm-mas-on-aws/config/masocp-products-config.yaml -n "$SLS_NAMESPACE"
oc create -f /root/ibm-mas-on-aws/config/cloudcredentialrequest-config.yaml -n "$SLS_NAMESPACE"

export ROLE_NAME=sls && ansible-playbook ibm.mas_devops.run_role

# UDS
export ROLE_NAME=uds && ansible-playbook ibm.mas_devops.run_role

## Install and Configure MAS
export MAS_WORKSPACE_ID=masdev
export MAS_WORKSPACE_NAME="MAS Workspace"
export ROLE_NAME=gencfg_workspace && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_dns && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_certs && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_install && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_config && ansible-playbook ibm.mas_devops.run_role
export ROLE_NAME=suite_verify && ansible-playbook ibm.mas_devops.run_role

# Create a secret with the MAS Admin console secrets
if [[ $? -ne 0 ]]; then
        echo `date "+%Y/%m/%d %H:%M:%S"` "Installation of MAS core failed"
        exit 1
else
        # Create a secret with MAS Credentials
        EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
        export AWS_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
        export MAS_PASSWORD=`oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .data.password | base64 -d`
        [ -z "$MAS_PASSWORD" ] && exit 1
        export MAS_USERNAME=`oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .data.username | base64 -d`
        [ -z $MAS_USERNAME ] && exit 1
        export MAS_ADMIN_URL=`oc get route ${MAS_INSTANCE_ID}-admin -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .status.ingress[0].host`
        [ -z $MAS_ADMIN_URL ] && exit 1
        export INFRAID=`cat /root/install-dir/metadata.json  | jq -r .infraID`"-mas-creds"
        echo `date "+%Y/%m/%d %H:%M:%S"` "Creating secret for MAS Admin console in Secrets Manager  .........  " $INFRAID
        aws secretsmanager create-secret \
        --name $INFRAID \
        --description "MAS Admin Console credentials" \
        --secret-string "{\"user\":\"${MAS_USERNAME}\",\"password\":\"${MAS_PASSWORD}\",\"consoleurl\":\"${MAS_ADMIN_URL}\"}" \
        --region $AWS_REGION
fi