# Platform Assessment Homework

# Flask Fargate Demo

Flask app deployed on AWS ECS Fargate with a full CI/CD pipeline.

**Live:** `http://fargate-demo-alb-1298687959.us-west-2.elb.amazonaws.com`

## Stack
- **App:** Python / Flask / Gunicorn
- **Infra:** Terraform (VPC, ALB, ECS Fargate, ECR)
- **CI/CD:** GitHub Actions

## Run Locally
```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt && pip install -e .
FLASK_APP=hello flask run
```

## Deploy Infrastructure
Configure AWS credentials, then:
```bash
cd terraform && terraform init && terraform apply
```

## CI/CD Pipeline

| Trigger | Workflow | What happens |
|---------|----------|-------------|
| Pull Request | CI | Runs tests + linting. Blocks merge on failure |
| Merge to main | Deploy | Builds image → pushes to ECR → updates ECS task definition → rolling deploy |
| Manual | Rollback | Rolls back ECS to any previous active task definition revision |

## Key Design Decisions
- **Image tagging:** Git SHA tags (not `:latest`) — every image is traceable to a commit
- **ECS Circuit Breaker:** If new tasks fail ALB health checks, ECS automatically rolls back to the last stable task definition with zero downtime
- **Manual Rollback:** GitHub Actions `workflow_dispatch` allows rolling back to any previous revision on demand
- **Branch protection:** `test` and `lint` are required checks before merge
- **Platform:** Images built for `linux/amd64` — required for Fargate on ARM Mac

## Testing the Pipeline

**CI pass scenario**
Create a branch, open a PR and watch both `test` and `lint` checks go green. Merge button is locked until both pass.

**CI fail scenario**
Break the app response or introduce a linting error in a branch. Open a PR and confirm the merge button is blocked.

**Full deploy**
Merge any passing PR to `main`. The Deploy workflow triggers automatically and the change is live on the ALB URL within ~3 minutes.

**Automatic rollback (circuit breaker)**
Deploy a broken image (e.g. wrong port in Dockerfile). ECS detects failed health checks and rolls back to the previous stable revision automatically — no manual intervention needed.

**Manual rollback**
Go to Actions → Rollback → Run workflow. Leave revision empty to roll back to the previous revision, or specify a revision number from the ECS task definition list.

## Known Limitations
| Issue | Why | Fix in production |
|-------|-----|-------------------|
| No CloudWatch logs | IAM permissions boundary | Grant `logs:CreateLogGroup` to task execution role |
| Long-lived AWS keys | OIDC provider creation blocked | Use OIDC federated identity |
| Local Terraform state | No S3 access | S3 backend + DynamoDB locking |



