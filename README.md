# Infrastructure As Code - Creating a Kubernetes Cluster using Kops and Terraform

The following Terraform script helps you create a complete Kubernetes cluster in AWS using the Kops tool. It also sets up the Kubernetes Dashboard. After you are done with your work, you can take down the entire cluster with a single command. Setup typically takes about 8 - 10 minutes for a cluster of one master and two nodes after invoking Terraform. Tearing down the cluster takes about 5 minutes. Most of the manual work is in setting up the pre-requiste components. The manual work is one-time only and can take about 30 - 45 minutes.

This Terraform script can create a Kubernetes cluster with a private domain (e.g. k8s.local) or with a public domain (e.g. k8s.yourcompany.com). By default the script creates a cluster with a private domain.

To use this Terraform script, clone this project using git. Make sure you check out the Pre-requisites section before trying anything.

```bash
ubuntu@ubuntu:~$git clone https://github.com/upalepu/kopsk8s.git
```

---

## *Pre-requisites*

This Terraform script was tested on 64-bit **Windows-10** and **Ubuntu-16.04** OS platforms.

Pre-requisite|Windows|Linux|Notes
---|---|---|---
CommandLine Environment|Git for Windows. You can download this from [here](https://gitforwindows.org/)|Linux Bash environment|Type ***bash --version*** at a *bash* command prompt to check the version. The *bash* version should be at least 4.x.x.
Folders for Applications|Use ***$HOME/bin*** folder. In Windows ***$HOME*** is set to the logged in user's directory. (e.g. root\Users\username)|Use ***usr/local/bin*** folder. In Linux, this already exists.|The ***bin*** folders are the recommended locations for installing required applications in this project. One benefit of doing this is that these folders are included in the PATH.
Terraform Application|Download the 64-bit Windows version ***0.11.10*** from [here](https://releases.hashicorp.com/terraform/0.11.10/terraform_0.11.10_windows_amd64.zip) |Download the 64-bit Linux version ***0.11.10*** from [here](https://releases.hashicorp.com/terraform/0.11.10/terraform_0.11.10_linux_amd64.zip)| The Terraform application is a single executable. After downloading, unzip the file and copy it to the appropriate ***bin*** folder. Type ***terraform --version*** at a *bash* command prompt to see which version you have installed. For the latest versions of Terraform application click [here](https://www.terraform.io/downloads.html).
CommandLine Application for AWS (aws)|Download the 64-bit Windows AWS client installer from [here](https://s3.amazonaws.com/aws-cli/AWSCLI64PY3.msi) and install it in the ***$HOME/bin*** folder.|On a Linux machine (ubuntu), you can use the instructions provided [here](#awsclilinuxinstall) to install the AWS CommandLine Application. |The Terraform script uses the aws command line utility to retrieve some aws information from route53. This is needed by kops when creating a Kubernetes cluster in a public domain. Check this [web page](https://aws.amazon.com/cli) for the latest information about the AWS CommandLine Application.
CommandLine Utility for downloading files (*wget*)|Download the 64-bit Windows version of wget from [here](https://eternallybored.org/misc/wget/). After downloading, copy this executable file to the Git Bash ***/usr/bin*** folder. Usually this folder will be under ***root\Program Files\Git\usr\bin*** if the installation was default. |On a linux machine, wget will usually be included as a part of the standard install. This is certainly true for ubuntu. |*wget* is a command line utility which is is used to download files using the familiar HTTP protocol.
CommandLine Utility for JSON manipulation (*jq*)|Download the 64-bit Windows version 1.6 from [here](https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe). After downloading, copy the file to the ***$HOME/bin*** folder.|*jq* version 1.5 is available in the standard ubuntu release. You can use ***sudo apt-get install*** to install it in ubuntu.|*jq* is a command line utility used for manipulating and extracting filtered JSON data from JSON input. The Terraform script uses this utility for parsing JSON data when creating a Kubernetes cluster in a public domain. You can check this [web page](https://stedolan.github.io/jq/download/) for all versions of *jq*. The latest version is 1.6, but 1.5 is also acceptable for this project.

---

## *Kubernetes Cluster on AWS using Kops*

## Steps to follow  

There are three major groupings of instructions to follow. First you will need to configure the Terraform script to your specific needs. Click on this link for instructions to [Configure](#cfg).

Once configured, you will need to create the Kubernetes cluster and when you're done experimenting with the cluster, you will need to destroy it. Click on these links for instructions to [Create](#create) and [Destroy](#destroy) the cluster.

### <a name="cfg"></a>Configure Kubernetes Cluster

The table below lists several configurable options. Review them to make sure they are appropriate for your specific needs.

Option|Key|Default Value|Notes
---|---|---|---
AWS Region|aws_region|us-east-1|The Kubernetes cluster will need to be created in a specific AWS region.
Domain Name|domain|local|***local*** domain is a private domain. A private domain is acceptable for testing and development projects. You don't need to change this for experimentation and testing. NOTE: If you want to use a public domain, you need to have a Route53 public domain already setup in AWS. You can find details of setting up a Route53 domain [here](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/setting-up-route-53.html).
Sub-domain|subdomain|k8s|***k8s*** is the sub-domain. It is not necessary to change this typically.
Workers Nodes|nodes|2|By default Kops will create one Master node and two Worker nodes.
Master Node Type|mastertype|t2.micro|This is ok for a single user small test environment. Anything larger than that will need a bigger machine. Consider t2.large or t2.xlarge if you have multiple people and/or multiple workloads to test. Note that these machine types can cost money.
Worker Node Type|nodetype|t2.micro|This is ok only for very light weight single user small test environments. Anything larger than that will need a bigger machine. Consider t2.large or t2.xlarge if you are not able to run multiple workloads. Note that these machine types can cost money.
Windows Kubernetes Directory|wink8sdir|$HOME/bin|In Windows 10, the Kops, Kubectl and other utilities needed by this project will be installed into this location. In Windows with Git for Windows installed, the $HOME environment variable is set to root\Users\username.
AWS Private Key File|pvtkey_file|None|This is the full path to the AWS private key (.PEM) file for your AWS account. It is used by kops to supply the certificate for the k8s cluster.
AWS Public Key File|pubkey_file|None|This is the full path to the AWS public key (.PUB) file for your AWS account. It is used by kops to supply the certificate for the k8s cluster.

- Open a *bash* command prompt (git bash if Windows 10) and change to the directory where you have cloned this project.

- Using your favorite editor create a new ***terraform.tfvars*** file and add the options as shown in the example below. Note, the sample below only shows a few of the options, you only need to add the options relevant to your situation. At a minimum, you need to add the **pvtkey_file** and the **pubkey_file**

```bash
aws_region = "us-west-2"
domain = "mycompany.com"
nodes = 3
nodetype = "t2.large"
pvtkey_file = "~/aws/keys/myawsuser.pem"
pubkey_file = "~/aws/keys/myawsuser.pub"
```

- Save the ***terraform.tfvars*** file and make sure it is in the same directory as the kopsk8s.tf Terraform script file. Configuration is complete. You are now ready to create the cluster.

- Go to [Create.](#create)

### <a name="create"></a>Create

- From a *bash* command prompt, type the following command ***terraform init*** and let Terraform take care of the rest. The output will be as below if it succeeded, details have been omitted for brevity.

```bash
ubuntu@ip-10-0-1-42:~/kopsk8s$ terraform init
Initializing modules...
.
.
Initializing provider plugins...
.
.
Terraform has been successfully initialized!
.
.
ubuntu@ip-10-0-1-42:~/kopsk8s$
```

- From a *bash* command prompt, type the following command ***terraform apply*** and let Terraform take care of the rest. The output will be as below if it succeeded, details have been omitted for brevity. When prompted, type ***yes*** to execute the Terraform plan.

```bash
ubuntu@ip-10-0-1-42:~/kopsk8s$ terraform apply
data.aws_caller_identity.current: Refreshing state...

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create
  ~ update in-place
 <= read (data resources)

Terraform will perform the following actions:
.
.
Plan: 21 to add, 1 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

That's it! You will likely have to wait for about 7 - 8 minutes for the Kubernetes cluster to be created. Check the Terraform messages to see progress. If there are errors in the Terraform execution, fix the errors and try again.

Experiment with the Kubernetes cluster. Try to run the Dashboard using the instructions provided on the Terraform output. When you're done, go to the [Destroy](#destroy) section to destroy the Kubernetes cluster.

### <a name="destroy"></a>Destroy

Follow the steps below for destroying the Kubernetes cluster you created.

- From a bash prompt and type ***terraform destroy***. When prompted, type ***yes*** after making sure that the number of items being destroyed matches the number of items created. You will see the result of the command similar to what is shown below. For brevity, most of the output is not shown.

```bash
ubuntu@ip-10-0-1-42:~/kopsk8s$ terraform destroy
.
.
Destroy complete! Resources: 21 destroyed.
ubuntu@ip-10-0-1-42:~/kopsk8s$ terraform destroy
```

Your Kubernetes Cluster, along with the VPC and all associated infrsatructure items have been destroyed. You can verify this by logging into your AWS console and checking out the EC2 machines, Route53, VPC etc.

## Summary

With Terraform, it's quite easy to create a Kops Kubernetes cluster whether it is with a private domain or a public domain. terraform maintains the state of the created infrastructure and when called to destroy it, it will make sure only those items it created are destroyed.

---

## <a name="awsclilinuxinstall"></a>*Installation instructions for AWS CommandLine Application on Linux (ubuntu)*

For installing the AWS CommandLine utility on a linux machine, follow the instructions below.

```bash
ubuntu@ubuntu:~$sudo apt-get update -y
ubuntu@ubuntu:~$sudo apt-get install -y python3 python3-pip
ubuntu@ubuntu:~$pip3 install awscli --upgrade --user
```

---
