# Calico HostEndpoint Validation Plan on Azure VMs

## Goal

Verify whether Calico HostEndpoints can provide one label-driven host firewall plane across:

- k3s nodes running Cilium as the Kubernetes CNI
- standalone Azure Linux VMs

The Azure environment is built from VMs rather than AKS so the test can control the node bootstrap path, the CNI choice, and any Calico components added later.

## Current position

### Documented and low-risk

- Calico can protect Kubernetes nodes with HostEndpoints.
- Calico can protect non-cluster hosts and VMs in policy-only mode by using a Kubernetes datastore.
- k3s supports a custom CNI when Flannel and the built-in network policy controller are disabled.
- Cilium has an official install path for k3s.

### Under test

- Calico HostEndpoint enforcement on k3s nodes when Cilium owns the Kubernetes CNI.
- Whether a minimal Calico policy footprint can coexist with Cilium on the same k3s nodes without taking over the CNI.
- Whether one label model can span Kubernetes nodes, Kubernetes workloads, and standalone VMs.

### Working assumption

- VM protection with Calico is a supported baseline.
- k3s with Cilium is a supported cluster baseline.
- Calico HostEndpoints on top of a Cilium-backed k3s cluster remain an interoperability experiment and should be treated as self-supported unless vendor guidance says otherwise.

## Questions this lab must answer

1. Can Calico HostEndpoints be created and targeted consistently on Azure VMs and k3s nodes?
2. Can label-based GlobalNetworkPolicy control traffic between workloads, nodes, and standalone VMs?
3. Does Calico policy enforcement remain stable when Cilium owns pod networking?
4. If the combination works, is the operational complexity acceptable?

## Success criteria

- The k3s server and agents stay `Ready` for at least 30 minutes after HostEndpoints are enabled.
- Cilium stays healthy and pod-to-pod and service networking continue to work.
- Calico HostEndpoints appear for the intended nodes and VMs.
- Label-based allow and deny behavior matches the expected matrix.
- Management access remains available through the baseline policy and explicit SSH allow rules.
- No unexplained regressions appear in `k3s`, `k3s-agent`, `cilium`, or Felix logs.

## Failure criteria

- k3s server or agents stop reporting `Ready` after the Calico experiment begins.
- Pod networking, service routing, or DNS breaks.
- HostEndpoint objects exist but do not enforce consistently.
- The only working state requires broad allow rules that defeat the host-firewall goal.

## Decision gates

- `Green`: the VM baseline passes and the k3s+Cilium experiment passes without instability.
- `Yellow`: the experiment mostly works, but the operational path is fragile or unclear.
- `Red`: the VM baseline passes but the k3s+Cilium experiment is unstable or inconsistent.

## Recommended Azure topology

| Component | Count | Purpose |
| --- | --- | --- |
| Jumpbox VM | 1 | Public entry point for SSH and diagnostics |
| k3s server VM | 1 | Single control-plane node that bootstraps Cilium |
| k3s agent VMs | 2 | Worker nodes for node-level and workload-level policy tests |
| Legacy VMs | 2 | Non-cluster hosts protected by Calico policy-only |

The repository Terraform provisions all of these resources and bootstraps k3s and Cilium automatically.

## Execution order

### Phase 0: Provision the Azure VM lab

- Apply the Terraform in `infra/azure/terraform`.
- Wait for cloud-init to finish on the jumpbox, k3s server, agents, and legacy VMs.
- Confirm:
  - local workstation -> jumpbox over SSH
  - jumpbox -> k3s server over SSH
  - jumpbox -> legacy VMs over SSH

### Phase 1: Prove the k3s plus Cilium baseline

- SSH to the k3s server through the jumpbox.
- Validate:
  - `kubectl get nodes -o wide`
  - `kubectl get pods -A -o wide`
  - `cilium status`
- Deploy the sample workloads from `manifests/k8s/test-workloads.yaml`.
- Verify pod-to-pod traffic and service access before touching Calico.

If this phase fails, stop. You do not yet have a stable cluster baseline.

### Phase 2: Prove the standalone VM baseline

- Install Calico Felix in policy-only mode on the legacy VMs using the Kubernetes datastore exposed by the k3s cluster.
- Create HostEndpoint objects for both legacy VMs.
- Apply the baseline host policy first, then a deny policy.
- Validate:
  - allowed SSH from the admin CIDR still works
  - allowed HTTP from labeled sources works
  - unlabeled sources are denied

If this phase fails, stop. The core VM requirement is not met.

### Phase 3: Primary experiment - minimal Calico on the k3s cluster

- Attempt the minimum Calico components needed for policy and HostEndpoints on the k3s cluster.
- Do not allow Calico to replace the active CNI or take ownership of the k3s CNI directories.
- Enable HostEndpoints for k3s nodes only after rollback is prepared.
- Re-run the same workload-to-host and host-to-host tests used in earlier phases.

This phase answers whether Calico HostEndpoints can coexist with Cilium on the same k3s nodes in practice.

### Phase 4: Fallback comparison

- If the experiment fails, compare the target use case against:
  - Cilium Host Firewall on k3s nodes
  - Calico policy-only on standalone VMs
- Use the comparison to decide whether one shared policy plane is truly required.

## Test matrix

| ID | Scenario | Expected result |
| --- | --- | --- |
| T01 | admin workstation -> jumpbox TCP/22 | allowed |
| T02 | jumpbox -> legacy VM A TCP/22 | allowed |
| T03 | labeled pod (`access=legacy-http`) -> legacy VM A TCP/80 | allowed |
| T04 | unlabeled pod -> legacy VM A TCP/80 | denied |
| T05 | legacy VM B with matching label -> legacy VM A TCP/80 | allowed |
| T06 | node HostEndpoint created automatically on k3s | present and labeled |
| T07 | pod-to-pod traffic on k3s after Calico experiment | still healthy |
| T08 | service access on k3s after Calico experiment | still healthy |
| T09 | `k3s` and `k3s-agent` stay healthy after host policy | still healthy |
| T10 | remove host deny policy | connectivity restored immediately |

## Observability checklist

- `kubectl get nodes -o wide`
- `kubectl get pods -A -o wide`
- `kubectl get heps -A -o wide`
- `kubectl get globalnetworkpolicies.crd.projectcalico.org`
- `kubectl logs -n calico-system ds/calico-node --tail=200`
- `kubectl logs -n kube-system ds/cilium --tail=200`
- `cilium status`
- `journalctl -u k3s -u k3s-agent --no-pager`
- `journalctl -u calico -u calico-node -u felix --no-pager`
- `/var/log/bootstrap-k3s-server.log`
- `curl`, `nc`, and `tcpdump` from the jumpbox and test pods

## Safety controls

- Keep the jumpbox outside the first wave of restrictive HostEndpoint policy.
- Apply explicit management allow rules before creating restrictive HostEndpoints.
- Start with one legacy VM and one k3s node selector before broadening selectors.
- Keep `99-disable-auto-hostendpoints.yaml` ready to apply immediately.
- Do not begin with wildcard policies that cover every k3s node.

## Recommended interpretation of results

- If Phases 1 and 2 pass but Phase 3 fails, Calico HostEndpoints are viable for standalone VMs but not a good fit for the k3s+Cilium cluster.
- If Phase 3 passes, the design is technically possible, but you still need an explicit support decision before production use.
- If Phase 3 is unstable but Cilium Host Firewall meets the cluster-side requirement, split the policy plane rather than forcing Calico onto the Cilium nodes.

## Repository assets

- Azure scaffolding: [infra/azure](/home/ubuntu/mon2/infra/azure/README.md)
- Terraform root: [infra/azure/terraform](/home/ubuntu/mon2/infra/azure/terraform)
- Calico manifests: [manifests/calico](/home/ubuntu/mon2/manifests/calico/README.md)
- Test workloads: [manifests/k8s/test-workloads.yaml](/home/ubuntu/mon2/manifests/k8s/test-workloads.yaml)
