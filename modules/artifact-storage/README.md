# Artifact Storage Module

Private Azure Storage account and blob container that hold [Packer golden-image pipeline](../../packer/README.md) build artifacts:
the Citrix VDA installer, the Citrix Optimizer zip, and any custom optimizer
templates.

The storage account has anonymous/public blob access disabled
(`allow_nested_items_to_be_public = false`) and the container access type is
`private`. Upload artifacts with the Azure CLI or AzCopy, then generate
short-lived, read-only SAS URLs for the specific blobs Packer needs - see
[packer/images](../../packer/images/README.md) for the upload/SAS workflow and
`citrix_vda_installer_url` / `citrix_optimizer_zip_url` in the Packer
`*.pkrvars.hcl` files.
