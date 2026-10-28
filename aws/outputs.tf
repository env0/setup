output "role_arn" {
  description = "ARN of the Cloud Compass read role (the management account's for an Organization)."
  value       = one(concat(module.single[*].role_arn, module.organization[*].role_arn))
}

output "account_id" {
  description = "ID of the AWS account (the management account for an Organization)."
  value       = one(concat(module.single[*].account_id, module.organization[*].account_id))
}

output "organization_id" {
  description = "ID of the AWS Organization. Null for one account."
  value       = one(module.organization[*].organization_id)
}

output "cur_export_name" {
  description = "Name of the CUR 2.0 export. Null without cost data."
  value       = one(concat(module.single[*].cur_export_name, module.organization[*].cur_export_name))
}

output "cur_bucket" {
  description = "S3 bucket of the CUR 2.0 export. Null without cost data."
  value       = one(concat(module.single[*].cur_bucket, module.organization[*].cur_bucket))
}

output "cur_prefix" {
  description = "S3 prefix of the CUR 2.0 export. Null without cost data."
  value       = one(concat(module.single[*].cur_prefix, module.organization[*].cur_prefix))
}

output "deploy_role_arns" {
  description = "ARN of the deploy role per member account ID, for the accounts whose stack instance is CURRENT."
  # From the instances, not the list: a failed account's instance stays OUTDATED and its role may not exist.
  value = {
    for summary in flatten(aws_cloudformation_stack_instances.deploy_roles[*].stack_instance_summaries) :
    summary.account_id => "arn:${data.aws_partition.current.partition}:iam::${summary.account_id}:role/${var.deploy_role_name}"
    if summary.status == "CURRENT" && contains(var.deploy_account_ids, summary.account_id)
  }

  precondition {
    condition     = local.organization || length(var.deploy_account_ids) == 0
    error_message = "deploy_account_ids is for an Organization; one account deploys with its own role."
  }
}
