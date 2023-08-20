variable "subnets_count" {
  type    = list(string)
  default = ["subnet1", "subnet2","subnet3"]
}

variable "region" {
  default = "us-east-2"
}

variable "availability_zone" {
  type    = list(string)
  default = ["us-east-2a", "us-east-2b","us-east-2c"]
}

variable "instance_ami" {
  type    = string
  default = "ami-05803413c51f242b7"
}

variable "instance_size" {
  type    = string
  default = "t2.medium"
}