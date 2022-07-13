#data source for AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#ec2
resource "aws_instance" "app" {
  count = var.instance_count #SET A VALUE OF A VARIABLE, when this module will be called through root main.tf

  ami           = data.aws_ami.amazon_linux.id #SET AN AMI WHICH DATA SOURCE FETCHED 
  instance_type = var.instance_type #SET A VALUE OF A VARIABLE, when this module will be called through root main.tf

  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)] #(Optional) VPC Subnet ID to launch in. 2 ec2s per subnet , so 2 subnets
  vpc_security_group_ids = var.security_group_ids

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
    EOF
}
