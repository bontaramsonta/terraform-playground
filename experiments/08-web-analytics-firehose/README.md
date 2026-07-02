# Web analytics ingestion (Firehose → Lambda → S3)

Browser-side analytics pipeline: a Cognito Identity Pool grants
unauthenticated visitors permission to `firehose:PutRecord`; Kinesis Data
Firehose buffers events, a Lambda processor transforms them, and results land
in S3 as CSV. Never committed originally — recovered from the git index.
