#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 AWS_SECRET_ARN_IBM_ENTITLEMENT_KEY"
    exit
fi

EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

export SECRET_ARN=$1
export IBM_ENTITLEMENT_KEY=`aws secretsmanager get-secret-value --secret-id $SECRET_ARN --region $AWS_DEFAULT_REGION | jq -r ."SecretString"`

export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig

echo `date "+%Y/%m/%d %H:%M:%S"` "Deploying Maximo Manage on MAS"
# Deploy Maximo Manage Application
export ROLE_NAME=suite_app_install export MAS_APP_ID=manage && export MAS_APP_CHANNEL="8.6.x" && export MAS_WORKSPACE_ID=masdev && ansible-playbook ibm.mas_devops.run_role