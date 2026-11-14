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
    ├── cloudfront/           # Passos 6 / 7.5 / 7.6 — distribuição, alias app., registro app.
    ├── observability/        # EC2 Grafana (pública) + EC2 backend (privada: Collector, Prometheus, Tempo, Loki, Alertmanager)
    │   ├── config/           #   configs de cada componente, regras de alerta e dashboard de SLI
    │   └── templates/        #   user_data das duas instâncias
    └── loadgen/              # service extra notas-loadgen (1 task que gera tráfego e logs)
```

Também na raiz: `Dockerfile` multistage (targets `app` e `loadgen`, sobre a imagem pública
`rafaelserpa/notas-da-nuvem:1.0.0`), `loadgen/loadgen.py`, `scripts/build-push.sh` e
`scripts/mirror-images.sh` (espelha as imagens do backend de observabilidade no ECR).

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

Ligada por `enable_observability` (padrão `true`). Diferente da apostila (um único
container `grafana/otel-lgtm`), a stack fica em **duas camadas**:

```
                      seu IP ──3000──▶ EC2 lab-obs-grafana   (Pub A, EIP, sg obs-grafana)
                                             │ 9090 / 3200 / 3100 / 9093
                                             ▼
tasks app + loadgen ──OTLP/HTTP 4318──▶ EC2 lab-obs-backend  (PrivateFargate A, sem IP público, sg obs-backend)
   (sg app)                               otel-collector ─┬─▶ Tempo       (traces, OTLP gRPC)
                                                          ├─▶ Prometheus  (métricas, remote write) ─▶ Alertmanager ─▶ Discord
                                                          └─▶ Loki        (logs, OTLP nativo)
```

| Security group | Entrada | Origem |
|---|---|---|
| `obs-grafana` | 3000 | só `grafana_allowed_cidrs` (seu IP /32; `0.0.0.0/0` é recusado pela validação) |
| `obs-backend` | 4318 | só `sg app` (tasks da aplicação e do loadgen) |
| `obs-backend` | 9090, 3200, 3100, 9093 | só `sg obs-grafana` |
| `endpoint` | 443 | `sg app`, `obs-backend`, `obs-grafana` |

**Sem NAT:** a EC2 de backend instala o Docker pelo endpoint gateway do S3 (repositórios do
AL2023), puxa as imagens dos repositórios `lab-obs/*` do ECR (espelhadas do Docker Hub por
`scripts/mirror-images.sh`), lê o webhook do Discord pelo endpoint do Secrets Manager e é
acessada pelo Session Manager (endpoints `ssm`, `ssmmessages` e `ec2messages`, criados só com a
observabilidade ligada). O Grafana, na subnet pública, baixa a própria imagem pela internet.

**Roles separadas (menor privilégio):** `lab-obs-ec2` (backend: SSM, leitura do ECR, segredo do
Discord) e `lab-obs-grafana` (SSM, segredo da senha do admin).

### Como subir

```bash
# no terraform.tfvars:
#   grafana_allowed_cidrs = ["<seu IP>/32"]      # curl -s https://checkip.amazonaws.com
#   discord_webhook_url   = "https://discord.com/api/webhooks/<id>/<token>"

terraform apply -target=module.ecr -target=module.obs_image_repos
scripts/mirror-images.sh   # Docker Hub -> ECR (collector, prometheus, tempo, loki, alertmanager)
scripts/build-push.sh      # app-2.2.0 e loadgen-1.1.0
terraform apply

terraform output grafana_url                    # http://<EIP>:3000
terraform output -raw grafana_admin_password    # login: admin
```

O bootstrap leva alguns minutos depois que a instância fica *running*. Log em
`/var/log/obs-bootstrap.log` nas duas EC2.

### O que já vem provisionado

- **Data sources:** Prometheus, Tempo (com link para logs), Loki (com link `trace_id` → Tempo) e
  Alertmanager (*Receive Grafana Alerts*). Alerting > Settings vai para *External*.
- **Regras no Prometheus** ([alert-rules.yml](modules/observability/config/alert-rules.yml)):
  - `sli:disponibilidade:ratio_rate5m` e `sli:latencia_p95:seconds_rate5m` (recording rules);
  - `DisponibilidadeAbaixoDoSLO` (< 99,5% por 1 min), `LatenciaP95Alta` (> 500 ms por 2 min) e
    `TelemetriaAusente`.
  O Prometheus avalia, o Alertmanager agrupa e o `discord_configs` (`send_resolved: true`) avisa no canal.
- **Dashboard** *Notas da Nuvem - SLI* (pasta *Notas da Nuvem*): disponibilidade, p95/p50,
  requisições por task, respostas por status/rota e logs.

### Instrumentação: diferenciando as tasks

Além das 7 variáveis `OTEL_*` da apostila, as tasks recebem:

| Variável | Para quê |
|---|---|
| `OTEL_EXPERIMENTAL_RESOURCE_DETECTORS=host,service_instance` | cada task ganha `host.name` (hostname da task, `ip-10-0-1x-y.ec2.internal`) e um `service.instance.id` próprio. No Tempo aparecem nos atributos de recurso; no Prometheus viram os rótulos `host_name`, `service_instance_id` e `instance` (o Collector usa `resource_to_telemetry_conversion`) |
| `OTEL_SEMCONV_STABILITY_OPT_IN=http` | semconv HTTP estável: a métrica fica fixa em `http_server_request_duration_seconds` com `http_response_status_code`, `http_request_method` e `http_route`, nomes que as regras e o dashboard usam |

A imagem `app-2.2.0` também roda o gunicorn com **1 worker e 8 threads**. Com 2 workers, o SDK
inicializado antes do fork fazia os dois processos exportarem métricas cumulativas com o mesmo
recurso, e as séries se misturavam no Prometheus. As versões do OpenTelemetry ficam fixas no
Dockerfile (SDK 1.45.2, contrib 0.66b2).

### Operação

- **Shell no backend:** `aws ssm start-session --target $(terraform output -raw obs_backend_instance_id)`,
  depois `sudo docker ps`.
- **Falha do Passo 9:** `terraform apply -var simulate_db_failure=true` remove a regra 5432 do sg `db`;
  `-var simulate_db_failure=false` desfaz. O health check do ALB tem timeout de 10 s: o `/health`
  demora ~5 s com o banco inalcançável (`connect_timeout`), e com o timeout padrão de 5 s o ALB
  derrubaria as tasks.
- **Desligar o gerador de carga** (para o Aurora pausar): `-var loadgen_desired_count=0`.

### Evidências

| Nº | Evidência | Onde/como |
|---|---|---|
| 1 | Data sources Prometheus, Tempo, Loki | Connections > Data sources. Sem admin/admin: a senha nasce aleatória no Secrets Manager |
| 2 | Nova revisão com a imagem OTel e as `OTEL_*` | ECS > Task definitions > `lab-test` (imagem `:app-2.2.0`, as 7 da apostila + 2 de identidade, `DB_*` mantidas) |
| 3 | 2 tasks na nova revisão | ECS > `lab-service` > Deployments |
| 4 | Trace `POST /notas` → `INSERT` | Explore > Tempo, `{ span.http.route = "/notas" }`. O `db.statement` fica `INSERT INTO notas (texto) VALUES (%s);`, ou seja, o texto da nota **não** vaza. Compare `host.name`/`service.instance.id` de dois traces |
| 5 | Dashboard com SLI e p95 | Dashboard *Notas da Nuvem - SLI* |
| 6 | SLI caindo + trace com erro | `simulate_db_failure=true` por ~2 min; o `POST /notas` vira 500 e o trace mostra a exceção do psycopg2 |
| 7 | EC2 Terminated | Último print, depois do `terraform destroy` (que também remove os SGs `obs-*` e as roles `lab-obs-*`) |
| 8 | Grafana na pública, backend na privada | EC2 > detalhes das duas instâncias (subnet, IP público / ausência dele) |
| 9 | Regras dos SGs | `obs-grafana` e `obs-backend` (tabela acima) |
| 10 | Containers do backend | Session Manager no backend → `sudo docker ps` |
| 11 | Alertmanager no Grafana + regra no Prometheus | Connections > Data sources > Alertmanager; Alerting > Alert rules (data source Prometheus) |
| 12 | Alerta disparando + Discord | Durante o Passo 9: Alerting > Alert rules / Alertmanager, e a mensagem no canal |
| 13 | Gerador de tráfego | ECS > service `notas-loadgen` e, no Tempo, `{ resource.service.name = "notas-loadgen" }` / painel de requisições subindo |

### Onde medir o SLI (Seção 7)

**Escolha: dentro da aplicação** (instrumentação OpenTelemetry no Flask), com o ALB como apoio.

> **SLI de disponibilidade:** proporção das requisições HTTP atendidas pela Notas da Nuvem,
> exceto o health check `/health`, que terminam com status diferente de 5xx, numa janela móvel
> de 5 minutos. SLO: 99,5%.
>
> **SLI de latência:** 95º percentil da duração das mesmas requisições, medida pelo servidor
> desde a chegada até a resposta, numa janela de 5 minutos. Objetivo: ≤ 500 ms.

Por quê:
- **Navegador** mede a experiência real, mas exige RUM, depende da rede de cada usuário e não
  vê o tráfego gerado por scripts/APIs.
- **ALB** vê toda requisição que chega, mas não explica a falha. No Passo 9 o ALB continua
  marcando as tasks como saudáveis, porque `/health` responde 200 com `"database": "erro: ..."`,
  enquanto o `POST /notas` devolve 500.
- **Na aplicação** a mesma telemetria que mede o SLI liga cada erro ao trace (span do
  psycopg2 com a exceção) e ao log, por rota e por task. O ponto cego (requisições que nem chegam
  à task, por exemplo erros 502/503 do próprio ALB) é coberto olhando as métricas do ALB no CloudWatch.

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
