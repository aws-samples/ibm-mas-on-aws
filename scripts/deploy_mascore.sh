#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 IBM_ENTITLEMENT_KEY UDS_CONTACT_EMAIL UDS_CONTACT_FIRSTNAME UDS_CONTACT_LASTNAME SLS_LICENSE_ID"
    exit
fi

export IBM_ENTITLEMENT_KEY=$1
export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig

export SLS_LICENSE_ID=$5
export SLS_LICENSE_FILE=/root/install-dir/entitlement.lic

export UDS_CONTACT_EMAIL=$2
export UDS_CONTACT_FIRSTNAME=$3
export UDS_CONTACT_LASTNAME=$4

export PROMETHEUS_ALERTMGR_STORAGE_CLASS="efs"
export PROMETHEUS_STORAGE_CLASS="gp2"
export PROMETHEUS_USERWORKLOAD_STORAGE_CLASS="gp2"
export GRAFANA_INSTANCE_STORAGE_CLASS="gp2"
export MONGODB_STORAGE_CLASS="gp2"
export UDS_STORAGE_CLASS="gp2"

echo `date "+%Y/%m/%d %H:%M:%S"` "Installing the MAS Operator on the OCP Cluster"
# Install the MAS Operator

# Below lines are added to add the kubeconfig parameter to the end of the oc adm policy add-scc-to-user. Else it errors when running the oneclick_core playbook via Systems Manager Run Command
#echo `date "+%Y/%m/%d %H:%M:%S"` "Altering mongodb community.yml to include kubeconfig"
#cp /root/.ansible/collections/ansible_collections/ibm/mas_devops/roles/mongodb/tasks/providers/community.yml /root/.ansible/collections/ansible_collections/ibm/mas_devops/roles/mongodb/tasks/providers/community.yml.bkup
#sed '/oc adm policy add-scc-to-user/ s/$/ --kubeconfig \/root\/install-dir\/auth\/kubeconfig/' /root/.ansible/collections/ansible_collections/ibm/mas_devops/roles/mongodb/tasks/providers/community.yml > /root/.ansible/collections/ansible_collections/ibm/mas_devops/roles/mongodb/tasks/providers/community.yml

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
