variable "aws_region" {
  description = "AWS region to deploy resources in"
  type = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the main VPC"
  type = string
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for the first public subnet"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for the second subnet"
  type = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances in this architecture"
  type = string
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type = string
}