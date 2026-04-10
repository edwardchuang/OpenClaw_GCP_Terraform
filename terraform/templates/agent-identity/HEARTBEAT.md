# HEARTBEAT.md - SRE Pre-flight Checklist

Every time a heartbeat is triggered, execute this routine sequentially.

**Task:** Query recent logs and metrics using the `gcloud` tool. You must use the `$GOOGLE_CLOUD_PROJECT` environment variable for all queries.

1.  **Check 1: Application & Workload Errors**
    Use `gcloud logging read "severity>=\"ERROR\" AND resource.type=(\"k8s_container\" OR \"gce_instance\" OR \"cloud_run_revision\" OR \"cloud_function\")" --limit=15 --project=$GOOGLE_CLOUD_PROJECT --format=json`
    *(Analyze for severe application crashes, unhandled exceptions, or infrastructure termination events in the last hour)*

2.  **Check 2: Security & Network Perimeter Drops**
    Use `gcloud logging read "(resource.type=\"network_firewall_rule\" OR resource.type=\"network_security_gateway\") AND jsonPayload.disposition=\"DENIED\"" --limit=10 --project=$GOOGLE_CLOUD_PROJECT --format=json`
    *(Analyze for denied egress/ingress traffic, indicating misconfigurations, compromised workloads, or aggressive threat intelligence blocking)*

3.  **Check 3: AI & Access Anomalies**
    Use `gcloud logging read "logName=~\"logs/modelarmor.googleapis.com\" OR (resource.type=\"audited_resource\" AND protoPayload.methodName=~\"SetIamPolicy\")" --limit=5 --project=$GOOGLE_CLOUD_PROJECT --format=json`
    *(Analyze for prompt injection attempts, sensitive data leakage, or unexpected IAM permission changes)*

---

### Post-Processing

*   If all checks return empty arrays `[]` or no novel, unactioned anomalies: **Reply exactly with `HEARTBEAT_OK`**. Do NOT add any extra text or pleasantries. This suppresses the notification to the operator.
*   If an anomaly is found that warrants attention: **Break silence.** Synthesize the findings across all three checks according to the formatting rules in `SOUL.md` (Severity, Synopsis, RCA, Recommended Action). Do not paste raw JSON logs unless specifically requested by the operator.