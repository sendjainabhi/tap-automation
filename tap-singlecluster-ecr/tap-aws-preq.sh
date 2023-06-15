#!/bin/bash
source var.conf

#export FULL_DOMAIN="full.ab-tap.customer.io"

#create a tmp file for now
#echo $full_domain > /tmp/tap-full-domain

#export EKS_CLUSTER_NAME=tap-full
#export TANZU_CLI_NO_INIT=true
#export TANZU_VERSION=v0.28.1
#export TAP_VERSION=1.5.2-build.1
#export TANZU_NET_API_TOKEN= 
#export AWS_REGION= us-east-1 
#export AWS_ACCOUNT_ID= 

#export CLI_FILENAME=tanzu-framework-linux-amd64-v0.28.1.tar
#export ESSENTIALS_FILENAME=tanzu-cluster-essentials-linux-amd64-1.5.0.tgz

#export TANZUNET_USERNAME=?
#export TANZUNET_PASSWORD= ?



export EKS_CLUSTER_NAME=tap-full
export TANZU_CLI_NO_INIT=true
export TANZU_VERSION=v0.28.1
export TAP_VERSION=1.5.2-build.1

export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=<aws account id>

export CLI_FILENAME=tanzu-framework-linux-amd64-v0.28.1.tar
export ESSENTIALS_FILENAME=tanzu-cluster-essentials-linux-amd64-1.5.0.tgz

export TANZUNET_USERNAME=abhishekja@vmware.com
export TANZUNET_PASSWORD=<tanzu net password>
export TANZU_NET_API_TOKEN=<<tanzu net token>>

export FULL_DOMAIN="full.ab-tap.customer.io"
export K8_Version=1.25
export K8_INST_TYPE=t3.xlarge


export token=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":"'${TANZU_NET_API_TOKEN}'"}')
access_token=$(echo ${token} | jq -r .access_token)

curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer ${access_token}" -X GET https://network.pivotal.io/api/v2/authentication

# 1. CREATE CLUSTER
echo
echo "<<< CREATING CLUSTER >>>"
echo

eksctl create cluster --name $EKS_CLUSTER_NAME --managed --region $AWS_REGION --instance-types $K8_INST_TYPE --version $K8_Version --with-oidc -N 3

rm $HOME/.kube/config

#configure kubeconfig
arn=arn:aws:eks:$AWS_REGION:$AWS_ACCOUNT_ID':cluster'

aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

kubectl config rename-context $arn/$EKS_CLUSTER_NAME $EKS_CLUSTER_NAME

kubectl config use-context $EKS_CLUSTER_NAME


# 2. INSTALL CSI PLUGIN (REQUIRED FOR K8S 1.23+)
echo
echo "<<< INSTALLING CSI PLUGIN >>>"
echo



#https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html

rolename=$EKS_CLUSTER_NAME-csi-driver-role

aws eks create-addon --cluster-name $EKS_CLUSTER_NAME --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID':role/'$rolename
   

#https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
oidc_id=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | awk -F '/' '{print $5}')

# Check if a IAM OIDC provider exists for the cluster
# https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
if [[ -z $(aws iam list-open-id-connect-providers | grep $oidc_id) ]]; then
    echo "Creating IAM OIDC provider"
    if ! [ -x "$(command -v eksctl)" ]; then
    echo "Error `eksctl` CLI is required, https://eksctl.io/introduction/#installation" >&2
    exit 1
    fi

    eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
fi

 export OIDCPROVIDER=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION | jq '.cluster.identity.oidc.issuer' | tr -d '"' | sed 's/https:\/\///')

cat << EOF > aws-ebs-csi-driver-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDCPROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDCPROVIDER}:aud": "sts.amazonaws.com",
          "${OIDCPROVIDER}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

  cat aws-ebs-csi-driver-trust-policy.json

aws iam create-role --role-name $rolename --assume-role-policy-document file://"aws-ebs-csi-driver-trust-policy.json"


aws iam attach-role-policy \
  --role-name $rolename \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

kubectl annotate serviceaccount ebs-csi-controller-sa \
    -n kube-system --overwrite \
    eks.amazonaws.com/role-arn=arn:aws:iam::$AWS_ACCOUNT_ID:role/$rolename

rm aws-ebs-csi-driver-trust-policy.json



# 5. RBAC FOR ECR FROM EKS CLUSTER
echo
echo "<<< CREATING IAM ROLES FOR ECR >>>"
echo


cat << EOF > build-service-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDCPROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDCPROVIDER}:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "${OIDCPROVIDER}:sub": [
                        "system:serviceaccount:kpack:controller",
                        "system:serviceaccount:build-service:dependency-updater-controller-serviceaccount"
                    ]
                }
            }
        }
    ]
}
EOF

cat << EOF > build-service-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ecr:DescribeRegistry",
                "ecr:GetAuthorizationToken",
                "ecr:GetRegistryPolicy",
                "ecr:PutRegistryPolicy",
                "ecr:PutReplicationConfiguration",
                "ecr:DeleteRegistryPolicy"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "TAPEcrBuildServiceGlobal"
        },
        {
            "Action": [
                "ecr:DescribeImages",
                "ecr:ListImages",
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:BatchGetRepositoryScanningConfiguration",
                "ecr:DescribeImageReplicationStatus",
                "ecr:DescribeImageScanFindings",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:GetRegistryScanningConfiguration",
                "ecr:GetRepositoryPolicy",
                "ecr:ListTagsForResource",
                "ecr:TagResource",
                "ecr:UntagResource",
                "ecr:BatchDeleteImage",
                "ecr:BatchImportUpstreamImage",
                "ecr:CompleteLayerUpload",
                "ecr:CreatePullThroughCacheRule",
                "ecr:CreateRepository",
                "ecr:DeleteLifecyclePolicy",
                "ecr:DeletePullThroughCacheRule",
                "ecr:DeleteRepository",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:PutImageScanningConfiguration",
                "ecr:PutImageTagMutability",
                "ecr:PutLifecyclePolicy",
                "ecr:PutRegistryScanningConfiguration",
                "ecr:ReplicateImage",
                "ecr:StartImageScan",
                "ecr:StartLifecyclePolicyPreview",
                "ecr:UploadLayerPart",
                "ecr:DeleteRepositoryPolicy",
                "ecr:SetRepositoryPolicy"
            ],
            "Resource": [
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-build-service",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-images"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrBuildServiceScoped"
        }
    ]
}
EOF

cat << EOF > workload-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ecr:DescribeRegistry",
                "ecr:GetAuthorizationToken",
                "ecr:GetRegistryPolicy",
                "ecr:PutRegistryPolicy",
                "ecr:PutReplicationConfiguration",
                "ecr:DeleteRegistryPolicy"
            ],
            "Resource": "*",
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadGlobal"
        },
        {
            "Action": [
                "ecr:DescribeImages",
                "ecr:ListImages",
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:BatchGetRepositoryScanningConfiguration",
                "ecr:DescribeImageReplicationStatus",
                "ecr:DescribeImageScanFindings",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetLifecyclePolicy",
                "ecr:GetLifecyclePolicyPreview",
                "ecr:GetRegistryScanningConfiguration",
                "ecr:GetRepositoryPolicy",
                "ecr:ListTagsForResource",
                "ecr:TagResource",
                "ecr:UntagResource",
                "ecr:BatchDeleteImage",
                "ecr:BatchImportUpstreamImage",
                "ecr:CompleteLayerUpload",
                "ecr:CreatePullThroughCacheRule",
                "ecr:CreateRepository",
                "ecr:DeleteLifecyclePolicy",
                "ecr:DeletePullThroughCacheRule",
                "ecr:DeleteRepository",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:PutImageScanningConfiguration",
                "ecr:PutImageTagMutability",
                "ecr:PutLifecyclePolicy",
                "ecr:PutRegistryScanningConfiguration",
                "ecr:ReplicateImage",
                "ecr:StartImageScan",
                "ecr:StartLifecyclePolicyPreview",
                "ecr:UploadLayerPart",
                "ecr:DeleteRepositoryPolicy",
                "ecr:SetRepositoryPolicy"
            ],
            "Resource": [
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tap-build-service",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform/tanzu-java-web-app-default",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform/tanzu-java-web-app-default-bundle",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform",
                "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/tanzu-application-platform/*"
            ],
            "Effect": "Allow",
            "Sid": "TAPEcrWorkloadScoped"
        }
    ]
}
EOF

cat << EOF > workload-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDCPROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDCPROVIDER}:sub": "system:serviceaccount:default:default",
                    "${OIDCPROVIDER}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF



# Create the Tanzu Build Service Role
aws iam create-role --role-name tap-build-service --assume-role-policy-document file://build-service-trust-policy.json
# Attach the Policy to the Build Role
aws iam put-role-policy --role-name tap-build-service --policy-name tapBuildServicePolicy --policy-document file://build-service-policy.json

# Create the Workload Role
aws iam create-role --role-name tap-workload --assume-role-policy-document file://workload-trust-policy.json
# Attach the Policy to the Workload Role
aws iam put-role-policy --role-name tap-workload --policy-name tapWorkload --policy-document file://workload-policy.json


rm build-service-trust-policy.json
rm build-service-policy.json
rm workload-trust-policy.json
rm workload-policy.json


# 6. TANZU PREREQS
# https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/1.5/tap/install-tanzu-cli.html
# https://network.tanzu.vmware.com/products/tanzu-application-platform#/releases/1287438/file_groups/12507
echo
echo "<<< INSTALLING TANZU AND CLUSTER ESSENTIALS >>>"
echo

export IMGPKG_REGISTRY_HOSTNAME_0=registry.tanzu.vmware.com
export IMGPKG_REGISTRY_USERNAME_0=$TANZUNET_USERNAME
export IMGPKG_REGISTRY_PASSWORD_0=$TANZUNET_PASSWORD
export IMGPKG_REGISTRY_HOSTNAME_1=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
export IMGPKG_REGISTRY_USERNAME_1=AWS
export IMGPKG_REGISTRY_PASSWORD_1=`aws ecr get-login-password --region $AWS_REGION`
export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$TANZUNET_USERNAME
export INSTALL_REGISTRY_PASSWORD=$TANZUNET_PASSWORD

export TARGET_TAP_REPO=tap-images
export TARGET_TBS_REPO=tap-build-service
export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446

rm -rf $HOME/tanzu
mkdir $HOME/tanzu

#tanzu cli
tanzucliurl_m=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1287412/product_files/1446071/download
tanzuclifilename_m=tanzu-framework-darwin-amd64.tar
tanzucliurl_l=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1287412/product_files/1446073/download
tanzuclifilename_l=tanzu-framework-linux-amd64.tar

#for mac , change filename and url for linux
wget $tanzucliurl_m --header="Authorization: Bearer $access_token" -O $HOME/tanzu/$tanzuclifilename_m
tar -xvf $HOME/tanzu/$tanzuclifilename_m -C $HOME/tanzu



install $HOME/tanzu/cli/core/$TANZU_VERSION/tanzu-core-darwin_amd64 /usr/local/bin/tanzu

cd $HOME/tanzu
tanzu plugin install --local cli all

tanzu version 

cd $HOME

# cluster essentials
# https://docs.vmware.com/en/Cluster-Essentials-for-VMware-Tanzu/1.5/cluster-essentials/deploy.html
# https://network.tanzu.vmware.com/products/tanzu-cluster-essentials/
rm -rf $HOME/tanzu-cluster-essentials
mkdir $HOME/tanzu-cluster-essentials

#tanzu essential 
export tanzu_ess_filename_m=tanzu-cluster-essentials-darwin-amd64-1.5.0.tgz
export tanzu_ess_filename_l=tanzu-cluster-essentials-linux-amd64-1.5.0.tgz
export tanzu_ess_url_m=https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1275537/product_files/1460874/download
export tanzu_ess_url_l=https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1275537/product_files/1460876/download

#for mac , change filename and url for linux
wget $tanzu_ess_url_m --header="Authorization: Bearer ${access_token}" -O $HOME/tanzu-cluster-essentials/$tanzu_ess_filename_m
tar -xvf $HOME/tanzu-cluster-essentials/$tanzu_ess_filename_m -C $HOME/tanzu-cluster-essentials

cd $HOME/tanzu-cluster-essentials
./install.sh --yes

sudo cp $HOME/tanzu-cluster-essentials/kapp /usr/local/bin/kapp
sudo cp $HOME/tanzu-cluster-essentials/imgpkg /usr/local/bin/imgpkg
   

cd $HOME

docker login $IMGPKG_REGISTRY_HOSTNAME_0 -u $IMGPKG_REGISTRY_USERNAME_0 -p $IMGPKG_REGISTRY_PASSWORD_0

rm $HOME/tanzu/$tanzuclifilename_m
rm $HOME/tanzu-cluster-essentials/$tanzu_ess_filename_m


# 7. IMPORT TAP PACKAGES
echo
echo "<<< IMPORTING TAP PACKAGES >>>"
echo

tap_images_ecr=$(aws ecr describe-repositories --query "repositories[?repositoryName=='tap-images'].repositoryName" --output text)

tap_build_service_ecr=$(aws ecr describe-repositories --query "repositories[?repositoryName=='tap-build-service'].repositoryName" --output text)

aws ecr get-login-password --region $AWS_REGION | docker login --username $IMGPKG_REGISTRY_USERNAME_1 --password-stdin $IMGPKG_REGISTRY_HOSTNAME_1

if [[ -z $tap_images_ecr ]]
then
  aws ecr create-repository --repository-name $TARGET_TAP_REPO --region $AWS_REGION
fi

images_count=$(aws ecr describe-images --repository-name $TARGET_TAP_REPO | jq .imageDetails | jq length)
if [[ $images_count = 0 ]]
then
  imgpkg copy --concurrency 1 -b $IMGPKG_REGISTRY_HOSTNAME_0/tanzu-application-platform/tap-packages:$TAP_VERSION --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/$TARGET_TAP_REPO
fi

if [[ -z $tap_build_service_ecr ]]
then
  aws ecr create-repository --repository-name $TARGET_TBS_REPO --region $AWS_REGION --no-cli-pager
fi

kubectl create ns tap-install

tanzu package repository add tanzu-tap-repository \
  --url $IMGPKG_REGISTRY_HOSTNAME_1/$TARGET_TAP_REPO:$TAP_VERSION \
  --namespace tap-install

#tanzu package repository get tanzu-tap-repository --namespace tap-install
#tanzu package available list --namespace tap-install
#tanzu package available list tap.tanzu.vmware.com --namespace tap-install

#download sample app code
#rm -rf tanzu-java-web-app
#git clone https://github.com/nycpivot/tanzu-java-web-app

