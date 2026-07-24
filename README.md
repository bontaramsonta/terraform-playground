# Terraform playground

One-off AWS (and GitHub) experiments, each self-contained under
`experiments/` with its own state key (`terraform/play/<name>.tfstate` in the
shared state bucket), so any experiment can be applied and destroyed
independently:

```sh
cd experiments/<name>
AWS_PROFILE=sourav terraform init
AWS_PROFILE=sourav terraform apply
```

Everything should be destroyed when not actively being poked at.

## Experiments

| # | Experiment | Notes |
|---|---|---|
| [01](experiments/01-tag-policy-check/) | GitHub deployment tag policy check | GitHub provider, not AWS |
| [02](experiments/02-cloudwatch-data-protection/) | CloudWatch Logs data protection | PII redaction policy on a log group |
| [03](experiments/03-guardduty-ecs-runtime-monitoring/) | GuardDuty ECS runtime monitoring | detector + feature flag POC |
| [04](experiments/04-cloudfront-ip-blocking/) | CloudFront IP-based request blocking | CF function, has diagram |
| [05](experiments/05-ssm-session-manager/) | SSM Session Manager in private subnets | interface-endpoint SG gotcha |
| [06](experiments/06-tls-keygen-secrets-manager/) | TLS RSA keygen → Secrets Manager | trailing-newline gotcha |
| [07](experiments/07-cloudfront-lambda-edge/) | CloudFront + Lambda@Edge | us-east-1 requirement |
| [08](experiments/08-web-analytics-firehose/) | Web analytics ingestion | Firehose → Lambda → S3 + Cognito |
| [09](experiments/09-ecs-fargate-spot/) | ECS Fargate on Spot | capacity providers, interruption handling |
| [10](experiments/10-sftp-fallback-lambda/) | SFTP fallback lambda host-key verification | multiple host keys via env var; `\n` vs comma; local Node, no AWS |

Older experiment iterations (the journey, not just the final state) remain in
git history — `git log --oneline`.
