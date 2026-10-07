# terraform-azurerm-rbac-subscription

Terraform module for managing Azure RBAC role assignments at the subscription level using a Cisco-style privilege level system (0-15).

Each privilege level maps to a default set of Azure built-in roles. Callers assign Entra ID groups to privilege levels, and the module creates the corresponding role assignments. Default roles can be overridden or extended per level, and custom role definitions can be created at the subscription scope.

## Default Privilege Levels

| Level | Name | Default Roles |
|-------|------|---------------|
| 0 | None | *(none)* |
| 1 | Low | `Reader` |
| 2-4 | *(reserved)* | *(none)* |
| 5 | Mid | `Reader`, `Azure Kubernetes Service RBAC Reader`, `AKS Port Forward`* |
| 6-9 | *(reserved)* | *(none)* |
| 10 | High | `Contributor`, `Key Vault Secrets Officer` |
| 11-15 | *(reserved)* | *(none)* |

Levels 2-4, 6-9, and 11-15 are empty by default and available for future use via `role_overrides` or `additional_roles`.

*\* Custom role created by the module — allows pod operations (port-forward, logs, etc.) but blocks exec and delete.*

> **Note:** Owner role assignments are explicitly blocked by this module. Owner access should be managed at the management group level.

## Default Custom Roles

The module includes built-in custom role definitions that are created automatically at the subscription scope. These can be overridden by passing a role with the same name in `custom_role_definitions`.

| Role | Included in Level | Description |
|------|-------------------|-------------|
| `AKS Port Forward` | 5 (Mid) | Grants `Microsoft.ContainerService/managedClusters/pods/*` but denies `pods/exec/action` and `pods/delete` |

## Usage

### Minimal

Assign a single group to the default "Low" privilege level using its object ID:

```hcl
module "rbac" {
  source = "github.com/AlexBritton-CAL/terraform-azurerm-rbac-subscription"

  subscription_id = "00000000-0000-0000-0000-000000000000"

  privilege_level_assignments = {
    "1" = {
      group_object_ids = ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
    }
  }
}
```

### Full

Demonstrates all features: multiple levels, group lookup by display name, additional roles, role overrides, and custom role definitions.

```hcl
module "rbac" {
  source = "github.com/AlexBritton-CAL/terraform-azurerm-rbac-subscription"

  subscription_id = "00000000-0000-0000-0000-000000000000"

  privilege_level_assignments = {
    # Low — control plane read-only
    "1" = {
      group_object_ids    = ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
      group_display_names = ["SG-Platform-Readers"]
    }

    # Mid — control plane + data plane read
    "5" = {
      group_display_names = ["SG-AKS-Readers"]
    }

    # High — break glass
    "10" = {
      group_object_ids = ["ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj"]
    }

    # Custom level using role_overrides below
    "3" = {
      group_display_names = ["SG-Network-Team"]
    }
  }

  # Add Network Contributor to the Mid level alongside its defaults
  additional_roles = {
    "5" = ["Network Contributor"]
  }

  # Replace level 3's defaults entirely with a custom set
  role_overrides = {
    "3" = ["Reader", "Custom Diagnostics Reader"]
  }

  # Define custom roles at the subscription scope
  custom_role_definitions = {
    "Custom Diagnostics Reader" = {
      description = "Read diagnostic settings and activity logs."
      actions = [
        "Microsoft.Insights/diagnosticSettings/read",
        "Microsoft.Insights/activityLogAlerts/read",
      ]
    }

    "Custom Cost Reader" = {
      description = "Read cost and billing data."
      actions = [
        "Microsoft.CostManagement/*/read",
        "Microsoft.Consumption/*/read",
      ]
    }
  }
}
```

### Adding Custom Roles

Define custom Azure role definitions and attach them to any privilege level. Custom roles are created at the subscription scope and can be referenced by name in `additional_roles` or `role_overrides`.

Multiple custom roles are defined as entries in a single `custom_role_definitions` map — not as separate blocks. Each key is the role name, and only the fields you need are required (all default to empty lists).

```hcl
module "rbac" {
  source = "github.com/AlexBritton-CAL/terraform-azurerm-rbac-subscription"

  subscription_id = "00000000-0000-0000-0000-000000000000"

  privilege_level_assignments = {
    "5" = {
      group_display_names = ["SG-AKS-Readers"]
    }
    "10" = {
      group_object_ids = ["ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj"]
    }
  }

  # All custom roles go in one map
  custom_role_definitions = {
    "Custom Diagnostics Reader" = {
      description = "Read diagnostic settings and activity logs."
      actions = [
        "Microsoft.Insights/diagnosticSettings/read",
        "Microsoft.Insights/activityLogAlerts/read",
      ]
    }

    "Custom Storage Blob Reader" = {
      description = "Read blobs without full Storage Account access."
      data_actions = [
        "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      ]
    }
  }

  # Then attach them by name to one or more levels
  additional_roles = {
    "5"  = ["Custom Diagnostics Reader"]
    "10" = ["Custom Diagnostics Reader", "Custom Storage Blob Reader"]
  }
}
```

Available fields for each custom role definition:

| Field | Description | Default |
|-------|-------------|---------|
| `description` | Role description | `""` |
| `actions` | Allowed control plane actions | `[]` |
| `not_actions` | Denied control plane actions | `[]` |
| `data_actions` | Allowed data plane actions | `[]` |
| `not_data_actions` | Denied data plane actions | `[]` |

## Providers

Both `azurerm` and `azuread` providers must be configured. The `azuread` provider is only used when `group_display_names` are provided, but Terraform initialises it regardless.

```hcl
provider "azurerm" {
  features {}
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

provider "azuread" {}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `subscription_id` | Target Azure subscription ID. | `string` | — | yes |
| `privilege_level_assignments` | Map of privilege levels (0-15) to Entra ID group assignments. Each level accepts `group_object_ids` and/or `group_display_names`. | `map(object)` | — | yes |
| `role_overrides` | Replace the default role list for a privilege level entirely. | `map(list(string))` | `{}` | no |
| `additional_roles` | Add roles to a privilege level's defaults without replacing them. | `map(list(string))` | `{}` | no |
| `custom_role_definitions` | Custom Azure role definitions to create at the subscription scope. Keys are role names. | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `role_assignments` | Map of all created role assignments (principal_id, role_name, scope). |
| `custom_role_definition_ids` | Map of custom role name to role definition resource ID. |
| `resolved_group_ids` | Map of group display name to resolved object ID. |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.6 |
| azurerm | ~> 4.0 |
| azuread | ~> 3.0 |
