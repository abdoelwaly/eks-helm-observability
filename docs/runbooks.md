# Runbooks

Alerts link here through their `runbook_url` annotation.

## availability-budget-burn

**What it means:** podinfo is returning 5xx errors fast enough to use up the 30-day error budget early. The alert name tells you how fast: `1h` and `6h` page someone now, `1d` and `3d` open a ticket.

**Check first**

1. Grafana dashboard **podinfo — SLOs**: is the error rate still climbing, or was it a short spike?
2. Recent changes:
   ```bash
   helm -n demo history podinfo
   kubectl -n demo rollout history deploy/podinfo
   ```
3. Pod health and logs:
   ```bash
   kubectl -n demo get pods -o wide
   kubectl -n demo logs deploy/podinfo --since=15m | grep -i error
   ```
4. Node or AZ problem: are failing pods on the same node or zone?
   ```bash
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

**Mitigate**

- Bad release: `helm -n demo rollback podinfo` to the previous revision.
- Capacity: `kubectl -n demo scale deploy/podinfo --replicas=6`.
- Single bad node: `kubectl cordon <node>` then `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`.

**Afterwards:** write a short incident note with the budget consumed (from the dashboard gauge) and the fix.

## latency-budget-burn

**What it means:** too many requests take longer than 250 ms.

**Check first**

1. The latency percentile panel: is p99 up across all paths, or one path?
2. CPU throttling or memory pressure:
   ```bash
   kubectl -n demo top pods
   kubectl -n demo describe pod <pod> | grep -A5 -i -E 'limits|oomkilled'
   ```
3. Node saturation: the **Kubernetes / Compute Resources / Node** dashboard that ships with kube-prometheus-stack.

**Mitigate**

- Scale out: raise replicas or the HPA maximum.
- Raise CPU requests if pods are throttled.
- Roll back if latency started with a release.
