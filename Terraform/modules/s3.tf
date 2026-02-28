# 1. Create the Static Files bucket
resource "aws_s3_bucket" "app_assets" {
  count  = var.enable_s3_assets ? 1 : 0
  bucket        = lower("${var.project_name}-assets-${var.environment}")
  force_destroy = true
}

# 2. Cancel the public access block to enable the bucket policy
resource "aws_s3_bucket_public_access_block" "app_assets_block" {
  count  = var.enable_s3_assets ? 1 : 0
  bucket = aws_s3_bucket.app_assets[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 3. Allowing only read access to anyone
resource "aws_s3_bucket_policy" "allow_public_read" {
  count  = var.enable_s3_assets ? 1 : 0
  bucket = aws_s3_bucket.app_assets[0].id
  depends_on = [aws_security_group.rds_sg, aws_s3_bucket_public_access_block.app_assets_block] 

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.app_assets[0].arn}/*"
      }
    ]
  })
}