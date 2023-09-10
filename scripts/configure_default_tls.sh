#!/bin/bash
#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Make sure certbot utility is installed:
certbot --version >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "certbot has been already installed."
else
  sudo python3 -m venv /opt/certbot/
  sudo /opt/certbot/bin/pip install --upgrade pip
  sudo /opt/certbot/bin/pip install certbot certbot-route53
  sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot  
fi

# Creates a TLS certificate based on the OpenShift cluster and MAS configurations:
TMPFILE=$(mktemp /tmp/foo-XXXXXXXX)
echo 'sudo certbot certonly \
--dns-route53 \
--agree-tos \
--email domain-owner@youremail.com \' > $TMPFILE  # use your own 

oc get route -A | \
  awk 'NR>1 {print $3}' | \
    awk '\
      BEGIN  { FS="." } \
      { sub($1,"*"); print "-d",$0,"\\" }' | sort| uniq >> $TMPFILE

echo ' -n' >> $TMPFILE 

echo "Creating the cert. It might take several seconds:"
cat $TMPFILE
sudo chmod +x $TMPFILE
$TMPFILE

# Create an OpenShift secret, and use it as the default TLS certificate for the cluster:
DOMAIN=`sudo ls /etc/letsencrypt/live/ | grep -v README`
PKEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
CLUSTER_DEFAULT_TLS_CERT="cluster-default-tls-cert"
sudo cp $CERT /tmp/CERT.crt
sudo cp $PKEY /tmp/PKEY.key
sudo chown $USER /tmp/CERT.crt 
sudo chown $USER /tmp/PKEY.key 
oc create secret tls cluster-default-tls-cert --key=/tmp/PKEY.key --cert=/tmp/CERT.crt -n openshift-ingress
oc patch -n openshift-ingress-operator ingresscontroller/default -p '{"spec":{"defaultCertificate":{"name": "cluster-default-tls-cert"}}}' --type=merge

# Verify the validity of the certificate:
echo "Please wait for 30 seconds (sometimes more) until the Ingress Controller is stabalized..."
sleep 30
curl -vI https://console-openshift-console.apps.`oc cluster-info | head -1 | cut -f2- -d. | cut -f1 -d:` 2>&1 | grep issuer >/dev/null
if [ $? -eq 0 ]; then
  echo "Great job! The TLS certificate has been installed successfully."
else
  echo "WARNING: TLS configuration was NOT successfull..."
fi
