locals {
  organization = var.account_mode == "organization"
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  # IAM is global; the region is only where each member account's stack runs, so an SCP must allow it.
  region      = var.deploy_roles_region
  read_region = "us-east-1"
  key         = var.account_mode

  read_keys   = var.read_access ? toset([var.account_mode]) : toset([])
  cur_keys    = var.include_cost_data ? local.read_keys : toset([])
  oidc        = var.context_layer_sign_in_method == "oidc"
  oidc_keys   = local.oidc ? local.read_keys : toset([])
  member_keys = local.oidc && local.organization ? local.read_keys : toset([])

  read_role_name        = var.names != null ? var.names.read_role : (local.organization ? var.read_role_name : null)
  read_stack_set_name   = var.names != null ? var.names.read_stack_set : var.name
  cur_bucket_name       = var.names != null ? var.names.cur_bucket : null
  cur_export_name       = var.names != null ? var.names.cur_export : "cq-cur-${var.name}"
  cur_policy_name       = var.names != null ? var.names.cur_policy : "cur-read"
  deploy_role_name      = var.names != null ? var.names.deploy_role : var.deploy_role_name
  deploy_stack_set_name = var.names != null ? var.names.deploy_stack_set : "${var.name}-deploy-roles"

  deploy_roles = local.organization && length(var.deploy_account_ids) > 0
  deploy_oidc  = var.deploy_sign_in_method == "oidc"
  deploy_role_policy_arns = (
    var.deploy_role_policy_arns != null
    ? var.deploy_role_policy_arns
    : ["arn:${local.partition}:iam::aws:policy/AdministratorAccess"]
  )
  deploy_permissions_boundary = try(split(":policy/", var.deploy_role_permissions_boundary_arn)[1], "")
  deploy_in_this_account = (
    local.organization ? var.deploy_management_account : var.deploy_single_account
  )
  deploy_project_ids_here = (
    var.deploy_project_ids_by_account == null
    ? var.deploy_project_ids
    : lookup(var.deploy_project_ids_by_account, local.account_id, [])
  )
  no_project_id = "none"
  deploy_template_by_account = (
    var.deploy_project_ids_by_account != null || can(regex(":root$", var.deploy_trusted_principal_arn))
  )
  deploy_template_source = file("${path.module}/deploy-role.yaml")
  deploy_template_mapped = local.deploy_template_by_account && local.deploy_oidc
  deploy_mapping_accounts = toset(concat(
    var.deploy_account_ids,
    keys(var.deploy_project_ids_by_account == null ? {} : var.deploy_project_ids_by_account)
  ))
  deploy_account_mappings = {
    for id in local.deploy_mapping_accounts : id => {
      Ids = (
        length(var.deploy_project_ids_by_account == null ? var.deploy_project_ids : lookup(var.deploy_project_ids_by_account, id, [])) > 0
        ? (var.deploy_project_ids_by_account == null ? var.deploy_project_ids : lookup(var.deploy_project_ids_by_account, id, []))
        : [local.no_project_id]
      )
    }
  }
  deploy_template_text = replace(
    replace(
      replace(local.deploy_template_source, local.trusted_principal_pattern, local.trusted_principal_pattern_with_root),
      local.project_ids_assertion,
      ""
    ),
    local.project_ids_join,
    local.deploy_template_mapped ? local.project_ids_from_mapping : local.project_ids_join
  )
  deploy_template = (
    local.deploy_template_by_account
    ? jsonencode(merge(yamldecode(local.deploy_template_text), local.deploy_template_mapped ? { Mappings = { AccountProjects = local.deploy_account_mappings } } : {}))
    : local.deploy_template_source
  )
  deploy_template_limit = 51200
  deploy_template_bytes = length(local.deploy_template)
  deploy_project_counts = concat([0], [for ids in values(var.deploy_project_ids_by_account == null ? {} : var.deploy_project_ids_by_account) : length(ids)])

  trusted_principal_pattern           = "AllowedPattern: '^(arn:aws[a-z-]*:iam::\\d{12}:role/[\\w+=,.@/-]+)?$'"
  trusted_principal_pattern_with_root = "AllowedPattern: '^(arn:aws[a-z-]*:iam::\\d{12}:(root|role/[\\w+=,.@/-]+))?$'"
  project_ids_assertion               = "      - Assert: {'Fn::Not': [{'Fn::EachMemberEquals': [{Ref: AllowedProjectIds}, '']}]}\n        AssertDescription: OIDC needs AllowedProjectIds.\n"
  project_ids_join                    = "ProjectIds: {'Fn::Join': ['\",\"', {Ref: AllowedProjectIds}]}"
  project_ids_from_mapping            = "ProjectIds: {'Fn::Join': ['\",\"', {'Fn::FindInMap': [AccountProjects, {Ref: 'AWS::AccountId'}, Ids]}]}"
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "current" {
  count = local.organization ? 1 : 0
}

module "oidc_provider" {
  for_each = local.oidc_keys
  source   = "https://env0-cloud-compass-templates-prod.s3.amazonaws.com/db31401ac476/cloud-compass-opentofu.zip//cloud-compass-oidc-provider"

  name     = var.name
  issuer   = var.context_layer_oidc_issuer
  audience = var.context_layer_oidc_audience
}

data "aws_iam_policy_document" "trust" {
  for_each = local.oidc ? toset([]) : local.read_keys

  lifecycle {
    precondition {
      condition     = var.context_layer_role_arn != null && var.external_id != null
      error_message = "assume_role needs context_layer_role_arn and external_id."
    }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.context_layer_role_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

# A role may assume itself only when its trust policy says so.
data "aws_iam_policy_document" "self_assume" {
  for_each = local.member_keys

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:${local.partition}:iam::${local.account_id}:role/${local.read_role_name}"]
    }
  }

  lifecycle {
    precondition {
      condition     = local.read_role_name != null
      error_message = "An Organization's read role needs a name, the one the member roles share."
    }
  }
}

# The provider's ARN comes from the module, so IAM never sees a trust in a provider not made yet.
data "aws_iam_policy_document" "oidc_trust" {
  for_each                = local.oidc_keys
  source_policy_documents = local.organization ? [data.aws_iam_policy_document.self_assume[local.key].json] : []

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.oidc_provider[local.key].provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.context_layer_oidc_issuer}:aud"
      values   = [var.context_layer_oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.context_layer_oidc_issuer}:sub"
      values   = [var.context_layer_oidc_subject]
    }
  }

  lifecycle {
    precondition {
      condition     = var.context_layer_oidc_issuer != null && var.context_layer_oidc_audience != null && var.context_layer_oidc_subject != null
      error_message = "oidc needs context_layer_oidc_issuer, context_layer_oidc_audience and context_layer_oidc_subject."
    }
  }
}

resource "aws_iam_role" "read" {
  for_each           = local.read_keys
  name               = local.read_role_name
  name_prefix        = local.read_role_name == null ? "${var.name}-read-" : null
  assume_role_policy = local.oidc ? data.aws_iam_policy_document.oidc_trust[each.key].json : data.aws_iam_policy_document.trust[each.key].json
}

resource "aws_iam_role_policy_attachment" "read_only" {
  for_each   = local.read_keys
  role       = aws_iam_role.read[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "cur_read" {
  for_each = local.cur_keys

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.cur[each.key].arn,
      "${aws_s3_bucket.cur[each.key].arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "bcm-data-exports:GetExport",
      "bcm-data-exports:ListExports",
      "bcm-data-exports:GetTable",
      "bcm-data-exports:ListTables",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cur_read" {
  for_each = local.cur_keys
  name     = local.cur_policy_name
  role     = aws_iam_role.read[each.key].id
  policy   = data.aws_iam_policy_document.cur_read[each.key].json
}

# CloudQuery's assetInventoryAdditionalReadActions (cdk-onboarding/lib/common/iam.ts), which ReadOnlyAccess lacks.
data "aws_iam_policy_document" "additional_read" {
  for_each = local.read_keys

  statement {
    effect = "Allow"
    actions = [
      "quicksight:ListGroups",
      "quicksight:ListUsers",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "additional_read" {
  for_each = local.read_keys
  name     = "additional-read"
  role     = aws_iam_role.read[each.key].id
  policy   = data.aws_iam_policy_document.additional_read[each.key].json
}

# CloudQuery's Deny list (cdk-onboarding/lib/common/iam.ts), with the CUR bucket kept readable as in its unified stack.
data "aws_iam_policy_document" "default_deny" {
  for_each = local.read_keys

  statement {
    effect = "Deny"
    actions = [
      "cloudformation:GetTemplate",
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "ec2:GetConsoleOutput",
      "ec2:GetConsoleScreenshot",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "kinesis:Get*",
      "lambda:GetFunction",
      "logs:GetLogEvents",
      "sdb:Select*",
      "sqs:ReceiveMessage",
      "secretsmanager:GetSecretValue",
      "ssm:GetCommandInvocation",
      "ssm:GetParameter*",
    ]
    resources = ["*"]
  }

  # Without cost data the role reads no S3 object at all.
  statement {
    effect        = "Deny"
    actions       = ["s3:GetObject"]
    resources     = var.include_cost_data ? null : ["*"]
    not_resources = var.include_cost_data ? ["${aws_s3_bucket.cur[each.key].arn}/*"] : null
  }
}

resource "aws_iam_role_policy" "default_deny" {
  for_each = local.read_keys
  name     = "default-deny"
  role     = aws_iam_role.read[each.key].id
  policy   = data.aws_iam_policy_document.default_deny[each.key].json
}

data "aws_iam_policy_document" "assume_member_roles" {
  for_each = local.member_keys

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:${local.partition}:iam::*:role/${local.read_role_name}"]
  }
}

resource "aws_iam_role_policy" "assume_member_roles" {
  for_each = local.member_keys
  name     = "assume-member-roles"
  role     = aws_iam_role.read[each.key].id
  policy   = data.aws_iam_policy_document.assume_member_roles[each.key].json
}
