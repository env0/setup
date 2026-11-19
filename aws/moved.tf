moved {
  from = module.single[0].module.oidc_provider[0]
  to   = module.oidc_provider["single"]
}

moved {
  from = module.organization[0].module.management.module.oidc_provider[0]
  to   = module.oidc_provider["organization"]
}

moved {
  from = module.single[0].aws_iam_role.read
  to   = aws_iam_role.read["single"]
}

moved {
  from = module.organization[0].module.management.aws_iam_role.read
  to   = aws_iam_role.read["organization"]
}

moved {
  from = module.single[0].aws_iam_role_policy_attachment.read_only
  to   = aws_iam_role_policy_attachment.read_only["single"]
}

moved {
  from = module.organization[0].module.management.aws_iam_role_policy_attachment.read_only
  to   = aws_iam_role_policy_attachment.read_only["organization"]
}

moved {
  from = module.single[0].aws_iam_role_policy.cur_read[0]
  to   = aws_iam_role_policy.cur_read["single"]
}

moved {
  from = module.organization[0].module.management.aws_iam_role_policy.cur_read[0]
  to   = aws_iam_role_policy.cur_read["organization"]
}

moved {
  from = module.single[0].aws_iam_role_policy.additional_read
  to   = aws_iam_role_policy.additional_read["single"]
}

moved {
  from = module.organization[0].module.management.aws_iam_role_policy.additional_read
  to   = aws_iam_role_policy.additional_read["organization"]
}

moved {
  from = module.single[0].aws_iam_role_policy.default_deny
  to   = aws_iam_role_policy.default_deny["single"]
}

moved {
  from = module.organization[0].module.management.aws_iam_role_policy.default_deny
  to   = aws_iam_role_policy.default_deny["organization"]
}

moved {
  from = module.organization[0].module.management.aws_iam_role_policy.assume_member_roles[0]
  to   = aws_iam_role_policy.assume_member_roles["organization"]
}

moved {
  from = module.single[0].aws_s3_bucket.cur[0]
  to   = aws_s3_bucket.cur["single"]
}

moved {
  from = module.organization[0].module.management.aws_s3_bucket.cur[0]
  to   = aws_s3_bucket.cur["organization"]
}

moved {
  from = module.single[0].aws_s3_bucket_server_side_encryption_configuration.cur[0]
  to   = aws_s3_bucket_server_side_encryption_configuration.cur["single"]
}

moved {
  from = module.organization[0].module.management.aws_s3_bucket_server_side_encryption_configuration.cur[0]
  to   = aws_s3_bucket_server_side_encryption_configuration.cur["organization"]
}

moved {
  from = module.single[0].aws_s3_bucket_public_access_block.cur[0]
  to   = aws_s3_bucket_public_access_block.cur["single"]
}

moved {
  from = module.organization[0].module.management.aws_s3_bucket_public_access_block.cur[0]
  to   = aws_s3_bucket_public_access_block.cur["organization"]
}

moved {
  from = module.single[0].aws_s3_bucket_ownership_controls.cur[0]
  to   = aws_s3_bucket_ownership_controls.cur["single"]
}

moved {
  from = module.organization[0].module.management.aws_s3_bucket_ownership_controls.cur[0]
  to   = aws_s3_bucket_ownership_controls.cur["organization"]
}

moved {
  from = module.single[0].aws_s3_bucket_policy.cur[0]
  to   = aws_s3_bucket_policy.cur["single"]
}

moved {
  from = module.organization[0].module.management.aws_s3_bucket_policy.cur[0]
  to   = aws_s3_bucket_policy.cur["organization"]
}

moved {
  from = module.single[0].aws_bcmdataexports_export.cur[0]
  to   = aws_bcmdataexports_export.cur["single"]
}

moved {
  from = module.organization[0].module.management.aws_bcmdataexports_export.cur[0]
  to   = aws_bcmdataexports_export.cur["organization"]
}

moved {
  from = module.organization[0].aws_cloudformation_stack_set.members
  to   = aws_cloudformation_stack_set.cloud_compass_read[0]
}

moved {
  from = module.organization[0].aws_cloudformation_stack_set_instance.members
  to   = aws_cloudformation_stack_set_instance.cloud_compass_read_root[0]
}
