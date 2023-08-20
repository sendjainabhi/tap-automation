## Purpose

This automation is designed to build following 

* Tanzu Application Platform 1.5.x single cluster instances on all AWS services i.e EKS , ECR , Route53 etc. 

* Tanzu Application Platform 1.5.x single cluster full profile on AWS eks . 

* AWS VPC terraform for Tanzu Mission Control AWS EKS LCM.

### TAP 1.5.x single cluster instances on all AWS services
Specifically, this automation will build:
- a aws VPC (internet facing)
- 1 EKS clusters named as tap-full and associated security IAM roles and groups and nodes into aws. 
- Install Tanzu Application Platform full profile on eks clusters. 
- Install Tanzu Application Platform sample demo app. 

### AWS VPC terraform for Tanzu Mission Control AWS EKS LCM
Specifically, this automation will build an internet facing aws VPC and a jumpbox ec2 instance for TMC provisioned EKS and its LCM. 

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
   * terraform cli


## Prepare the Environment

First, be sure that your AWS access credentials are available within your environment.

### Set aws env variables.
 
```bash
export AWS_ACCESS_KEY_ID=<your AWS access key>
export AWS_SECRET_ACCESS_KEY=<your AWS secret access key>
export AWS_REGION=us-east-1  # ensure the region is set correctly. this must agree with what you set in the tf files below.
```


### TAP 1.5.x single cluster instances on all AWS services steps

### Add TAP configuration mandatory details 

Add following details into `/var.conf` file to fullfill tap prerequisite. Examples and default values given in below sample. All fields are mandatory and can't be leave blank and must be filled before executing the `tap-index.sh` . Please refer below sample config file. 

**Note** - Even if you are only running TAP scripts on existing eks clusters , please set above `aws` environment variables.

```



AWS_REGION=us-east-1
AWS_ACCOUNT_ID=

TANZUNET_USERNAME=abhishekja@vmware.com
TANZUNET_PASSWORD=
TANZU_NET_API_TOKEN=

FULL_DOMAIN="full.ab-tap.customer.io"

#tanzu cli
tanzucliurl_m=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1287412/product_files/1446071/download
tanzuclifilename_m=tanzu-framework-darwin-amd64.tar
tanzucliurl_l=https://network.tanzu.vmware.com/api/v2/products/tanzu-application-platform/releases/1287412/product_files/1446073/download
tanzuclifilename_l=tanzu-framework-linux-amd64.tar
tanzucli_version=v0.28.1

#tanzu essential 
tanzu_ess_filename_m=tanzu-cluster-essentials-darwin-amd64-1.5.0.tgz
tanzu_ess_filename_l=tanzu-cluster-essentials-linux-amd64-1.5.0.tgz
tanzu_ess_url_m=https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1275537/product_files/1460874/download
tanzu_ess_url_l=https://network.tanzu.vmware.com/api/v2/products/tanzu-cluster-essentials/releases/1275537/product_files/1460876/download



GIT_CATALOG_REPOSITORY=tanzu-application-platform
INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
TARGET_TBS_REPO=tap-build-service


EKS_CLUSTER_NAME=tap-full
TANZU_CLI_NO_INIT=true
TANZU_VERSION=v0.28.1
TAP_VERSION=1.5.2-build.1


 

```
## Install TAP on EKS

Execute following steps to Install TAP multi clusters (Run/View/Build/Iterate)
```

#Step 1 - Execute Permission to tap-index.sh file
chmod +x tap-index.sh

#Step 2 - Execute tap-index file 
./tap-index.sh


```
**Note** - 

 Pick an external ip from service output from eks view and run clusters and configure DNS wildcard records in your dns server for tap-full cluster
 * **Example full cluster** - *.full.customer0.io ==> <ingress external ip/cname>


#### Clean up
 Delete TAP instances from eks cluster

## AWS VPC terraform for Tanzu Mission Control AWS EKS LCM

To create an internet facing aws vpc for eks creation from TMC please following below steps :
```
cd tmc-vpc-terraform

1. terraform init

2. terraform plan

3. terraform apply

# to delete vpc run

terraform destroy

```

