locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"

  default_custom_role_definitions = {
    "AKS Port Forward" = {
      description = "Allow port forwarding to pods without exec or delete access."
      actions     = []
      not_actions = []
      data_actions = [
        "Microsoft.ContainerService/managedClusters/pods/*",
      ]
      not_data_actions = [
        "Microsoft.ContainerService/managedClusters/pods/exec/action",
        "Microsoft.ContainerService/managedClusters/pods/delete",
      ]
    }
  }

  all_custom_role_definitions = merge(local.default_custom_role_definitions, var.custom_role_definitions)

  default_privilege_levels = {
    "0"  = []
    "1"  = ["Reader"]
    "2"  = []
    "3"  = []
    "4"  = []
    "5"  = ["Reader", "Azure Kubernetes Service RBAC Reader", "AKS Port Forward"]
    "6"  = []
    "7"  = []
    "8"  = []
    "9"  = []
    "10" = ["Contributor", "Key Vault Secrets Officer"]
    "11" = []
    "12" = []
    "13" = []
    "14" = []
    "15" = []
  }

  effective_roles_per_level = {
    for level, default_roles in local.default_privilege_levels :
    level => distinct(
      contains(keys(var.role_overrides), level)
      ? var.role_overrides[level]
      : concat(default_roles, try(var.additional_roles[level], []))
    )
  }

  all_display_names = toset(flatten([
    for _, assignment in var.privilege_level_assignments :
    assignment.group_display_names
  ]))

  resolved_groups_per_level = {
    for level, assignment in var.privilege_level_assignments :
    level => distinct(concat(
      assignment.group_object_ids,
      [for name in assignment.group_display_names : data.azuread_group.lookup[name].object_id]
    ))
  }

  role_assignments = {
    for entry in flatten([
      for level, group_ids in local.resolved_groups_per_level : [
        for group_id in group_ids : [
          for role in local.effective_roles_per_level[level] : {
            key       = "lvl${level}_grp${group_id}_role${replace(role, " ", "-")}"
            level     = level
            group_id  = group_id
            role_name = role
            is_custom = contains(keys(local.all_custom_role_definitions), role)
          }
        ]
      ]
    ]) : entry.key => entry
  }
}
