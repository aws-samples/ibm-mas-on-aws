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

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 AWS_SECRET_ARN_IBM_ENTITLEMENT_KEY"
    exit
fi

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone -H "X-aws-ec2-metadata-token: $TOKEN"`

export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

export SECRET_ARN=$1
export IBM_ENTITLEMENT_KEY=`aws secretsmanager get-secret-value --secret-id $SECRET_ARN --region $AWS_DEFAULT_REGION | jq -r ."SecretString"`

export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig

echo `date "+%Y/%m/%d %H:%M:%S"` "Deploying Maximo Manage on MAS"
# Deploy Maximo Manage Application
export ROLE_NAME=suite_app_install export MAS_APP_ID=manage && export MAS_APP_CHANNEL="8.7.x" && export MAS_WORKSPACE_ID=masdev && ansible-playbook ibm.mas_devops.run_role