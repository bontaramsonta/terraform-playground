# T3 Code box

Ubuntu 24.04 arm64 EC2 in ap-south-1 running T3 Code as a background service,
reached over Tailscale HTTPS, with
[T3 Connect](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
kept on for mobile push notifications.

- Own VPC, public subnet. Inbound: SSH from the applier's IP
  (`checkip.amazonaws.com`, re-apply after it changes) and UDP 41641 for
  direct Tailscale connections. Without the UDP rule traffic goes through a
  DERP relay.
- Key pair from `~/.ssh/id_ed25519.pub`. SSM Session Manager also works.
- `user_data.sh` installs `t3`, Claude Code, `gh`, Docker, Vite+ (`vp`, with
  Node 24 and Bun 1.4.4) and browser deps, and enables linger for `ubuntu`.
  It touches `/var/lib/t3code-box-ready` when done.
- The instance ignores `ami` and `user_data` changes, so editing the script
  never replaces a configured box.

## Finish setup (interactive, once)

```sh
$(terraform output -raw ssh)
test -f /var/lib/t3code-box-ready && echo ready
claude                                    # sign in to the provider
gh auth login -h github.com -p https -w && gh auth setup-git
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=t3code-box --operator=ubuntu
t3 up --connect                           # T3 Connect sign-in
t3 connect publish                        # mobile push notifications
t3 pair --tailscale --ttl 30m             # https://t3code-box.<tailnet>.ts.net/
```

Add the pairing link in the app with **Add route**, then move the Tailscale
route to the top.

## Teardown

Run `t3 connect logout` on the box (or **Deregister** in the T3 Connect
page) and remove the machine from the Tailscale admin before
`terraform destroy`. The root volume is not kept.
