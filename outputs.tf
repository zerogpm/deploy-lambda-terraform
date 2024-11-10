# outputs.tf
output "lambda_function_arn" {
  value       = aws_lambda_function.list_buckets_lambda.arn
  description = "ARN of the Lambda function"
}

output "lambda_function_name" {
  value       = aws_lambda_function.list_buckets_lambda.function_name
  description = "Name of the Lambda function"
}