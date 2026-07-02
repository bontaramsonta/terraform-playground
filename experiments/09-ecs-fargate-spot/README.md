# ECS Fargate on Spot playground

One nginx task (`desired_count = 1`) running 100% on `FARGATE_SPOT` in the
default VPC, ap-south-1. Goal: learn how Fargate Spot behaves, not build
production infra.

Previous lab notes live in [notes/](notes/) (SSM Session Manager).

## The mental model

You never ask for "a Spot task" directly. The flow is:

1. **Capacity providers** (`FARGATE`, `FARGATE_SPOT`) are attached to the
   *cluster* — they are AWS-managed, you just opt in.
2. Each **service** declares a `capacity_provider_strategy`: a list of
   `(provider, base, weight)` entries.
   - `base` — run *this many* tasks on this provider before anything else.
     Only one entry may have a base.
   - `weight` — the ratio for tasks *above* the bases. `FARGATE base=1` +
     `FARGATE_SPOT weight=4, FARGATE weight=1` means: first task on-demand,
     the rest split 4:1 spot:on-demand.
3. `launch_type` and `capacity_provider_strategy` are mutually exclusive on a
   service — setting the strategy *is* how you choose Spot.

## What happens on an interruption

- AWS reclaims capacity → the container gets **SIGTERM** and a **2-minute
  warning**. `stopTimeout` (max 120s on Fargate) is how long ECS waits after
  SIGTERM before SIGKILL.
- The task stops with `stopCode: SpotInterruption`.
- The service scheduler notices `running < desired` and launches a
  replacement — **there is no guarantee replacement Spot capacity exists**.
  If the pool is empty you'll see service events like
  `unable to place a task because ... FARGATE_SPOT`.
- With a public-IP-per-task setup (this playground), the replacement task
  gets a **new public IP**. This is why real setups put an ALB in front.

Stopped-task details evaporate from the console within hours, so this
playground ships an EventBridge rule that writes every STOPPED task event to
the `/ecs/play-task-events` log group — that's where you'll find
`stopCode`/`stoppedReason` evidence after the fact.

## Nuances worth knowing

- **No SLA, no capacity guarantee.** Fargate Spot is spare capacity. Unlike
  EC2 Spot there's no bidding and no per-pool price signal you can watch;
  the discount is a fairly stable ~70%.
- **ARM64 (Graviton) on Spot** only works since Sep 2024, needs platform
  version 1.4.0+ (`LATEST` resolves to it). Graviton stacks another ~20%
  savings on top of the Spot discount. This playground uses it.
- **Windows containers are not supported** on Fargate Spot.
- **Graceful shutdown is on you.** nginx handles SIGTERM natively (fast
  shutdown); your own apps must catch SIGTERM and drain within 120s.
- **No rebalance recommendation.** EC2 Spot gives you an early
  "rebalance recommendation" signal; Fargate Spot gives you only the
  2-minute SIGTERM warning.
- **More AZs = better placement odds.** Spreading the service across all
  default subnets (as here) gives the scheduler more Spot pools to try.
- **Changing the strategy** on an existing service forces a new deployment;
  older provider versions required destroying the service entirely.

## Experiments to run

1. **See the discount**: check Cost Explorer after a day; compare
   `FARGATE_SPOT` vs `FARGATE` usage types.
2. **Simulate an interruption** (can't trigger a real one):
   `aws ecs stop-task ... --reason "manual chaos"` and watch the service
   replace the task; check the events log group.
3. **Base + weight mix**: set `desired_count = 5` with
   `FARGATE base=1 weight=1` + `FARGATE_SPOT weight=4` and check each task's
   `capacityProviderName` in `describe-tasks`.
4. **ECS Exec into the task** (enabled here — same SSM plumbing as your
   Session Manager notes):
   `aws ecs execute-command --cluster play-spot --task <id> --container nginx --interactive --command /bin/sh`
5. **Stable endpoint**: add an ALB and watch tasks deregister within the
   2-minute window (deregistration delay must be < 120s to finish draining
   before SIGKILL).
6. **Compare with EC2 Spot capacity providers**: ASG-backed, supports
   rebalance signals + managed scaling — different trade-off space.
