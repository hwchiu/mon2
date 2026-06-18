# Cilium Standalone Host Validation

## Why this exists

This repository already has a Calico-based validation story. This document is the
single-file Cilium counterpart for the standalone-host question.

Round 1 asks one narrow question: can one k3s cluster, with Cilium as the only
cluster CNI and policy engine, author policy for three target types without
blurring product boundaries?

- Cluster nodes use Cilium host policy. This is the supported cluster-side path.
- The Linux standalone host uses deprecated external workloads on an older
  pinned lab toolchain. This is a lab validation path, not a forward-looking
  support promise.
- The Windows standalone host is an explicit target, but it may end in a
  validated fail if no viable Cilium-managed attachment path exists.

The test shape stays intentionally small:

- one dedicated test service
- one dedicated port, TCP `18080`
- one allow/deny matrix
- no first-pass interference with SSH, RDP, kube-api, kubelet, DNS, or general
  host access

## Topology

Round 1 should use this lab shape:

| Component | Count | Purpose |
| --- | --- | --- |
| Jumpbox | 1 | Public entry point for SSH, log collection, and pivoting into the private subnets |
| k3s server | 1 | Control-plane node; boots with Flannel disabled and Cilium installed |
| k3s agents | 2 | Narrow host policy targets for the zone-isolation checks |
| Linux standalone VM | 1 | Deprecated external-workload attachment target |
| Windows standalone VM | 1 | Explicit Windows attachment attempt target |

Conceptually:

```text
workstation
  |
  v
jumpbox
  |
  +--> k3s server + k3s agents (Cilium-only cluster, host policy on selected nodes)
  |
  +--> Linux standalone VM (attempted attachment through deprecated external workloads)
  |
  +--> Windows standalone VM (attempted standalone path, no assumed success)
```

Round 1 clones the repository's zone-isolation style:

- `zone1`: selected k3s nodes, plus the Linux standalone VM if it attaches
- `zone2`: one alternate selected target, or the Windows standalone VM if it
  attaches meaningfully

## What is actually under test

This document is not testing "Cilium everywhere" as one blended headline. It is
testing three different attachment and enforcement stories:

| Target | Attachment model | Policy primitive | How it is judged in round 1 |
| --- | --- | --- | --- |
| Cluster nodes | Native Kubernetes node in the k3s cluster | Cilium host policy through `CiliumClusterwideNetworkPolicy` with `nodeSelector` | TCP `18080` matches the declared matrix and the cluster stays healthy |
| Linux standalone VM | Pinned deprecated external-workload registration to the cluster | Endpoint-style Cilium policy on the attached workload | Counts only as a deprecated-path result on the pinned older lab toolchain, with visible cluster-side attachment and a matching TCP `18080` matrix |
| Windows standalone VM | Attempted Cilium-managed standalone path | Only counts if Cilium remains the enforcing component | Default round-1 outcomes are `No official standalone Windows path found`, `Attempted path incompatible with Windows`, `Lab/config error`, or `Unclear / needs more evidence` |

Round 1 does not try to prove:

- all-port host lockdown
- workload identity on standalone hosts
- multi-cluster policy distribution
- Windows Firewall translation or any non-Cilium fallback
- broad host hardening beyond the dedicated test service on TCP `18080`

## Important limitations

- Cluster nodes use Cilium host policy. In this document, `host policy` means
  the cluster node host-firewall path.
- The Linux standalone path is a deprecated lab-only workflow pinned to an
  older pre-`1.18` Cilium line that still included external workloads. It is
  not the same enforcement primitive as Kubernetes node host policy.
- The exact `cilium clustermesh ...` and `cilium clustermesh vm ...`
  subcommands are version-specific. Take them from the pinned lab toolchain for
  the round; do not assume they exist in a current Cilium CLI release.
- A Linux pass still counts as a deprecated-path result, not as proof that
  standalone-host support is current or recommended.
- No official standalone Windows path is assumed. Windows may end in a
  validated fail if the lab can show that no viable Cilium-managed attachment
  path exists.
- Round 1 only touches a dedicated service on TCP `18080`. It is not evidence
  for blanket host policy behavior.
- Keep SSH, RDP, kube-api, kubelet, DNS, and the Cilium datapath out of the
  first restrictive rules.
- If a Windows attempt requires translating policy into native Windows Firewall,
  the attempt no longer counts as Cilium standalone validation.
- Changing away from the pinned older lab toolchain changes the experiment and
  invalidates comparison with prior deprecated-path results.

## Azure provisioning

Provision the lab from `infra/azure/terraform` and keep the topology narrow.

1. Prepare Terraform input:

   ```bash
   cd infra/azure/terraform
   cp terraform.tfvars.example terraform.tfvars
   $EDITOR terraform.tfvars
   ```

2. Ensure the plan includes:

   - one jumpbox
   - one k3s server
   - at least two k3s agents
   - one Linux standalone VM for the Cilium test
   - one Windows standalone VM for the Cilium test

3. Apply the lab:

   ```bash
   terraform init
   terraform plan
   terraform apply
   terraform output
   ```

4. Capture and save:

   - jumpbox public IP
   - k3s server private IP
   - k3s agent private IPs
   - Linux standalone private IP
   - Windows standalone private IP

5. Before any policy work, prove connectivity:

   - workstation -> jumpbox over SSH
   - jumpbox -> k3s server over SSH
   - jumpbox -> Linux standalone over SSH
   - jumpbox -> Windows standalone over RDP or OpenSSH, depending on bootstrap

Bootstrap expectations for this round:

- the k3s server disables Flannel and the built-in network-policy controller
- the k3s server installs Cilium and waits for it to become healthy
- the Linux standalone host can run a dedicated HTTP test service on TCP `18080`
- the Windows standalone host exposes IIS or an equivalent HTTP test surface on
  TCP `18080`

## Cluster setup

The cluster remains the single source of truth for authored Cilium policy.

1. Reach the k3s server through the jumpbox and fetch or tunnel the kubeconfig.
2. From a shell on the k3s server, prove the baseline before any host policy
   change:

   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A -o wide
   cilium status
   ```

3. Choose a narrow first selector:

   - one node labeled `lab.cilium.io/zone=zone1`
   - one node labeled `lab.cilium.io/zone=zone2`

4. Enable the minimum Cilium host policy needed for those nodes. In this
   document, that is the cluster node host-firewall path. Do not replace the
   CNI and do not broaden selectors yet.
5. Install a dedicated HTTP probe on the selected nodes so each node answers on
   TCP `18080`.
6. Apply only the narrow experiment policy:

   - one allow policy for `zone1` on TCP `18080`
   - one cross-zone deny for `zone2` on TCP `18080`

7. From a shell on the k3s server, re-check cluster health immediately after
   policy is active:

   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A -o wide
   cilium status
   ```

If the cluster becomes unstable here, stop. The supported path already failed.

## Linux standalone host attachment

The Linux standalone host does not use Cilium host policy. It uses the older,
deprecated external-workload path and must be reported that way.

This is a deprecated lab-only workflow pinned to an older pre-`1.18` Cilium
line that still included the external-workload path. The exact CLI subcommands
are version-specific and must be taken from the pinned lab toolchain for the
round. Do not assume a current Cilium CLI still exposes the same commands or
behavior.

Recommended round-1 flow:

1. Select and record the pinned older Cilium lab toolchain that still supports
   external workloads.
2. Using that pinned lab CLI, enable the needed cluster-side support. Example
   only, from the pinned toolchain:

   ```bash
   cilium clustermesh enable --service-type LoadBalancer --enable-external-workloads
   ```

3. Using that same pinned lab toolchain, create the external-workload
   registration and generate the installer. Example only, from the pinned
   toolchain:

   ```bash
   cilium clustermesh vm create <linux-workload-name> -n default --ipv4-alloc-cidr <cidr>
   cilium clustermesh vm install ./install-external-workload.sh
   ```

4. Copy the generated installer to the Linux VM through the jumpbox and run it
   with the host IP exported if the installer requires it.
5. Install or verify the dedicated HTTP probe on TCP `18080`.
6. Target the attached Linux endpoint with endpoint-style Cilium policy. Do not
   call this host policy; it is not the same primitive.
7. Record the exact Cilium version, commands, manifests, labels, and status
   views used for the attempt.

If the pinned toolchain does not expose the expected external-workload
subcommands, stop and re-pin the lab instead of rewriting the flow against a
different current CLI.

Minimum evidence that the Linux host is really attached:

- it appears in the expected cluster-side Cilium status or endpoint views
- the TCP `18080` matrix changes because of cluster-authored Cilium policy
- the raw test output can distinguish allow from deny

If the Linux path passes, classify it as `Deprecated path pass`.
If the Linux path fails after a correct attempt, classify it as
`Deprecated path fail`.

## Windows standalone host attempt

Windows is not optional in the story, but success is not assumed.

The Windows branch should be attempted in this order:

1. Look for an official standalone Windows onboarding path that keeps Cilium as
   the enforcement component.
2. Look for any older, supportable-on-paper external-workload-style path that
   still applies to Windows.
3. Look for any reconstructible cluster-authenticated path that still keeps
   Cilium, not native Windows Firewall, as the enforcement layer.

Round-1 setup for the host itself:

- bootstrap the VM so it is reachable from the jumpbox
- expose IIS or an equivalent HTTP probe on TCP `18080`
- keep RDP or management access out of restrictive policy scope

For every Windows attempt, record:

| Attempt | Cilium version or tooling | Commands or manifests used | Failure point or success point | Evidence saved |
| --- | --- | --- | --- | --- |
| W1 |  |  |  |  |
| W2 |  |  |  |  |
| W3 |  |  |  |  |

Windows may end in a validated fail. That is acceptable only when the evidence
shows one of these two conclusions:

- `No official standalone Windows path found`
- `Attempted path incompatible with Windows`

If the Windows path fails because the lab never had a working VM, networking, or
artifact set, the result is not a product limitation. It is `Lab/config error`.

The default Windows verdict families for round 1 are:

- `No official standalone Windows path found`
- `Attempted path incompatible with Windows`
- `Lab/config error`
- `Unclear / needs more evidence`

Do not use `Supported pass` or `Supported fail` for Windows by default. Only if
a real Cilium-managed Windows attachment path is empirically established should
the report be amended with a Windows pass/fail statement, and that should not
be described as supported unless upstream support is separately established.

## Round 1 test cases

Round 1 keeps the blast radius small:

- dedicated TCP `18080` only
- dedicated HTTP probe per target
- baseline reachability first
- then zone-isolation style allow or deny checks

Run the baseline before restrictive policy:

- every selected target should answer on TCP `18080`
- cluster health must stay green

Then run this concrete matrix:

| ID | Source | Destination | Port | Expected | Notes |
| --- | --- | --- | --- | --- | --- |
| C01 | zone1 node | zone1 node | 18080 | allow | cluster host policy |
| C02 | zone1 node | zone2 node | 18080 | deny | cluster host policy |
| C03 | zone1 node | linux standalone | 18080 | allow/deny per policy | deprecated external workload path |
| C04 | linux standalone | zone1 node | 18080 | allow/deny per policy | deprecated external workload path |
| C05 | zone1 node | windows standalone | 18080 | classify only; no default pass/fail | explicit Windows branch |

Execution notes:

- Treat C01 and C02 as the supported baseline. If they fail, stop and roll back
  before spending time on standalone hosts.
- For C03 and C04, declare the Linux host's intended zone before the run. A
  same-zone placement should allow; a cross-zone placement should deny. Record
  the Linux outcome as a deprecated-path verdict either way.
- For C05, only expect an allow or deny result if the Windows host actually
  attached through a Cilium-managed path. Otherwise the correct result must be
  one of `No official standalone Windows path found`,
  `Attempted path incompatible with Windows`, `Lab/config error`, or
  `Unclear / needs more evidence`, not a synthetic pass/fail.

## Expected results matrix

Each target should end the round with one clear summary row.

| Target | OS | Attachment model | Policy primitive | Expected behavior on TCP `18080` | Primary verdict family |
| --- | --- | --- | --- | --- | --- |
| Selected k3s nodes | Linux | In-cluster Kubernetes nodes | Cilium host policy with `nodeSelector` | same-zone allow, cross-zone deny, no cluster instability | `Supported pass` or `Supported fail` |
| Linux standalone VM | Linux | Deprecated external workload | Endpoint-style Cilium policy | behavior matches declared zone placement, plus visible cluster-side attachment | `Deprecated path pass` or `Deprecated path fail` |
| Windows standalone VM | Windows Server | Attempted standalone attachment | Only valid if Cilium remains the enforcing component | no default pass/fail; classify the attempt unless a real Cilium-managed Windows attachment path is empirically established | `No official standalone Windows path found`, `Attempted path incompatible with Windows`, `Lab/config error`, or `Unclear / needs more evidence` |

The headline for the round should never collapse these rows into one blended
pass or fail. The unit of validation is per target and per attachment model.

## Result classification

Use this verdict taxonomy exactly:

- `Supported pass`
- `Supported fail`
- `Deprecated path pass`
- `Deprecated path fail`
- `No official standalone Windows path found`
- `Attempted path incompatible with Windows`
- `Lab/config error`
- `Unclear / needs more evidence`

In this document, `Supported pass` and `Supported fail` are reserved for the
cluster node host policy path. They are not default Windows outcomes.

Interpretation:

- `Supported pass`: the supported cluster node host policy path behaved as
  declared and did not destabilize the cluster.
- `Supported fail`: the supported cluster node host policy path was attempted
  correctly but the declared matrix did not hold, or the cluster became
  unstable.
- `Deprecated path pass`: the Linux standalone host attached through deprecated
  external workloads and matched the declared matrix.
- `Deprecated path fail`: the Linux deprecated path was attempted correctly but
  did not attach cleanly or did not honor the declared matrix.
- `No official standalone Windows path found`: the Windows investigation
  exhausted the official path search with enough evidence to show the path does
  not exist in the needed shape.
- `Attempted path incompatible with Windows`: a concrete Cilium-managed Windows
  attachment path was attempted, but the path itself was incompatible with
  Windows.
- `Lab/config error`: the evidence shows the lab was wrong, incomplete, or
  internally inconsistent, so the result cannot be pinned on Cilium.
- `Unclear / needs more evidence`: there is not enough raw evidence to separate
  product limitation from operator or lab error.

If Windows ever reaches a real Cilium-managed attachment path, record that as a
separate empirical Windows note and do not describe it as supported unless
upstream support is independently established.

The important line is simple: product limitation and lab error must not be
mixed.

## Evidence checklist

Capture the same evidence every time so verdicts can be defended later.

- Terraform outputs that identify the jumpbox, cluster nodes, Linux standalone,
  and Windows standalone addresses
- exact Cilium version and CLI version used for the round
- the exact manifests or policy objects applied for the node host policy checks
- `kubectl get nodes -o wide`
- `kubectl get pods -A -o wide`
- `kubectl get ciliumendpoints -A` or the closest supported endpoint view
- `kubectl get ciliumclusterwidenetworkpolicies`
- `cilium status` from a shell on the k3s server
- Linux standalone host logs for the external-workload install and runtime
- Windows service status, IIS status, event logs, and any onboarding-script
  output
- raw `curl`, `nc`, or script output for C01 through C05 on TCP `18080`
- timestamps for when restrictive policy was applied and when it was removed
- rollback commands issued, if rollback was needed

Preserve raw evidence for every Windows non-pass verdict. A Windows limitation
claim without raw evidence is not complete.

## Rollback

Keep rollback ready before the first restrictive rule is applied.

1. Remove the narrow Cilium experiment policies from the cluster nodes.
2. Remove the temporary `lab.cilium.io/zone` labels from the selected nodes if
   they were added only for this round.
3. If host policy settings were enabled only for the experiment, revert them
   and wait for Cilium to settle before proceeding.
4. Remove the Linux external-workload registration and uninstall its agent or
   container from the standalone VM using the same Cilium toolchain used to
   onboard it.
5. Delete or clean up any partial Windows onboarding artifacts, but leave
   management access intact for postmortem collection.
6. From a shell on the k3s server, re-check baseline health:

   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A -o wide
   cilium status
   ```

7. Confirm the dedicated test services on TCP `18080` are no longer influencing
   the environment.

If rollback does not restore a healthy baseline, stop and classify the round as
`Lab/config error` until the environment is clean again.
