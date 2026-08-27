# Image Gallery Module

Azure Shared Image Gallery (Azure Compute Gallery) and image definition that
the [Packer golden-image pipeline](../../packer/README.md) publishes VDA
master images into.

This module only manages the gallery and image *definition* (the long-lived
container). Image *versions* are created by Packer during each build, not by
Terraform - keeping build-time artifacts out of Terraform state.

The resulting `image_definition_id` output is what the Citrix machine catalog
will reference as its master image source once machine catalogs are
scaffolded.
