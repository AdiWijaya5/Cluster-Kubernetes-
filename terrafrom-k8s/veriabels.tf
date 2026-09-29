variable "aws_region" {
  type        = string
  default     = "ap-southeast-3"
  description = "AWS Region Jakarta"
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Tipe instance server (2 vCPU, 2 GB RAM)"
}

variable "volume_size" {
  type        = number
  default     = 15
  description = "Ukuran root storage (GB) untuk setiap server"
}

variable "key_name" {
  type        = string
  default     = "k8s-key" 
  description = "AWS Key Pair untuk akses SSH"
}