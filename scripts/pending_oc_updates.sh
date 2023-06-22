#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

if [[ $# -ne  3 ]]; then
        echo "Usage: $0 BUCKETNAME CLUSTERNAME BASEDOMAIN"
        exit
fi

export BUCKETNAME=$1
export CLUSTER_NAME=$2
export BASE_DOMAIN=$3
#export OCP_USERNAME=kubeadmin
#export OCP_PASSWORD=`cat /root/install-dir/auth/kubeadmin-password`

## Fetch current AWS region
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
export AWS_DEFAULT_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
export IPI_REGION=$AWS_DEFAULT_REGION

echo `date "+%Y/%m/%d %H:%M:%S"` "Copy container runtime config yaml"
aws s3 cp s3://${BUCKETNAME}/container-runtime-config.yml /root/install-dir/container-runtime-config.yml --region ${IPI_REGION}

echo `date "+%Y/%m/%d %H:%M:%S"` "Sleeping before connecting to OCP Cluster using oc"
sleep 10

oc create -f /root/install-dir/container-runtime-config.yml --kubeconfig /root/install-dir/auth/kubeconfig

## Fetch the VPC where the Load Balancer has been created by the openshift-install program
export VPCID=`aws ec2 describe-vpcs --region ${IPI_REGION} --query 'Vpcs[?(Tags[?contains(Key,'\'${CLUSTER_NAME}\'' )])].VpcId' --output text`
echo `date "+%Y/%m/%d %H:%M:%S"` "VPC ID = " $VPCID

## Fetch the update-elb-timeout.sh for aws from ibm-mas/multicloud-bootstrap
wget -q https://raw.githubusercontent.com/ibm-mas/multicloud-bootstrap/main/aws/ocp-terraform/ocp/scripts/update-elb-timeout.sh -P /root/install-dir/
chmod +x /root/install-dir/update-elb-timeout.sh

oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true,"replicas":3}}'  -n openshift-image-registry --kubeconfig /root/install-dir/auth/kubeconfig
oc patch svc/image-registry -p '{"spec":{"sessionAffinity": "ClientIP"}}' -n openshift-image-registry --kubeconfig /root/install-dir/auth/kubeconfig
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"managementState":"Unmanaged"}}' --kubeconfig /root/install-dir/auth/kubeconfig
echo `date "+%Y/%m/%d %H:%M:%S"` "Sleeping for 3 minutes before adding annotations to default-route"
sleep 3m
oc annotate route default-route haproxy.router.openshift.io/timeout=600s -n openshift-image-registry --kubeconfig /root/install-dir/auth/kubeconfig
oc set env deployment/image-registry -n openshift-image-registry REGISTRY_STORAGE_S3_CHUNKSIZE=1048576000 --kubeconfig /root/install-dir/auth/kubeconfig
echo `date "+%Y/%m/%d %H:%M:%S"` "Sleeping for 2 minutes before altering the timeout on Classic Load balancer to 10 mins"
sleep 2m

/root/install-dir/update-elb-timeout.sh $VPCID 600
exit 0