output "role_arn" {
  description = "ARN of the Cloud Compass read role (the management account's for an Organization). Null without read access."
  value       = one(values(aws_iam_role.read)[*].arn)
}

output "account_id" {
  description = "ID of the AWS account (the management account for an Organization)."
  value       = local.account_id
}

output "organization_id" {
  description = "ID of the AWS Organization. Null for one account."
  value       = one(data.aws_organizations_organization.current[*].id)
}

output "cur_export_name" {
  description = "Name of the CUR 2.0 export. Null without cost data or read access."
  value       = one([for export in values(aws_bcmdataexports_export.cur) : export.export[0].name])
}

output "cur_bucket" {
  description = "S3 bucket of the CUR 2.0 export. Null without cost data or read access."
  value       = one(values(aws_s3_bucket.cur)[*].bucket)
}

output "cur_prefix" {
  description = "S3 prefix of the CUR 2.0 export. Null without cost data or read access."
  value       = length(local.cur_keys) > 0 ? local.cur_prefix : null
}

output "deploy_role_arns" {
  description = "ARN of the deploy role per account ID: the member accounts whose stack instance is CURRENT, and this account when it has a deploy role."
  # From the instances, not the list: a failed account's instance stays OUTDATED and its role may not exist. The read
  # lists every instance of the StackSet, so one made outside the module in another region is left out.
  value = merge(
    {
      for summary in flatten(aws_cloudformation_stack_instances.deploy_roles[*].stack_instance_summaries) :
      summary.account_id => "arn:${local.partition}:iam::${summary.account_id}:role/${local.deploy_role_name}"
      if summary.region == local.region && summary.status == "CURRENT" && contains(var.deploy_account_ids, summary.account_id)
    },
    { for role in aws_iam_role.deploy : local.account_id => role.arn },
    { for role in aws_iam_role.deploy_management : local.account_id => role.arn },
  )

  precondition {
    condition     = local.organization || length(var.deploy_account_ids) == 0
    error_message = "deploy_account_ids is for an Organization; one account deploys with its own role."
  }
}

output "deploy_stack_instance_statuses" {
  description = "Status of the deploy role's stack instance in deploy_roles_region per member account ID. An account with none there has no deploy role from this module; one that is not CURRENT may keep the role an earlier apply made."
  # A failed StackSet update leaves accounts OUTDATED with their earlier role, and a later apply with no change succeeds.
  value = {
    for summary in flatten(aws_cloudformation_stack_instances.deploy_roles[*].stack_instance_summaries) :
    summary.account_id => summary.status if summary.region == local.region
  }
}

output "deploy_roles_template_bytes" {
  description = "Size in bytes of the deploy StackSet's template, which AWS limits to 51,200. Null without member deploy roles."
  value       = local.deploy_roles ? local.deploy_template_bytes : null
}

output "deploy_stack_set_name" {
  description = "Name of the deploy StackSet. Null without member deploy roles."
  value       = one(aws_cloudformation_stack_set.deploy_roles[*].name)
}

output "deploy_stack_set_region" {
  description = "Region of the deploy StackSet's instances. Null without member deploy roles."
  value       = local.deploy_roles ? local.region : null
}
