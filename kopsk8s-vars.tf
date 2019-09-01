variable "aws_region" { description = "AWS region to launch servers.", default = "us-east-1" }
variable "project" { default = "k8s-demo" }
variable "nodes" { description = "Number of worker nodes in k8s cluster. Default = 2", default = 2 }
variable "nodetype" { description = "Worker node type (AWS machine type). Default = t2.micro", default = "t2.micro" }
variable "mastertype" { description = "Master node type (AWS machine type). Default = t2.micro", default = "t2.micro" }
variable "domain" { description = "Name of the domain. Default = local.", default = "local" }
variable "subdomain" { description = "Name of the subdomain. Default = k8s.", default = "k8s" }
variable "wink8sdir" { description = "Location for storing kops and kubectl. User should make sure this is in the PATH", default = "$HOME/.local/bin" }

variable "comment" { description = "Comment for the hosted zone.", default = "Kubernetes cluster subdomain" }

variable "userforcedestroy" { description = "Option to destroy forcefully.", default = "false" }
variable "pvtkey_file" { description = "AWS private key file. Used by kops for creating the k8s cluster" }
variable "pubkey_file" { description = "AWS public key file. Used by kops for creating the k8s cluster" }
