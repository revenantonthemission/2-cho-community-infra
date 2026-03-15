###############################################################################
# ECR Module
# K8s Docker 이미지 레지스트리
###############################################################################

resource "aws_ecr_repository" "additional" {
  for_each = toset(var.additional_repositories)

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "additional" {
  for_each = toset(var.additional_repositories)

  repository = aws_ecr_repository.additional[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Untagged images: keep last ${var.image_retention_count}"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Tagged images: keep last ${var.image_retention_count}"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "build-", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
