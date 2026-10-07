variable "subscription_id" {
  description = "The ID of the Azure subscription to manage RBAC for."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid UUID."
  }
}

variable "privilege_level_assignments" {
  description = <<-EOT
    Map of privilege levels (0-15) to Entra ID group assignments.
    Each level can specify group_object_ids, group_display_names, or both.
    Display names are resolved via the azuread_group data source.
  EOT
  type = map(object({
    group_object_ids    = optional(list(string), [])
    group_display_names = optional(list(string), [])
  }))

  validation {
    condition = alltrue([
      for k, _ in var.privilege_level_assignments :
      can(tonumber(k)) && tonumber(k) >= 0 && tonumber(k) <= 15
    ])
    error_message = "Privilege level keys must be numbers between 0 and 15."
  }

  validation {
    condition = alltrue([
      for k, v in var.privilege_level_assignments :
      length(v.group_object_ids) > 0 || length(v.group_display_names) > 0
    ])
    error_message = "Each privilege level assignment must specify at least one group_object_id or group_display_name."
  }
}

variable "role_overrides" {
  description = "Replace the default role list for a privilege level entirely. Keys are level numbers (0-15)."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for k, _ in var.role_overrides :
      can(tonumber(k)) && tonumber(k) >= 0 && tonumber(k) <= 15
    ])
    error_message = "Role override keys must be numbers between 0 and 15."
  }

  validation {
    condition = alltrue([
      for _, roles in var.role_overrides :
      !contains(roles, "Owner")
    ])
    error_message = "Owner role assignments are not permitted by this module (managed at management group level)."
  }
}

variable "additional_roles" {
  description = "Add roles to a privilege level's defaults without replacing them. Keys are level numbers (0-15)."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for k, _ in var.additional_roles :
      can(tonumber(k)) && tonumber(k) >= 0 && tonumber(k) <= 15
    ])
    error_message = "Additional role keys must be numbers between 0 and 15."
  }

  validation {
    condition = alltrue([
      for _, roles in var.additional_roles :
      !contains(roles, "Owner")
    ])
    error_message = "Owner role assignments are not permitted by this module (managed at management group level)."
  }
}

variable "custom_role_definitions" {
  description = <<-EOT
    Custom Azure role definitions to create at the subscription scope.
    Keys are role names. Once created, reference by name in role_overrides or additional_roles.
  EOT
  type = map(object({
    description      = optional(string, "")
    actions          = optional(list(string), [])
    not_actions      = optional(list(string), [])
    data_actions     = optional(list(string), [])
    not_data_actions = optional(list(string), [])
  }))
  default = {}
}
