# Create cluster
https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html

## Install aws client

## Locally login
```
aws configure
aws eks update-kubeconfig --region region-code --name my-cluster
```

## Add User

## Update auth configmap on cluster to permit user to call kube api

```yaml
apiVersion: v1
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::<<accountid>>:role/AmazonEKSNodeRole
      username: system:node:{{EC2PrivateDNSName}}
  mapUsers: |
   - userarn: arn:aws:iam::<<acountid>>:user/<<userid>
     username: <<userid>>
     groups:
     - system:masters
```

```
kubectl apply -f aws-auth.yaml --namespace=kube-system
```
