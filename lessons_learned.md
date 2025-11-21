# Lessons Learned: Kubernetes DNS Resolution

## Issue

Applications running in Kubernetes pods were unable to resolve external hostnames using standard libraries (e.g., `curl`), while `nslookup` worked correctly. This was observed in a GKE cluster created with `kubeadm`.

The symptoms were:
*   `curl <external-hostname>` failed with "Could not resolve host".
*   `nslookup <external-hostname>` successfully resolved the IP address.
*   The issue persisted even after configuring CoreDNS to use an external forwarder (`8.8.8.8`).

## Root Cause

The root cause was the default `ndots:5` option in the pods' `/etc/resolv.conf` file. This setting is standard in Kubernetes and instructs the system's DNS resolver (`glibc`'s `getaddrinfo`) to try appending the configured `search` domains to any hostname with fewer than 5 dots before attempting to resolve it as a fully qualified domain name (FQDN).

For a hostname like `lqs5rkmy81.cloud.tetrate.com` (which has 3 dots), the resolver would first try to resolve:
1.  `lqs5rkmy81.cloud.tetrate.com.<namespace>.svc.cluster.local`
2.  `lqs5rkmy81.cloud.tetrate.com.svc.cluster.local`
3.  `lqs5rkmy81.cloud.tetrate.com.cluster.local`
4.  ...and so on for all search domains.

These attempts would fail or time out, causing the overall DNS resolution to fail for applications like `curl`. `nslookup` and `dig` do not use the same resolver behavior by default, which is why they were able to resolve the hostname directly.

## Fix

The solution is to explicitly set `ndots:1` in the `dnsConfig` of the pod specification. This tells the resolver to treat any hostname with at least one dot as an FQDN, preventing the unnecessary and problematic appending of search domains.

### Implementation

To apply this fix to a Deployment, StatefulSet, or other pod controller, add the `dnsConfig` section to the pod template spec:

```yaml
spec:
  template:
    spec:
      # ... other pod spec configurations ...
      dnsConfig:
        options:
        - name: ndots
          value: "1"
      containers:
      # ... your container definitions ...
```

This change ensures that applications within the pod can correctly resolve external hostnames without being affected by the search domain behavior.
