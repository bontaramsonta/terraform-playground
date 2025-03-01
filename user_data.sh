#!/bin/bash
# example http server
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from Terraform on ARM!</h1>" > /var/www/html/index.html
