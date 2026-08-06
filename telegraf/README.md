# Telegraf Monitoring Stack

This Telegraf deployment collects metrics, logs, and traces from your Kubernetes cluster and sends them to Grafana Cloud.

## Features

### 1. **Node Metrics** (Host-level monitoring)
- CPU usage (per-core and total)
- Memory usage
- Disk usage and I/O
- Network traffic
- System load
- Swap usage
- Process count
- Kernel metrics

### 2. **Kubernetes Metrics**
- Pod metrics from kubelet
- Node metrics
- Kubernetes inventory (pods, nodes)

### 3. **Prometheus Collector**
- Scrapes metrics from Kubernetes pods with `prometheus.io/scrape: "true"` annotation
- Scrapes metrics from specified ports via `prometheus.io/port` annotation
- Custom metrics path via `prometheus.io/path` annotation

### 4. **Log Collector**
- Collects logs from all Kubernetes pods
- Parses Kubernetes log metadata
- Filters and processes log streams

### 5. **OpenTelemetry Collector**
- Receives OTLP metrics over gRPC (port 4317)
- Receives OTLP metrics over HTTP (port 4318)
- Compatible with OpenTelemetry SDKs

## Configuration

### Grafana Cloud Connection

The deployment uses InfluxDB line protocol to send metrics to Grafana Cloud:

```yaml
outputs:
  - influxdb:
      urls:
        - "https://influx-prod-13-prod-us-east-0.grafana.net/api/v1/push/influx/write"
      username: "YOUR_METRICS_INSTANCE_ID"
      password: "YOUR_CLOUD_ACCESS_POLICY_TOKEN"
```

**Update the credentials in `secrets.yaml`:**
- `username`: Your Metrics instance ID from Grafana Cloud
- `password`: Your Cloud Access Policy token

### Deployment Mode

- **DaemonSet**: Runs one Telegraf pod per node
- **Host Network**: Uses host networking for direct access to node metrics
- **Host PID**: Access to host processes for accurate monitoring

## Installation

```bash
# Deploy using helmfile
helmfile -f helmfile.yaml apply

# Or sync with specific options
helmfile -f helmfile.yaml sync
```

## Verification

```bash
# Check Telegraf pods
kubectl get pods -n monitoring -l app=telegraf

# Check logs
kubectl logs -n monitoring -l app=telegraf --tail=50

# Check metrics endpoint
kubectl exec -n monitoring <telegraf-pod> -- curl http://localhost:8888/metrics
```

## Prometheus Scraping

Telegraf will automatically scrape pods that have these annotations:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"        # optional, defaults to pod port
    prometheus.io/path: "/metrics"    # optional, defaults to /metrics
```

## OpenTelemetry Integration

Applications can send OTLP data to Telegraf:

```bash
# gRPC endpoint
OTEL_EXPORTER_OTLP_ENDPOINT=http://<node-ip>:4317

# HTTP endpoint
OTEL_EXPORTER_OTLP_ENDPOINT=http://<node-ip>:4318
```

## Architecture

```
┌─────────────────────────────────────────────┐
│           Telegraf DaemonSet                │
│                                             │
│  ┌────────────┐  ┌──────────────┐          │
│  │   Node     │  │  Prometheus  │          │
│  │  Metrics   │  │   Scraper    │          │
│  └────────────┘  └──────────────┘          │
│                                             │
│  ┌────────────┐  ┌──────────────┐          │
│  │    Log     │  │     OTLP     │          │
│  │ Collector  │  │   Receiver   │          │
│  └────────────┘  └──────────────┘          │
│                                             │
│           InfluxDB Output                   │
└───────────────┬─────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │ Grafana Cloud │
        └───────────────┘
```

## Comparison with OpenTelemetry Collector

| Feature | OpenTelemetry | Telegraf |
|---------|---------------|----------|
| Node Metrics | ✅ hostMetrics preset | ✅ Native plugins |
| Prometheus Scraping | ✅ prometheus receiver | ✅ prometheus input |
| Log Collection | ✅ filelog receiver | ✅ tail input |
| OTLP Support | ✅ Native | ✅ opentelemetry input |
| Output Format | OTLP | InfluxDB Line Protocol |
| Resource Usage | ~50-100Mi | ~128-256Mi |

## Troubleshooting

### Logs not appearing
- Check pod annotations for log exclusions
- Verify file paths in tail input configuration
- Check permissions on /var/log/pods

### Metrics not showing up
- Verify Grafana Cloud credentials
- Check network connectivity to Grafana endpoint
- Review Telegraf logs for errors

### OTLP receiver not working
- Verify ports 4317/4318 are exposed
- Check firewall rules
- Ensure hostNetwork: true is set

## Resource Tuning

Default resource limits:
- Memory: 128Mi request, 256Mi limit
- CPU: 100m request, 500m limit

Adjust in `helmfile.yaml` based on your cluster size and metric volume.
