data "azurerm_resource_group" "x" {
  name = var.arm_template_parameters.resource_group_name
}

resource "azurerm_resource_group_template_deployment" "quorum" {
  name                = "terraform-${var.arm_template_parameters.name_prefix}"
  resource_group_name = data.azurerm_resource_group.x.name
  deployment_mode     = "Complete"
  template_content    = file("${path.module}/arm-custom/azuredeploy.json")
  parameters_content = jsonencode({
    "namePrefix"         = { value = var.arm_template_parameters.name_prefix }
    "env"                = { value = "prod" }
    "aksNodeVmSize"      = { value = var.arm_template_parameters.vm_size }
    "aksNodeCount"       = { value = var.arm_template_parameters.node_count }
    "aksNodeDiskSizeGB"  = { value = var.arm_template_parameters.node_disksize_gb }
    "bcClient"           = { value = "goq" }
    "location"           = { value = data.azurerm_resource_group.x.location }
    "vnetAddressCIDR"    = { value = var.arm_template_parameters.subnet }
    "subnet1AddressCIDR" = { value = var.arm_template_parameters.subnet }
  })
}

data "azurerm_kubernetes_cluster" "x" {
  name                = jsondecode(azurerm_resource_group_template_deployment.quorum.output_content).cluster.value
  resource_group_name = data.azurerm_resource_group.x.name
}

resource "null_resource" "quorum_bootstrap" {
  depends_on = [azurerm_resource_group_template_deployment.quorum]
  provisioner "local-exec" {
    working_dir = "${path.module}/arm-custom"
    command     = <<-EOT
      az extension add --name aks-preview \
      && ./bootstrap.sh \
        ${data.azurerm_resource_group.x.name} \
        ${jsondecode(azurerm_resource_group_template_deployment.quorum.output_content).cluster.value} \
        ${jsondecode(azurerm_resource_group_template_deployment.quorum.output_content).managedIdentity.value} \
        quorum
    EOT
    interpreter = ["/bin/sh", "-c"]
  }
}

resource "null_resource" "enable_http_application_routing" {
  depends_on = [null_resource.quorum_bootstrap]
  provisioner "local-exec" {
    command = <<-EOT
      az aks enable-addons \
        --resource-group ${data.azurerm_resource_group.x.name} \
        --name ${jsondecode(azurerm_resource_group_template_deployment.quorum.output_content).cluster.value} \
        --addons http_application_routing
    EOT
  }
}
