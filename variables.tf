# variables.tf
variable "lambda_function_name" {
  type    = string
  default = "s3_list_buckets"
  description = "Name of the Lambda function"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "deploy-lambda-terraform"
  description = "Name used for various resources"
}