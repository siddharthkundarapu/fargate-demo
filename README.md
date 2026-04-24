# Platform Assessment Homework

T# Flask Fargate Demo

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

## CI/CD Pipeline

| Trigger | Workflow | What happens |
|---------|----------|-------------|
| Pull Request | CI | Runs tests + linting. Blocks merge on failure |
| Merge to main | Deploy | Builds image → pushes to ECR → updates ECS task definition → rolling deploy |
| Manual | Rollback | Rolls back ECS to any previous active task definition revision |

## Key Design Decisions
- **Image tagging:** Git SHA tags (not `:latest`) — every image is traceable to a commit
- **Circuit breaker:** ECS auto-rolls back if new tasks fail health checks
- **Branch protection:** `test` and `lint` are required checks before merge
- **Platform:** Images built for `linux/amd64` — required for Fargate on ARM Mac

## Known Limitations
| Issue | Why | 
|-------|-----|
| No CloudWatch logs | IAM permissions boundary | 
| Long-lived AWS keys | OIDC provider creation blocked | 
| Local Terraform state | No S3 access | S3 backend + DynamoDB locking |

