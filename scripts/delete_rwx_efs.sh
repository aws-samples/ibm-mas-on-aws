#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Trap the SIGINT signal (Ctrl+C)
trap ctrl_c INT

function ctrl_c() {
    echo "Stopping the script..."
    exit 1
}

if [[ $# -ne  1 ]]; then
        echo "Usage: $0 CLUSTERNAME"
        exit
fi

CLUSTER_NAME=$1

## Fetch current AWS region
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
export IPI_REGION=$AWS_DEFAULT_REGION
## Fetch the VPC where the installation must progress
export VPCID=`aws ec2 describe-vpcs --region ${IPI_REGION} --query 'Vpcs[?(Tags[?contains(Key,'\'${CLUSTER_NAME}\'' )])].VpcId' --output text`
echo `date "+%Y/%m/%d %H:%M:%S"` "VPC ID = " $VPCID
## Fetch the security group for the worker EC2 instances and authorize ingress to EFS from the worker nodes
export WORKERSGID=`aws ec2 describe-security-groups --region ${IPI_REGION} --filters Name=vpc-id,Values=${VPCID} Name=tag:Name,Values='*worker*' --query "SecurityGroups[*].{ID:GroupId}[0]" --output text`
echo `date "+%Y/%m/%d %H:%M:%S"` "Workers Security Group ID = " $WORKERSGID
echo `date "+%Y/%m/%d %H:%M:%S"` "Revoking Security group ingress"
aws ec2 revoke-security-group-ingress --group-id ${WORKERSGID} --source-group ${WORKERSGID} --protocol tcp --port 2049

EFSID=`aws efs describe-file-systems --region ${IPI_REGION}  --creation-token mas_devops.${CLUSTER_NAME} --query 'FileSystems[0].FileSystemId' --output text`
## Delete the Mount Targets
MOUNT_TARGET_IDS=`aws efs describe-mount-targets --file-system-id  ${EFSID} --query 'MountTargets[].MountTargetId' --output text`
for MOUNT_TARGET_ID in ${MOUNT_TARGET_IDS}; do aws efs delete-mount-target --mount-target-id ${MOUNT_TARGET_ID}; done

echo `date "+%Y/%m/%d %H:%M:%S"` "Wait for EFS mount targets to be deleted"
while [[ `aws efs describe-mount-targets --file-system-id  ${EFSID} --query 'MountTargets[].MountTargetId' --output text` != '' ]]; do sleep 10; done

echo `date "+%Y/%m/%d %H:%M:%S"` "Deleting EFS Filesystems"
aws efs delete-file-system --file-system-id ${EFSID}