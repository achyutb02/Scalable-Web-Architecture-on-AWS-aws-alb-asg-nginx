# Basic provisioning
terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}

# Configures the AWS Provider and region
provider "aws" {
  region = var.aws_region
}

# Create a VPC
resource "aws_vpc" "main" {
    cidr_block = var.vpc_cidr_block

    tags = {
        Name = "main-vpc"
    }
}


/*
    vpc_id attaches the subnet to our VPC
	availability_zone spreads our architecture across 2 AZs → high availability (this is a requirement for AWS Well-Architected Framework)
	map_public_ip_on_launch = true makes instances get public IPs
	cidr_block uses variables, so it's reusable and clean
*/




# Create Public Subnet 1
resource "aws_subnet" "public_subnet_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_1_cidr 
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true # Enable auto-assign public IP

  tags = {
    Name = "public-subnet-1"
  }
}
# Create Public Subnet 2
resource "aws_subnet" "public_subnet_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_2_cidr
  availability_zone = "us-west-2b"
  map_public_ip_on_launch = true # Enable auto-assign public IP

  tags = {
    Name = "public-subnet-2"
  }
}


# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

/*
    vpc_id attaches this route table to our VPC.

  The route block adds a default route:
  any traffic with a destination outside our VPC CIDR
  (0.0.0.0/0 = all IPv4 addresses) is sent to the Internet
  Gateway (igw).

  Traffic whose destination is inside 10.0.0.0/16 uses the
  automatically created "local" route and stays inside the VPC.

*/

# Create a Route Table
resource "aws_route_table" "public_rt" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

    tags = {
        Name = "public-route-table"
    }

}

# Associate Public Subnet 1 with Route Table
resource "aws_route_table_association" "public_subnet_1_association" {
    subnet_id = aws_subnet.public_subnet_1.id # fetches the ID of Public Subnet 1
    route_table_id = aws_route_table.public_rt.id # fetches the ID of the Route Table
}

# Associate Public Subnet 2 with Route Table
resource "aws_route_table_association" "public_subnet_2_association" {

  subnet_id = aws_subnet.public_subnet_2.id # fetches the ID of Public Subnet 2
  route_table_id = aws_route_table.public_rt.id # fetches the ID of the Route Table
}


# Create a Security Group for Application Load Balancer
resource "aws_security_group" "application_load_balancer_sg" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP traffic from anywhere

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-security-group"
  }

}

# Create a Security Group for EC2 instances
resource "aws_security_group" "ec2_instance_sg" {
  name = "ec2-sg"
  description = "Security group for EC2 instances behind ALB"
  vpc_id = aws_vpc.main.id

  # Allow HTTP traffic only from the ALB's security group
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.application_load_balancer_sg.id]
  }

  # Allow all outbound traffic (permission for the instance to initiate a connection to the outside world.)
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }

}

# Crate a launch template for EC2 instances
resource "aws_launch_template" "web_lt" {
  name_prefix = "web-launch-template"
  
  image_id = var.ami_id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.ec2_instance_sg.id]
  }


  # User data script to install Nginx in base64 encoding
  user_data = base64encode(file("${path.module}/scripts/user-data.sh"))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "web-server-instance"
    }
  }
}

# Create a Target Group for the ALB

resource "aws_lb_target_group" "web_tg" {
  name = "web-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id

  health_check {
    path = "/" // Health check path / root of the web server
    protocol = "HTTP"
    matcher = "200" // Expect HTTP 200 response for healthy OK
    interval = 30  // Check every 30 seconds
    timeout = 5 // If server doesn't respond in 5 seconds, consider it unhealthy
    healthy_threshold = 3 // Must pass 3 consecutive health checks to be considered healthy
    unhealthy_threshold = 2 // Consider unhealthy after 2 consecutive failures

  }

  tags = {
    Name = "web-target-group"
  }
}

# Create an Application Load Balancer

resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false # internet-facing ALB
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.application_load_balancer_sg.id
  ]

  subnets = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id
  ]

  tags = {
    Name = "web-alb"
  }
}

# Create a Listener for the ALB

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80 
  protocol          = "HTTP"

  default_action {
    type             = "forward" #listen form port 80 and forward to target group
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Create an Auto Scaling Group

resource "aws_autoscaling_group" "web_asg" {
  name                      = "web-asg"
  desired_capacity          = 2
  min_size                  = 2
  max_size                  = 4
  health_check_type         = "EC2"
  health_check_grace_period = 60

  vpc_zone_identifier = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id
  ]

  target_group_arns = [
    aws_lb_target_group.web_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-asg-instance"
    propagate_at_launch = true
  }
}


# Create a Scaling Policy (CPU-based)
resource "aws_autoscaling_policy" "cpu_policy" {
  name                   = "cpu-tracking-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    # Target 30% CPU. If average CPU > 30%, it adds instances.
    target_value = 30.0 
  }
}