# ArgoCD GitOps Configuration

This directory contains ArgoCD Application manifests for GitOps-based deployment.

## Prerequisites

ArgoCD must be installed in the cluster:

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Deploy Application

```bash
# Update the repoURL in application.yaml with your Git repository
sed -i 's|your-org|YOUR_GITHUB_ORG|g' application.yaml

# Apply the ArgoCD Application
kubectl apply -f application.yaml

# Check sync status
kubectl get application -n argocd redemption

# Watch the sync
kubectl get application -n argocd redemption -w
```

## Access ArgoCD UI

1. Open browser: https://localhost:8080
2. Login: admin / (password from above)
3. View the "redemption" application

## Features Enabled

- **Auto-sync**: Automatically deploys changes from Git
- **Self-heal**: Reverts manual changes to match Git state
- **Prune**: Removes resources deleted from Git
- **Retry logic**: Handles transient failures
- **Ignore HPA replicas**: Lets HPA manage pod count

## Manual Sync

If auto-sync is disabled:

```bash
# Sync via CLI
argocd app sync redemption

# Or via kubectl
kubectl patch application redemption -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

## Rollback

```bash
# List history
argocd app history redemption

# Rollback to previous version
argocd app rollback redemption <revision-number>
```

## Best Practices

1. **Separate repos**: Consider separate repos for app code and manifests
2. **Environment branches**: Use branches (main, staging, prod) or directories
3. **Secrets**: Use sealed-secrets or external-secrets-operator
4. **Notifications**: Configure Slack/email notifications for sync failures
5. **RBAC**: Restrict who can sync to production

## Troubleshooting

```bash
# Check application status
kubectl describe application redemption -n argocd

# View sync logs
argocd app logs redemption

# Force refresh
argocd app get redemption --refresh
```
