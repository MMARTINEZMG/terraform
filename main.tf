# Tabla DynamoDB para Formulario
resource "aws_dynamodb_table" "support_table" {
  name         = "SupportTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# Tabla DynamoDB para Usuarios
resource "aws_dynamodb_table" "users_table" {
  name         = "UsersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }
}

# Rol de IAM para Lambda
resource "aws_iam_role" "lambda_role" {
  name = "support-lambda-role"

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

# Actualización de la política de permisos de IAM para incluir la tabla de usuarios
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.support_table.arn,
          aws_dynamodb_table.users_table.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Actualización de la función Lambda para usar las dos tablas
resource "aws_lambda_function" "support_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "support-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.support_table.name
      USERS_TABLE    = aws_dynamodb_table.users_table.name
    }
  }
}

# Grupo de logs de CloudWatch
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.support_lambda.function_name}"
  retention_in_days = 14
}

# API Gateway
resource "aws_apigatewayv2_api" "support_api" {
  name          = "support-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "support_stage" {
  api_id      = aws_apigatewayv2_api.support_api.id
  name        = "$default"
  auto_deploy = true
}

# Integración de Lambda con API Gateway
resource "aws_apigatewayv2_integration" "support_integration" {
  api_id                 = aws_apigatewayv2_api.support_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.support_lambda.invoke_arn
  payload_format_version = "2.0"
}

# Rutas de API Gateway
resource "aws_apigatewayv2_route" "create_support" {
  api_id    = aws_apigatewayv2_api.support_api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.support_integration.id}"
}

resource "aws_apigatewayv2_route" "get_supports" {
  api_id    = aws_apigatewayv2_api.support_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.support_integration.id}"
}

# Nueva ruta de API Gateway para Login
resource "aws_apigatewayv2_route" "login" {
  api_id    = aws_apigatewayv2_api.support_api.id
  route_key = "POST /login"
  target    = "integrations/${aws_apigatewayv2_integration.support_integration.id}"
}

# Permiso para invocar Lambda desde la ruta Login
resource "aws_lambda_permission" "api_gateway_login_lambda" {
  statement_id  = "AllowAPIGatewayInvokeLogin"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.support_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.support_api.execution_arn}/*"
}
# Outputs
output "api_gateway_url" {
  value = aws_apigatewayv2_stage.support_stage.invoke_url
}