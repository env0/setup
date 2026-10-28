# env zero setup

Templates that env zero deploys in your cloud accounts to give itself access.

## aws

The "env zero aws roles" OpenTofu template. On the Add Cloud Compass credential page, pick the environment option:
env zero deploys `aws/` as an environment in its "env zero setup" project, with an organization-level AWS deployment
credential, and asks you to approve the plan before it applies. When the deployment finishes, env zero reads the
outputs and creates the Cloud Compass credential, and for an Organization one deployment credential per picked member
account.

It creates:

- **Cloud Compass read role.** `ReadOnlyAccess`, assumed by CloudQuery's sync role with an External ID.
- **CUR 2.0 export** to a private S3 bucket, and the read role's permission to read it. Off with
  `include_cost_data = false`.
- **For an AWS Organization** (run in the management account):
  - the read role in every member account, through a service-managed StackSet;
  - an `env-zero-deploy` role with `AdministratorAccess` in each picked member account (`deploy_account_ids`),
    through the service-managed StackSet `<name>-deploy-roles` and `deploy-role.yaml`. It trusts env zero's OpenID
    Connect issuer (adding the provider to the account, or env zero's audience to an existing one), or env zero's AWS
    account with your env zero organization ID as External ID.

An Organization needs trusted access for CloudFormation StackSets turned on in AWS Organizations. Everything is created
in `us-east-1`.

The Cloud Compass modules come from env zero's published archive, pinned by commit:
`https://env0-cloud-compass-templates-prod.s3.amazonaws.com/<commit>/cloud-compass-opentofu.zip`.

### Variables

| Name | Default | Description |
| --- | --- | --- |
| `account_mode` | required | `single` for one AWS account, `organization` for an AWS Organization. |
| `cloudquery_role_arn` | required | ARN of the CloudQuery sync role that assumes the read role. |
| `external_id` | required | External ID the CloudQuery sync role sends. Sensitive. |
| `name` | `env0-cloud-compass` | Prefix of the resource names, unique in the AWS account. |
| `include_cost_data` | `true` | Create the CUR 2.0 export and its bucket. |
| `deploy_account_ids` | `[]` | Organization member accounts that get a deploy role. Not the management account. |
| `deploy_role_name` | `env-zero-deploy` | Name of the deploy role in each member account. |
| `deploy_role_max_session_duration` | `18000` | Longest deploy role session, in seconds (3600 to 43200). |
| `deploy_sign_in_method` | `oidc` | `oidc` or `assume_role`, as the deployment credential that runs the template. |
| `env0_oidc_issuer` | `login.app.env0.com/` | env zero's OpenID Connect issuer, without the scheme. |
| `env0_oidc_subject` | `""` | Subject of your env zero organization's tokens. Needed with `oidc`. |
| `env0_aws_account_id` | `913128560467` | env zero's AWS account. Used with `assume_role`. |
| `env0_organization_id` | `""` | Your env zero organization ID, the External ID. Needed with `assume_role`. |

### Outputs

`role_arn`, `account_id`, `organization_id`, `cur_export_name`, `cur_bucket`, `cur_prefix`, and `deploy_role_arns`
(deploy role ARN per member account ID).
