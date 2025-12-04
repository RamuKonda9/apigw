terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# ---------------------------
# Lambda Function
# ---------------------------
resource "aws_lambda_function" "hello_lambda" {
  function_name    = "hello-api-lambda"
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_role.arn
  filename         = "lambda.zip" # Will create below
  source_code_hash = filebase64sha256("lambda.zip")
  lifecycle {
  ignore_changes = [filename, source_code_hash]
}

}

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name = "hello-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach AWS Basic Execution Policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------
# API Gateway
# ---------------------------
resource "aws_api_gateway_rest_api" "api" {
  name        = "HelloAPI"
  description = "Simple API Gateway calling Lambda"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "get_hello" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hello_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.get_hello.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.hello_lambda.invoke_arn
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_invoke" {
  statement_id_prefix = "AllowAPIGatewayInvoke"
  action              = "lambda:InvokeFunction"
  function_name       = aws_lambda_function.hello_lambda.function_name
  principal           = "apigateway.amazonaws.com"
  source_arn          = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}


# Deployment + Stage
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on = [
    aws_api_gateway_integration.hello_integration
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = "prod"
}

output "invoke_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.ap-south-1.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}
