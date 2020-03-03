variable "target_user" {
  description = "SSH user used to connect to the target_host"
  default     = "root"
}

variable "target_host" {
  description = "DNS host to deploy to"
}

variable "ssh_private_key_file" {
  description = "Path to private key used to connect to the target_host. Ignored if `-` or empty."
  default     = "-"
}

variable "ssh_agent" {
  description = "Whether to use an SSH agent"
  type        = bool
  default     = true
}

variable "NIX_PATH" {
  description = "Allow to pass custom NIX_PATH. Ignored if `-`."
  default     = "-"
}

variable "nixos_config" {
  description = "Path to a NixOS configuration"
  default     = ""
}

variable "config" {
  description = "NixOS configuration to be evaluated. This argument is required unless 'nixos_config' is given"
  default     = ""
}

variable "config_pwd" {
  description = "Directory to evaluate the configuration in. This argument is required if 'config' is given"
  default     = ""
}

variable "extra_eval_args" {
  description = "List of arguments to pass to the nix evaluation"
  type        = list(string)
  default     = []
}

variable "extra_build_args" {
  description = "List of arguments to pass to the nix builder"
  type        = list(string)
  default     = []
}

variable "build_on_target" {
  type        = string
  description = "Avoid building on the deployer. Must be true or false. Has no effect when deploying from an incompatible system."
  default     = false
}

variable "triggers" {
  type        = map(string)
  description = "Triggers for deploy"
  default     = {}
}

variable "keys" {
  type        = map(string)
  description = "A map of filename to content to upload as secrets in /var/keys"
  default     = {}
}

variable "system" {
  type = string
  description = "Nix system string"
  default = "x86_64-linux"
}

# --------------------------------------------------------------------------

locals {
  triggers = {
    deploy_nixos_drv  = data.external.nixos-instantiate.result["drv_path"]
    deploy_nixos_keys = sha256(jsonencode(var.keys))
  }

  target_system_options = ["--argstr", "system", "${local.target_system}"]
  target_system = var.system

  extra_build_args = concat([
    "--option", "substituters", data.external.nixos-instantiate.result["substituters"],
    "--option", "trusted-public-keys", data.external.nixos-instantiate.result["trusted-public-keys"],
    ],
    var.extra_build_args,
  )
  ssh_private_key_file = var.ssh_private_key_file == "" ? "-" : var.ssh_private_key_file
  build_on_target = data.external.nixos-instantiate.result["currentSystem"] != local.target_system ? true : tobool(var.build_on_target)

  instantiate = concat([
    "${path.module}/nixos-instantiate.sh",
    var.NIX_PATH,
    var.config != "" ? var.config : var.nixos_config,
    var.config_pwd != "" ? var.config_pwd : ".",
    ],
    local.target_system_options,
    var.extra_eval_args,
  )
}

# used to detect changes in the configuration
data "external" "nixos-instantiate" {
  program = local.instantiate
}

resource "null_resource" "deploy_nixos" {
  triggers = merge(var.triggers, local.triggers)

  connection {
    type        = "ssh"
    host        = var.target_host
    user        = var.target_user
    agent       = var.ssh_agent
    timeout     = "100s"
    private_key = local.ssh_private_key_file != "-" ? file(var.ssh_private_key_file) : null
  }

  # copy the secret keys to the host
  # copy the secret keys to the host
  provisioner "file" {
    content     = jsonencode(var.keys)
    destination = "packed-keys.json"
  }

  # FIXME: move this to nixos-deploy.sh
  # FIXME: move this to nixos-deploy.sh
  provisioner "file" {
    source      = "${path.module}/unpack-keys.sh"
    destination = "unpack-keys.sh"
  }

  # FIXME: move this to nixos-deploy.sh
  # FIXME: move this to nixos-deploy.sh
  provisioner "file" {
    source      = "${path.module}/maybe-sudo.sh"
    destination = "maybe-sudo.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x unpack-keys.sh maybe-sudo.sh",
      "./maybe-sudo.sh ./unpack-keys.sh ./packed-keys.json",
    ]
  }

  # re-run instantiation, in case the plan was copied to a clean environment
  # TODO: only if the drv does not exist
  provisioner "local-exec" {
    interpreter = local.instantiate
    # we use `interpreter` for correct argument list handling
    # however we need to provide a command too which will be appended
    # we pick a harmless flag
    command = "--keep-failed"
  }

  # do the actual deployment
  provisioner "local-exec" {
    interpreter = concat([
      "${path.module}/nixos-deploy.sh",
      data.external.nixos-instantiate.result["drv_path"],
      data.external.nixos-instantiate.result["out_path"],
      "${var.target_user}@${var.target_host}",
      local.build_on_target,
      local.ssh_private_key_file,
      "switch",
      ],
      local.extra_build_args
    )
    command = "ignoreme"
  }
}

# --------------------------------------------------------------------------

output "id" {
  description = "random ID that changes on every nixos deployment"
  value       = null_resource.deploy_nixos.id
}

