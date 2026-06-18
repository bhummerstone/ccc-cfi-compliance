# Azure Policy — CCC Centralised Guardrails

Native [Azure Policy](https://learn.microsoft.com/azure/governance/policy/overview)
definitions and an initiative (policy set) that provide **preventive** guardrails for
the CCC controls exercised by the AVM test samples in [`remote/azure/avm`](../avm).

Unlike the detective compliance checks under [`testing/policy`](../../../testing/policy)
(which assert the state of already-deployed resources via `az` CLI queries), these are
`Microsoft.Authorization/policyDefinitions` intended to be assigned **centrally** at
subscription or management-group scope, so non-compliant resources are audited or denied
at deployment time. The same control is therefore enforced from both directions: the AVM
`.tfvars` set the secure value on the resource, and the policy guards against drift.

## Provenance

Derived from the
[`azure-policy-ccc`](https://github.com/bhummerstone/azure-policy-ccc) repository, which
maps FINOS CCC controls to Azure Policy. The two storage definitions are direct reuses of
that repo's custom policies; the rest are authored here from its `mappings/*.yaml`
references in the same JSON convention. Each definition's `metadata.source` records its
origin. These are **examples** — review, validate the field aliases against your tenant
(`az provider show` / Policy alias list), and parameterise before assigning for real.

## Layout

```
policies/
├── versions.tf · provider.tf · variables.tf · main.tf · assignment.tf · outputs.tf
├── storage-account/          # avm-res-storage-storageaccount  (CCC.ObjStor + Core)
├── serverless-function/      # avm-res-web-site                (CCC.SvlsComp + Core)
├── log-analytics-workspace/  # avm-res-operationalinsights-workspace (CCC.Core)
├── key-vault/                # avm-res-keyvault-vault          (CCC.KeyMgmt + Core)
├── virtual-machine/          # avm-res-compute-virtualmachine  (CCC.Core)
└── initiatives/
    └── ccc-avm-initiative.json   # bundles all definitions, grouped by CCC control
```

The `.tf` files create the definitions + initiative from the JSON and assign them; the
JSON files remain the source of truth.

## Coverage by service

Each row is one policy definition. `effect` is the parameterised default (start with
`Audit`, switch guardrails to `Deny` once impact is measured).

### storage-account (`storage-account.tfvars`)
| CCC control | Policy | Effect |
|---|---|---|
| CCC.Core.CN01 | `core-cn01-secure-transfer-tls.json` | Deny |
| CCC.Core.CN02 | `core-cn02-infrastructure-encryption.json` | Audit |
| CCC.Core.CN05 | `core-cn05-network-default-deny.json` | Deny |
| CCC.ObjStor.CN02 | `objstor-cn02-no-public-blob-access.json` | Deny |
| CCC.ObjStor.CN02 | `objstor-cn02-disable-shared-key.json` | Audit |
| CCC.ObjStor.CN04 | `objstor-cn04-blob-soft-delete-retention.json` | Audit |
| CCC.ObjStor.CN05 | `objstor-cn05-blob-versioning.json` | Audit |

### serverless-function (`serverless-function.tfvars`)
| CCC control | Policy | Effect |
|---|---|---|
| CCC.Core.CN01 | `core-cn01-https-only.json` | Deny |
| CCC.Core.CN03 | `core-cn03-managed-identity.json` | Audit |
| CCC.Core.CN05 | `core-cn05-client-certificate.json` | Audit |
| CCC.SvlsComp.CN01 | `svlscomp-cn01-no-public-network.json` | Deny |
| CCC.SvlsComp.CN02 | _gap — rate limiting not expressible as a Policy field_ | — |

### log-analytics-workspace (`log-analytics-workspace.tfvars`)
| CCC control | Policy | Effect |
|---|---|---|
| CCC.Core.CN05 | `core-cn05-no-public-network.json` | Audit |
| CCC.Core.CN09 | `core-cn09-retention.json` | Audit |

### key-vault (`key-vault.tfvars`)
| CCC control | Policy | Effect |
|---|---|---|
| CCC.Core.CN05 | `core-cn05-no-public-network.json` | Deny |
| CCC.KeyMgmt.CN01 | `keymgmt-cn01-purge-protection.json` | Deny |
| CCC.KeyMgmt.CN02 | `keymgmt-cn02-rbac-authorization.json` | Audit |
| CCC.KeyMgmt.CN04 | `keymgmt-cn04-premium-sku.json` | Audit |

### virtual-machine (`virtual-machine.tfvars`)
| CCC control | Policy | Effect |
|---|---|---|
| CCC.Core.CN02 | `core-cn02-encryption-at-host.json` | Audit |
| CCC.Core.CN03 | `core-cn03-managed-identity.json` | Audit |
| CCC.Core.CN04 | `core-cn04-boot-diagnostics.json` | Audit |
| CCC.Core.CN05 | `core-cn05-disable-password-auth.json` | Audit |
| CCC.Core.CN05 | `core-cn05-trusted-launch.json` | Audit |

### Known gaps (no Azure Policy field)
| CCC control | Why | Compensating control |
|---|---|---|
| CCC.SvlsComp.CN02 | Per-caller invocation rate limits are not a resource property | Azure API Management rate-limit policy or Front Door WAF throttling |

Every other control setting present in the five `.tfvars` samples has a corresponding
definition above, giving full coverage of the policy-expressible controls for the
in-scope services.

## Policy-only governance baseline (Policy can, AVM can't)

The definitions above are the *intersection* of "expressible in Azure Policy" and "set by
the AVM samples". Some CCC controls, however, can be enforced by Policy but have **no
AVM-configurable resource property** — they are about what is *allowed to exist* or about
*ongoing posture*, not how a single resource is shaped at deploy time. These are added as a
separate **governance baseline** that references **Azure built-in** policies (toggle with
`include_governance_baseline`). All are report-only (`Audit` / `AuditIfNotExists`) or a
parameterised `Deny`, so **no remediation managed identity is required**.

| CCC control | Built-in policy | GUID | Effect | Why AVM can't |
|---|---|---|---|---|
| CCC.Core.CN06 | Allowed locations | `e56962a6-4747-49cd-b67b-bf8b01975c4c` | Audit (→ Deny) | Trust-perimeter / region governance; AVM deploys to the location you pass, it can't *prevent* a bad one |
| CCC.Core.CN11 | Keys should have a rotation policy… | `d8cf8476-a2ec-4916-896e-992351803c44` | Audit | AVM can wire CMK but can't enforce ongoing rotation cadence |
| CCC.Core.CN04 | Resource logs in Key Vault should be enabled | `cf820ca0-f99e-4f3e-84fb-66e913812d21` | AuditIfNotExists | Existence/drift of diagnostic settings; AVM can't guarantee logs stay on |
| CCC.Core.CN14 | Azure Backup should be enabled for Virtual Machines | `013e242c-8828-4970-87b3-ab247555486d` | AuditIfNotExists | The AVM VM module doesn't configure Recovery Services protection |

> **DeployIfNotExists left out by design.** The CN04 control could auto-deploy diagnostic
> settings via a DINE built-in, but that needs a remediation identity and makes changes to
> resources. Per the report-only intent, the baseline uses the **AuditIfNotExists** variant
> that only flags missing logs. Swap in the DINE built-in (and add an assignment identity)
> if you later want auto-remediation.

Further Policy-only controls worth adding as the perimeter matures (not yet wired):
CCC.Core.CN10 (replication perimeter), CCC.Core.CN13 (certificate rotation lifetime),
CCC.Core.CN08 (geo-redundancy), and VM in-guest posture via Machine Configuration.

## Deploy with Terraform (recommended)

This folder is a self-contained Terraform root module. It creates all definitions, the
initiative, and (optionally) the assignment in one `apply`. There is **no AVM module for
policy/initiative definitions** — those use the native `azurerm_policy_definition` and
`azurerm_policy_set_definition` resources — but the assignment is made through the Azure
Verified Module [`Azure/avm-ptn-policyassignment/azurerm`](https://registry.terraform.io/modules/Azure/avm-ptn-policyassignment/azurerm).

The definitions are read straight from the JSON files via `fileset`/`jsondecode`, so the
JSON remains the single source of truth and the Terraform stays generic — drop a new
`<service>/<control>.json` file in and it is picked up automatically (add a matching entry
to `initiatives/ccc-avm-initiative.json` to include it in the initiative). Initiative
members whose `policyDefinitionId` is a literal `/providers/...` ID (the governance
built-ins) are referenced as-is; members carrying the `{scope}` placeholder resolve to the
custom definitions created in this module.

```bash
cd remote/azure/policies

export TF_VAR_subscription_id="<subscription-id>"

terraform init
terraform apply
```

Key variables (see `variables.tf`):

| Variable | Default | Purpose |
|---|---|---|
| `subscription_id` | — (required) | Provider subscription; default assignment scope. |
| `location` | `westeurope` | Region for the assignment identity (module requirement). |
| `management_group_id` | `null` | Create definitions + initiative at a management group instead of the subscription. |
| `assignment_scope` | provider subscription | Scope the initiative is assigned to. |
| `create_assignment` | `true` | Set `false` to deploy definitions + initiative only. |
| `enforcement_mode` | `Default` | Set `DoNotEnforce` for an audit-only / dry-run roll-out before enforcing `Deny` effects. |
| `include_governance_baseline` | `true` | Include the built-in policy-only governance baseline (CN06/CN11/CN04/CN14). |
| `allowed_locations` | `[]` (→ `[location]`) | CCC.Core.CN06 trust-perimeter regions. |
| `allowed_locations_effect` | `Audit` | CN06 effect; set `Deny` to block out-of-perimeter regions. |
| `key_rotation_maximum_days` | `365` | CCC.Core.CN11 maximum key age before rotation. |
| `governance_log_retention_days` | `365` | CCC.Core.CN04 required log retention (days). |


> **Audit-first roll-out:** start with `enforcement_mode = "DoNotEnforce"` to evaluate
> compliance without blocking deployments, then switch to `Default` once impact is
> understood. Per-definition `effect` defaults still apply (Deny for clear-cut preventable
> misconfigurations, Audit otherwise); change a definition's `effect` `defaultValue` in its
> JSON to soften an individual guardrail.

## Deploy with Azure CLI (alternative)

Definitions first, then the initiative, then assign:

```bash
SCOPE="/subscriptions/<subscription-id>"   # or a management group path

# 1. Create every definition
Get-ChildItem -Recurse -Filter *.json -Path storage-account,serverless-function,log-analytics-workspace,key-vault,virtual-machine |
  ForEach-Object {
    $d = Get-Content $_.FullName -Raw | ConvertFrom-Json
    az policy definition create `
      --name $d.name `
      --display-name $d.properties.displayName `
      --rules ($d.properties.policyRule | ConvertTo-Json -Depth 50 -Compress) `
      --params ($d.properties.parameters | ConvertTo-Json -Depth 50 -Compress) `
      --mode $d.properties.mode
  }

# 2. Create the initiative (substitute {scope} in policyDefinitionId first)
az policy set-definition create `
  --name ccc-avm-initiative `
  --definitions (Get-Content initiatives/ccc-avm-initiative.json -Raw).Replace('{scope}', $SCOPE) `
  ...

# 3. Assign at the desired scope
az policy assignment create --name ccc-avm --policy-set-definition ccc-avm-initiative --scope $SCOPE
```

> The initiative's `policyDefinitionId` values use a `{scope}` placeholder — replace it
> with the subscription ID or management-group path where the definitions were created.
