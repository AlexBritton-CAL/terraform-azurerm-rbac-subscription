# CLAUDE.md

## What this module does

Terraform module that manages Azure RBAC role assignments at the subscription level. It uses a Cisco IOS-style privilege level system (0–15) where each level maps to a set of Azure roles. Callers assign Entra ID groups to privilege levels; the module creates the role assignments.

## Architecture decisions

### Privilege levels 0–15 (Cisco-style)

Chosen over named tiers (Reader/Contributor/Owner) to allow future expansion without interface changes. 16 levels provides enough headroom — currently only 3 are populated (1, 5, 10) with gaps between them for inserting new tiers later. The numbering is arbitrary; the gaps are intentional.

### Owner role is blocked

Owner access is managed at the management group level, not subscription. The module enforces this with validation blocks on `role_overrides` and `additional_roles` — passing "Owner" is a hard error, not just a convention.

### Two mechanisms for customising roles per level

- **`role_overrides`** — completely replaces the default role list for a level. Use when the defaults are wrong for a specific subscription.
- **`additional_roles`** — appends to the defaults. Use when the defaults are fine but a subscription needs extras (e.g., Network Contributor at level 5).

When both are provided for the same level, `role_overrides` wins (the override replaces defaults, so there's nothing for `additional_roles` to append to). This is by design — override means override.

### Default custom roles vs caller custom roles

The module ships with built-in custom role definitions in `local.default_custom_role_definitions` (e.g., "AKS Port Forward"). Callers can also pass their own via `var.custom_role_definitions`. These are merged in `local.all_custom_role_definitions` — caller definitions take precedence if they use the same name, allowing overrides of the defaults.

### Group resolution — object IDs and display names

Both `group_object_ids` and `group_display_names` are optional per privilege level. The module resolves display names via `data.azuread_group.lookup` and merges the results with any directly-provided object IDs, deduplicating with `distinct()`.

The `azuread` provider is always initialised (it's in `required_providers`) even when no display names are used. This means the caller must configure it, but it won't make API calls unless display names are present. The `security_enabled = true` filter on the data source assumes Entra ID security groups — this is intentional for RBAC use cases.

### Flattening pattern for `for_each`

The core complexity is in `locals.tf`. The chain is:

1. `default_privilege_levels` — static map of level → role names
2. `effective_roles_per_level` — merges defaults with overrides/additions
3. `all_display_names` — flattened set driving the `azuread_group` data source
4. `resolved_groups_per_level` — merges object IDs with resolved display name IDs
5. `role_assignments` — triple-nested flatten (level → group → role) producing a flat map keyed as `lvl{N}_grp{id}_role{name}` for stable `for_each` addressing

### `for_each` over `count`

All resources use `for_each` with descriptive keys. This means adding/removing a group or role doesn't cause unrelated resources to be destroyed and recreated (which `count` with index-based addressing would).

### Custom role detection in role assignments

`azurerm_role_assignment` uses `role_definition_name` for built-in Azure roles and `role_definition_id` for custom roles. The `is_custom` flag in `local.role_assignments` checks if the role name exists in `local.all_custom_role_definitions` to pick the right attribute. The other attribute is set to `null`.

### Custom role names are suffixed with the subscription display name

Azure custom role names must be unique within a tenant. Since this module is deployed per-subscription, a `data.azurerm_subscription.current` lookup appends the subscription display name to each custom role's Azure name (e.g. "AKS Port Forward NP-DI"). Internal keys (locals, privilege levels, `for_each`) use the short name — only the `name` attribute on `azurerm_role_definition.custom` gets the suffix.

## File layout

| File | Responsibility |
|------|---------------|
| `versions.tf` | Provider requirements (azurerm ~> 4.0, azuread ~> 3.0) and terraform version constraint (>= 1.6) |
| `variables.tf` | All inputs with types, defaults, descriptions, and validation blocks |
| `locals.tf` | Default privilege levels, default custom roles, role merging logic, group resolution, assignment flattening |
| `main.tf` | Resources: `azuread_group` data source, `azurerm_role_definition`, `azurerm_role_assignment` |
| `outputs.tf` | Three outputs: role_assignments, custom_role_definition_ids, resolved_group_ids |

## Current default privilege levels

| Level | Purpose | Roles |
|-------|---------|-------|
| 0 | No access | *(empty)* |
| 1 | Low — control plane read | Reader |
| 5 | Mid — control + data plane read | AcrPull, AKS Port Forward (custom), App Configuration Data Owner, App Configuration Reader, Azure Event Hubs Data Receiver, Azure Kubernetes Service Cluster User Role, Azure Kubernetes Service RBAC Reader, Azure Kubernetes Service RBAC Writer, Azure Service Bus Data Receiver, Azure Service Bus Data Sender, Cosmos DB Account Reader Role, Cosmos DB Operator, Key Vault Certificate User, Key Vault Purge Operator, Key Vault Secrets Officer, Reader, Redis Cache Contributor, SQL DB Contributor, Storage Account Contributor, Storage Blob Data Contributor |
| 10 | High — break glass | App Configuration Contributor, Azure Kubernetes Service Cluster Admin Role, Azure Service Bus Data Owner, Contributor, DocumentDB Account Contributor, Key Vault Secrets Officer |
| 2–4, 6–9, 11–15 | Reserved for future use | *(empty)* |

## Current default custom roles

| Name | Actions | Data Actions | Denied Data Actions | Rationale |
|------|---------|-------------|-------------------|-----------|
| AKS Port Forward | `managedClusters/listClusterUserCredential/action`, `managedClusters/read` | `managedClusters/pods/*`, `managedClusters/services/*` | `pods/exec/action`, `pods/delete`, `services/write`, `services/delete` | Allows port-forwarding, log access, and service listing on pods without granting exec, delete, or service mutation — needed at level 5 for debugging without full cluster write access |

## How to add a new default privilege level

1. Add roles to the level's entry in `local.default_privilege_levels` in `locals.tf`
2. If the level needs a new custom role, add it to `local.default_custom_role_definitions` in `locals.tf`
3. Update the privilege levels table in `README.md`
4. Run `terraform validate`

## How to add a new default custom role

1. Add the role definition to `local.default_custom_role_definitions` in `locals.tf`
2. Reference the role by name in the appropriate level in `local.default_privilege_levels`
3. Update the "Default Custom Roles" section in `README.md`
4. Run `terraform validate`

## Gotchas

- **Map keys are strings.** Privilege level keys in all variables must be quoted strings (`"1"`, not `1`), because Terraform map keys are always strings.
- **azuread provider must be configured** even if you only use `group_object_ids`. Terraform initialises all providers in `required_providers` regardless of whether their resources/data sources are created.
- **Same group at multiple levels is fine.** Each level produces separate role assignments with distinct keys. A group at level 1 (Reader) and level 5 (Reader + AKS roles) gets all roles from both levels.
- **`role_overrides` suppresses `additional_roles`** for the same level. If level 5 has both an override and additions, only the override takes effect.
- **Custom role names must be unique across defaults and caller definitions.** If a caller passes a custom role with the same name as a default, the caller's definition wins (merge behaviour).
