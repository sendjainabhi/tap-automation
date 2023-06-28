#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

#get route 53 zone id and trim it to get exact zone id
hosted_zone_id=$(
  aws route53 list-hosted-zones \
    --output text \
    --query 'HostedZones[?Name==`'$domain_name_route53'.`].Id'
)
#string trimming for exact zone id
hosted_zone_id="${hosted_zone_id:12:${#hosted_zone_id}}"

echo $hosted_zone_id


#retrive ingress lb - 
ingress_lb=$(kubectl get svc server -n tap-gui  -o json | jq -r .status.loadBalancer.ingress | jq '.[]'.hostname) 

#tapgui_lb=$(kubectl get svc server -n tap-gui  -o json | jq -r .status.loadBalancer.ingress | jq '.[]'.hostname) 


#remove double quote from string (lb) 
ingress_lb=$(sed -e 's/^"//' -e 's/"$//' <<<"$ingress_lb")
echo $ingress_lb

rm -r $change_batch_filename.json
change_batch_filename=change-batch-$RANDOM

cat <<EOF | tee $change_batch_filename.json
{
    "Comment": "Update record.",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "*.$tap_domain",
                "Type": "CNAME",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$ingress_lb"
                    }
                ]
            }
        }
    ]
}

EOF

echo $change_batch_filename.json

aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file://./$change_batch_filename.json

