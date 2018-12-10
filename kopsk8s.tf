provider "aws" {
    # Assumes that the AWS credentials are available in ~/.aws/credentials
    region = "${var.aws_region}"    # Region is coming from the variables.tf file. 
	version = "~> 1.6"
}
locals { interpreter = "bash", arg1 = "-c" }
// Dependency checks. 
module "depchk" {
    source = "./modules/lclcmd"
	cmds = [{ 
		dir = "${path.root}", 
		createcmd = <<CMDS
result=$(which bash &>/dev/null); if (($?)); then echo "Cannot find [bash]. Please install git bash or another windows bash environment."; exit 1; fi
version=$(bash --version | grep -Eo "[0-9]\.[0-9]"); if [[ "$version" != "4"* ]]; then echo '[bash] version is [$version]. Should be 4.x.x.'; exit 1; fi
result=$(which wget &>/dev/null); if (($?)); then echo "Cannot find [wget]. Install wget.exe from https://eternallybored.org/misc/wget/ and try again."; exit 1; fi
result=$(which aws &>/dev/null); if (($?)); then echo "[aws] not installed. Install aws.exe and try again."; exit 1; fi
result=$(which jq &>/dev/null); if (($?)); then echo "[jq] not installed. Install jq.exe and try again."; exit 1; fi
env | grep -E "OS=" &>/dev/null; if (($?)); then PROFILE=.profile; else PROFILE=.bash_profile; fi
if [[ ! -f $HOME/$PROFILE ]]; then echo "Cannot find [$HOME/$PROFILE]. Please create this file and include a 'source $HOME/.bashrc' cmd in it."; exit 1; fi
CMDS
	}]
}
// Creates the s3bucket for k8s to store its state
module "s3bucket" {
    source = "./modules/s3bucket"
    region = "${var.aws_region}"
}
// Creates the vpc for running the k8s cluster in
module "k8svpc" {
	source = "./modules/network"
    project = "${var.project}"
    security_group_name = "${var.project}-sg"
}
locals {
    realdomain = "${var.domain == "local" ? 0 : 1}" // Set to 0 if domain is "local". Set to 1 if domain is "real". i.e. Either purchased via Route53 or some other domain authority.
    localdomain = "${var.domain == "local" ? 1 : 0}" // Only set to 1 if it's a local domain.  
}
// This points to a real domain. Note that the user has to create the domain in Route53 or map it to a Route53 domain manually outside this program.
// We will import the information using this command. 
// This is instantiated only if there is a real domain. (i.e. var.domain is not marked 'local')
data "aws_route53_zone" "hz" {
    count = "${local.realdomain}"   // Only instantiated if domain is real.  
    name = "${var.domain}"
}
// This subdomain is a private subdomain and created within a VPC if we're using a local domain 
resource "aws_route53_zone" "pvthz" {
    count = "${local.localdomain}"
    name = "${var.subdomain}.${var.domain}"
    comment = "${var.comment}"
    vpc { vpc_id = "${module.k8svpc.vpc_id}" }
    tags {
        Name = "${var.project}-pvthz"
        Project = "${var.project}"
    }
}
// This is a public subdomain and created under the real domain  
resource "aws_route53_zone" "subhz" {
    count = "${local.realdomain}"
    name = "${var.subdomain}.${var.domain}"
    comment = "${var.comment}"
    tags {
        Name = "${var.project}-subhz"
        Project = "${var.project}"
    }
}
// Retrieves the NS records from the real 'var.domain'. 
data "external" "subhz_nsrecords" {
    count = "${local.realdomain}"   // Only instantiated if domain is real. 
    program = [ "bash", "nsrecords.sh" ] 
    query = {
        # "hosted_zone is passed in as json to the program nsrecords.sh"
        hosted_zone = "${aws_route53_zone.subhz.id}"
    }
    # Results are returned in "result" attribute
}
// The NS records obtained from the real domain are incorporated into the subdomain. Not instantiated for private "local" domain. 
resource "aws_route53_record" "subhz_nsrecords" {
    count = "${local.realdomain}"
    depends_on = [ "aws_route53_zone.subhz" ] 
    zone_id = "${data.aws_route53_zone.hz.0.zone_id}"
    name    = "${var.subdomain}.${var.domain}"
    type    = "NS"
    ttl     = "300"
    records = ["${values(data.external.subhz_nsrecords.0.result)}"]
}
// This module creates the kubernetes cluster using kops.
module "k8s" {
    // NOTE: The nsrec trigger listed below needs to be specified as "${jsonencode(aws_route53_record.subhz_nsrecords.*.name)}"
    // because the data for nsrecords is instantiated only when the subdomain is part of a real domain. 
    // For a local domain situation, there will be no ns-records for the subdomain. 
    // The splat format with jsonencode() allows terraform to handle the situation where count is zero without an error.
    // jsonencode converts a list of maps to a string whether it exists or not. 
    // This may change in 0.12.0 release of terraform. In the meantime, this works for both a local domain and a real domain.    
    triggers = { nsrec = "${jsonencode(aws_route53_record.subhz_nsrecords.*.name)}", s3b = "${module.s3bucket.data["id"]}" }
    source = "./modules/k8scluster"
    vpc_id = "${module.k8svpc.vpc_id}"
    nodes = "${var.nodes}"
    nodetype = "${var.nodetype}"
    mastertype = "${var.mastertype}"
    domain = "${var.domain}"
    subdomain = "${var.subdomain}"
    region = "${var.aws_region}"
    s3bucket_id = "${module.s3bucket.data["id"]}"
    wink8sdir = "${var.wink8sdir}"
    pvtkey_file = "${var.pvtkey_file}"
    pubkey_file = "${var.pubkey_file}"
}
// This is used to setup dashboard and metrics 
module "dashboardetc" {
    triggers = { k8s = "${module.k8s.done["k8scompleteid"]}" }
    source = "./modules/lclcmd"
	cmds = [{ 
		dir = "${path.root}", 
		createcmd = <<CMDS
env | grep -E "OS=" &>/dev/null; if (($?)); then KUBECTL=kubectl; else KUBECTL=kubectl.exe; fi
$KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml            
$KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
$KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
$KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
CMDS
/*        ,destroycmd = <<CMDS
env | grep -E "OS=" &>/dev/null; if (($?)); then KUBECTL=kubectl; else KUBECTL=kubectl.exe; fi
$KUBECTL delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
$KUBECTL delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
$KUBECTL delete -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
$KUBECTL delete -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml            
CMDS */
	}]
}
// Final messages 
module "msgs" {
    triggers = { dashboard = "${module.dashboardetc.done}" }
    source = "./modules/lclcmd"
	cmds = [{ 
		dir = "${path.root}", 
		createcmd = <<CMDS
env | grep -E "OS=" &>/dev/null; if (($?)); then KUBECTL=kubectl; else KUBECTL=kubectl.exe; fi
$KUBECTL get nodes
echo ""
echo "**********************************************************************"
echo "Run 'kubectl proxy' first, then go to the browser and ..."
echo "Use http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/ to launch dashboard."
echo "Dashboard, sign-in-token can be found in the '${module.k8s.adminsvctokenfile}' file."
echo "**********************************************************************"
echo ""
CMDS
	}]
}
