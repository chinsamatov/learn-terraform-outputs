#The configuration in main.tf defines a web application, including a VPC, load balancer, EC2 instances, and a database.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.16.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.64.0"

  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names #4 subnets, 2 per AZ, just A & B ????
  private_subnets = slice(var.private_subnet_cidr_blocks, 0, 2) #list: 0,1,2,3,4,5,6,7 => 0,1 = 2
  public_subnets  = slice(var.public_subnet_cidr_blocks, 0, 2) #list: 0,1,2,3,4,5,6,7 => 0,1 = 2

  enable_nat_gateway = true
  enable_vpn_gateway = false
}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "web-server-sg"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks #one of the outputs of the VPC module passed
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "lb-sg-project-alpha-dev"
  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "random_string" "lb_id" {
  length  = 3
  special = false
}

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "2.4.0"

  # Ensure load balancer name is unique
  name = "lb-${random_string.lb_id.result}-project-alpha-dev"

  internal = false

  security_groups = [module.lb_security_group.this_security_group_id]
  subnets         = module.vpc.public_subnets #PUBLIC GUYS ONLY

  number_of_instances = length(module.ec2_instances.instance_ids) #all ec2s
  instances           = module.ec2_instances.instance_ids

  listener = [{
    instance_port     = "80"
    instance_protocol = "HTTP"
    lb_port           = "80"
    lb_protocol       = "HTTP"
  }]

  health_check = {
    target              = "HTTP:80/index.html"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
  }
}

module "ec2_instances" {
  source = "./modules/aws-instance"
                      #default = 2          *          # 0, 1 = 2    =   4 
  instance_count     = var.instances_per_subnet * length(module.vpc.private_subnets)
  instance_type      = var.instance_type
  subnet_ids         = module.vpc.private_subnets[*] #0, 1 = 2
  security_group_ids = [module.app_security_group.this_security_group_id] #access the value via SG output
}

#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
resource "aws_db_subnet_group" "private" {
  subnet_ids = module.vpc.private_subnets
}

#https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
resource "aws_db_instance" "database" {
  allocated_storage = 5
  engine            = "mysql"
  instance_class    = "db.t2.micro"
  username          = var.db_username
  password          = var.db_password

  db_subnet_group_name = aws_db_subnet_group.private.name

  skip_final_snapshot = true
}
