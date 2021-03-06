# AWS provider for ap-southeast-1 region. Used as default.
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_regions[0]
}

# AWS provider for us-east-1 region.
provider "aws" {
  alias      = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_regions[1]
}

# Bucket used to store website content.
resource "aws_s3_bucket" "website_bucket" {
  bucket = var.website_domain_name
}

# ACL policy for website objects.
resource "aws_s3_bucket_acl" "website_bucket_acl" {
  bucket = aws_s3_bucket.website_bucket.id
  acl    = var.acl
}

# S3 Bucket Static Website Configuration.
resource "aws_s3_bucket_website_configuration" "website_bucket_configuration" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# S3 Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "website_bucket_versioning" {
  bucket = aws_s3_bucket.website_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket Policy to allow read access to objects.
resource "aws_s3_bucket_policy" "website_bucket_allow_read_access_to_objects" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "PublicReadGetObject",
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : "s3:GetObject",
        "Resource" : "arn:aws:s3:::wiki.${var.hosted_zone}/*"
      }
    ]
  })
}

# Request SSL Certificate in ACM.
resource "aws_acm_certificate" "cert" {
  provider                  = aws.us-east-1
  domain_name               = "*.${var.hosted_zone}"
  subject_alternative_names = [var.hosted_zone, "www.${var.hosted_zone}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Cloudfront Distribution for S3 bucket.
resource "aws_cloudfront_distribution" "website_bucket_s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [var.website_domain_name]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    cache_policy_id  = var.managed_caching_policy
    target_origin_id = local.s3_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }
}

# Retrieve existing hosted zone.
data "aws_route53_zone" "my_domain" {
  name = var.hosted_zone
}

# Add A record in Route53 for website.
resource "aws_route53_record" "website_record" {
  zone_id = data.aws_route53_zone.my_domain.zone_id
  name    = var.website_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_bucket_s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_bucket_s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
