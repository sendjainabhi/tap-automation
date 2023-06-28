## Purpose

This automation is designed to build a Tanzu Application Platform 1.5.x single cluster instances on all AWS services i.e EKS , ECR , Route53 etc. 


Specifically, this automation will build:
- a aws VPC (internet facing)
- 1 EKS clusters named as tap-full and associated security IAM roles and groups and nodes into aws. 
- Install Tanzu Application Platform full profile on eks clusters. 
- Install Tanzu Application Platform sample demo app. 

## AWS resources matrix 

 **Resource Name** | **Size/Number**  
 -----|-----
 VPC | 1
 Subnets | 2 private , 2 public
 VPC cidr | 10.0.0.0/16
 EKS clusters | 1
 Nodes per eks cluster | Nodes : 3, Node Size : t3.xlarge , Storage : 100GB disk size
## Prerequisite 

Following cli must be setup into jumbbox or execution machine/terminal. 

   * aws cli 
   * eksctl cli 
   * tanzu cli


## Prepare the Environment

First, be sure that your AWS access credentials are available within your environment.

### Set aws env variables.
 
```bash
export AWS_ACCESS_KEY_ID=<your AWS access key>
export AWS_SECRET_ACCESS_KEY=<your AWS secret access key>
export AWS_REGION=us-east-1  # ensure the region is set correctly. this must agree with what you set in the tf files below.
```
**Note** - Even if you are only running TAP scripts on existing eks clusters , please set above `aws` environment variables.

### Add TAP configuration mandatory details 

Add following details into `/var.conf` file to fullfill tap prerequisite. Examples and default values given in below sample. All fields are mandatory and can't be leave blank and must be filled before executing the `tap-index.sh` . Please refer below sample config file. 
```



os=m

INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:c7b0988cf3e982625287b241db5d78c30780886dfe9ada01559bb5cd341e6181
INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
TAP_VERSION=1.5.1

#gitops property 
 gitops_repo=tap-gitops
 github_token=<add your github token with admin access>
 cluster_name=tap-full

#tanzu net credentials
tanzu_net_reg_user=<tanzu net user id>
tanzu_net_reg_password=<tanzu net password>
tanzu_net_api_token=<tanzu net token>

#aws details
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=



tap_domain= <add tap domain for full profile like - full.ab-tap.customer0.io >
domain_name_route53=<add your route 53 domain like - customer0.io >

#user registry credentials 
registry_url=# <add user registry url>
registry_user= #<user registry user>
registry_password= #<user registry password>

#tanzu cli
tanzucliurl_m=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1287412/product_files/1446071/download
tanzuclifilename_m=tanzu-framework-darwin-amd64.tar
tanzucliurl_l=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1287412/product_files/1446073/download
tanzuclifilename_l=tanzu-framework-linux-amd64.tar
tanzucli_version=v0.28.1

#tanzu essential 
tanzu_ess_filename_m=tanzu-cluster-essentials-darwin-amd64-1.5.1.tgz
tanzu_ess_filename_l=tanzu-cluster-essentials-linux-amd64-1.5.1.tgz
tanzu_ess_url_m=https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1303471/product_files/1501573/download
tanzu_ess_url_l=https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1303471/product_files/1501579/download

#tanzu gitops ri
tanzu_gitopsri_filename=tanzu-gitops-ri-0.1.0.tgz
tanzu_gitopsri_url=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1317341/product_files/1467377/download

tap_git_catalog_url=https://github.com/sendjainabhi/tap/blob/main/catalog-info.yaml
tap_gitops_repo_url=https://github.com/sendjainabhi
TAP_DEV_NAMESPACE="default"


 

```
## Install TAP on EKS

Execute following steps to Install TAP multi clusters (Run/View/Build/Iterate)
```

#Step 1 - Execute Permission to tap-index.sh file
chmod +x tap-index.sh

#Step 2 - Execute tap-index file 
./tap-index.sh


```


## Clean up

### Delete TAP instances from eks cluster
```
Execute below command 
kapp delete -a tanzu-sync

```

### Delete EKS cluster