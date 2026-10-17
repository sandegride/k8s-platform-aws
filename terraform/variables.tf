variable "name" {
  type    = string
  default = "platform"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "azs_count" {
  type    = number
  default = 3
}

variable "node_instance_types" {
  type    = list(string)
  default = ["m6i.large"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "gpu_nodes_enabled" {
  type    = bool
  default = false
}

variable "gpu_instance_types" {
  type    = list(string)
  default = ["g5.xlarge"]
}

variable "admin_role_arns" {
  type    = list(string)
  default = []
}
