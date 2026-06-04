# DevOps Project 007 — Deployment of Super Mario on Kubernetes using Terraform

![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=for-the-badge&logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazonaws)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Orchestration-326CE5?style=for-the-badge&logo=kubernetes)
![Docker](https://img.shields.io/badge/Docker-Containerization-2496ED?style=for-the-badge&logo=docker)

> Deploy the classic Super Mario game on Amazon EKS using Terraform for infrastructure automation and Kubernetes for container orchestration.

---

## Architecture Overview

```
EC2 (Ubuntu) + IAM Role (AdministratorAccess)
        ↓
Terraform → AWS EKS Cluster (EKS_CLOUD)
        ↓
Node Group (2x t3.medium)
        ↓
kubectl apply → Mario Deployment (2 Pods)
        ↓
LoadBalancer Service
        ↓
Browser → 🎮 Super Mario Game!
```

---

## Tools and Technologies

![Terraform](https://img.shields.io/badge/Terraform-v1.15.5-7B42BC?style=flat&logo=terraform)
![AWS EKS](https://img.shields.io/badge/AWS-EKS-FF9900?style=flat&logo=amazonaws)
![AWS EC2](https://img.shields.io/badge/AWS-EC2-FF9900?style=flat&logo=amazonaws)
![AWS S3](https://img.shields.io/badge/AWS-S3-569A31?style=flat&logo=amazonaws)
![Docker](https://img.shields.io/badge/Docker-29.1.3-2496ED?style=flat&logo=docker)
![kubectl](https://img.shields.io/badge/kubectl-v1.36.1-326CE5?style=flat&logo=kubernetes)
![AWS CLI](https://img.shields.io/badge/AWS_CLI-2.34.61-FF9900?style=flat&logo=amazonaws)

---

## Project Structure

```
super-mario/
├── deployment.yaml          # Kubernetes Deployment — Mario pods
├── service.yaml             # Kubernetes Service — LoadBalancer
└── EKS-TF/
    ├── backend.tf           # S3 remote backend + provider
    └── main.tf              # EKS Cluster + Node Group + IAM Roles
```

---

## Prerequisites

- AWS Account
- EC2 instance (Ubuntu 22.04, t2.micro)
- IAM Role with AdministratorAccess attached to EC2
- S3 bucket for Terraform state

---

## Step-by-Step Implementation

### Step 1 — Launch EC2 Instance

Launch an EC2 instance with the following configuration:

| Setting | Value |
|---|---|
| Name | mario-server |
| AMI | Ubuntu 22.04 LTS |
| Instance Type | t2.micro |
| Storage | 20 GB |

Security Group inbound rules:

| Port | Purpose |
|---|---|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |

---

### Step 2 — Install Tools

SSH into EC2 and run:

```bash
sudo su
apt update -y

# Docker
apt install docker.io -y
usermod -aG docker ubuntu

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt update && apt install terraform -y

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt-get install unzip -y
unzip awscliv2.zip
./aws/install

# kubectl
apt install curl -y
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
docker --version
terraform --version
aws --version
kubectl version --client
```

---

### Step 3 — Create IAM Role for EC2

1. AWS Console → IAM → Roles → Create Role
2. Trusted entity: AWS Service → EC2
3. Permission: **AdministratorAccess**
4. Role name: `mario-eks-role`
5. Create Role

---

### Step 4 — Attach IAM Role to EC2

1. AWS Console → EC2 → mario-server
2. Actions → Security → Modify IAM Role
3. Select `mario-eks-role` → Update IAM Role

---

### Step 5 — Create S3 Bucket (Terraform State)

```bash
aws s3api create-bucket \
  --bucket mario-eks-tfstate-umar \
  --region us-east-1
```

---

### Step 6 — Create Project Structure

```bash
mkdir -p /home/ubuntu/super-mario/EKS-TF
cd /home/ubuntu/super-mario
```

---

### Step 7 — Create backend.tf

```bash
cat > /home/ubuntu/super-mario/EKS-TF/backend.tf << 'EOF'
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
EOF
```

---

### Step 8 — Create main.tf

Get supported subnet IDs first:

```bash
aws ec2 describe-subnets \
  --filters "Name=availability-zone,Values=us-east-1a,us-east-1b,us-east-1c" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
  --output table
```

> **Note:** Avoid `us-east-1e` — EKS does not support it. Use subnets from `us-east-1a`, `us-east-1b`, `us-east-1c` only.

```bash
cat > /home/ubuntu/super-mario/EKS-TF/main.tf << 'EOF'
# EKS Cluster IAM Role
resource "aws_iam_role" "eks-cluster-role" {
  name = "EKS_CLOUD_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks-cluster-policy" {
  role       = aws_iam_role.eks-cluster-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks-node-role" {
  name = "EKS_CLOUD_Node_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks-worker-node-policy" {
  role       = aws_iam_role.eks-node-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks-cni-policy" {
  role       = aws_iam_role.eks-node-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks-ecr-policy" {
  role       = aws_iam_role.eks-node-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS Cluster
resource "aws_eks_cluster" "mario-eks" {
  name     = "EKS_CLOUD"
  role_arn = aws_iam_role.eks-cluster-role.arn

  vpc_config {
    subnet_ids = [
      "subnet-0415d174ef2ef72b2",  # us-east-1c
      "subnet-021637e5ab2d40ee1",  # us-east-1b
      "subnet-0adfb34eba7952108"   # us-east-1a
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-policy
  ]
}

# EKS Node Group
resource "aws_eks_node_group" "mario-nodes" {
  cluster_name    = aws_eks_cluster.mario-eks.name
  node_group_name = "mario-node-group"
  node_role_arn   = aws_iam_role.eks-node-role.arn
  subnet_ids      = [
    "subnet-0415d174ef2ef72b2",
    "subnet-021637e5ab2d40ee1",
    "subnet-0adfb34eba7952108"
  ]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks-worker-node-policy,
    aws_iam_role_policy_attachment.eks-cni-policy,
    aws_iam_role_policy_attachment.eks-ecr-policy
  ]
}
EOF
```

---

### Step 9 — Create Kubernetes Manifests

**deployment.yaml:**

```bash
cat > /home/ubuntu/super-mario/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mario-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mario
  template:
    metadata:
      labels:
        app: mario
    spec:
      containers:
      - name: mario
        image: sevenajay/mario:latest
        ports:
        - containerPort: 80
EOF
```

**service.yaml:**

```bash
cat > /home/ubuntu/super-mario/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: mario-service
spec:
  selector:
    app: mario
  type: LoadBalancer
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF
```

---

### Step 10 — Deploy Infrastructure

```bash
cd /home/ubuntu/super-mario/EKS-TF

# Initialize
terraform init

# Validate
terraform validate

# Plan
terraform plan

# Apply
terraform apply --auto-approve
```

Expected output:
```
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

⏳ 10-15 minutes for EKS cluster creation.

---

### Step 11 — Configure kubectl

```bash
aws eks update-kubeconfig --name EKS_CLOUD --region us-east-1

# Verify nodes
kubectl get nodes
```

Expected output:
```
NAME                            STATUS   ROLES    AGE   VERSION
ip-xxx-xxx-xxx-xxx.ec2.internal Ready    <none>   Xm    v1.35.x
ip-xxx-xxx-xxx-xxx.ec2.internal Ready    <none>   Xm    v1.35.x
```

---

### Step 12 — Deploy Super Mario

```bash
cd /home/ubuntu/super-mario

kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Check status
kubectl get all
```

Get LoadBalancer URL:

```bash
kubectl describe service mario-service | grep "LoadBalancer Ingress"
```

Open in browser:
```
http://<LoadBalancer-Ingress-URL>
```

---

## Final Result

| Component | Status |
|---|---|
| EC2 (mario-server) | ✅ |
| Docker + Terraform + kubectl + AWS CLI | ✅ |
| IAM Role (AdministratorAccess) | ✅ |
| S3 Backend (Terraform State) | ✅ |
| EKS Cluster (EKS_CLOUD) | ✅ |
| Node Group (2x t3.medium) | ✅ |
| Mario Deployment (2 Pods Running) | ✅ |
| LoadBalancer Service | ✅ |
| Super Mario Live on Browser | ✅ |

---

## Common Issues and Fixes

**UnsupportedAvailabilityZoneException:**
EKS does not support `us-east-1e`. Get supported subnet IDs first:
```bash
aws ec2 describe-subnets \
  --filters "Name=availability-zone,Values=us-east-1a,us-east-1b,us-east-1c" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
  --output table
```
Use only subnets from `us-east-1a`, `us-east-1b`, `us-east-1c`.

**Cluster already exists error:**
If apply was interrupted and cluster already exists, import it:
```bash
terraform import aws_eks_cluster.mario-eks EKS_CLOUD
terraform import aws_eks_node_group.mario-nodes EKS_CLOUD:mario-node-group
```

**Terminal disconnects during apply:**
Use tmux to keep session alive:
```bash
apt install tmux -y
tmux new -s mario
# Run terraform apply inside tmux
# If disconnected: tmux attach -t mario
```

---

## Cleanup

```bash
# Delete Kubernetes resources first
kubectl delete service mario-service
kubectl delete deployment mario-deployment

# Destroy EKS infrastructure
cd /home/ubuntu/super-mario/EKS-TF
terraform destroy --auto-approve

# Delete S3 bucket
aws s3 rm s3://mario-eks-tfstate-umar --recursive
aws s3api delete-bucket --bucket mario-eks-tfstate-umar
```

---

## What I Learned

- Provisioning EKS clusters from scratch using Terraform
- Managing Terraform remote state with S3 backend
- Creating IAM roles for EKS cluster and node groups
- Configuring kubectl to connect to EKS clusters
- Deploying containerized applications on Kubernetes
- Exposing applications via Kubernetes LoadBalancer service
- Troubleshooting EKS availability zone restrictions
- Using tmux to keep long-running processes alive over SSH
