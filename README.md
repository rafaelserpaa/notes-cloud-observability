# Lab Nuvem em Terraform — CloudFront + ALB + ECS Fargate + Aurora

Tradução em módulos Terraform da arquitetura documentada na Entrega 1
(aplicação **Notas da Nuvem** em `https://app.labdenuvemarquiteturavinicius.click`).
O código já nasce na **topologia final**: HTTPS de ponta a ponta com ACM e
**sem NAT Gateway**, com a saída das tasks só por VPC Endpoints.

## Estrutura

```
.
├── versions.tf               # Terraform >= 1.6, provider AWS ~> 6.0, backend S3 (comentado)
├── providers.tf              # região, trava de conta, default_tags
├── variables.tf              # padrões = valores da documentação
├── main.tf                   # composição dos módulos
├── outputs.tf
├── terraform.tfvars.example
└── modules/
    ├── budget/               # Passo 1 — AWS Budgets (85% / 100% real, 100% previsto)
    ├── network/              # Passo 2 — VPC, 6 subnets em 2 AZs, IGW, route tables
    ├── security-groups/      # Passo 2.3 — alb → app → db, + endpoint
    ├── vpc-endpoints/        # Passo 8 — ecr.api, ecr.dkr, secretsmanager, logs + S3 gateway
    ├── aurora/               # Passo 3 — subnet group, cluster Serverless v2, writer + reader
    ├── ecr/                  # Passo 4 — repositório IMMUTABLE, scan on push
    ├── acm/                  # Passo 7.1 — certificado domínio + curinga, validação DNS
    ├── alb/                  # Passos 5.3 / 7.3 / 7.4 — ALB, tg-lab (IP), HTTPS:443, registro origin.
    ├── ecs/                  # Passo 5 — log group, execution role, cluster, task definition, service
    ├── cloudfront/           # Passos 6 / 7.5 / 7.6 — distribuição, alias app., registro app. (reusado para o Grafana)
    ├── observability/        # EC2 lab-observabilidade (otel-lgtm + Alertmanager), sg obs, role, EIP, senha do Grafana
    └── loadgen/              # service extra notas-loadgen (1 task que gera tráfego e logs)
```

Também na raiz: `otel/Dockerfile.otel`, `loadgen/` (código + Dockerfile) e `scripts/build-push-otel.sh`.

## Dependências entre módulos

| Módulo | Depende de |
|---|---|
| security-groups | network |
| vpc-endpoints | network, security-groups |
| aurora | network, security-groups |
| alb | network, security-groups, acm |
| ecs | network, security-groups, ecr, aurora, alb, vpc-endpoints |
| cloudfront | acm, alb (registro `origin.`) |

O ECS só é criado depois que os endpoints existem, o listener HTTPS está ligado
ao target group e a instância writer do Aurora está disponível.

## Pré-requisitos

- Terraform >= 1.6 e credenciais da conta (`aws configure` / SSO).
- O domínio `labdenuvemarquiteturavinicius.click` com **hosted zone pública** no
  Route 53 (já existe, foi criada no registro do domínio; o código só a lê).
- Docker, para buildar e enviar a imagem.

## Como subir

O ECS precisa da imagem no ECR antes de iniciar as tasks, então o primeiro
deploy é em duas fases.

```bash
cp terraform.tfvars.example terraform.tfvars   # preencha budget_emails
terraform init

# Fase 1 — só o repositório
terraform apply -target=module.ecr

# Build e push (o mesmo do Passo 4.2)
REGISTRY=$(terraform output -raw ecr_repository_url | cut -d/ -f1)
REPO_URL=$(terraform output -raw ecr_repository_url)
TAG=v1-1.0.0
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REGISTRY"
docker build --platform linux/amd64 -t "$REPO_URL:$TAG" .
docker push "$REPO_URL:$TAG"

# Fase 2 — todo o resto (Aurora leva de 10 a 15 min)
terraform apply
```

Para uma versão nova da aplicação: push com **tag nova** (o repositório é
IMMUTABLE), depois `terraform apply -var image_tag=v1-1.0.1`. Isso gera uma nova
revisão da task definition e o service faz o rolling deploy.

### Validação

```bash
terraform output app_url
curl -I "$(terraform output -raw app_url)"
aws ecs describe-services --cluster lab-cluster --services lab-service \
  --query 'services[0].{running:runningCount,desired:desiredCount}'
```

A evidência do `SELECT * FROM notas;` continua pelo RDS Query Editor: a Data
API já vem habilitada, e os ARNs necessários saem em
`terraform output aurora_cluster_arn` e `terraform output aurora_secret_arn`.

## Observabilidade (OpenTelemetry)

Ligada por `enable_observability` (padrão `true`). Cria a EC2 com `grafana/otel-lgtm`
e Alertmanager, o CloudFront do Grafana (`https://grafana.<domínio>`), o service
`notas-loadgen` e troca a aplicação para a imagem `2.0.0-otel` com as variáveis `OTEL_*`.

Ordem (as imagens precisam existir no ECR antes do service subir):

```bash
terraform apply -target=module.ecr
scripts/build-push-otel.sh /caminho/para/aula-06-cloud-cyber-app   # 2.0.0-otel e 1.0.0-loadgen
terraform apply
terraform output -raw grafana_admin_password    # login: admin
```

- **Alertmanager** só em loopback; túnel:
  `aws ssm start-session --target $(terraform output -raw obs_instance_id) --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["9093"],"localPortNumber":["9093"]}'`
- **Falha do Passo 9:** `terraform apply -var simulate_db_failure=true` remove a regra 5432 do sg `db`;
  `-var simulate_db_failure=false` desfaz.
- **Desligar o gerador de carga** (para o Aurora pausar): `-var loadgen_desired_count=0`.
- **Fica manual** (de propósito): ligar o Alertmanager no Grafana (Alerting > Settings), o painel de SLI e a
  regra de alerta (dependem dos nomes de métrica que você descobre no Metrics browser) e os prints.

## Convivência com a stack criada pelo console

Se a stack do console ainda existir, vários nomes vão colidir: repositório ECR,
`alb-lab`, `tg-lab`, `lab-cluster`, `lab-aurora2`, `db-subnets`, o log group e os
registros `app.` e `origin.` no Route 53. Duas saídas:

1. **Recomendado para o lab:** apagar a stack do console e subir tudo pelo Terraform.
2. **Adotar o que existe:** usar blocos `import { to = ... id = ... }` para cada
   recurso antes do `apply`, e ajustar as variáveis até o `plan` ficar sem diff.

A execution role ganhou o nome `lab-nuvem-ecsTaskExecutionRole` justamente para
não brigar com a `ecsTaskExecutionRole` da conta.

## Como o código evita os problemas da documentação

| Problema na entrega | Como fica no Terraform |
|---|---|
| PrivateAurora(B) criada na AZ errada | AZ e CIDR vêm do mesmo índice (`azs[i]`, `data_subnet_cidrs[i]`) |
| sg db criado como MySQL 3306 | Regra já nasce como TCP 5432 com origem no sg app |
| `relation "notas" does not exist` | O output `cluster_endpoint` depende da instância writer, então as tasks só sobem com o banco no ar; `health_check_grace_period_seconds = 120` cobre o `wait_for_db` |
| Cota do sg alb estourada | Só existe a regra 443 com a prefix list do CloudFront |
| Listener HTTP:443 sem certificado | Listener criado como `HTTPS` com `certificate_arn` |
| Um único endpoint `ecr.dkr` não bastava | Os 4 endpoints de interface + gateway S3 desde o início, sem NAT |

## Diferenças em relação ao console

- **Sem NAT nem Elastic IP:** a configuração inicial (Passo 2.4) foi substituída no
  Passo 8, então o código vai direto para os endpoints.
- **Egress dos SGs:** o console cria "todo tráfego de saída" sozinho; aqui está
  declarado no módulo `security-groups`.
- **Nome do service:** `lab-service` no lugar do nome gerado pelo console
  (`lab-test-service-gb84znfc`).
- **Grace period de 120 s** no service (não estava no console).

## Custos e destroy

Os itens que cobram por hora mesmo parados: ALB, os 4 endpoints de interface
(× 2 AZs) e o Aurora quando não está pausado. Ao fim do lab:

```bash
terraform destroy
```

O Aurora está com `skip_final_snapshot = true` e sem deletion protection. O ECR
tem `force_delete = false`: apague as imagens antes ou passe `force_delete = true`
no módulo. O orçamento do Passo 1 também é removido no destroy.
