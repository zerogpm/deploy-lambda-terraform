# Deploy Lambda with Terraform and GitHub Actions

This project demonstrates how to deploy an AWS Lambda function using Terraform and GitHub Actions with OIDC authentication.

## Project Structure

```bash
deploy-lambda-terraform/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── src/
│   ├── index.js            # Lambda function code
│   └── package.json        # Node.js dependencies
├── main.tf                 # Terraform configuration
├── variables.tf           # Terraform variables
└── .gitignore            # Git ignore file
```

## Prerequisites

- AWS Account
- GitHub Account
- AWS CLI installed locally
- Terraform installed locally (for testing)

## Setup Instructions

### 1. Create GitHub Repository
```bash
# Clone the repository
git clone https://github.com/zerogpm/deploy-lambda-terraform.git
cd deploy-lambda-terraform
```

### 2. Set up AWS OIDC Provider

First, check if you have any existing OIDC providers:
```bash
aws iam list-open-id-connect-providers
```

If empty, create a new OIDC provider:
```bash
aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

### 3. Create IAM Role for GitHub Actions

Create trust policy:
```bash
cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::541356534908:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:zerogpm/deploy-lambda-terraform:*"
                }
            }
        }
    ]
}
EOF
```

Create IAM role:
```bash
aws iam create-role \
    --role-name GithubActionRole \
    --assume-role-policy-document file://trust-policy.json
```

Create permissions policy:
```bash
cat > permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets",
                "lambda:*",
                "iam:*",
                "logs:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
```

Attach policy to role:
```bash
aws iam put-role-policy \
    --role-name GithubActionRole \
    --policy-name GithubActionPolicy \
    --policy-document file://permissions-policy.json
```

### 4. Set up GitHub Actions Workflow

Create `.github/workflows/deploy.yml`:
```yaml
name: 'Deploy Lambda'

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::541356534908:role/GithubActionRole
          aws-region: us-east-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7.0"

      - name: Install Dependencies
        run: |
          cd src
          npm install
          cd ..

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        if: github.event_name == 'pull_request'

      - name: Terraform Apply
        if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
        run: terraform apply -auto-approve
```

### 5. Lambda Function Code

Create `src/index.js`:
```javascript
import { S3Client, ListBucketsCommand } from "@aws-sdk/client-s3";

const s3Client = new S3Client({ 
    region: process.env.AWS_REGION || 'us-east-1'
});

export const handler = async (event, context) => {
    try {
        console.log(`Listing buckets in region: ${process.env.AWS_REGION}`);
        
        const command = new ListBucketsCommand({});
        const response = await s3Client.send(command);

        const buckets = response.Buckets.map(bucket => ({
            name: bucket.Name,
            creationDate: bucket.CreationDate
        }));

        console.log(`Found ${buckets.length} buckets`);

        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                region: process.env.AWS_REGION,
                buckets: buckets,
                count: buckets.length
            }, null, 2)
        };

    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({
                error: error.message,
                region: process.env.AWS_REGION
            })
        };
    }
};
```

Create `src/package.json`:
```json
{
    "name": "deploy-lambda-terraform",
    "version": "1.0.0",
    "type": "module",
    "dependencies": {
        "@aws-sdk/client-s3": "^3.450.0"
    }
}
```

### 6. Terraform Configuration

Create `main.tf`:
```hcl
provider "aws" {
  region = var.aws_region
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}_lambda_role"

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

resource "aws_iam_role_policy" "s3_policy" {
  name = "${var.project_name}_s3_policy"
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

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/${var.project_name}.zip"
  depends_on  = [null_resource.npm_install]
}

resource "null_resource" "npm_install" {
  triggers = {
    package_json = filemd5("${path.module}/src/package.json")
    source_code  = filemd5("${path.module}/src/index.js")
  }

  provisioner "local-exec" {
    command = "cd ${path.module}/src && npm install --production"
  }
}

resource "aws_lambda_function" "list_buckets_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}_function"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "nodejs18.x"
  timeout         = 10

  environment {
    variables = {
      AWS_REGION = var.aws_region
    }
  }
}
```

Create `variables.tf`:
```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "deploy-lambda-terraform"
}
```

### 7. Create .gitignore

Create `.gitignore`:
```
*.zip
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.backup
node_modules/
```

### 8. Deploy

Push your changes to GitHub:
```bash
git add .
git commit -m "Initial commit"
git push origin main
```

The GitHub Actions workflow will automatically deploy your Lambda function.

## Testing

You can test the Lambda function through the AWS Console or using AWS CLI:
```bash
aws lambda invoke \
  --function-name deploy-lambda-terraform_function \
  --payload '{}' \
  response.json
```

## Notes

- The IAM permissions in this example are broad for demonstration. In production, you should restrict them to the minimum necessary permissions.
- The Lambda function lists all S3 buckets in your AWS account.
- The GitHub Actions workflow deploys on pushes to main and can be manually triggered.


## Cleanup Instructions

To clean up all resources and avoid unwanted AWS charges, follow these steps:

### 1. Terraform Resources Cleanup
Delete all resources created by Terraform (Lambda function, IAM roles, etc.):
```bash
terraform destroy -auto-approve
```

### 2. Manual OIDC Cleanup
Remove the OIDC and IAM resources we created with AWS CLI:

```bash
# 1. Remove the IAM role policy
aws iam remove-role-policy \
    --role-name GithubActionRole \
    --policy-name GithubActionPolicy

# 2. Delete the IAM role
aws iam delete-role \
    --role-name GithubActionRole

# 3. List OIDC providers to get the ARN
aws iam list-open-id-connect-providers

# 4. Delete the OIDC provider
aws iam delete-open-id-connect-provider \
    --open-id-connect-provider-arn arn:aws:iam::541356534908:oidc-provider/token.actions.githubusercontent.com
```

### Verify Cleanup
You can verify that all resources have been deleted:

```bash
# Check OIDC providers
aws iam list-open-id-connect-providers
# Should return empty list: {"OpenIDConnectProviderList": []}

# Check if role exists
aws iam get-role --role-name GithubActionRole
# Should return error indicating role doesn't exist

# Check Lambda function
aws lambda get-function --function-name deploy-lambda-terraform_function
# Should return error indicating function doesn't exist
```

### Important Notes
- Always clean up resources when you're done to avoid unnecessary AWS charges
- Make sure to delete resources in the correct order to handle dependencies
- If you get any errors about resources being in use, check the AWS Console for any remaining dependencies
- The GitHub repository and local files are not affected by this cleanup

## License

MIT