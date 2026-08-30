variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for team-alpha"
  type        = string
  default     = "team-alpha-data"
}

variable "floci_endpoint" {
  description = "Floci emulator endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}
