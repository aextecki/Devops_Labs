GitHub Portfolio: The Local System Health Monitor

Author: aextecki

The Project: Write a lightweight diagnostic tool that evaluates system performance metrics and creates clean summaries.

Objective: Create a tool that reads Web Services,CPU idle states, active memory thresholds, and firewall logs.

Deliverable: A  script named sysmon.sh that alerts checking via running it to terminal if memory utilization crosses 85%.

Linux & Network Telemetry
**Project:** Local System Health Monitor (`sysmon.sh`) with Datadog Telemetry
- **Objective:** Real-time performance auditing without a GUI, backed by centralized cloud telemetry.
- **Key Features:** CPU idle state tracking, local memory utilization alerts (>85%), and automated shipping of system events to Datadog via dogstatsd / API.
- **Tools:** `systemd`, `ss`, `journalctl`, Datadog Agent
