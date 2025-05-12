
```markdown
# ⚡ FlashProxy `sdk-gateway` – Production Terraform Stack

> **Purpose:**  
> Deploy and auto-scale a fleet of lightweight TCP gateway nodes for FlashProxy's infrastructure. These act as TCP endpoints for clients, behind a Network Load Balancer, with CloudWatch-based traffic-driven scaling.

---

## 📁 Directory Purpose

This directory defines the **production environment** for `sdk-gateway`, including:

- One **public subnet** in a VPC
- A **Network Load Balancer** (NLB)
- An **Auto Scaling Group** of Amazon Linux 2 EC2 instances
- **CloudWatch alarms** for dynamic scale in/out
- A **Go build script** that compiles the gateway at instance boot

---

## 🔍 Architecture Overview

```

User → NLB (:8080) → ASG (EC2) → echo-id Go binary

+---------+      +---------------------+
\| Client  | ---> | NLB (sdk-nlb)       | → Target Group (sdk-tg)
+---------+      | Network Load Balancer
+---------------------+
↓
Auto Scaling Group (sdk\_asg, 1–10 instances)
↳ Launch Template builds echo-id

````

---

## 📦 Files Breakdown

| File | Description |
|------|-------------|
| `main.tf` | VPC, subnet, security group, launch template, ASG, NLB |
| `scaling.tf` | CloudWatch metric math, step scaling policies, alarms |
| `variables.tf` | Environment variables and defaults |
| `versions.tf` | Terraform and AWS provider requirements |
| `userdata.tpl` | Cloud-init Go build script for EC2 |
| `outputs.tf` | DNS name output of the load balancer |
| `README.md` | What you’re reading |

---

## ⚙️ What’s Deployed

### VPC & Network

- VPC CIDR: `10.10.0.0/16`
- Public Subnet: `10.10.1.0/24`
- Route to Internet Gateway
- Security Group: allows TCP :8080 and SSH :22

### Load Balancer (NLB)

- Type: `network`
- Listener: TCP :8080
- Target Type: `instance`
- Health Check: TCP

### Launch Template

- Amazon Linux 2 (latest)
- Builds Go binary at boot (`echo-id`)
- Uses GitHub tag `sdk_gateway_tag` (default: `v0.1.0`)

### Auto Scaling Group

- Desired: 3 instances
- Min: 1 / Max: 10
- In AZ: `eu-central-1a`
- Tags instances with `Name=sdk-gateway`

---

## 📈 Scaling Logic

### CloudWatch Metric Math

```hcl
flows = FILL(raw_flows, 0)
hosts = FILL(raw_hosts, 1)
fpi   = flows / hosts
````

Where:

* `raw_flows` is NLB `ActiveFlowCount`
* `raw_hosts` is NLB `HealthyHostCount`

### Alarms

| Name            | Trigger                       | Action             |
| --------------- | ----------------------------- | ------------------ |
| `HighFlows`     | `fpi >= 200` for 3 datapoints | ASG scale-out (+1) |
| `LowFlows`      | `fpi <= 50` for 10 datapoints | ASG scale-in (−1)  |
| `LowCPUCredits` | `CPUCreditBalance < 20`       | ASG scale-out (+1) |

---

## 🚀 Deployment

```bash
cd fp-prod/flashproxy-infrastructure/live/prod/sdk-gateway/

terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

### Output

```hcl
sdk_gateway_endpoint = sdk-nlb-xxxxx.elb.eu-central-1.amazonaws.com
```

Test connectivity:

```bash
curl sdk-nlb-xxxxx.elb.eu-central-1.amazonaws.com:8080
# → should return EC2 instance ID
```

---

## 🧪 Load Testing

### Slow connection flood

```bash
go run slowflood.go \
  -addr sdk-nlb-xxxxx.elb.eu-central-1.amazonaws.com:8080 \
  -n 211 -batch 10 -delay 3s -hold 5m
```

* Opens 211 TCP connections over 63s
* Keeps them open for 5 minutes
* NLB `ActiveFlowCount` and `FlowsPerInstance` increase
* Triggers `HighFlows` → scales out

---

## 🕵️ Observability

| Metric             | Source                 |
| ------------------ | ---------------------- |
| `ActiveFlowCount`  | AWS/NetworkELB         |
| `HealthyHostCount` | AWS/NetworkELB         |
| `FlowsPerInstance` | CloudWatch Metric Math |
| ASG activity       | Auto Scaling console   |

Use the CloudWatch → Alarms view to watch scale-in/scale-out behavior.

---

## 🛠️ Tips & Customization

| Need                       | How                                                         |
| -------------------------- | ----------------------------------------------------------- |
| Add AZs                    | Extend subnet and NLB subnets                               |
| Change scaling thresholds  | Edit `scaling.tf` alarm blocks                              |
| Change instance type       | Edit `variables.tf` → `instance_type`                       |
| Prebuild Go binary instead | Replace `userdata.tpl` logic with `curl` of compiled binary |

---

## ✅ Tested With

* Terraform `>= 1.5`
* AWS provider `~> 5.0`
* Go `>= 1.22`
* EC2: `t3.small`

---

## 🧼 Cleanup

To tear down this environment:

```bash
terraform destroy
```

---

## 🔐 Notes

* Flow metrics use `arn_suffix` for CloudWatch compatibility
* All connections are stateless TCP
* Scaling behavior is automatic, no manual intervention required

---

## 🧠 Reference

* [AWS NLB Metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html)
* [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

© FlashProxy, 2025 – Internal infrastructure module

```

---

Let me know if you want it exported as a downloadable `.md` file via a file tool when available. For now, just copy the entire contents and paste into:

```

fp-prod/flashproxy-infrastructure/live/prod/sdk-gateway/README.md

```
```
