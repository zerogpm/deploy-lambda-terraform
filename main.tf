# main.tf
provider "aws" {
  region = "us-east-1"
}

# IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "s3_list_buckets_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# S3 List Buckets permission
resource "aws_iam_role_policy" "s3_policy" {
  name = "s3_list_buckets_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs permissions
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Zip Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/lambda_function.zip"

  depends_on = [null_resource.npm_install]
}

# Run npm install
resource "null_resource" "npm_install" {
  triggers = {
    package_json = filemd5("${path.module}/src/package.json")
    source_code  = filemd5("${path.module}/src/index.js")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/src && npm install --production"
  }
}

# Lambda Function
resource "aws_lambda_function" "s3_list_buckets_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "nodejs18.x"
  timeout         = 10

  environment {
    variables = {
      AWS_REGION = var.aws_region  # Explicitly set the region
    }
  }
}