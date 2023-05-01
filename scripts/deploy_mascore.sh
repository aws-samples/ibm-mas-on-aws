#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 IBM_ENTITLEMENT_KEY"
    exit
fi

export IBM_ENTITLEMENT_KEY=$1
export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig

export SLS_LICENSE_FILE=/root/install-dir/entitlement.lic
export SLS_LICENSE_ID=`head -1 $SLS_LICENSE_FILE| cut -d" " -f2`
[ -z "$SLS_LICENSE_ID" ] && echo "Could not fetch SLS License ID. Check the entitlement.lic file" && exit 1

export PULL_SECRET_FILE=/root/install-dir/pull-secret.txt
[ ! -f "/root/install-dir/pull-secret.txt" ] && echo "pull-secret file not found. Ensure file is present in the pre-requisite s3 bucket" && exit 1

export UDS_CONTACT_EMAIL=`cat $PULL_SECRET_FILE| jq -r '.[]|."cloud.openshift.com"."email"'`
[ -z "$UDS_CONTACT_EMAIL" ] && echo "Could not fetch email ID from pull secret. Check if pull secret is valid" && exit 1
export UDS_CONTACT_FIRSTNAME=$UDS_CONTACT_EMAIL
export UDS_CONTACT_LASTNAME=$UDS_CONTACT_EMAIL

export PROMETHEUS_ALERTMGR_STORAGE_CLASS="efs"
export PROMETHEUS_STORAGE_CLASS="gp2"
export PROMETHEUS_USERWORKLOAD_STORAGE_CLASS="gp2"
export GRAFANA_INSTANCE_STORAGE_CLASS="gp2"
export MONGODB_STORAGE_CLASS="gp2"
export UDS_STORAGE_CLASS="gp2"

echo `date "+%Y/%m/%d %H:%M:%S"` "Installing the MAS Operator on the OCP Cluster"
# Install the MAS Operator
ansible-playbook ibm.mas_devops.oneclick_core

# Create a secret with the MAS Admin console secrets
if [[ $? -ne 0 ]]; then
        echo `date "+%Y/%m/%d %H:%M:%S"` "Installation of MAS core failed"
        exit 1
else
        # Create a secret with MAS Credentials
        EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
        export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
        export MAS_PASSWORD=`oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .data.password | base64 -d`
        export MAS_USERNAME=`oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .data.username | base64 -d`
        export MAS_ADMIN_URL=`oc get route ${MAS_INSTANCE_ID}-admin -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .status.ingress[0].host`
        export INFRAID=`cat /root/install-dir/metadata.json  | jq -r .infraID`"-mas-creds"
        echo `date "+%Y/%m/%d %H:%M:%S"` "Creating secret for MAS Admin console in Secrets Manager  .........  " $INFRAID
        aws secretsmanager create-secret \
        --name $INFRAID \
        --description "MAS Admin Console credentials" \
        --secret-string "{\"user\":\"${MAS_USERNAME}\",\"password\":\"${MAS_PASSWORD}\",\"consoleurl\":\"${MAS_ADMIN_URL}\"}" \
        --region $AWS_DEFAULT_REGION
fi
