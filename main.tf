terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }

    github = {
      source  = "integrations/github"
      version = "~> 4.0"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

variable "repo-name" {
  type = string
  description = "Used for naming github repo and projects for dev ops resources"
}

resource "github_repository" "repo" {
  name        = var.repo-name
  description = "Scaffolded from terraform"

  visibility = "public"
  auto_init = true
}

resource "github_repository_file" "build-file" {
  repository          = github_repository.repo.name
  branch              = "main"
  file                = "buildspec.yml"
  content             = file("codebuild/buildspec.yml")
  commit_message      = "Managed by Terraform"
  commit_author       = "Terraform User"
  commit_email        = "terraform@example.com"
  overwrite_on_create = true
}

resource "aws_iam_role_policy" "cloudwatch-policy" {
  name = "${var.repo-name}-cloudwatch-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Resource": [
          "arn:aws:logs:us-east-1:778172975102:log-group:codebuild-${var.repo-name}",
          "arn:aws:logs:us-east-1:778172975102:log-group:codebuild-${var.repo-name}:*"
        ],
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild-policy" {
  name = "${var.repo-name}-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Resource": [
          "arn:aws:logs:us-east-1:778172975102:log-group:/aws/codebuild/${var.repo-name}",
          "arn:aws:logs:us-east-1:778172975102:log-group:/aws/codebuild/${var.repo-name}:*"

        ],
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
      },
      {
        "Effect": "Allow",
        "Resource": [
          "arn:aws:s3:::codepipeline-us-east-1-*"
        ],
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ],
        "Resource": [
          "arn:aws:codebuild:us-east-1:778172975102:report-group/${var.repo-name}-*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.repo-name}-codebuild-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    project: var.repo-name
  }
}

resource "aws_codebuild_project" "example" {
  name          = var.repo-name
  description   = "Builds each commit of ${var.repo-name} in ${github_repository.repo.html_url}"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:1.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${var.repo-name}"
    }

    # Currently not using s3 logs
#    s3_logs {
#      status   = "ENABLED"
#      location = "${aws_s3_bucket.example.id}/codebuild-log"
#    }
  }

  source {
    type            = "GITHUB"
    location        = github_repository.repo.html_url
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  tags = {
    project = var.repo-name
  }
}

resource "aws_codebuild_webhook" "example" {
  project_name = aws_codebuild_project.example.name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "ACTOR_ACCOUNT_ID"
      # use https://api.github.com/users/<username> and use your "id" this will restrict builds to only trigger via
      # this github user pushing
      pattern = "8989563"
    }
  }
}