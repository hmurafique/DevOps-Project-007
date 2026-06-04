terraform {
  backend "s3" {
    bucket  = "mario-eks-tfstate-umar"
    region  = "us-east-1"
    key     = "super-mario/terraform.tfstate"
    encrypt = true
  }
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
