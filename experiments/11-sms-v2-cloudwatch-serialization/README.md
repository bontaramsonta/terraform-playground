# SMS v2 → CloudWatch serialization (out-of-band proof)

Confirms **how AWS End User Messaging SMS (`pinpoint-sms-voice-v2`) serializes an
event into CloudWatch Logs**, and whether the production ticket-04 metric filter
`{ $.eventType = "…" || … }` actually matches a real v2 **failure** line — the
one thing that design can't desk-check (AWS doesn't document the serialization).

Out-of-band confirmation path for ticket 06 of the `sms-failure-alarm` effort
(`.scratch/sms-failure-alarm/`). The primary proof is still decision B's Avhana
canary; this just gets the `$.eventType`-lands answer sooner and in isolation.

## Scope — read before running

Research ([`03-simulator-failure-feasibility.md`](../../../../avhana/avhana_amalgam_notification_subscriber/.scratch/sms-failure-alarm/research/03-simulator-failure-feasibility.md))
found AWS exposes **one** success and **one** failure "magic" destination number
per country, and does **not** document which `TEXT_*` subtype the failure number
emits. So this experiment **cannot** prove the ≥2-distinct-failure-types
requirement (that needs real 10DLC, deliberately out of scope). It proves the
narrower, still-valuable thing:

- Is the log line **compact or pretty-printed**? Bare event JSON or **enveloped**?
- Does **`$.eventType`** sit at the top level so a JSON metric filter resolves?
- Does the exact ticket-04 filter **increment** (`LogMetrics/SMS_Failure_JsonCanary`)?
- **Bonus finding:** which `TEXT_*` subtype the failure magic number actually emits.

Origination simulator numbers are **US-only**, so this runs in **us-east-1**
(not the play default ap-south-1). Simulator numbers **don't require
registration** and never touch the carrier network.

## Run

```sh
cd experiments/11-sms-v2-cloudwatch-serialization
AWS_PROFILE=sourav terraform init
AWS_PROFILE=sourav terraform apply

npm install
AWS_PROFILE=sourav npm run send   # sends success+failure, prints raw log lines

AWS_PROFILE=sourav terraform destroy
```

`caller.js` sends to the US success (`+14254147755`) and failure
(`+14254147167`) simulator numbers through the config set, waits ~60s, then
prints each raw CloudWatch log line via `JSON.stringify` (so compact-vs-pretty is
visible) and reports the top-level `eventType`. Then check the
`LogMetrics/SMS_Failure_JsonCanary` metric in CloudWatch (us-east-1): a datapoint
of `1` means the ticket-04 filter matched.

The event destination matches `TEXT_ALL` (not just the nine failure types) on
purpose — the failure number's subtype is undocumented, so we capture whatever
it emits rather than risk logging nothing.

Destroy when done — nothing here should live when it isn't being poked at.
