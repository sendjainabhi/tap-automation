#!/bin/bash
source var.conf

clear

app_name=tanzu-java-web-app
git_repo=https://github.com/nycpivot/tanzu-java-web-app
sub_path=ootb-supply-chain-basic


aws eks --region $AWS_REGION update-kubeconfig --name $EKS_CLUSTER_NAME

#creating workload registries
#repo1=$(aws ecr delete-repository --repository-name tanzu-application-platform/$app_name-default --region $AWS_REGION --force)
#repo2=$(aws ecr delete-repository --repository-name tanzu-application-platform/$app_name-default-bundle --region $AWS_REGION --force)

tanzu apps cluster-supply-chain list

tanzu apps workload list

#creating workload registries
aws ecr create-repository --repository-name tanzu-application-platform/$app_name-default --region $AWS_REGION 
aws ecr create-repository --repository-name tanzu-application-platform/$app_name-default-bundle --region $AWS_REGION

#create workload
tanzu apps workload create $app_name --git-repo $git_repo --git-branch main --type web --label app.kubernetes.io/part-of=$app_name --yes

tanzu apps workload tail $app_name --since 1h --timestamp

tanzu apps workload list

tanzu apps workload get $app_name

sleep 60
echo "get app url and copy into browser to test the app"
kubectl get ksvc
