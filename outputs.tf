output "role_assignments" {
  description = "Map of all created role assignments."
  value = {
    for k, v in azurerm_role_assignment.this :
    k => {
      principal_id = v.principal_id
      role_name    = local.role_assignments[k].role_name
      scope        = v.scope
    }
  }
}

output "custom_role_definition_ids" {
  description = "Map of custom role name to role definition resource ID."
  value = {
    for k, v in azurerm_role_definition.custom :
    k => v.role_definition_resource_id
  }
}

output "resolved_group_ids" {
  description = "Map of group display name to resolved object ID."
  value = {
    for name, group in data.azuread_group.lookup :
    name => group.object_id
  }
}
