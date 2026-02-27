# Application Placeholder

This directory is reserved for the actual application code.

For this SRE assessment, the focus is on infrastructure and deployment configuration. The application deployment is fully defined in:

- **Helm Charts**: `../k8s/helm/redemption/`
- **Karpenter Config**: `../k8s/karpenter/`

## Application Requirements

The redemption service should expose:

- `GET /health` - Health check endpoint (returns 200 OK)
- `GET /ready` - Readiness check endpoint
- `GET /metrics` - Prometheus metrics endpoint (port 9090)
- `POST /redeem` - Main redemption endpoint

## Container Image

The Helm chart expects a container image at:
```
ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/redemption:latest
```

Build and push your application image to ECR before deploying.
