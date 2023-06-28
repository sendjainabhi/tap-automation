#!/bin/bash
source var.conf
export TAP_APP_NAME=tanzu-java-web-app
echo "Build source code in build cluster !!!"

echo "Login to build cluster !!!"
aws eks --region $aws_region update-kubeconfig --name $cluster_name

tanzu apps workload list

echo "delete existing app"

tanzu apps workload delete ${TAP_APP_NAME} --yes

tanzu apps workload create tanzu-java-web-app \
--git-repo https://github.com/vmware-tanzu/application-accelerator-samples \
--sub-path tanzu-java-web-app \
--git-branch main \
--type web \
--label app.kubernetes.io/part-of=tanzu-java-web-app \
--yes \
--namespace ${TAP_DEV_NAMESPACE}


#tanzu apps workload tail tanzu-java-web-app --since 3m --timestamp --namespace ${TAP_DEV_NAMESPACE}
echo "Waiting for app build !!!! "
sleep 50


tanzu apps workload get "${TAP_APP_NAME}"

kubectl get httpproxy --namespace ${DEVELOPER_NAMESPACE}

sleep 15
echo "get app url and copy into browser to test the app"
kubectl get ksvc



