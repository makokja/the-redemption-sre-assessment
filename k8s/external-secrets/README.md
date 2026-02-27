# External Secrets Configuration

This directory contains the configuration for integrating AWS Secrets Manager with Kubernetes using the [External Secrets Operator](https://external-secrets.io/).

## Overview

Instead of storing sensitive credentials directly in Kubernetes Secrets or Helm values, this setup:
- Stores secrets securely in **AWS Secrets Manager**
- Uses **External Secrets Operator** to sync secrets from AWS to Kubernetes
- Leverages **IRSA** (IAM Roles for Service Accounts) for secure authentication

## Architecture

```
AWS Secrets Manager
       ↓
  SecretStore (connects to AWS using IRSA)
       ↓
  ExternalSecret (defines which secrets to sync)
       ↓
  Kubernetes Secret (automatically created/updated)
       ↓
  Application Pods (consume as environment variables)
```

## Files

### [`secret-store.yaml`](./secret-store.yaml)
Configures the connection to AWS Secrets Manager:
- **Namespace**: `redemption`
- **Authentication**: Uses IRSA via service account `redemption-sa`
- **Region**: `us-east-1`

### [`external-secret.yaml`](./external-secret.yaml)
Defines which secrets to sync from AWS Secrets Manager:
- **Source**: AWS Secrets Manager secrets at paths:
  - `redemption/database` - Database credentials (host, port, name, username, password)
  - `redemption/redis` - Redis credentials (host, port, password)
- **Target**: Kubernetes Secret named `redemption-secrets`
- **Refresh**: Every 1 hour

## Prerequisites

1. **External Secrets Operator** installed in the cluster:
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets-system --create-namespace
   ```

2. **AWS Secrets Manager** secrets created:
   ```bash
   # Run the setup script
   ./scripts/setup-secrets-manager.sh
   ```

3. **IAM Role** with Secrets Manager permissions attached to service account:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "secretsmanager:GetSecretValue",
           "secretsmanager:DescribeSecret"
         ],
         "Resource": [
           "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:redemption/*"
         ]
       }
     ]
   }
   ```

## Deployment

1. **Create secrets in AWS Secrets Manager**:
   ```bash
   ./scripts/setup-secrets-manager.sh
   ```

2. **Apply External Secrets configuration**:
   ```bash
   kubectl apply -f k8s/external-secrets/
   ```

3. **Verify the SecretStore is ready**:
   ```bash
   kubectl get secretstore -n redemption
   ```
   
   Expected output:
   ```
   NAME                   AGE   STATUS   READY
   aws-secrets-manager    10s   Valid    True
   ```

4. **Verify the ExternalSecret is synced**:
   ```bash
   kubectl get externalsecret -n redemption
   ```
   
   Expected output:
   ```
   NAME                  STORE                 REFRESH INTERVAL   STATUS         READY
   redemption-secrets    aws-secrets-manager   1h                 SecretSynced   True
   ```

5. **Verify the Kubernetes Secret was created**:
   ```bash
   kubectl get secret redemption-secrets -n redemption
   kubectl describe secret redemption-secrets -n redemption
   ```

## Secret Structure

### AWS Secrets Manager

**`redemption/database`** (JSON):
```json
{
  "host": "redemption-db.xxxxx.us-east-1.rds.amazonaws.com",
  "port": "5432",
  "name": "redemption",
  "username": "redemption_user",
  "password": "your-secure-password"
}
```

**`redemption/redis`** (JSON):
```json
{
  "host": "redemption-redis.xxxxx.cache.amazonaws.com",
  "port": "6379",
  "password": "your-redis-password"
}
```

### Kubernetes Secret

The ExternalSecret creates a Kubernetes Secret with these keys:
- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`
- `REDIS_HOST`
- `REDIS_PORT`
- `REDIS_PASSWORD`

These are consumed by the application as environment variables.

## Troubleshooting

### ExternalSecret shows "SecretSyncedError"

Check the ExternalSecret status:
```bash
kubectl describe externalsecret redemption-secrets -n redemption
```

Common issues:
1. **IAM permissions**: Ensure the service account has the correct IAM role with Secrets Manager permissions
2. **Secret not found**: Verify secrets exist in AWS Secrets Manager:
   ```bash
   aws secretsmanager list-secrets --region us-east-1 | grep redemption
   ```
3. **Wrong region**: Ensure the SecretStore region matches where secrets are stored

### SecretStore shows "Invalid"

Check the SecretStore status:
```bash
kubectl describe secretstore aws-secrets-manager -n redemption
```

Common issues:
1. **Service account not found**: Ensure `redemption-sa` exists
2. **IRSA not configured**: Verify the service account has the `eks.amazonaws.com/role-arn` annotation
3. **External Secrets Operator not running**: Check operator pods:
   ```bash
   kubectl get pods -n external-secrets-system
   ```

### Secrets not updating

The ExternalSecret refreshes every 1 hour by default. To force an immediate refresh:
```bash
kubectl annotate externalsecret redemption-secrets \
  force-sync=$(date +%s) -n redemption
```

## Security Best Practices

1. **Use IRSA**: Never use static AWS credentials
2. **Least privilege**: Grant only `GetSecretValue` and `DescribeSecret` permissions
3. **Scope permissions**: Limit to specific secret paths (`redemption/*`)
4. **Rotate secrets**: Regularly rotate database and Redis passwords
5. **Monitor access**: Enable CloudTrail logging for Secrets Manager access
6. **Use encryption**: Secrets Manager encrypts data at rest by default

## Updating Secrets

To update a secret:

1. **Update in AWS Secrets Manager**:
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id redemption/database \
     --secret-string '{"host":"new-host","port":"5432",...}'
   ```

2. **Wait for sync** (up to 1 hour) or force immediate sync:
   ```bash
   kubectl annotate externalsecret redemption-secrets \
     force-sync=$(date +%s) -n redemption
   ```

3. **Restart pods** to pick up new values:
   ```bash
   kubectl rollout restart deployment redemption -n redemption
   ```

## Cost Considerations

- **Secrets Manager**: $0.40 per secret per month + $0.05 per 10,000 API calls
- **External Secrets Operator**: Free (open source)
- **Estimated monthly cost**: ~$1-2 for 2 secrets with hourly refresh

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
