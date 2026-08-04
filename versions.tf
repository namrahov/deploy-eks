terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Real layihede state-i S3-de saxla (komanda ile isleyende mutleqdir):
  # backend "s3" {
  #   bucket         = "my-tfstate-bucket"
  #   key            = "springboot/terraform.tfstate"
  #   region         = "eu-central-1"
  #   dynamodb_table = "tf-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
