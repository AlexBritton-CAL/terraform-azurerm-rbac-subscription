data "azurerm_subscription" "current" {
  subscription_id = var.subscription_id
}

data "azuread_group" "lookup" {
  for_each = local.all_display_names

  display_name     = each.value
  security_enabled = true
}

resource "azurerm_role_definition" "custom" {
  for_each = local.all_custom_role_definitions

  name  = "${each.key} ${data.azurerm_subscription.current.display_name}"
  scope = local.subscription_scope

  permissions {
    actions          = each.value.actions
    not_actions      = each.value.not_actions
    data_actions     = each.value.data_actions
    not_data_actions = each.value.not_data_actions
  }

  assignable_scopes = [local.subscription_scope]
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope                = local.subscription_scope
  principal_id         = each.value.group_id
  role_definition_name = each.value.is_custom ? null : each.value.role_name
  role_definition_id   = each.value.is_custom ? azurerm_role_definition.custom[each.value.role_name].role_definition_resource_id : null
}
