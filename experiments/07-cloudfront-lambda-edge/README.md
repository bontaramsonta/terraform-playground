# CloudFront + Lambda@Edge POC

CloudFront distribution with a hello-world Lambda@Edge function association,
including the IAM trust policy quirk (`edgelambda.amazonaws.com` principal)
and custom cache/origin-request policies. Lambda@Edge must live in us-east-1.
