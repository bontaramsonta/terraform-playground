# SSM Features

## SSM Session Manager

what are the requirements/prerequisites of ssm session manager?

### lets try a scenario.

- create an instance using amz-linux-2 ami which includes ssm agent in default vpc/subnet
- restrict access to port 22 in security group
- lets try connecting to the instance using ssm-session-manager

#### will it work?

nope

*Getting Error*
> SSM Agent is not online
> The SSM Agent was unable to connect to a Systems Manager endpoint to register itself with the service.

*Possible Issues*
- maybe because port 22 is not open
- maybe because ssm agent is not running
- maybe instance is not authorized to connect to ssm.

Now, I opened port 22. But, didn't help.
But after opening port 22, I am able to connect to instance using ec2-instance-connect
I ran `sudo systemctl status amazon-ssm-agent` and it was running but error out with message
<something related to insufficient permissions on instance profile to connect to ssm>

- create ec2messages, ssm, ssmmessages interface endpoints with private dns enabled.

# Ok, now lets do easy mode

I am gonna create the setup in a public subnet this time with managed policy and lax security group.

and it works. Great!. Looks like it most probably because of the interface endpoints.
I missing something in the networking part.

# Let's try again with the same scenario

this time with managed policy and lax security group but private subnet/interface endpoints.

# Solution

Turns out, I was missing security group in the interface endpoints. My understanding was that the interface
endpoints deployed with no specific security group uses the default security group which allows all traffic.
But turns out, it only allows traffic from other resources using the same security group.🤯
