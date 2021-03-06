# ---------------------------------------------------------------------------------------------------------------------
# CREATE A S3 BUCKET THAT IS SECURED BY DEFAULT
# - Bucket public access blocking all set to true
# - Server-Side-Encryption (SSE) at rest enabled by default (AES256),
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Set default values for the S3 Bucket
# ---------------------------------------------------------------------------------------------------------------------

locals {
  cors_enabled    = length(keys(var.cors_rule)) > 0
  logging_enabled = length(keys(var.logging)) > 0
  sse_enabled     = length(keys(var.apply_server_side_encryption_by_default)) > 0

  cors       = local.cors_enabled ? [var.cors_rule] : []
  logging    = local.logging_enabled ? [var.logging] : []
  encryption = local.sse_enabled ? [var.apply_server_side_encryption_by_default] : []

  versioning = try(
    [{ enabled = tobool(var.versioning) }],
    length(keys(var.versioning)) > 0 ? [var.versioning] : [],
    []
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Create the S3 Bucket
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "bucket" {
  count = var.create ? 1 : 0

  bucket              = var.bucket
  bucket_prefix       = var.bucket_prefix
  acl                 = var.acl
  tags                = var.tags
  force_destroy       = var.force_destroy
  acceleration_status = var.acceleration_status
  region              = var.region
  request_payer       = var.request_payer

  dynamic "cors_rule" {
    for_each = local.cors

    content {
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }

  dynamic "versioning" {
    for_each = local.versioning

    content {
      enabled    = lookup(versioning.value, "enabled", null)
      mfa_delete = lookup(versioning.value, "mfa_delete", false)
    }
  }

  dynamic "logging" {
    for_each = local.logging

    content {
      target_bucket = logging.value.target_bucket
      target_prefix = lookup(logging.value, "target_prefix", null)
    }
  }

  dynamic "server_side_encryption_configuration" {
    for_each = local.encryption
    iterator = sse

    content {
      rule {
        apply_server_side_encryption_by_default {
          kms_master_key_id = lookup(sse.value, "kms_master_key_id", null)
          sse_algorithm = lookup(sse.value, "sse_algorithm",
            lookup(sse.value, "kms_master_key_id", null) == null ? "AES256" : "aws:kms"
          )
        }
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    iterator = rule

    content {
      id                                     = lookup(rule.value, "id", null)
      prefix                                 = lookup(rule.value, "prefix", null)
      tags                                   = lookup(rule.value, "tags", null)
      abort_incomplete_multipart_upload_days = lookup(rule.value, "abort_incomplete_multipart_upload_days", null)
      enabled                                = rule.value.enabled

      dynamic "expiration" {
        for_each = length(keys(lookup(rule.value, "expiration", {}))) == 0 ? [] : [rule.value.expiration]

        content {
          date                         = lookup(expiration.value, "date", null)
          days                         = lookup(expiration.value, "days", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker", null)
        }
      }

      dynamic "transition" {
        for_each = lookup(rule.value, "transition", [])

        content {
          date          = lookup(transition.value, "date", null)
          days          = lookup(transition.value, "days", null)
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = length(keys(lookup(rule.value, "noncurrent_version_expiration", {}))) == 0 ? [] : [rule.value.noncurrent_version_expiration]
        iterator = expiration

        content {
          days = lookup(expiration.value, "days", null)
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = lookup(rule.value, "noncurrent_version_transition", [])
        iterator = transition

        content {
          days          = lookup(transition.value, "days", null)
          storage_class = transition.value.storage_class
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Set default values for the S3 Bucket Policy
# ---------------------------------------------------------------------------------------------------------------------

locals {
  bucket_id  = join("", aws_s3_bucket.bucket.*.id)
  bucket_arn = join("", aws_s3_bucket.bucket.*.arn)

  cross_account_bucket_actions_enabled                 = length(var.cross_account_bucket_actions) > 0
  cross_account_object_actions_enabled                 = length(var.cross_account_object_actions) > 0
  cross_account_object_actions_with_forced_acl_enabled = length(var.cross_account_object_actions_with_forced_acl) > 0

  cross_account_actions_enabled = local.cross_account_bucket_actions_enabled || local.cross_account_object_actions_enabled || local.cross_account_object_actions_with_forced_acl_enabled

  cross_account_enabled = length(var.cross_account_identifiers) > 0 && local.cross_account_actions_enabled

  policy_enabled = var.create && (var.policy != null || local.cross_account_enabled)
}

# ---------------------------------------------------------------------------------------------------------------------
# Create the S3 Bucket Public Access Block Policy
# All public access should be blocked per default
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "bucket" {
  count = var.create ? 1 : 0

  bucket = local.bucket_id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# ---------------------------------------------------------------------------------------------------------------------
# Attach a Policy to the S3 Bucket to control:
# - Cross account bucket actions
# - Cross account object actions
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "bucket" {
  count = local.policy_enabled ? 1 : 0

  depends_on = [
    aws_s3_bucket_public_access_block.bucket
  ]

  bucket = local.bucket_id
  policy = join("", data.aws_iam_policy_document.bucket.*.json)
}

data "aws_iam_policy_document" "bucket" {
  count = local.policy_enabled ? 1 : 0

  source_json = var.policy

  dynamic "statement" {
    for_each = length(var.cross_account_bucket_actions) == 0 ? [] : [1]

    content {
      actions   = var.cross_account_bucket_actions
      resources = [local.bucket_arn]

      principals {
        type        = "AWS"
        identifiers = var.cross_account_identifiers
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.cross_account_object_actions) == 0 ? [] : [1]

    content {
      actions   = var.cross_account_object_actions
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.cross_account_identifiers
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.cross_account_object_actions_with_forced_acl) == 0 ? [] : [1]

    content {
      actions   = var.cross_account_object_actions_with_forced_acl
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.cross_account_identifiers
      }

      dynamic "condition" {
        for_each = length(var.cross_account_forced_acls) == 0 ? [] : [1]

        content {
          test     = "StringEquals"
          variable = "s3:x-amz-acl"
          values   = var.cross_account_forced_acls
        }
      }
    }
  }
}
