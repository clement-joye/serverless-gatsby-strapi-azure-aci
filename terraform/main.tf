################################## PROVIDERS ##################################
# --------------------------------------------------------------------------- #
###############################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.10.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

################################## RESOURCES ##################################
# -------------------------------------------------------------------------- -#
###############################################################################

data "azurerm_subscription" "primary" {
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}"
  location = var.location
}

resource "azurerm_storage_account" "sa" {
  name                      = "sa${var.project_name}aci"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier              = "Standard"
  account_kind              = "StorageV2"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
}

resource "azurerm_storage_container" "sc" {
  name                  = "media"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "blob"
}

resource "azurerm_storage_share" "caddy_share_strapi_prod" {
  name                 = "aci-caddy-strapi-prod"
  storage_account_name = azurerm_storage_account.sa.name
  quota                = 1
}

resource "azurerm_storage_share" "caddy_share_gatsby_prod" {
  name                 = "aci-caddy-gatsby-prod"
  storage_account_name = azurerm_storage_account.sa.name
  quota                = 1
}

resource "azurerm_storage_share" "strapi_share_prod" {
  name                 = "aci-strapi-db-prod"
  storage_account_name = azurerm_storage_account.sa.name
  quota                = 1
}

resource "azurerm_service_plan" "asp" {
  name                = "asp-${var.project_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = "${var.location}"
  os_type             = "Windows"
  sku_name            = "Y1"
}

resource "azurerm_windows_function_app" "fa" {
  name                        = "fa-${var.project_name}-prod"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = "${var.location}"
  service_plan_id             = azurerm_service_plan.asp.id
  storage_account_name        = azurerm_storage_account.sa.name
  storage_account_access_key  = azurerm_storage_account.sa.primary_access_key
  functions_extension_version = "~4"
  https_only                  = true
  ftps_state                  = "FtpsOnly"

  site_config {
    application_insights_key = "${azurerm_application_insights.appi.instrumentation_key}"
    application_stack {
      powershell_core_version = 7
    }
  }

  identity { 
    type = "SystemAssigned" 
  }

  

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "powershell"
    "WEBSITE_RUN_FROM_PACKAGE"       = "1"
    "RESOURCE_GROUP_NAME"            = "rg-${var.project_name}"
    "STRAPI_CONTAINER_GROUP_NAME"    = "aci-${var.project_name}-strapi-prod"
    "GATSBY_CONTAINER_GROUP_NAME"    = "aci-${var.project_name}-gatsby-prod"
    "STRAPI_ACI_URL"                 = "https://aci-${var.project_name}-strapi-prod.${var.location}.azurecontainer.io"
    "GATSBY_ACI_URL"                 = "https://aci-${var.project_name}-gatsby-prod.${var.location}.azurecontainer.io"
    "SUBSCRIPTION_ID"                = var.subscription_id
  }
}

data "azurerm_function_app_host_keys" "fa_host_keys" {
  name                = azurerm_windows_function_app.fa.name
  resource_group_name = azurerm_resource_group.rg.name

  depends_on = [azurerm_windows_function_app.fa]
}

resource "azurerm_application_insights" "appi" {
  name                = "ai-${var.project_name}-prod"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "other"
}

resource "azurerm_role_assignment" "role" {
  scope                = "${data.azurerm_subscription.primary.id}/resourceGroups/${azurerm_resource_group.rg.name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_windows_function_app.fa.identity[0].principal_id
}

resource "azurerm_container_group" "aci_strapi" {
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = var.location
  name                      = "aci-${var.project_name}-strapi-prod"
  os_type                   = "Linux"
  dns_name_label            = "aci-${var.project_name}-strapi-prod"
  ip_address_type           = "Public"
  restart_policy            = "OnFailure"

  image_registry_credential {
    username = var.image_registry_credential_username
    password = var.image_registry_credential_password
    server   = var.image_registry_credential_server
  }

  container {
    name   = "${var.project_name}_strapi_aci"
    image  = "${var.image_registry_credential_server}/${var.project_name}_strapi_aci:latest"
    cpu    = "0.5"
    memory = "0.5"
    environment_variables = {
      FUNCTION_APP_URL    = "https://${azurerm_windows_function_app.fa.name}.azurewebsites.net/api/UpdateAci?action=stop&code=${data.azurerm_function_app_host_keys.fa_host_keys.default_function_key}"
      STRAPI_TIMEOUT      = "600"
      STORAGE_ACCOUNT     = azurerm_storage_account.sa.name
      STORAGE_ACCOUNT_KEY = azurerm_storage_account.sa.primary_access_key
    }

    volume {
      name                 = "aci-strapi-db-prod"
      mount_path           = "/opt/app/tmp/"
      storage_account_name = azurerm_storage_account.sa.name
      storage_account_key  = azurerm_storage_account.sa.primary_access_key
      read_only            = false
      share_name           = azurerm_storage_share.strapi_share_prod.name
    }
  }

  container {
    name   = "caddy"
    image  = "caddy"
    cpu    = "0.5"
    memory = "0.5"

    ports {
      port     = 443
      protocol = "TCP"
    }

    ports {
      port     = 80
      protocol = "TCP"
    }

    volume {
      name                 = "aci-caddy-strapi-prod"
      mount_path           = "/data"
      storage_account_name = azurerm_storage_account.sa.name
      storage_account_key  = azurerm_storage_account.sa.primary_access_key
      share_name           = azurerm_storage_share.caddy_share_strapi_prod.name
    }

    commands = ["caddy", "reverse-proxy", "--from", "aci-${var.project_name}-strapi-prod.${var.location}.azurecontainer.io", "--to", "localhost:8080"]
  }
}

resource "azurerm_container_group" "aci_gatsby" {
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = var.location
  name                      = "aci-${var.project_name}-gatsby-prod"
  os_type                   = "Linux"
  dns_name_label            = "aci-${var.project_name}-gatsby-prod"
  ip_address_type           = "Public"
  restart_policy            = "OnFailure"

  image_registry_credential {
    username = var.image_registry_credential_username
    password = var.image_registry_credential_password
    server   = var.image_registry_credential_server
  }

  container {
    name   = "${var.project_name}_gatsby_aci"
    image  = "${var.image_registry_credential_server}/${var.project_name}_gatsby_aci:latest"
    cpu    = "2"
    memory = "2"
    environment_variables = {
      ENABLE_GATSBY_REFRESH_ENDPOINT  = true
      GRAPHQL_URL                     = "https://aci-${var.project_name}-strapi-prod.${var.location}.azurecontainer.io/graphql"
    }
  }

  container {
    name   = "caddy"
    image  = "caddy"
    cpu    = "0.5"
    memory = "0.5"

    ports {
      port     = 443
      protocol = "TCP"
    }

    ports {
      port     = 80
      protocol = "TCP"
    }

    volume {
      name                 = "aci-caddy-gatsby-prod"
      mount_path           = "/data"
      storage_account_name = azurerm_storage_account.sa.name
      storage_account_key  = azurerm_storage_account.sa.primary_access_key
      share_name           = azurerm_storage_share.caddy_share_gatsby_prod.name
    }

    commands = ["caddy", "reverse-proxy", "--from", "aci-${var.project_name}-gatsby-prod.${var.location}.azurecontainer.io", "--to", "localhost:8000"]
  }
}

output "strapi_aci_url" {
  value = "https://${azurerm_container_group.aci_strapi.fqdn}"
  description = "Url to Strapi ACI"
}

output "gatsby_aci_url" {
  value = "https://${azurerm_container_group.aci_gatsby.fqdn}"
  description = "Url to Gatsby ACI"
}

output "fa_start_url" {
  value = "https://${azurerm_windows_function_app.fa.name}.azurewebsites.net/api/UpdateAci?action=start&code=${data.azurerm_function_app_host_keys.fa_host_keys.default_function_key}"
  description = "Url to start ACI"
  sensitive = true
}
