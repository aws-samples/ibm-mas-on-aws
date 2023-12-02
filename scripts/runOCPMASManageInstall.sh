#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/root/ocp_mas_provisining.log 2>&1

fetch_secret() {
        json=`aws secretsmanager get-secret-value --secret-id ${1} --region ${2}`
        ibmentitlementkey=`echo $json | jq -r .SecretString | jq -r .ibmentitlementkey`
        echo $ibmentitlementkey
}
# Main
if [[ $# -ne 8 ]]; then
        echo "Usage: $0 \"BUCKETNAME\" \"CLUSTER_NAME\" \"BASE_DOMAIN\" \"IBM_ENTITLEMENT_KEY_ARN\"  \"UDS_CONTACT_EMAIL\" \"UDS_CONTACT_FIRSTNAME\" \"UDS_CONTACT_LASTNAME\" \"SLS_LICENSE_ID\""
        exit
fi

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone -H "X-aws-ec2-metadata-token: $TOKEN"`
export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

export IBM_ENTITLEMENT_KEY=`fetch_secret ${4} ${AWS_DEFAULT_REGION}`

# deploy_cluster.sh
# This script creates a RedHat OCP Cluster using the openshift-install utility
if [[ ! -f /root/install-dir/metadata.json ]]; then
    /root/ibm-mas-on-aws/scripts/deploy_cluster.sh ${1} ${2} ${3}
    if [[ $? -ne 0 ]]; then
        echo `date "+%Y/%m/%d %H:%M:%S"` "[ERROR]: Failed to create an RHOCP cluster"
        exit 1
    fi
fi

# create_efs_rwx_sc.sh
# This script creates a RedHat OCP Cluster using the openshift-install utility
/root/ibm-mas-on-aws/scripts/create_efs_rwx_sc.sh ${2} ${3}
if [[ $? -ne 0 ]]; then
    echo `date "+%Y/%m/%d %H:%M:%S"` "[ERROR]   Failed creation of EFS filesystem"
    exit 1
fi

# pending_oc_updates.sh
# This script applies pending oc updates to the RH OCP cluster
/root/ibm-mas-on-aws/scripts/pending_oc_updates.sh ${1} ${2} ${3}
if [[ $? -ne 0 ]]; then
    echo `date "+%Y/%m/%d %H:%M:%S"` "[ERROR]   Failed while applying pending openshift updates"
    exit 1
fi

# deploy_mascore.sh
# This script deploys MAS core on RH OCP Cluster
#/root/ibm-mas-on-aws/scripts/deploy_mascore.sh ${IBM_ENTITLEMENT_KEY} ${5} ${6} ${7} ${8}
#if [[ $? -ne 0 ]]; then
#    echo `date "+%Y/%m/%d %H:%M:%S"` "[ERROR]   Could not deploy MAS Core on RH OCP"
#    exit 1
#fi


# add_maximo_manage.sh
# This script deploys MAS Manage on Maximo Application Suite
#/root/ibm-mas-on-aws/scripts/add_maximo_manage.sh ${IBM_ENTITLEMENT_KEY}
#if [[ $? -ne 0 ]]; then
#    echo `date "+%Y/%m/%d %H:%M:%S"` "[ERROR]  Could not deploy Maximo Manage"
#    exit 1
#fi

echo `date "+%Y/%m/%d %H:%M:%S"` "Please configure your Maximo Database and then Activate Maximo Manage in Maximo Application Suite Administration Console"
# Exit
exit 0