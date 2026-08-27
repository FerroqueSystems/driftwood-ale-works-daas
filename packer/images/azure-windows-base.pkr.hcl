packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 2.2.0"
    }
  }
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type = string
}

variable "build_resource_group_name" {
  type    = string
  default = null
}

variable "gallery_resource_group_name" {
  type = string
}

variable "gallery_name" {
  type = string
}

variable "gallery_image_name" {
  type = string
}

variable "gallery_image_version" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_D4as_v5"
}

variable "shared_image_replica_count" {
  type    = number
  default = 1
}

variable "shared_image_replication_regions" {
  type    = list(string)
  default = []
}

variable "azure_imgpublisher" {
  type = string
}

variable "azure_imgoffer" {
  type = string
}

variable "azure_imgsku" {
  type = string
}

variable "azure_imgversion" {
  type    = string
  default = "latest"
}

variable "communicator_username" {
  type    = string
  default = "packer"
}

variable "winrm_timeout" {
  type    = string
  default = "30m"
}

variable "managed_image_tags" {
  type    = map(string)
  default = {}
}

variable "install_chocolatey_packages" {
  type    = bool
  default = false
}

variable "chocolatey_packages" {
  type    = list(string)
  default = []
}

variable "install_m365_apps" {
  type    = bool
  default = false
}

variable "m365_apps_odt_url" {
  type    = string
  default = "https://driftwoodctximages.blob.core.windows.net/image-build-artifacts/officedeploymenttool_20228-20124.exe"
}

variable "m365_apps_config_xml" {
  type    = string
  default = "https://driftwoodctximages.blob.core.windows.net/image-build-artifacts/Configuration.xml"
}

variable "install_citrix_vda" {
  type    = bool
  default = false
}

variable "citrix_vda_installer_url" {
  type    = string
  default = ""
}

variable "citrix_vda_installer_args" {
  type    = string
  default = ""
}

variable "install_cloudpaging_player" {
  type    = bool
  default = false
}

variable "cloudpaging_player_installer_url" {
  type    = string
  default = "https://driftwoodctximages.blob.core.windows.net/image-build-artifacts/cloudpaging-player-setup-x64.msi"
}

variable "cloudpaging_player_installer_args" {
  type    = string
  default = "/qn /norestart SERVERURL=https://api-driftwood.cloudpaging.net"
}
variable "run_citrix_optimizer" {
  type    = bool
  default = false
}

variable "citrix_optimizer_zip_url" {
  type    = string
  default = ""
}

variable "citrix_optimizer_template_name" {
  type    = string
  default = ""
}

variable "prepare_for_citrix_mcs" {
  type    = bool
  default = true
}

# Optional local admin account baked into the image for break-glass Bastion
# RDP access - AzureAD-joined VDAs (see modules/citrix/README.md) otherwise
# rely solely on Entra ID native RDP over Bastion, with no local fallback.
# Leave local_admin_username empty to skip creating one.
variable "local_admin_username" {
  type    = string
  default = ""
}

variable "local_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

locals {
  shared_image_replication_regions = length(var.shared_image_replication_regions) > 0 ? var.shared_image_replication_regions : [var.location]
}

source "azure-arm" "windows" {
  use_azure_cli_auth = true

  subscription_id = var.subscription_id
  location        = var.build_resource_group_name == null ? var.location : null
  vm_size         = var.vm_size
  os_type         = "Windows"

  build_resource_group_name = var.build_resource_group_name

  image_publisher = var.azure_imgpublisher
  image_offer     = var.azure_imgoffer
  image_sku       = var.azure_imgsku
  image_version   = var.azure_imgversion

  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = var.winrm_timeout
  winrm_username = var.communicator_username

  shared_image_gallery_destination {
    resource_group      = var.gallery_resource_group_name
    gallery_name        = var.gallery_name
    image_name          = var.gallery_image_name
    image_version       = var.gallery_image_version
    replication_regions = local.shared_image_replication_regions
  }

  shared_image_gallery_replica_count = var.shared_image_replica_count

  azure_tags = merge(var.managed_image_tags, {
    SourcePublisher = var.azure_imgpublisher
    SourceOffer     = var.azure_imgoffer
    SourceSku       = var.azure_imgsku
    GalleryImage    = var.gallery_image_name
  })
}

build {
  name    = var.gallery_image_name
  sources = ["source.azure-arm.windows"]

  provisioner "powershell" {
    inline = [
      "$ProgressPreference = 'SilentlyContinue'",
      "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force"
    ]
  }

  provisioner "powershell" {
    environment_vars = [
      "INSTALL_CHOCOLATEY_PACKAGES=${var.install_chocolatey_packages}"
    ]
    script = "${path.root}/scripts/windows/install-chocolatey.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "INSTALL_CHOCOLATEY_PACKAGES=${var.install_chocolatey_packages}",
      "CHOCOLATEY_PACKAGES=${join(",", var.chocolatey_packages)}"
    ]
    script = "${path.root}/scripts/windows/install-chocolatey-packages.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "INSTALL_M365_APPS=${var.install_m365_apps}",
      "M365_APPS_ODT_URL=${var.m365_apps_odt_url}",
      "M365_APPS_CONFIG_XML=${var.m365_apps_config_xml}"
    ]
    script = "${path.root}/scripts/windows/install-m365-apps.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "INSTALL_CITRIX_VDA=${var.install_citrix_vda}",
      "CITRIX_VDA_INSTALLER_URL=${var.citrix_vda_installer_url}",
      "CITRIX_VDA_INSTALLER_ARGS=${var.citrix_vda_installer_args}",
      "CITRIX_VDA_INSTALL_PHASE=initial"
    ]
    script = "${path.root}/scripts/windows/install-citrix-vda.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "45m"
  }

  provisioner "powershell" {
    environment_vars = [
      "INSTALL_CITRIX_VDA=${var.install_citrix_vda}",
      "CITRIX_VDA_INSTALLER_URL=${var.citrix_vda_installer_url}",
      "CITRIX_VDA_INSTALLER_ARGS=${var.citrix_vda_installer_args}",
      "CITRIX_VDA_INSTALL_PHASE=resume"
    ]
    script = "${path.root}/scripts/windows/install-citrix-vda.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "INSTALL_CLOUDPAGING_PLAYER=${var.install_cloudpaging_player}",
      "CLOUDPAGING_PLAYER_INSTALLER_URL=${var.cloudpaging_player_installer_url}",
      "CLOUDPAGING_PLAYER_INSTALLER_ARGS=${var.cloudpaging_player_installer_args}"
    ]
    script = "${path.root}/scripts/windows/install-cloudpaging-player.ps1"
  }

  # install-cloudpaging-player.ps1 treats exit code 3010 (reboot required) as
  # success and continues without restarting - unlike the VDA install above,
  # which has an explicit restart between its initial/resume phases. Without
  # this, sysprep further down can generalize the image mid-install with a
  # pending reboot, which is a known cause of clones hanging on first boot
  # (never reaching a normal login state).
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  provisioner "powershell" {
    environment_vars = [
      "RUN_CITRIX_OPTIMIZER=${var.run_citrix_optimizer}",
      "CITRIX_OPTIMIZER_ZIP_URL=${var.citrix_optimizer_zip_url}",
      "CITRIX_OPTIMIZER_TEMPLATE_NAME=${var.citrix_optimizer_template_name}"
    ]
    script = "${path.root}/scripts/windows/run-citrix-optimizer.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "LOCAL_ADMIN_USERNAME=${var.local_admin_username}",
      "LOCAL_ADMIN_PASSWORD=${var.local_admin_password}"
    ]
    script = "${path.root}/scripts/windows/create-local-admin.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "PREPARE_FOR_CITRIX_MCS=${var.prepare_for_citrix_mcs}"
    ]
    script = "${path.root}/scripts/windows/prepare-citrix-master-image.ps1"
  }

  # Final catch-all reboot before generalizing - clears any reboot still
  # pending from Citrix Optimizer tweaks, local admin account creation, or
  # anything else upstream that the per-step restarts don't specifically
  # cover, so sysprep never captures the image mid-change.
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/windows/sysprep.ps1"
  }
}
