provider "aws" {
  region     = var.region
  access_key = var.my_access_key
  secret_key = var.my_secret_key
}

resource "aws_vpc" "default" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
      Name        = var.name,
      Project     = var.project,
      Environment = var.environment
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidr_blocks)
  vpc_id = aws_vpc.default.id

}

resource "aws_route" "private" {
  count = length(var.private_subnet_cidr_blocks)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.default[count.index].id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidr_blocks)

  vpc_id            = aws_vpc.default.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]

}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidr_blocks)

  vpc_id                  = aws_vpc.default.id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidr_blocks)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidr_blocks)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


#
# NAT resources
#
resource "aws_eip" "nat" {
  count = length(var.public_subnet_cidr_blocks)

  vpc = true
}

resource "aws_nat_gateway" "default" {
  depends_on = [aws_internet_gateway.default]

  count = length(var.public_subnet_cidr_blocks)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

}

resource "aws_security_group" "ec2_instance" {
  vpc_id = aws_vpc.default.id
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface_sg_attachment" "ec2_instance" {
  security_group_id    = aws_security_group.ec2_instance.id
  network_interface_id = aws_instance.ec2_instance.primary_network_interface_id
}

resource "aws_instance" "ec2_instance" {
  ami                         = var.ec2_instance_ami
  availability_zone           = var.availability_zones[1]
#   ebs_optimized               = var.ec2_instance_ebs_optimized
  instance_type               = var.ec2_instance_instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[1].id
  associate_public_ip_address = true

}

resource "aws_ebs_volume" "coalfire_ebs" {

  availability_zone = var.availability_zones[1]
  size              = 20
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.coalfire_ebs.id
  instance_id = aws_instance.ec2_instance.id
}


resource "aws_launch_configuration" "asg-launch-config-coalfire" {
  image_id          = var.ec2_instance_ami
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instance-sg.id]
  
  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd.x86_64
                systemctl start httpd.service
                systemctl enable httpd.service
                echo “Hello World from $(hostname -f)” > /var/www/html/index.html
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "asg_coalfire" {
  launch_configuration = aws_launch_configuration.asg-launch-config-coalfire.id
  min_size = 2
  max_size = 6
  vpc_zone_identifier = ["${aws_subnet.private[1].id}"]
  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

resource "aws_lb" "coalfire-alb" {
  name               = "coalfire-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public.*.id
  security_groups    = [aws_security_group.coalfire_elb_sg.id]

}

resource "aws_lb_listener" "coalfire-alb-listener" {
  load_balancer_arn = aws_lb.coalfire-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.coalfire-tg.arn
  }
}

resource "aws_lb_target_group" "coalfire-tg" {
  name     = "coalfire-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.default.id
}

resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.asg_coalfire.id
  alb_target_group_arn   = aws_lb_target_group.coalfire-tg.arn
}

resource "aws_security_group" "coalfire_elb_sg" {
  name = "coalfire_elb_sg"
  vpc_id      = aws_vpc.default.id
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port   = var.elb_port    
    to_port     = var.elb_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "instance-sg" {
  name = "instance-sg"
  vpc_id      = aws_vpc.default.id
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "coalfire_bucket_tim_shamraliev" {
  bucket = "coalfire-bucket-tim-shamraliev"
  acl    = "private"

  lifecycle_rule {
    id      = "images"
    prefix  = "images/"
    enabled = true

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  lifecycle_rule {
    id      = "log"
    enabled = true

    prefix = "log/"

    tags = {
      rule      = "log"
      autoclean = "true"
    }

    expiration {
      days = 90
    }
  }

}