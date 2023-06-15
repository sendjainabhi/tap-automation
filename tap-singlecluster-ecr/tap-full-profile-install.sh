#!/bin/bash

TAP_VERSION=1.5.2-build.1
GIT_CATALOG_REPOSITORY=tanzu-application-platform
INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
TARGET_TBS_REPO=tap-build-service

tap_git_catalog_url=https://github.com/sendjainabhi/tap/blob/main/catalog-info.yaml

FULL_DOMAIN="full.ab-tap.customer.io"


#RESET AN EXISTING INSTALLATION
#tanzu package installed delete ootb-supply-chain-testing-scanning -n tap-install --yes
#tanzu package installed delete ootb-supply-chain-testing -n tap-install --yes
#tanzu package installed delete tap -n tap-install --yes

# 8. INSTALL FULL TAP PROFILE
echo
echo "<<< INSTALLING FULL TAP PROFILE >>>"
echo

#GENERATE VALUES
#rm tap-values-full.yaml
cat <<EOF | tee tap-values-full.yaml
profile: full
ceip_policy_disclosed: true

excluded_packages:
  - policy.apps.tanzu.vmware.com 

shared:
  ingress_domain: "$FULL_DOMAIN"
supply_chain: basic
ootb_supply_chain_basic:
  registry:
    server: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    repository: "tanzu-application-platform"
buildservice:
  kp_default_repository: ${AWS_ACCOUNT_ID}.dkr.ecr.$AWS_REGION.amazonaws.com/tap-build-service
  kp_default_repository_aws_iam_role_arn: "arn:aws:iam::${AWS_ACCOUNT_ID}:role/tap-build-service"
contour:
  envoy:
    service:
      type: LoadBalancer
ootb_templates:
  # Enable the config writer service to use cloud based iaas authentication
  # which are retrieved from the developer namespace service account by
  # default
  iaas_auth: true
tap_gui:
  service_type: ClusterIP
  app_config:
    catalog:
      locations:
        - type: url
          target: ${tap_git_catalog_url}
metadata_store:
  ns_for_export_app_cert: "default"
  app_service_type: ClusterIP # Defaults to LoadBalancer. If shared.ingress_domain is set earlier, this must be set to ClusterIP.
scanning:
  metadataStore:
    url: ""
grype:
  namespace: "default"
  #targetImagePullSecret: "registry-credentials"
cnrs:
  domain_name: $FULL_DOMAIN

 
EOF

tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file tap-values-full.yaml -n tap-install
echo

rm source-controller-values.yaml
cat <<EOF | tee source-controller-values.yaml
aws_iam_role_arn: "eks.amazonaws.com/role-arn: arn:aws:iam::$AWS_ACCOUNT_ID:role/tap-workload"
EOF

#tanzu package install source-controller -p controller.source.apps.tanzu.vmware.com \
 # --values-file source-controller-values.yaml -v 0.63 -n tap-install
echo


# 9. DEVELOPER NAMESPACE
#https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.4/tap/scc-ootb-supply-chain-basic.html
echo
echo "<<< CREATING DEVELOPER NAMESPACE >>>"
echo

#do we need create this ? 
tanzu secret registry add registry-credentials \
  --server $INSTALL_REGISTRY_HOSTNAME \
  --username "AWS" \
  --password "$INSTALL_REGISTRY_HOSTNAME" \
  --namespace default

#rm rbac-dev.yaml
cat <<EOF | tee rbac-dev.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::$AWS_ACCOUNT_ID:role/tap-workload"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-deliverable
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deliverable
subjects:
  - kind: ServiceAccount
    name: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: default-permit-workload
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workload
subjects:
  - kind: ServiceAccount
    name: default
EOF

kubectl apply -f rbac-dev.yaml


# 10. CONFIGURE DNS NAME WITH ELB IP
echo
echo "<<< CONFIGURING DNS in route53 with elb ip >>>"
echo

