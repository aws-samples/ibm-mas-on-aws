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
if [[ $# -ne 2 ]]; then
        echo "Usage: $0 CLUSTER_NAME IBM_ENTITLEMENT_SECRET_ARN "
        exit
fi

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone -H "X-aws-ec2-metadata-token: $TOKEN"`
export AWS_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"

# Cluster Name
export CLUSTERNAME=$1
# Entitlement Key secret ARN
export IBM_ENTITLEMENT_SECRET_ARN=$2
export IBM_ENTITLEMENT_KEY=`aws secretsmanager get-secret-value --secret-id $IBM_ENTITLEMENT_SECRET_ARN --region $AWS_REGION | jq -r ."SecretString"`
export CLUSTERTYPE=`oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.resourceTags}{"\n"}'| jq -r '.[] | select(.key == "red-hat-clustertype") | .value'`

if [[ -z $CLUSTERTYPE ]]; then
    echo `date "+%Y/%m/%d %H:%M:%S"` "Creating new machineset for worker-gpu"
    # Note: Here we are only creating a single Machineset for GPU. Recommended to perform this for each AZ.
    export SOURCE_MACHINESET=$(oc get machineset -n openshift-machine-api -o name | grep 'worker' | head -1)
    oc get -o json -n openshift-machine-api $SOURCE_MACHINESET > /tmp/source-machineset.json
    export OLD_MACHINESET_NAME=$(jq '.metadata.name' -r /tmp/source-machineset.json )
    export NEW_MACHINESET_NAME=${OLD_MACHINESET_NAME/worker/worker-gpu}
    jq -r '.spec.template.spec.providerSpec.value.instanceType = "g4dn.2xlarge"
    | del(.metadata.selfLink)
    | del(.metadata.uid)
    | del(.metadata.creationTimestamp)
    | del(.metadata.resourceVersion)
    ' /tmp/source-machineset.json > /tmp/gpu-machineset1.json
    sed -i "s/$OLD_MACHINESET_NAME/$NEW_MACHINESET_NAME/g" /tmp/gpu-machineset1.json
    # OCP -- Create a new machineset for GPU with g4dn.2xlarge EC2 instance type
    oc create -f /tmp/gpu-machineset1.json
else
    # ROSA cluster
    rosa create machinepool --cluster=$CLUSTERNAME --name=$CLUSTERNAME-gpu --replicas=3 --instance-type=g4dn.2xlarge --labels=app=mvi --region $AWS_REGION
    echo `date "+%Y/%m/%d %H:%M:%S"` "Wait for 60 seconds before proceeding to check number of machines in Running state"
    sleep 60
fi
# Wait until worker-gpu is Running
echo `date "+%Y/%m/%d %H:%M:%S"` "Wait until machine is in a state running"

while [[ `oc get machines -n openshift-machine-api | awk '{print $2}'|wc -l` -ne `oc get machines -n openshift-machine-api | awk '{print $2}' | grep Running|wc -l`+1 ]]; do
    sleep 5
done

echo `date "+%Y/%m/%d %H:%M:%S"` "Wait until the new node is in a state Ready"
while [[ `oc get nodes | grep 'NotReady'| wc -l` -gt 0 ]]; do  sleep 5; done

echo `date "+%Y/%m/%d %H:%M:%S"` "Setting the env variables and initiating installation"
export MAS_APP_SETTINGS_VISUALINSPECTION_STORAGE_CLASS=efs$CLUSTERNAME # Must be RWX storage class and named efs$CLUSTERNAME
export MAS_APP_SETTINGS_VISUALINSPECTION_STORAGE_SIZE=100Gi
export MAS_WORKSPACE_ID=masdev
export MAS_INSTANCE_ID=masinst1
export MAS_CONFIG_DIR=/root/install-dir/masconfig/

ansible-playbook ibm.mas_devops.oneclick_add_visualinspection