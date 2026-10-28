terraform {
  # Terraform 1.5.7, the last MPL release, must work.
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.4"
    }
  }
}

# The Cloud Compass resources pin their own region; the StackSets use this one.
provider "aws" {
  region = "us-east-1"
}
