# This module creates an AWS S3 bucket with appropriate policies.
variable "name" { 
    description = <<DESC
S3 Bucket name. It needs to be unique. If none is provided 
it defaults to using the caller_identity [12 digit account number]
and project name to create a unique bucket name.
Example: 123456789012-myproject 
DESC
    default = "default" // Dummy, is replaced with above logic. 
}
variable "project" { description = "Unique Project Name. Default = s3b-project", default = "s3b-project"  }
variable "region" { description = "AWS region where bucket should be created. Default = us-east-1", default = "us-east-1" }
variable "policy_principal_id" { 
    description = "IAM Principal Id. Default = current aws_caller_identity [12 digit number]"
    default = "default" // Dummy, is replaced with current aws_caller_identity - 12 digit number
}
variable "forcedestroy" { description = "Force destroy the object.", default = "true" }
variable "acl" { description = "Whether ACL is public or private. Default = private", default = "private" }
variable "versioning_enabled" { description = "Whether versioning is enabled. Default = true", default = "true" }
variable "resource" { 
    description = <<DESC
Path to resource inside the bucket for this project's data. 
Example: my/path/resource
Default = '*'. Allows any resource
DESC
    default = "*" // Allows any key Dummy, is replaced with project name-key. Example: s3b-project-key
}
data "aws_caller_identity" "current" {} // AWS Account Id (or number). 

locals {
    bucket_name = "${var.name == "default" ? "${data.aws_caller_identity.current.account_id}-${var.project}" : "${var.name}" }"
    policy_principal_id = "${var.policy_principal_id == "default" ? "${data.aws_caller_identity.current.account_id}": "${var.policy_principal_id}" }"
    bucket_resource = "${var.resource}"
}

resource "aws_s3_bucket" "s3b" {
    bucket = "${local.bucket_name}"
    acl    = "${var.acl}"
    force_destroy = "${var.forcedestroy}"
    region = "${var.region}"
    tags {
        Name = "${local.bucket_name}"
        Project = "${var.project}"
    }
    versioning { enabled = "${var.versioning_enabled}" }
}

resource "aws_s3_bucket_policy" "s3bpol" {
  bucket = "${aws_s3_bucket.s3b.id}"
  policy =<<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "AWS": "arn:aws:iam::${local.policy_principal_id}:root" },
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${aws_s3_bucket.s3b.id}"
        },
        {
            "Effect": "Allow",
            "Principal": { "AWS": "arn:aws:iam::${local.policy_principal_id}:root" },
            "Action": [ "s3:GetObject", "s3:PutObject" ],
            "Resource": "arn:aws:s3:::${aws_s3_bucket.s3b.id}/${local.bucket_resource}"
        }
    ]
}
POLICY
}
output "data" { value = { id = "${aws_s3_bucket.s3b.id}", arn = "${aws_s3_bucket.s3b.arn}" } }
