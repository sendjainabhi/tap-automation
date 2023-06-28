#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

#pre-req - install soap and age cli 

#install soap cli in mac 
brew install sops  
soap --version

#install gh cli in mac 
brew install gh

#install age cli in mac 
brew install age
age --version


#set public git api for trust.
echo github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl >> ~/.ssh/known_hosts
echo github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg= >> ~/.ssh/known_hosts
echo github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk= >> ~/.ssh/known_hosts

ssh-keygen -t ed25519 -C "git@github.com" -N '' <<< $'\ny' >/dev/null 2>&1


#DELETE AND CLONE REPO
rm -rf $gitops_repo

#get github token
echo $github_token
echo $github_token >git-token.txt

# gh auth refresh -h github.com -s delete_repo
gh auth login --git-protocol ssh --with-token < git-token.txt
rm git-token.txt

#delete existing tap-git repo
gh repo delete $gitops_repo --confirm
#create tap-git repo and clone
gh repo create $gitops_repo --public --clone




export TANZU_NET_API_TOKEN=$tanzu_net_api_token

#Download and unpack Tanzu GitOps Reference Implementation (RI) from tanzu net 

export token=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":"'${TANZU_NET_API_TOKEN}'"}')

access_token=$(echo ${token} | jq -r .access_token)

curl -i -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer ${access_token}" -X GET https://network.pivotal.io/api/v2/authentication

wget $tanzu_gitopsri_url --header="Authorization: Bearer ${access_token}" -O $tanzu_gitopsri_filename

tar xvf $tanzu_gitopsri_filename -C $gitops_repo

rm $tanzu_gitopsri_filename

cd $gitops_repo

#Commit the initial state:

git add . 
git commit -s  -m "Initialize Tanzu GitOps RI"
git push -u origin main

#Create cluster configuration
#1. Seed configuration for a cluster using SOPS:

#This script creates the directory clusters/full-tap-cluster/ and copies in the configuration required to sync this Git repository with the cluster and installing Tanzu Application Platform.

./setup-repo.sh $cluster_name sops


#Commit and push
git add . && git commit -m "Add full-tap-cluster"
git push

cd ..

#Preparing sensitive Tanzu Application Platform values

mkdir -p  tmp-enc
chmod 700 tmp-enc

cd tmp-enc

age-keygen -o key.txt

cat key.txt

cat <<EOF | tee tap-sensitive-values.yaml
tap_install:
 sensitive_values:
   shared:
     image_registry:
       project_path: "$registry_url/build-service"
       username: "$registry_user"
       password: "$registry_password"
EOF

#Encrypt tap-sensitive-values.yaml with Age using SOPS
export SOPS_AGE_RECIPIENTS=$(cat key.txt | grep "# public key: " | sed 's/# public key: //')
sops --encrypt tap-sensitive-values.yaml > tap-sensitive-values.sops.yaml

#Verify the encrypted file can be decrypted
export SOPS_AGE_KEY_FILE=key.txt
sops --decrypt tap-sensitive-values.sops.yaml


#Move the sensitive Tanzu Application Platform values into the cluster config
mv tap-sensitive-values.sops.yaml ../${gitops_repo}/clusters/${cluster_name}/cluster-config/values/

cd ..

#backup directory
mkdir -p  backup-dir
chmod 700 backup-dir

#move key.txt into back-directory
mv tmp-enc/key.txt backup-dir

rm -rf tmp-enc

#namespace provisioner config file 

mkdir $gitops_repo/clusters/$cluster_name/cluster-config/namespaces
rm $gitops_repo/clusters/$cluster_name/cluster-config/namespaces/desired-namespaces.yaml
cat <<EOF | tee $gitops_repo/clusters/$cluster_name/cluster-config/namespaces/desired-namespaces.yaml
#@data/values
---
namespaces:
#! The only required parameter is the name of the namespace. All additional values provided here 
#! for a namespace will be available under data.values for templating additional sources
- name: dev
- name: qa
EOF

rm $gitops_repo/clusters/$cluster_name/cluster-config/namespaces/namespaces.yaml
cat <<EOF | tee $gitops_repo/clusters/$cluster_name/cluster-config/namespaces/namespaces.yaml
#@ load("@ytt:data", "data")
#! This for loop will loop over the namespace list in desired-namespaces.yaml and will create those namespaces.
#! NOTE: if you have another tool like Tanzu Mission Control or some other process that is taking care of creating namespaces for you, 
#! and you don’t want namespace provisioner to create the namespaces, you can delete this file from your GitOps install repository.
#@ for ns in data.values.namespaces:
---
apiVersion: v1
kind: Namespace
metadata:
  name: #@ ns.name
#@ end
EOF

#Preparing non-sensitive Tanzu Application Platform values

rm ${gitops_repo}/clusters/${cluster_name}/cluster-config/values/tap-non-sensitive-values.yaml

cat <<EOF | tee ${gitops_repo}/clusters/${cluster_name}/cluster-config/values/tap-non-sensitive-values.yaml
---
tap_install:
  values:
    profile: full
    ceip_policy_disclosed: true

    excluded_packages:
      - policy.apps.tanzu.vmware.com
    
    shared:
      ingress_domain: "$tap_domain"
    supply_chain: basic
    ootb_supply_chain_basic:
      registry:
        server: $registry_url
        repository: "supply-chain"
    buildservice:
        kp_default_repository: ${registry_url}/build-service
        kp_default_repository_username: $registry_user
        kp_default_repository_password: $registry_password
    contour:
      envoy:
        service:
          type: LoadBalancer
    ootb_templates:
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
      app_service_type: ClusterIP
    scanning:
      metadataStore:
        url: "metadata-store.$tap_domain"
    grype:
      namespace: "default"
      targetImagePullSecret: "registry-credentials"
    cnrs:
      domain_name: $tap_domain
    namespace_provisioner:
      controller: false
      gitops_install:
        ref: origin/main
        subPath: clusters/tap-full/cluster-config/namespaces
        url: $tap_gitops_repo_url/$gitops_repo.git

EOF


#tanzu sync process - 

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$tanzu_net_reg_user
export INSTALL_REGISTRY_PASSWORD=$tanzu_net_reg_password
export GIT_SSH_PRIVATE_KEY=$(cat $HOME/.ssh/id_ed25519)
export GIT_KNOWN_HOSTS=$(ssh-keyscan github.com)
export SOPS_AGE_KEY=$(cat backup-dir/key.txt)
export TAP_PKGR_REPO=registry.tanzu.vmware.com/tanzu-application-platform/tap-packages

#Generate the Tanzu Application Platform install and the Tanzu Sync configuration files by using the provided script:
cd $gitops_repo/clusters/$cluster_name

./tanzu-sync/scripts/configure.sh

#Commit the generated configured to Git repository
git add cluster-config/ tanzu-sync/
git commit -m "Configure install of TAP 1.5.0"
git push

#install kapp and ytt if not have installed already
#sudo cp $HOME/tanzu-cluster-essentials/kapp /usr/local/bin/kapp
#sudo cp $HOME/tanzu-cluster-essentials/ytt /usr/local/bin/ytt

#Deploy the Tanzu Sync component
./tanzu-sync/scripts/deploy.sh

cd ../../../$gitops_repo/..
