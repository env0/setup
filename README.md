# env zero setup

Templates that env zero deploys in your cloud accounts to give itself access.

## aws

The "env zero aws roles" OpenTofu template. On the Add Cloud Compass credential page, pick the environment option:
env zero deploys `aws/` as an environment in its "env zero setup" project, with an organization-level AWS deployment
credential, and asks you to approve the plan before it applies. When the deployment finishes, env zero reads the
outputs and creates the Cloud Compass credential, and for an Organization one deployment credential per picked member
account.

It creates:

- **Cloud Compass read role.** `ReadOnlyAccess`. The Context Layer signs in to it either:
  - with `assume_role` (the default), as its sync role with an External ID;
  - with `oidc`, with your Context Layer workspace's OpenID Connect tokens. A stack adds the workspace's issuer to the
    account as an OpenID Connect provider, or the workspace's audience to an existing one.
- **CUR 2.0 export** to a private S3 bucket, and the read role's permission to read it. Off with
  `include_cost_data = false`.
- **For an AWS Organization** (run in the management account):
  - the read role in every member account, through a service-managed StackSet. With `oidc`, the Context Layer signs in
    to the management account's read role and assumes the member read roles from it;
  - a deploy role, `env0-deploy` by default, in each picked member account (`deploy_account_ids`), through the
    service-managed StackSet `<name>-deploy-roles` and `deploy-role.yaml`. It has `AdministratorAccess` unless
    `deploy_role_policy_arns` names other AWS managed policies, and an optional permissions boundary. It trusts either:
    - with `oidc`, env zero's OpenID Connect tokens for your organization's subject, and only from deployments of the
      projects in `deploy_project_ids`. The stack adds the provider to the account, or env zero's audience to an
      existing one;
    - with `assume_role`, your self-hosted env zero agent's role (`deploy_trusted_principal_arn`), with your env zero
      organization ID as External ID.

An Organization needs trusted access for CloudFormation StackSets turned on in AWS Organizations. The Cloud Compass
resources and the StackSets are in `us-east-1`. The deploy role stacks run in `deploy_roles_region`, `us-east-1` by
default, so the Organization's SCPs must allow that region in the picked accounts.

The Cloud Compass modules come from env zero's published archive, pinned by commit:
`https://env0-cloud-compass-templates-prod.s3.amazonaws.com/<commit>/cloud-compass-opentofu.zip`.

`aws/tests/` runs the template on a mocked AWS provider: `tofu init -backend=false && tofu test` in `aws/`.

### Variables

| Name | Default | Description |
| --- | --- | --- |
| `account_mode` | required | `single` for one AWS account, `organization` for an AWS Organization. |
| `cloudquery_sign_in_method` | `assume_role` | How the Context Layer signs in to the read role: `assume_role` or `oidc`. |
| `cloudquery_role_arn` | `null` | ARN of the Context Layer sync role that assumes the read role. Needed with `assume_role`. |
| `external_id` | `null` | External ID the Context Layer sync role sends. Sensitive. Needed with `assume_role`. |
| `cloudquery_oidc_issuer` | `null` | OpenID Connect issuer of your Context Layer workspace, without the scheme. Needed with `oidc`. |
| `cloudquery_oidc_audience` | `null` | Audience of your Context Layer workspace's tokens. Needed with `oidc`. |
| `cloudquery_oidc_subject` | `null` | Subject of your Context Layer workspace's tokens. Needed with `oidc`. |
| `name` | `env0-cloud-compass` | Prefix of the resource names, unique in the AWS account. |
| `include_cost_data` | `true` | Create the CUR 2.0 export and its bucket. |
| `deploy_account_ids` | `[]` | Organization member accounts that get a deploy role. Not the management account. |
| `deploy_role_name` | `env0-deploy` | Name of the deploy role in each member account. Give each setup its own, so two can share an account. |
| `deploy_role_policy_arns` | `null` | 1 to 10 AWS managed policy ARNs for the deploy roles. `null` gives `AdministratorAccess`. |
| `deploy_role_permissions_boundary_arn` | `""` | Permissions boundary of the deploy roles: a customer managed policy ARN. Each member account must have a policy with the same path and name. Empty for none. |
| `deploy_roles_region` | `us-east-1` | Region the deploy role stacks run in. IAM is global; your SCPs must allow this region. |
| `deploy_role_max_session_duration` | `18000` | Longest deploy role session, in seconds (3600 to 43200). |
| `deploy_sign_in_method` | `oidc` | How env zero signs in to the deploy roles: `oidc` or `assume_role`. |
| `env0_oidc_issuer` | `login.app.env0.com/` | env zero's OpenID Connect issuer, without the scheme. Only env zero's issuers are accepted. |
| `env0_oidc_subject` | `""` | Subject of your env zero organization's tokens. Needed with `oidc`. |
| `deploy_project_ids` | `[]` | Up to 20 env zero project IDs whose deployments may use the deploy roles. Needed with `oidc`. Another project needs the template applied again. |
| `deploy_trusted_principal_arn` | `""` | IAM role ARN of your self-hosted env zero agent. Needed with `assume_role`. |
| `env0_organization_id` | `""` | Your env zero organization ID, the External ID. Needed with `assume_role`. |

### Outputs

`role_arn`, `account_id`, `organization_id`, `cur_export_name`, `cur_bucket`, `cur_prefix`, `deploy_role_arns`
(deploy role ARN per member account ID, only for accounts whose stack instance is `CURRENT`), and
`deploy_stack_instance_statuses` (status of the deploy role's stack instance in `deploy_roles_region` per member
account ID).
