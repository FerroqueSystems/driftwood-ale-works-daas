output "gallery_id" {
  description = "Resource ID of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.this.id
}

output "gallery_name" {
  description = "Name of the Shared Image Gallery"
  value       = azurerm_shared_image_gallery.this.name
}

output "image_definition_id" {
  description = "Resource ID of the VDA image definition - use this as the Packer shared_image_gallery_destination target and as the machine catalog's master image source"
  value       = azurerm_shared_image.vda.id
}

output "image_definition_name" {
  description = "Name of the VDA image definition"
  value       = azurerm_shared_image.vda.name
}
