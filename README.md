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
