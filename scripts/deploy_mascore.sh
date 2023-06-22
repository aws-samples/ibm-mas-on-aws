#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 CLUSTER_NAME AWS_SECRET_ARN_IBM_ENTITLEMENT_KEY"
    exit
fi
echo `date "+%Y/%m/%d %H:%M:%S"` "Setting up the environment variables for MASCore Deployment"
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
# The MongoDB role in ansible automation requires the AWS_REGION to be set
export AWS_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

export SECRET_ARN=$2
export IBM_ENTITLEMENT_KEY=`aws secretsmanager get-secret-value --secret-id $SECRET_ARN --region $AWS_REGION | jq -r ."SecretString"`

export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig
export MONGODB_PROVIDER=aws
export MONGODB_ACTION=install
export CLUSTER_NAME=$1


export VPC_ID=`aws ec2 describe-vpcs --region ${AWS_REGION} --query 'Vpcs[?(Tags[?contains(Key,'\'${CLUSTER_NAME}\'' )])].VpcId' --output text --region $AWS_REGION`
export DOCDB_CLUSTER_NAME=docnonmp
export DOCDB_INSTANCE_IDENTIFIER_PREFIX=docnonmp

export DOCDB_CIDR_AZ1=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private-ap-southeast-2a*" --query 'Subnets[0].CidrBlock' --output text --region $AWS_REGION`
export DOCDB_CIDR_AZ2=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private-ap-southeast-2b*" --query 'Subnets[0].CidrBlock' --output text --region $AWS_REGION`
export DOCDB_CIDR_AZ3=`aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private-ap-southeast-2c*" --query 'Subnets[0].CidrBlock' --output text --region $AWS_REGION`
echo `date "+%Y/%m/%d %H:%M:%S"` "Fetched the CIDR ranges for Document DB Private SubnetIDs"

export SUBNET_ID_AZ1=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=$DOCDB_CIDR_AZ1" --query 'Subnets[0].SubnetId' --output text --region $AWS_REGION)
export SUBNET_ID_AZ2=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=$DOCDB_CIDR_AZ2" --query 'Subnets[0].SubnetId' --output text --region $AWS_REGION)
export SUBNET_ID_AZ3=$(aws ec2 describe-subnets --filters "Name=cidr-block,Values=$DOCDB_CIDR_AZ3" --query 'Subnets[0].SubnetId' --output text --region $AWS_REGION)
echo `date "+%Y/%m/%d %H:%M:%S"` "Fetched the Private SubnetIDs where the Document DB will be installed"

export TAGNAME_SUBNET_ID_AZ1=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$SUBNET_ID_AZ1" "Name=key,Values=Name" --query 'Tags[0].Value' --output text --region $AWS_REGION)
export TAGNAME_SUBNET_ID_AZ2=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$SUBNET_ID_AZ2" "Name=key,Values=Name" --query 'Tags[0].Value' --output text --region $AWS_REGION)
export TAGNAME_SUBNET_ID_AZ3=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$SUBNET_ID_AZ3" "Name=key,Values=Name" --query 'Tags[0].Value' --output text --region $AWS_REGION)
echo `date "+%Y/%m/%d %H:%M:%S"` "Fetched the Tagnames that need to be restored post Document DB installation"

# Update the tags to $DOCDB_CLUSTER_NAME because the mongo role needs it. We will reset this back later
aws ec2 create-tags --resources $SUBNET_ID_AZ1 --tags Key="Name",Value=$DOCDB_CLUSTER_NAME --region $AWS_REGION
aws ec2 create-tags --resources $SUBNET_ID_AZ2 --tags Key="Name",Value=$DOCDB_CLUSTER_NAME --region $AWS_REGION
aws ec2 create-tags --resources $SUBNET_ID_AZ3 --tags Key="Name",Value=$DOCDB_CLUSTER_NAME --region $AWS_REGION
echo `date "+%Y/%m/%d %H:%M:%S"` "Set the Tagnames for the private subnets to $DOCDB_CLUSTER_NAME"

# This is to allow the Ingress and Egress trafic to the VPC CIDR
export DOCDB_INGRESS_CIDR=`aws ec2 describe-vpcs --region ${AWS_REGION} --query 'Vpcs[?(Tags[?contains(Key,'\'${CLUSTER_NAME}\'' )])].CidrBlock' --output text`
export DOCDB_EGRESS_CIDR=$DOCDB_INGRESS_CIDR
export MONGODB_RETRY_WRITES=false

export SLS_LICENSE_FILE=/root/install-dir/entitlement.lic
export SLS_LICENSE_ID=`head -1 $SLS_LICENSE_FILE| cut -d" " -f3`
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
#export MONGODB_STORAGE_CLASS="gp2" # Required if MongoDB Storage class is community
export UDS_STORAGE_CLASS="gp2"

echo `date "+%Y/%m/%d %H:%M:%S"` "Installing the MAS Operator on the OCP Cluster"
# Install the MAS Operator
ansible-playbook ibm.mas_devops.oneclick_core

# Reset the Subnet ID tagnames back to original
aws ec2 create-tags --resources $SUBNET_ID_AZ1 --tags Key="Name",Value=$TAGNAME_SUBNET_ID_AZ1 --region $AWS_REGION
aws ec2 create-tags --resources $SUBNET_ID_AZ2 --tags Key="Name",Value=$TAGNAME_SUBNET_ID_AZ2 --region $AWS_REGION
aws ec2 create-tags --resources $SUBNET_ID_AZ3 --tags Key="Name",Value=$TAGNAME_SUBNET_ID_AZ3 --region $AWS_REGION

# Create a secret with the MAS Admin console secrets
if [[ $? -ne 0 ]]; then
        echo `date "+%Y/%m/%d %H:%M:%S"` "Installation of MAS core failed"
        exit 1
else
        # Create a secret with MAS Credentials
        EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
        export AWS_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
        export MAS_PASSWORD=`oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .data.password | base64 -d`
        export MAS_USERNAME=`oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .data.username | base64 -d`
        export MAS_ADMIN_URL=`oc get route ${MAS_INSTANCE_ID}-admin -n mas-${MAS_INSTANCE_ID}-core -o yaml | yq -r .status.ingress[0].host`
        export INFRAID=`cat /root/install-dir/metadata.json  | jq -r .infraID`"-mas-creds"
        echo `date "+%Y/%m/%d %H:%M:%S"` "Creating secret for MAS Admin console in Secrets Manager  .........  " $INFRAID
        aws secretsmanager create-secret \
        --name $INFRAID \
        --description "MAS Admin Console credentials" \
        --secret-string "{\"user\":\"${MAS_USERNAME}\",\"password\":\"${MAS_PASSWORD}\",\"consoleurl\":\"${MAS_ADMIN_URL}\"}" \
        --region $AWS_REGION
fi