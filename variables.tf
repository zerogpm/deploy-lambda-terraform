# variables.tf
variable "lambda_function_name" {
  type    = string
  default = "s3_list_buckets"
  description = "Name of the Lambda function"
}
