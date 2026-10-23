data "aws_secretsmanager_secret" "alert_webhook" {
  name = "project2/alertmanager/webhook-secret"
}
data "archive_file" "alert_lambda" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/sns_alert_handler.py"
  output_path = "${path.module}/sns_alert_handler.zip"
}

resource "aws_iam_role" "alert_lambda" {
  name = "project2-alert-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alert_lambda_logs" {
  role       = aws_iam_role.alert_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "alert_lambda_sns" {
  name = "project2-alert-sns-publish"
  role = aws_iam_role.alert_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.monitoring_alerts.arn
    }]
  })
}


resource "aws_iam_role_policy" "alert_lambda_secret" {
  name = "project2-alert-secret-read"
  role = aws_iam_role.alert_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = data.aws_secretsmanager_secret.alert_webhook.arn
    }]
  })
}


resource "aws_lambda_function" "alert_webhook" {
  function_name    = "project2-alert-webhook"
  role             = aws_iam_role.alert_lambda.arn
  handler          = "sns_alert_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.alert_lambda.output_path
  source_code_hash = data.archive_file.alert_lambda.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN      = aws_sns_topic.monitoring_alerts.arn
      WEBHOOK_SECRET_ARN = data.aws_secretsmanager_secret.alert_webhook.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.alert_lambda_logs,
    aws_iam_role_policy.alert_lambda_sns,
    aws_iam_role_policy.alert_lambda_secret
  ]
}

resource "aws_apigatewayv2_api" "alert_webhook" {
  name          = "project2-alert-webhook"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "alert_lambda" {
  api_id                 = aws_apigatewayv2_api.alert_webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.alert_webhook.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "alert_webhook" {
  api_id    = aws_apigatewayv2_api.alert_webhook.id
  route_key = "POST /alerts"
  target    = "integrations/${aws_apigatewayv2_integration.alert_lambda.id}"
}

resource "aws_apigatewayv2_stage" "alert_webhook" {
  api_id      = aws_apigatewayv2_api.alert_webhook.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.alert_webhook.execution_arn}/*/POST/alerts"
}

output "alert_webhook_url" {
  value = "${aws_apigatewayv2_api.alert_webhook.api_endpoint}/alerts"
}
