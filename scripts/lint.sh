#!/usr/bin/env bash
# 인프라 코드 품질 검사 스크립트
set -euo pipefail

echo "=== Terraform Format Check ==="
terraform fmt -check -recursive .

echo ""
echo "=== Terraform Validate (dev) ==="
cd environments/dev
terraform init -backend=false > /dev/null 2>&1
terraform validate
cd ../..

echo ""
echo "✅ All quality checks passed"
