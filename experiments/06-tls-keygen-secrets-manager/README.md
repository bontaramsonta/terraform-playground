# TLS RSA keygen → Secrets Manager

Generates an RSA-4096 keypair with the `tls` provider and stores the private
key in AWS Secrets Manager. Output trims the trailing newline from the public
key (that was the gotcha this experiment chased).
