# This is a module file which setups a kubernetes cluster using kops
# It will also check and install kops and kubectl if not existing.
# Note that this module expects to run the commands specific in the 
# null resource in a bash environment. If it is a windows machine it  expects
# either a WSL (Ubunut for Windows) or git bash.
variable "vpc_id" { description = "Id of the VPC in which to create the k8s cluster." }
variable "s3bucket_id" { description = "AWS Id of the s3 bucket where state should be stored." }
variable "pvtkey_file" { description = "Path to the AWS user account private key file. Will be copied to ~/.ssh/id_rsa for use by kops to create k8s cluster." }
variable "pubkey_file" { description = "Path to the AWS user account public key file. Will be copied to ~/.ssh/id_rsa.pub for use by kops to create k8s cluster." }
variable "region" { description = "AWS region where the cluster should be created. Default = us-east-1", default = "us-east-1" }
variable "nodes" { description = "Number of worker nodes in k8s cluster. Default = 2", default = 2 }
variable "nodetype" { description = "Worker node type (AWS machine type). Default = t2.micro", default = "t2.micro" }
variable "mastertype" { description = "Master node type (AWS machine type). Default = t2.micro", default = "t2.micro" }
variable "domain" { description = "Name of the domain. Default = local.", default = "local" }
variable "subdomain" { description = "Name of the subdomain. Default = k8s.", default = "k8s" }
variable "triggers" { type = "map", description = "Map of triggers", default = {} }
variable "wink8sdir" { description = "Location for storing kops and kubectl. User should make sure this is in the PATH", default = "$HOME/bin" }
variable "adminusertokenfile" { description = "Local file in which to store the admin user token. Default = adminusertoken", default = "adminusertoken" }
variable "adminsvctokenfile" { description = "Local file in which to store the admin service token. Default = adminsvctoken", default = "adminsvctoken" }


locals {
    interpreter = "bash"
    arg1 = "-c"
    winkops = "kops.exe"
    winkopsfile = "kops-windows-amd64"    // Assumes 64 bit windows.  
    linuxkops = "kops"
    linuxkopsfile = "kops-linux-amd64"    // Assumes 64 bit linux.
    winkubectl= "kubectl.exe"
    linuxkubectl = "kubectl"
}
// Downloads and Installs kops if it doesn't exist in $KOPSLOCATION. Does not remove it. 
// If the platform is "bash" within Windows, then it $KOPSLOCATION is $HOME/bin. It can be overriden by caller.  
module "kops" {
    triggers = "${var.triggers}"
    source = "../lclcmd"
	cmds = [{ 
		dir = "${path.root}", 
		createcmd = <<CMDS
env | grep -E "OS=" &>/dev/null
if (($?)); then 
    KOPS=${local.linuxkops}; KOPSFILE=${local.linuxkopsfile}; KOPSLOCATION=/usr/local/bin; SUDOCMD=sudo
else 
    KOPS=${local.winkops}; KOPSFILE=${local.winkopsfile}; KOPSLOCATION=${var.wink8sdir}; SUDOCMD=
fi
if [[ ! -f $KOPSLOCATION/$KOPS ]]; then  
    wget -O $KOPS https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/$KOPSFILE &>/dev/null
    chmod +x ./$KOPS
    if [[ ! -d $KOPSLOCATION ]]; then mkdir -p $KOPSLOCATION; fi
    $SUDOCMD mv ./$KOPS $KOPSLOCATION
    $KOPS version
fi
CMDS
	}]
}
// Downloads and Installs kubectl if it doesn't exist in $KUBECTLLOCATION. Does not remove it. 
// If the platform is "bash" within Windows, then it $KUBECTLLOCATION is $HOME/bin. It can be overriden by caller.  
module "kubectl" {
    triggers = "${var.triggers}"
    source = "../lclcmd"
	cmds = [{ 
		dir = "${path.root}", 
		createcmd = <<CMDS
env | grep -E "OS=" &>/dev/null
if (($?)); then 
    KUBECTL=${local.linuxkubectl}; PLATFORM=linux; KUBECTLLOCATION=/usr/local/bin; SUDOCMD=sudo
else 
    KUBECTL=${local.winkubectl}; PLATFORM=windows; KUBECTLLOCATION=${var.wink8sdir}; SUDOCMD=
fi
if [[ ! -f $KUBECTLLOCATION/$KUBECTL ]]; then  
    wget -O $KUBECTL https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/$PLATFORM/amd64/$KUBECTL &>/dev/null
    chmod +x ./$KUBECTL &>/dev/null
    if [[ ! -d $KUBECTLLOCATION ]]; then mkdir -p $KUBECTLLOCATION; fi
    $SUDOCMD mv ./$KUBECTL $KUBECTLLOCATION
fi
CMDS
	}]
}
locals { pkidir = "$HOME/.ssh" }
// Copies the AWS pvt and pub keys to $HOME/.ssh directory where they are expected by kops. 
module "rsakeysetup" {
    triggers = "${var.triggers}"
    source = "../lclcmd"
	cmds = [{ 
        dir = "${path.root}", 
        createcmd = "mkdir -p ${local.pkidir}; cp ${var.pvtkey_file} ${local.pkidir}/id_rsa; cp ${var.pubkey_file} ${local.pkidir}/id_rsa.pub",
        destroycmd = "rm ${local.pkidir}/id_rsa*"
    }]
}
locals {
    _cluster_name = "${var.subdomain}.${var.domain}"
    _state = "s3://${var.s3bucket_id}"
}
data "aws_vpc" "vpc" { id = "${var.vpc_id}" } // Instantiates a vpc object. Provides the cidr_block for the k8s cluster. 
// Create the k8s cluster using kops commands. 
resource "null_resource" "k8scluster" {
//    depends_on = [ "null_resource.kops", "null_resource.kubectl" ]
    triggers {
        state = "${var.s3bucket_id}"
        kops = "${module.kops.done}"
        kubectl = "${module.kubectl.done}"
        rsakeysetup = "${module.rsakeysetup.done}"
    }
    provisioner "local-exec" {
        when = "create"
        # Using heredoc syntax for running multiple cmds
        # First we check to see if a public key for ssh access by kops is already present. If so we delete it.  
        # Now we create a public key for ssh access by kops to the various kops systems. 
        # NOTE: kops assumes a key-pair id_rsa in the .ssh directory. So the ssh-keygen cmd is important.  
        # admin is the user name required for Debian. (Seems like kops defaults to using debian for its cluster machines)
        # Then we create the cluster. 
        # Then we copy the export commands for the env variables for use by kops into the .bashrc file. 
        #   
        command = <<CMD
env | grep -E "OS=" &>/dev/null
if (($?)); then KOPS=${local.linuxkops}; else KOPS=${local.winkops}; fi
if [[ ! -f ${local.pkidir}/id_rsa && ! -f ${local.pkidir}/id_rsa.pub ]]; then
    mkdir -p ${local.pkidir}; ssh-keygen -t rsa -N "" -f ${local.pkidir}/id_rsa; if (($?)); then exit 1; fi
fi
sleep 20s # Needed so DNS for public subdomain can become ready. 
created=0; tries=0; looplimit=5;	# Safety net to avoid forever loop. 
while ((!created && looplimit)); do	# Loop while create cluster fails and looplimit non-zero.
    ((tries++))
    echo -e "Creating kubernetes cluster ... [$tries]" 
    $KOPS create cluster \
    --cloud=aws \
    --name=${local._cluster_name} \
    --state=${local._state} \
    --zones=${var.region}a \
    --node-count=${var.nodes} \
    --node-size=${var.nodetype} \
    --master-size=${var.mastertype} \
    --dns-zone=${local._cluster_name} \
    --vpc=${data.aws_vpc.vpc.id} \
    --network-cidr=${data.aws_vpc.vpc.cidr_block} \
    --yes
    if (($?)); then 
        echo -e "Create cluster failed. Deleting cluster ..."
        $KOPS delete cluster --name=${local._cluster_name} --state=${local._state} --yes 
    else
        created=1   # Create succeeded
    fi
    ((looplimit--))
    sleep 20s
done
if ((!created)); then echo -e "Failed to create cluster after [$tries] tries."; exit 1; fi

echo -e "Validating kubernetes cluster. This might take a few minutes, please wait ..." 
validated=0; tries=0; looplimit=8;	# Safety net to avoid forever loop. 
while ((!validated && looplimit)); do	# Loop while create cluster fails and looplimit non-zero.
    ((tries++))
    $KOPS validate cluster --name=${local._cluster_name} --state=${local._state} &>/dev/null
    if ((!$?)); then validated=1; else echo -e "Retrying [$tries] validation of kubernetes cluster ... "; fi
    ((looplimit--))
    sleep 60s
done
if ((!validated)); then 
    echo -e "Failed to validate cluster after [$tries] tries. Deleting cluster ..."
    $KOPS delete cluster --name=${local._cluster_name} --state=${local._state} --yes
    exit 1
else
    echo -e "Validation succeeded after [$tries] tries."
fi
CMD
        interpreter = [ "${local.interpreter}", "${local.arg1}" ] 
    }

    provisioner "local-exec" {
        when = "destroy"
        command = <<CMD
env | grep -E "OS=" &>/dev/null
if (($?)); then KOPS=${local.linuxkops}; else KOPS=${local.winkops}; fi
$KOPS delete cluster --name=${local._cluster_name} --state=${local._state} --yes
CMD
        interpreter = [ "${local.interpreter}", "${local.arg1}" ] 
    }
}
locals {
    masterfile = "k8smaster"
    adminsvctokenfile = "${var.adminsvctokenfile}"
    adminusertokenfile = "${var.adminusertokenfile}"
}
// Post k8s cluster creation tasks.  
resource "null_resource" "k8scomplete" {
    depends_on = [ "null_resource.k8scluster" ]
    provisioner "local-exec" {
        when = "create"
        working_dir = "${path.root}"
        # Using heredoc syntax for running multiple cmds
        # Here we do some house keeping and complete the cluster creation. 
        command = <<CMD
env | grep -E "OS=" &>/dev/null
if (($?)); then 
    KOPS=${local.linuxkops}; KUBECTL=${local.linuxkubectl}
else 
    KOPS=${local.winkops}; KUBECTL=${local.winkubectl}
fi
echo -e "\n\nGetting Kubernetes master name ..."
k8smaster=$($KUBECTL cluster-info | grep "Kubernetes master" | sed -r -e "s/.*(https.*)/\1/g")
echo $k8smaster > ${local.masterfile}
echo -e "Saving the Kubernetes master name to the file 'k8smaster' for future reference"
echo -e "\n\nFrom any browser type $k8smaster to access the Kubernetes REST API"

echo -e "\n\nGetting admin user token (password) ..."
adminusertoken=$($KOPS get secrets kube --state=${local._state} --type=secret -oplaintext)
echo -n $adminusertoken > ${local.adminusertokenfile}
echo -e "When logging into the Kubernetes Master for the first time,"
echo -e "username is 'admin' and password is the value in the file '${local.adminusertokenfile}'."

echo -e "\n\nGetting admin service token ..."
adminsvctoken=$($KOPS get secrets admin --state=${local._state} --type=secret -oplaintext)
echo -n $adminsvctoken > ${local.adminsvctokenfile}
echo -e "For the dashboard, select 'token' and provide the admin service token found in the file '${local.adminsvctokenfile}'."

BASHRCFILE=$HOME/.bashrc
if [[ -f $BASHRCFILE ]]; then mv $BASHRCFILE $HOME/.bashrc.bak; fi
touch $BASHRCFILE
echo -e "export NAME=${local._cluster_name}" >> $BASHRCFILE   # Sets it for future
echo -e "export KOPS_STATE_STORE=${local._state}" >> $BASHRCFILE # Sets it for future

echo -e "Setting up kubectl completion ..."
if [[ ! -d $HOME/.kube ]]; then mkdir -p $HOME/.kube; fi
$KUBECTL completion bash > $HOME/.kube/kctl.completion
echo -e "source $HOME/.kube/kctl.completion" >> $BASHRCFILE # Sets it for future

echo -e "Setting up kops completion ..."
$KOPS completion bash > $HOME/.kube/kops.completion
echo -e "source $HOME/.kube/kops.completion" >> $BASHRCFILE # Sets it for future

echo -e "Don't forget to exit from this bash session and re-run, so ENV vars can be properly setup."
echo -e "To [ssh] into master and worker requires the pvt [id_rsa] key in ~/.ssh and the [admin] user name."
CMD
        interpreter = [ "${local.interpreter}", "${local.arg1}" ] 
    }

    # Remove the KOPS ENV variables and restore the .bashrc file. 
    provisioner "local-exec" {
        when = "destroy"
        working_dir = "${path.root}"
        command = <<CMD
BASHRCFILE=$HOME/.bashrc
if [[ -f $HOME/.bashrc.bak ]]; then 
    rm $BASHRCFILE
    mv $HOME/.bashrc.bak $HOME/.bashrc
else
    mv $BASHRCFILE $HOME/.bashrc-k8s.bak
    touch $BASHRCFILE
    while IFS= read -r line; do
        echo -e "$line" | grep "NAME" > /dev/null; if ((!$?)); then continue; fi
        echo -e "$line" | grep "KOPS_STATE_STORE" > /dev/null; if ((!$?)); then continue; fi
        echo -e "$line" | grep ".kube/kops.completion" > /dev/null; if ((!$?)); then continue; fi
        echo -e "$line" | grep ".kube/kctl.completion" > /dev/null; if ((!$?)); then continue; fi
        echo "$line" >> $BASHRCFILE
    done < $HOME/.bashrc-k8s.bak
    if (($?)); then 
        echo -e "Error updating $BASHRCFILE. Restoring backup"; mv $HOME/.bashrc-k8s.bak $BASHRCFILE
    else
        rm $HOME/.bashrc-k8s.bak
    fi
fi
unset NAME; unset KOPS_STATE_STORE
if [[ -f ./${local.masterfile} ]]; then rm ./${local.masterfile}; fi
if [[ -f ./${local.adminusertokenfile} ]]; then rm ./${local.adminusertokenfile}; fi
if [[ -f ./${local.adminsvctokenfile} ]]; then rm ./${local.adminsvctokenfile}; fi
CMD
        interpreter = [ "${local.interpreter}", "${local.arg1}" ] 
    }
}
# Needed to make sure all the local commands are completed before
# returning the output value. ensures that when the caller uses this module and sets a 
# trigger on it, it will only trigger after the local commands are completed  
data "null_data_source" "done" {
    inputs = { 
        kopsid = "${module.kops.done}"
        kubectlid = "${module.kubectl.done}"
        k8sclusterid = "${null_resource.k8scluster.id}"
        k8scompleteid = "${null_resource.k8scomplete.id}" 
    }
}
output "done" { value = "${data.null_data_source.done.outputs}" }    // This only gets set after all cmds are done.
output "adminsvctokenfile" { value = "${local.adminsvctokenfile}" }
output "adminusertokenfile" { value = "${local.adminusertokenfile}" }
