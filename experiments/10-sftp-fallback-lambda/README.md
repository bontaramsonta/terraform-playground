# 10 - SFTP fallback lambda host-key verification

Local (no AWS) reproduction of how the `avhana-etl` SFTP **fallback replication
lambda** verifies the server host key it is pinned to, and specifically whether
passing **multiple** host keys through the `SFTP_TRUSTED_HOST_KEYS` environment
variable works.

## Why this exists

In prod, the fallback lambda's trusted host keys are built in Terraform:

```hcl
SFTP_TRUSTED_HOST_KEYS = join("\n", distinct(concat(
  each.value.sftp_trusted_host_keys_list,   # RSA (what the AWS Transfer connector accepts)
  each.value.fallback_sftp_trusted_hosts,   # extras, e.g. ed25519
)))
```

and the lambda splits them back apart:

```js
(process.env.SFTP_TRUSTED_HOST_KEYS || '').split('\n').map(l => l.trim()).filter(Boolean)
```

The open question: is `\n` a safe/correct separator for a *list* of host keys,
or should it be a comma? And does the lambda actually accept a connection when
more than one key is pinned?

## How it works

- [`handler.js`](handler.js) is the prod lambda's host-key logic verbatim
  (`makeHostVerifier` + the `ssh2-sftp-client` connect), with S3/Secrets Manager
  stripped. The split delimiter is injectable **only** so the matrix can prove
  what happens on a producer/consumer mismatch; prod hardcodes `'\n'`.
- [`sftp-server.js`](sftp-server.js) starts a real in-process `ssh2` SFTP server
  that presents exactly the host key it is handed. Host-key verification happens
  during the SSH handshake, before any file op, so a resolved `connect()` means
  ACCEPTED and a rejected one means DENIED.
- [`run.js`](run.js) runs the matrix: for each case it starts the server with a
  chosen key, sets the env var the way Terraform's `join()` would, and invokes
  the handler.

No `terraform apply` - this experiment is pure Node.

```sh
npm install
npm test
```

## Result

All seven cases behave as expected:

| Server presents | Trusted (env var) | Join / Split | Outcome | Proves |
|---|---|---|---|---|
| ed25519 | `[ed]` | `\n` / `\n` | ACCEPTED | baseline |
| ed25519 | `[rsa, ed]` | `\n` / `\n` | ACCEPTED | **multiple keys via `\n` parse correctly** |
| rsa | `[rsa, ed]` | `\n` / `\n` | ACCEPTED | the prod merge: connector RSA key now trusted by fallback |
| rsa | `[ed]` | `\n` / `\n` | DENIED | latent bug the merge fixed: RSA-negotiating server was rejected |
| stranger | `[rsa, ed]` | `\n` / `\n` | DENIED | fails closed on an unknown key |
| ed25519 | `[rsa, ed]` | **`,`** / `\n` | DENIED | changing the join to comma without changing the split **breaks** it |
| ed25519 | `[rsa, ed]` | `,` / `,` | ACCEPTED | comma works too *if both sides agree* - no advantage over `\n` |

## Conclusion

- **Multiple host keys work.** The server presents one key per connection
  (whichever algorithm gets negotiated); the lambda trusts a *set*, so any pinned
  key matches. `\n` is fine.
- **`\n` is the right separator**, not comma. SSH public keys are canonically
  one-per-line (`known_hosts` / `authorized_keys`); the base64 body never
  contains `\n` **or** `,`, so both are collision-free - comma buys nothing and
  is non-idiomatic. The last two rows show comma only "works" if you change the
  Terraform join *and* the lambda split together, for zero benefit.
- **The merge was a real fix, not just ergonomics.** Row 4 reproduces the
  pre-merge state where a server negotiating its RSA host key would have been
  rejected by a fallback that only trusted ed25519.
