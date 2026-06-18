# Cilium Standalone Host Validation Design

Date: 2026-06-18
Status: Draft for review
Owner: Codex

## Goal

Clone the repository's existing Calico-based validation pattern into a Cilium-based validation plan that:

- keeps one Kubernetes cluster as the only source of truth for policy
- validates Cilium-controlled traffic behavior for:
  - Kubernetes nodes in the cluster
  - one standalone Linux VM
  - one standalone Windows Server VM
- mirrors the current repo's first-round test style:
  - narrow blast radius
  - dedicated test service and port
  - allow/deny matrix
  - no first-pass interference with SSH, RDP, Kubernetes control-plane traffic, or general host access
- records Windows limitations explicitly and treats a well-evidenced fail as a valid result

## Non-Goals

- No production-ready mixed-OS policy platform is promised by this design.
- No attempt is made to prove workload identity on standalone hosts in round 1.
- No attempt is made to enforce broad all-port host lockdown in round 1.
- No attempt is made to prove multi-cluster Cilium policy distribution in round 1.
- No attempt is made to hide Cilium feature gaps behind custom translation layers.

## Repo Context

This repository already contains a repeatable Azure VM lab and a validation pattern for:

- one jumpbox
- one primary k3s cluster
- standalone Linux VMs
- optional second k3s cluster
- narrow experiment-specific manifests and scripts

The existing Calico experiments prove a useful test shape:

- establish a stable infrastructure baseline first
- isolate policy validation to a dedicated port and service
- keep rollback simple
- produce a connectivity matrix and an explicit expected/actual result table

This design keeps that test shape and replaces the control model with Cilium where possible.

## Constraints And Known Product Shape

### Cilium Controller Model

Current Cilium's default and documented control model is Kubernetes-centric:

- policy and state are normally distributed through Kubernetes CRDs
- host policy is documented for Kubernetes nodes through `CiliumClusterwideNetworkPolicy` with `nodeSelector`
- running Cilium without Kubernetes requires a key-value store such as `etcd`

This means a true "one Kubernetes cluster distributes host policy uniformly to arbitrary standalone hosts" model is not a first-class current Cilium shape in the same way the existing Calico lab is.

### Linux Standalone Host Path

The closest upstream Cilium analogue for a standalone host is the older `external-workloads` path:

- the VM joins through `clustermesh-apiserver`
- the VM is represented as a Cilium-managed external workload
- policy is enforced as endpoint-style policy on the joined workload
- upstream documentation for this path required:
  - recent Linux kernel
  - Docker
  - IP reachability with the cluster
- upstream documentation marked this feature deprecated before removal in Cilium `v1.18`

Therefore the Linux standalone VM can be tested, but the test must explicitly state:

- this is a deprecated onboarding path
- this is not the same primitive as Kubernetes node host policy
- any pass result is a lab validation result, not a forward-looking support guarantee

### Windows Standalone Host Path

No official standalone Windows onboarding path has been identified for current Cilium in the same shape as:

- Kubernetes node host firewall
- Linux external workloads
- CRD-distributed host policy on a standalone Windows VM

This design therefore treats Windows as:

- an explicit validation target
- an expected high-risk target
- a target that may conclude with a documented fail if all plausible onboarding attempts are exhausted

The result must distinguish:

- "Windows failed because the lab was wrong"
- from
- "Windows failed because no viable Cilium standalone attachment/enforcement path was found"

## Recommended Architecture

### Topology

Round 1 should provision:

- 1 jumpbox VM
- 1 k3s server VM
- 2 k3s agent VMs
- 1 standalone Linux VM
- 1 standalone Windows Server VM

The cluster remains:

- k3s
- Cilium as the only CNI and policy engine inside the cluster
- the single source of truth for all authored policy objects

### Attachment Model By Target

#### Kubernetes Nodes

Use Cilium host firewall / host policy on selected cluster nodes.

Mechanism:

- enable the relevant Cilium host-policy path in the cluster
- attach narrow labels to one or more nodes
- apply `CiliumClusterwideNetworkPolicy` using `nodeSelector`

This is the cleanest and most directly supported Cilium target in the lab.

#### Linux Standalone VM

Use the legacy external workload path as the closest available Cilium-managed analogue.

Mechanism:

- enable the external-workload / clustermesh support on a Cilium version that still contains it
- register the Linux VM as an external workload
- install the Cilium external workload agent/container on the Linux VM
- target it with endpoint-style Cilium policy from the cluster

Important limitation:

- this is not the same enforcement primitive as cluster-node host firewall
- result reporting must call this out explicitly

#### Windows Standalone VM

Attempt attachment as a standalone host receiving cluster-authored policy.

Candidate paths to test in order:

1. Look for a supported or reconstructible standalone Windows Cilium agent path that can connect to the cluster control plane.
2. Look for an older external-workload-style path that is valid on Windows.
3. If neither exists, record Windows as a validated fail with evidence.

Important limitation:

- no fallback translation into Windows Firewall is allowed in round 1
- otherwise the experiment would stop being a Cilium-managed validation

## Validation Questions

This round must answer:

1. Can Cilium host policy be applied safely to selected k3s nodes without destabilizing the cluster?
2. Can a standalone Linux VM be attached to the cluster's Cilium policy plane using the legacy external-workload mechanism?
3. Can a standalone Windows Server VM be attached to the same policy plane in a meaningful way?
4. If Windows cannot be attached, can the failure be attributed clearly to product limitations rather than lab error?
5. Does the first-round allow/deny matrix behave exactly as expected on the targets that do attach?

## Success Criteria

### Overall

- k3s and Cilium remain healthy throughout the test window
- the round-1 allow/deny matrix is reproducible
- all limitations are stated explicitly in the result

### Kubernetes Node Success

- selected nodes receive host policy
- test port behavior matches the expected matrix
- cluster health and pod networking remain intact

### Linux VM Success

- the Linux VM joins through the chosen external-workload path
- the Linux VM is visible to the cluster in the expected Cilium objects/status views
- test port behavior matches the expected matrix
- the final report labels this as a deprecated-path result

### Windows VM Success

Any of the following counts as success for the purpose of this validation:

- the Windows VM attaches and enforces the expected policy behavior
- or the Windows VM definitively fails after a complete attempt set with enough evidence to classify the result as a product/path limitation rather than an operator mistake

## Failure Criteria

- cluster instability after enabling host policy
- loss of pod-to-pod or service connectivity unrelated to the narrow experiment
- inability to distinguish between lab error and product limitation
- undocumented drift from the intended narrow-scope test shape

## Phase Plan

### Phase 0: Azure Lab Provisioning

Extend the current Azure Terraform lab to include:

- one Linux standalone VM suitable for Cilium external-workload testing
- one Windows Server VM suitable for standalone-host testing

Requirements:

- both VMs must be reachable from the jumpbox
- both VMs must share routed connectivity with the cluster network
- public exposure remains limited to the jumpbox

### Phase 1: Prove The Cluster Baseline

Validate:

- k3s node health
- Cilium health
- pod-to-pod networking
- service access

Deploy a small probe workload set similar in spirit to the existing `hep-lab` clients.

If this phase fails, stop.

### Phase 2: Prove Cluster Node Host Policy

Enable the minimum Cilium host-policy path on a narrow selector.

Apply:

- a safe baseline
- a dedicated test service on a dedicated port
- a narrow allow/deny rule set

Validate that:

- test traffic follows the expected matrix
- non-test control-plane traffic remains stable

If this phase fails, stop and roll back.

### Phase 3: Attempt Linux Standalone VM Attachment

Using a pre-`1.18` compatible Cilium toolchain:

- enable the needed external-workload support in the cluster
- register the Linux VM
- install the external-workload agent/container on the Linux VM
- verify the VM appears in cluster-side status
- apply the same round-1 matrix on the dedicated test port

Record:

- exact Cilium version
- exact CLI commands
- exact manifests
- exact workload identity labels or selectors used

### Phase 4: Attempt Windows Standalone VM Attachment

Investigate and try, in order:

1. Any official standalone Windows onboarding path
2. Any older supported-on-paper Windows variant of external workload onboarding
3. Any reconstructible cluster-authenticated path that still keeps Cilium as the enforcing component

For each attempted path, record:

- prerequisites
- setup steps
- failure point
- logs or error text
- why the next step is or is not justified

If no viable path is found, classify the result as:

- `No official standalone Windows path found`
or
- `Attempted path incompatible with Windows`

### Phase 5: Comparative Result And Conclusion

Produce a final validation table showing:

- Kubernetes nodes: pass/fail
- Linux standalone VM: pass/fail/partial
- Windows standalone VM: pass/fail/unsupported

Every non-pass result must include a reason class.

## Round 1 Test Shape

This round explicitly clones the current zone-isolation testing philosophy.

### Scope

- one dedicated TCP port only
- one dedicated lightweight test service per target
- no blanket deny rules on SSH, RDP, Kubernetes API, kubelet, DNS, or broad egress

### Model

Use a simple grouping model such as:

- `zone1`: selected k3s nodes plus Linux standalone VM if attached
- `zone2`: Windows standalone VM if attached, otherwise one alternate attached target

The exact labeling can change, but the matrix should preserve the same shape as the existing repo experiment:

- in-group allow
- cross-group deny
- dedicated service only

## Result Classification

Every tested target must end with one of these classes:

- `Supported pass`
- `Supported fail`
- `Deprecated path pass`
- `Deprecated path fail`
- `No official standalone Windows path found`
- `Attempted path incompatible with Windows`
- `Lab/config error`
- `Unclear / needs more evidence`

## Required Result Tables

### Target Summary

Each target must have:

- target name
- operating system
- attachment model
- policy primitive
- test service
- expected behavior
- observed behavior
- verdict
- limitation class

### Attempt Log

Windows and Linux standalone targets must also have an attempt log:

- attempt number
- Cilium version / tooling used
- commands or manifests applied
- observed error or success
- interpretation

## Error Handling And Safety

### Safety Controls

- start with one node selector, not all nodes
- keep the experiment on a disposable test port
- keep rollback commands ready before restrictive policy is applied
- keep jumpbox management traffic out of the first restrictive rules
- keep Windows RDP out of the initial experiment scope

### Rollback Requirements

Need explicit rollback for:

- host-policy changes on cluster nodes
- external-workload registration for the Linux VM
- external-workload agent/container uninstall on the Linux VM
- any partial Windows onboarding artifacts

## Observability And Evidence

Collect evidence from:

- `kubectl get nodes -o wide`
- `kubectl get pods -A -o wide`
- `kubectl get ciliumendpoints -A` or equivalent supported views
- `kubectl get ciliumclusterwidenetworkpolicies`
- `cilium status`
- `cilium-dbg` / cluster-agent diagnostics where relevant
- system logs on Linux VM
- Windows event/log output and service status where relevant
- test client output for the dedicated port matrix

The final report must preserve raw evidence for every Windows failure classification.

## Testing Strategy

### Unit Of Validation

The unit of validation is not "did Cilium work everywhere."

The unit is:

- which targets attached
- under which mechanism
- with which policy primitive
- and whether the observed traffic matched the declared matrix

### Assertions

Assertions are per-target:

- cluster node host policy path
- Linux deprecated external-workload path
- Windows standalone path attempt

These must not be collapsed into a single pass/fail headline.

## Recommended Deliverables

Round 1 implementation should add:

- a new validation plan document for the Cilium experiment
- Azure Terraform additions for Linux and Windows standalone VMs
- experiment manifests for cluster-node host policy
- helper scripts for:
  - Linux VM onboarding
  - dedicated test service deployment
  - matrix execution
  - result collection
- a result template with explicit limitation classification

## Open Decisions Resolved By This Spec

- One Kubernetes cluster is the single source of truth for all authored policy.
- Round 1 clones the existing narrow-scope zone-isolation pattern.
- Windows must be included as a target even if the expected outcome is a documented failure.
- The report must explicitly distinguish product limitation from lab error.
- No non-Cilium fallback enforcement layer is allowed in round 1.

## Risks

- Linux standalone validation may depend on older, deprecated Cilium tooling.
- Windows may not have a viable standalone Cilium attachment path at all.
- The Linux standalone attachment model is not equivalent to Kubernetes node host policy.
- Version skew between modern cluster Cilium and deprecated external-workload tooling may force the lab onto an older Cilium line for the whole round.

## Recommendation

Proceed with a phase-gated implementation that prefers clarity over coverage:

1. prove cluster-node host policy first
2. prove Linux standalone attachment second
3. attempt Windows third
4. classify Windows honestly if no viable path exists

This gives the repo a direct Cilium counterpart to the current Calico lab while preserving technical honesty about where the models do not align.
