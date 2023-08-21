terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

# Start of Back end
# DynamoDB portion
resource "aws_dynamodb_table" "resume-dynamodb-table" {
  name         = "resumeVisits"
  billing_mode = "PAY_PER_REQUEST"
  # hash_key is the partition key
  hash_key = "resumeViewCounts"

  attribute {
    name = "resumeViewCounts"
    type = "S"
  }

}

resource "aws_dynamodb_table_item" "resume-dynamodb-table-item" {
  table_name = aws_dynamodb_table.resume-dynamodb-table.name
  hash_key   = aws_dynamodb_table.resume-dynamodb-table.hash_key

  item = <<ITEM
{
    "resumeViewCounts": {"S": "resumeViewCount"},
    "viewCount": {"N": "1"}
}
ITEM
}

# Lambda Portion
data "aws_iam_policy_document" "assume-role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam-for-lambda" {
  name               = "iam-for-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume-role.json
}

resource "aws_iam_role_policy_attachment" "lambda-roles" {
  for_each = toset([
    "arn:aws:iam::391570305388:policy/service-role/AWSLambdaMicroserviceExecutionRole-8eebce10-3c4f-490f-8e87-66f1c4242635",
    "arn:aws:iam::391570305388:policy/service-role/AWSLambdaBasicExecutionRole-2ce8f5ef-d35b-4c6f-b3a6-f7600535236d"
  ])

  role       = aws_iam_role.iam-for-lambda.name
  policy_arn = each.value
}

resource "aws_lambda_function" "resume-lambda" {
  filename      = "C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\updateVisitorCounter.zip"
  function_name = "updateViewsCounter"
  role          = aws_iam_role.iam-for-lambda.arn
  handler       = "lambda_function.lambda_handler"

  runtime = "python3.10"
}

# API Portion

resource "aws_api_gateway_rest_api" "resume-api" {
  name        = "ResumeAPI"
  description = "Terraform-created Resume API"

  depends_on = [aws_lambda_function.resume-lambda]
}

resource "aws_api_gateway_resource" "resume-api-resource" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  parent_id   = aws_api_gateway_rest_api.resume-api.root_resource_id
  path_part   = "viewcounterresource"

  depends_on = [aws_api_gateway_rest_api.resume-api]
}

resource "aws_api_gateway_method" "resume-api-method-patch" {
  rest_api_id   = aws_api_gateway_rest_api.resume-api.id
  resource_id   = aws_api_gateway_resource.resume-api-resource.id
  http_method   = "PATCH"
  authorization = "NONE"

  depends_on = [aws_api_gateway_resource.resume-api-resource]
}

resource "aws_api_gateway_method" "resume-api-method-options" {
  rest_api_id   = aws_api_gateway_rest_api.resume-api.id
  resource_id   = aws_api_gateway_resource.resume-api-resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"

  depends_on = [aws_api_gateway_resource.resume-api-resource]
}

resource "aws_lambda_permission" "apigw-lambda-perm" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume-lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.resume-api.execution_arn}/*/*${aws_api_gateway_resource.resume-api-resource.path}"

  depends_on = [aws_api_gateway_method.resume-api-method-patch]
}

resource "aws_api_gateway_integration" "apigw-lambda-integration-patch" {
  rest_api_id             = aws_api_gateway_rest_api.resume-api.id
  resource_id             = aws_api_gateway_resource.resume-api-resource.id
  http_method             = aws_api_gateway_method.resume-api-method-patch.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.resume-lambda.invoke_arn
}


resource "aws_api_gateway_integration" "apigw-lambda-integration-options" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  resource_id = aws_api_gateway_resource.resume-api-resource.id
  http_method = aws_api_gateway_method.resume-api-method-options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = <<TEMPLATE
{
  "statusCode": 200
}
TEMPLATE
  }
}


resource "aws_api_gateway_method_response" "method-response-200-patch" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  resource_id = aws_api_gateway_resource.resume-api-resource.id
  http_method = aws_api_gateway_method.resume-api-method-patch.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true,
  }

  depends_on = [aws_api_gateway_method_response.method-response-200-patch]
}

resource "aws_api_gateway_method_response" "method-response-200-options" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  resource_id = aws_api_gateway_resource.resume-api-resource.id
  http_method = aws_api_gateway_method.resume-api-method-options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = {
    "application/json" = "Empty"
  }

  depends_on = [aws_api_gateway_method_response.method-response-200-options]
}

resource "aws_api_gateway_integration_response" "integration-response-200-patch" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  resource_id = aws_api_gateway_resource.resume-api-resource.id
  http_method = aws_api_gateway_method.resume-api-method-patch.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'",
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With'",
    "method.response.header.Access-Control-Allow-Methods" = "'PATCH'"
  }

  depends_on = [aws_api_gateway_method_response.method-response-200-patch]
}


resource "aws_api_gateway_integration_response" "integration-response-200-options" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  resource_id = aws_api_gateway_resource.resume-api-resource.id
  http_method = aws_api_gateway_method.resume-api-method-options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'",
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Requested-With'",
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS, PATCH'"
  }

  depends_on = [aws_api_gateway_method_response.method-response-200-options]
}


resource "aws_api_gateway_deployment" "test_deployment" {
  rest_api_id = aws_api_gateway_rest_api.resume-api.id
  stage_name  = "test"

  depends_on = [
    aws_api_gateway_integration.apigw-lambda-integration-patch,
    aws_api_gateway_integration_response.integration-response-200-patch
  ]
}

# JSON file for API call by Resume Javascript

resource "local_file" "apiCallFile" {
  content  = templatefile("C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\apiCallFile.json.tpl", { apiCall = "${aws_api_gateway_deployment.test_deployment.invoke_url}${aws_api_gateway_resource.resume-api-resource.path}" })
  filename = "C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\apiCallFile.json"

  depends_on = [aws_api_gateway_deployment.test_deployment]
}

# Start of Front End

# S3 Resume Bucket generation

resource "aws_s3_bucket" "resume-bucket" {
  bucket = "eh-resume.net"

  depends_on = [local_file.apiCallFile]
}

resource "aws_s3_bucket_public_access_block" "bucket-public" {
  bucket = aws_s3_bucket.resume-bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  depends_on = [aws_s3_bucket.resume-bucket]
}

resource "aws_s3_bucket_policy" "bucket-policy" {
  bucket = aws_s3_bucket.resume-bucket.id

  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[
    {
      "Sid":"PublicReadGetObject",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${aws_s3_bucket.resume-bucket.id}/*"]
    }
    ]
}
POLICY

  depends_on = [aws_s3_bucket_public_access_block.bucket-public]
}

# Locals map to set correct content type to file when going through for_each loop

locals {
  s3_origin_id = "myS3WebOrigin"

  mime_types = {
    ".html" = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".ico"  = "image/vnd.microsoft.icon"
    ".jpeg" = "image/jpeg"
    ".png"  = "image/png"
    ".svg"  = "image/svg+xml"
  }
}

resource "aws_s3_object" "object" {
  for_each = fileset("C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\", "*")

  bucket       = aws_s3_bucket.resume-bucket.id
  key          = each.value
  source       = "C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\${each.value}"
  etag         = filemd5("C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\${each.value}")
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.value), null)
  depends_on   = [aws_s3_bucket.resume-bucket]
}

resource "aws_s3_object" "object-json" {
  bucket = aws_s3_bucket.resume-bucket.id
  key    = "apiCallFile.json"
  source = "C:\\Users\\eldon\\Documents\\Cloud-Resume\\resume\\apiCallFile.json"

  content_type = "application/json"
  depends_on   = [aws_s3_bucket.resume-bucket]
}


resource "aws_s3_bucket_website_configuration" "resume-bucket-site" {
  bucket = aws_s3_bucket.resume-bucket.id

  index_document {
    suffix = "ehresume.html"
  }

  error_document {
    key = "error.html"
  }

  depends_on = [aws_s3_object.object]
}

resource "aws_acm_certificate" "resume-cert" {
  domain_name       = "eh-resume.net"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "resume-zone" {
  name         = "eh-resume.net"
  private_zone = false
}

resource "aws_route53_record" "resume-record" {
  for_each = {
    for dvo in aws_acm_certificate.resume-cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = dvo.domain_name == "eh-resume.net" ? data.aws_route53_zone.resume-zone.zone_id : data.aws_route53_zone.resume-zone.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

resource "aws_acm_certificate_validation" "resume-verify" {
  certificate_arn         = aws_acm_certificate.resume-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.resume-record : record.fqdn]
}

resource "aws_cloudfront_distribution" "resume-distribution" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.resume-bucket-site.website_endpoint
    origin_id   = local.s3_origin_id
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Resume distribution w/ S3 Bucket Website as origin"
  default_root_object = "ehresume.html"
  aliases             = ["eh-resume.net"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "PUT", "POST"]
    cached_methods   = ["GET", "HEAD"]
    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    target_origin_id = local.s3_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    ssl_support_method = "sni-only"
    acm_certificate_arn = aws_acm_certificate.resume-cert.arn
  }


  depends_on = [aws_s3_bucket_website_configuration.resume-bucket-site]
}

resource "aws_route53_record" "resume-a-record" {
  zone_id = data.aws_route53_zone.resume-zone.zone_id
  name = "eh-resume.net"
  type = "A"

  alias {
    name = aws_cloudfront_distribution.resume-distribution.domain_name
    zone_id = aws_cloudfront_distribution.resume-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "resume-aaa-record" {
  zone_id = data.aws_route53_zone.resume-zone.zone_id
  name = "eh-resume.net"
  type = "AAAA"

  alias {
    name = aws_cloudfront_distribution.resume-distribution.domain_name
    zone_id = aws_cloudfront_distribution.resume-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}


# End of Front end

# Outputs

output "api_test_link" {
  value = "${aws_api_gateway_deployment.test_deployment.invoke_url}${aws_api_gateway_resource.resume-api-resource.path}"
}

output "s3-tf-webdomain" {
  value = aws_s3_bucket_website_configuration.resume-bucket-site.website_domain
}

output "s3-tf-webpoint" {
  value = aws_s3_bucket_website_configuration.resume-bucket-site.website_endpoint
}

output "s3-tf-distribution" {
  value = aws_cloudfront_distribution.resume-distribution.id
}

output "origin-domain-name" {
  value = aws_s3_bucket.resume-bucket.bucket_regional_domain_name
}