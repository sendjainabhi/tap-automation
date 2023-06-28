#!/bin/bash
source var.conf

export EKS_CLUSTER_NAME=tap-gitops
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=964001864378
export K8_Version=1.25
export K8_INST_TYPE=t3.xlarge


# 1. CREATE CLUSTER
echo
echo "<<< CREATING CLUSTER >>>"
echo

eksctl create cluster --name $EKS_CLUSTER_NAME --managed --region $AWS_REGION --instance-types $K8_INST_TYPE --version $K8_Version --with-oidc -N 3

rm $HOME/.kube/config

#configure kubeconfig
arn=arn:aws:eks:$AWS_REGION:$AWS_ACCOUNT_ID':cluster'
echo $arn

aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

kubectl config rename-context $arn/$EKS_CLUSTER_NAME $EKS_CLUSTER_NAME

kubectl config use-context $EKS_CLUSTER_NAME



# 2. INSTALL CSI PLUGIN (REQUIRED FOR K8S 1.23+)
echo
echo "<<< INSTALLING CSI PLUGIN >>>"
echo



#https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html

rolename=$EKS_CLUSTER_NAME-csi-driver-role

echo $rolename

aws eks create-addon --cluster-name $EKS_CLUSTER_NAME --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID':role/'$rolename
   

#https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
oidc_id=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | awk -F '/' '{print $5}')
echo $oidc_id

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

echo $OIDCPROVIDER

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
    eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${rolename}


rm aws-ebs-csi-driver-trust-policy.json