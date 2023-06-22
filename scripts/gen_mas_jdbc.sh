#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 MAS_JDBC_USER MAS_JDBC_PASSWORD MAS_JDBC_URL S3URI_CERTPEM_FILE"
    exit
fi
echo `date "+%Y/%m/%d %H:%M:%S"` "Certificate File ..... " $4
echo `date "+%Y/%m/%d %H:%M:%S"` "JDBC Url ......... " $3

## Fetch current AWS region
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

aws s3 cp $4 /root/install-dir/db_cert.pem --region ${AWS_DEFAULT_REGION}
export MAS_INSTANCE_ID=masinst1
export MAS_WORKSPACE_ID=masdev
export MAS_JDBC_USER=$1
export MAS_JDBC_PASSWORD=$2
export MAS_JDBC_URL=$3
export MAS_JDBC_CERT_LOCAL_FILE="/root/install-dir/db_cert.pem"
export MAS_CONFIG_SCOPE=wsapp
export MAS_APP_ID=manage
export MAS_CONFIG_DIR="/root/install-dir/masconfig"
export SSL_ENABLED=True

echo `date "+%Y/%m/%d %H:%M:%S"` "Installing the MAS Operator on the OCP Cluster"
# Configure JDBC URL
export ROLE_NAME=gencfg_jdbc && ansible-playbook ibm.mas_devops.run_role

echo `date "+%Y/%m/%d %H:%M:%S"` "Sleeping for 10 before connecting using oc"
sleep 10
## Apply the jdbc in the masdev-Manage workspace app scope
oc create -f /root/install-dir/masconfig/jdbc.yml --kubeconfig /root/install-dir/auth/kubeconfig