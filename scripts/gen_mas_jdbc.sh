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

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 MAS_JDBC_USER MAS_JDBC_PASSWORD MAS_JDBC_URL"
    exit
fi
echo `date "+%Y/%m/%d %H:%M:%S"` "Certificate File ..... " $4
echo `date "+%Y/%m/%d %H:%M:%S"` "JDBC Url ......... " $3

## Fetch current AWS region
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone -H "X-aws-ec2-metadata-token: $TOKEN"`
export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

#aws s3 cp $4 /root/install-dir/db_cert.pem --region ${AWS_DEFAULT_REGION}
export MAS_INSTANCE_ID=masinst1
export MAS_WORKSPACE_ID=masdev
export MAS_JDBC_USER=$1
export MAS_JDBC_PASSWORD=$2
export MAS_JDBC_URL=$3
export MAS_JDBC_CERT_LOCAL_FILE="/root/install-dir/${AWS_DEFAULT_REGION}-bundle.pem"
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
if [[ -f /root/install-dir/auth/kubeconfig ]]; then 
    oc create -f /root/install-dir/masconfig/jdbc.yml --kubeconfig /root/install-dir/auth/kubeconfig
else
    oc create -f /root/install-dir/masconfig/jdbc.yml
fi