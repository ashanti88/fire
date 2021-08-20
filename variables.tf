variable "my_access_key" {
    sensitive = true
}
variable "my_secret_key" {
    sensitive = true
}

variable "name" {
  default     = "Default"
  type        = string
  description = "Name of the VPC"
}

variable "project" {
  default = "coalfire_vpc" 
  type        = string
  description = "Name of project this VPC is meant to house"
}

variable "environment" {
  default = "dev"
  type        = string
  description = "Name of environment this VPC is targeting"
}

variable "region" {
  default     = "us-east-1"
  type        = string
  description = "Region of the VPC"
}

variable "key_name" {
  default     = "coalfire_key1"
  type        = string
  description = "EC2 Key pair name for the instance"
}

variable "cidr_block" {
  default     = "10.1.0.0/16"
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidr_blocks" {
  default     = ["10.1.0.0/24", "10.1.1.0/24"]
  type        = list
  description = "List of public subnet CIDR blocks"
}

variable "private_subnet_cidr_blocks" {
  default     = ["10.1.2.0/24", "10.1.3.0/24"]
  type        = list
  description = "List of private subnet CIDR blocks"
}

variable "availability_zones" {
  default     = ["us-east-1a", "us-east-1b"]
  type        = list
  description = "List of availability zones"
}

variable "ec2_instance_ami" {
  type        = string
  description = "Amazon Machine Image (AMI) ID"
}

variable "ec2_instance_ebs_optimized" {
  default     = true
  type        = bool
  description = "If true, the instance will be EBS-optimized"
}

variable "ec2_instance_instance_type" {
  default     = "t2.micro"
  type        = string
  description = "Instance type for instance"
}

variable "elb_port" {
    default = 80
}

variable "server_port" {
    default = 80
}