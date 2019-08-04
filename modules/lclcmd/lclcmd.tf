# This is a module file which performs local commands
# Note that commands will run in parallel so there should be
# no expectation of sequential dependencies between the commands. 

variable "triggers" { type = "map", description = "Map of triggers", default = {} }
variable "cmds" {
    description = <<DESCRIPTION
Specifies a list of cmd maps consisting of the following information
{ createcmd: "string", destroycmd: "string", dir: "string" },
{ createcmd: "string", destroycmd: "string", dir: "string" },
NOTE: Commands will run in parallel.
NOTE: The 'dir' string can be a fully qualified or a relative path. No interpretation is done.
NOTE: Don't include 'destroycmd' if there's nothing to destroy.
DESCRIPTION
    type = "list"
}

variable "os" {
    description = <<DESCRIPTION
Specifies which OS the local command will run on.
Valid options are "linux", "windows". Default is "linux"
If an invalid option is specified it will use the default.
The interpreter will be set based on what is supplied here. 
DESCRIPTION
    default = "linux"
}
locals {
  interpreter = "${var.os == "windows" ? "c:\\windows\\system32\\cmd.exe" : "bash" }"
  arg1 = "${var.os == "windows" ? "/c" : "-c" }" 
}

# Used for running local commands.  
resource "null_resource" "cmd" {
    triggers = "${var.triggers}"
    count = "${length(var.cmds)}"    
    provisioner "local-exec" {
        when = "create"
        working_dir = "${lookup(var.cmds[count.index],"dir","${path.root}")}"
        command = "${lookup(var.cmds[count.index],"createcmd","")}" // No default. We need at least create cmd to be specified. 
        interpreter = [ "${local.interpreter}", "${local.arg1}" ]
    }
    provisioner "local-exec" {
        when = "destroy"
        working_dir = "${lookup(var.cmds[count.index],"dir","${path.root}")}"
        command = "${lookup(var.cmds[count.index],"destroycmd"," ")}"   // If destroycmd is not specified, default 'space' will run to success.
        interpreter = [ "${local.interpreter}", "${local.arg1}" ]
    }
}

# Needed to make sure all the local commands are completed before
# returning the output value. ensures that when the caller uses this module and sets a 
# trigger on it, it will only trigger after the local commands are completed  
data "null_data_source" "done" {
    depends_on = [ "null_resource.cmd" ]
    inputs = { ids = "${join(",",null_resource.cmd.*.id)}" } // Collects all the ids of the null_resource.cmd instances
}
output "done" { value = "${data.null_data_source.done.outputs["ids"]}" }    // This only gets set after all cmds are done.
