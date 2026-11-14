# Guia do lab: observabilidade da Notas da Nuvem

Passo a passo para subir o ambiente, tirar os **13 prints** na ordem que dá menos trabalho,
simular a falha do banco e destruir tudo. A arquitetura e o porquê das escolhas estão no
[README](README.md); o histórico das mudanças, no [ALTERACOES.md](ALTERACOES.md).

**Tempo total:** ~1 h 30 (40 min de deploy, 40 min de prints, 10 min de destroy).
**Custo:** ~US$ 0,50/h enquanto estiver no ar. Não deixe ligado à toa.

---

## 0. Antes de começar

Ferramentas: Terraform ≥ 1.6, AWS CLI com credenciais da conta, Docker (com buildx), `jq`,
plugin do Session Manager para a AWS CLI.

No `terraform.tfvars`:

```hcl
account_id            = "092304627167"
budget_emails         = ["..."]
grafana_allowed_cidrs = ["<seu IP>/32"]                 # curl -s https://checkip.amazonaws.com
discord_webhook_url   = "https://discord.com/api/webhooks/<id>/<token>"
```

> O IP de casa muda. Se o Grafana parar de abrir, veja [Problemas comuns](#problemas-comuns).

---

## 1. Subir o ambiente

```bash
terraform init

# 1) repositórios no ECR
terraform apply -target=module.ecr -target=module.obs_image_repos

# 2) imagens de terceiros do backend (Docker Hub -> ECR), só linux/amd64
scripts/mirror-images.sh

# 3) imagens de vocês (app-2.2.0 e loadgen-1.1.0)
scripts/build-push.sh

# 4) todo o resto (Aurora leva 10-15 min)
terraform apply
```

Depois do `apply`, **espere ~5 min** pelo bootstrap das duas EC2 e confira:

```bash
terraform output app_url              # abre a aplicação
terraform output grafana_url          # http://<EIP>:3000
terraform output -raw grafana_admin_password   # usuário: admin
```

Na aplicação, crie umas 2–3 notas pela interface. O `notas-loadgen` já está gerando tráfego
sozinho, mas uma nota sua facilita achar o trace depois.

**Espere mais ~5 min** antes dos prints de métricas: as janelas do SLI são de 5 minutos.

---

## 2. Prints, na ordem

### Infra (pode fazer enquanto as métricas acumulam)

**Print 8: EC2 em subnets diferentes**
EC2 > Instances. Mostre as duas instâncias e, nos detalhes de cada uma:
- `lab-obs-grafana`: subnet `Pub(A)`, **IP público** (o EIP), IP privado `10.0.1.250`.
- `lab-obs-backend`: subnet `PrivateFargate(A)`, **sem IP público**, IP privado `10.0.11.250`.

**Print 9: Security groups**
EC2 > Security Groups > aba *Inbound rules*:
- `obs-grafana`: 3000 do seu IP `/32`; 3128 do `obs-backend`.
- `obs-backend`: 4318 do `app`; 9090, 3200, 3100, 9093 do `obs-grafana`.

Nenhuma regra com `0.0.0.0/0`.

**Print 10: Containers do backend**
```bash
aws ssm start-session --target $(terraform output -raw obs_backend_instance_id)
sudo docker ps
```
Devem aparecer `otel-collector`, `prometheus`, `tempo`, `loki`, `alertmanager`.

**Print 2: Nova revisão da task definition**
ECS > Task definitions > `lab-test` > última revisão > container `app`:
- imagem `...labarquiteturanuvem:app-2.2.0`;
- as 7 variáveis da apostila: `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`,
  `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_TRACES_EXPORTER`, `OTEL_METRICS_EXPORTER`,
  `OTEL_LOGS_EXPORTER`, `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED`;
- as 2 extras (`OTEL_EXPERIMENTAL_RESOURCE_DETECTORS`, `OTEL_SEMCONV_STABILITY_OPT_IN`);
- `DB_*` e os segredos `DB_USER`/`DB_PASSWORD` mantidos.

**Print 3: Deployments**
ECS > Clusters > `lab-cluster` > `lab-service` > aba *Deployments*: 2 tasks rodando na revisão nova.

**Print 13 (parte 1): Gerador de tráfego**
ECS > `lab-cluster` > service `notas-loadgen`: 1 task rodando + a task definition `notas-loadgen`.

### Grafana

**Print 1: Data sources**
Connections > Data sources: **Prometheus, Tempo, Loki** (e Alertmanager). Não tem troca de
admin/admin: a senha já nasce aleatória no Secrets Manager. Vale citar isso no texto.

**Print 11: Alertmanager e regras**
- Connections > Data sources > **Alertmanager**.
- Alerting > Alert rules: grupo `notas-da-nuvem-sli` do data source **Prometheus**, com
  `DisponibilidadeAbaixoDoSLO`, `LatenciaP95Alta` e `TelemetriaAusente` em *Normal*.

**Print 4: Trace `POST /notas` até o `INSERT`**
Explore > Tempo > aba *Search* (ou TraceQL):
```
{ span.http.route = "/notas" && span.http.request.method = "POST" }
```
Abra um trace e mostre:
- o span `POST /notas` com o filho `INSERT`;
- no `INSERT`, `db.statement = INSERT INTO notas (texto) VALUES (%s);`. **O texto da nota não vaza**,
  só o placeholder;
- em *Resource attributes*, `host.name` e `service.instance.id`. Abra um segundo trace e mostre
  que esses valores mudam: são as **duas tasks**.

**Print 13 (parte 2): Traces do loadgen**
Explore > Tempo:
```
{ resource.service.name = "notas-loadgen" }
```
Ou o painel *Requisições/s por task* do dashboard mostrando o tráfego contínuo.

**Print 5: Dashboard de SLI**
Dashboards > pasta *Notas da Nuvem* > **Notas da Nuvem - SLI**: disponibilidade (deve estar
~100%), latência p95, requisições por task (duas linhas, uma por task), status por rota, logs.

---

## 3. Simular a falha (prints 6 e 12)

Deixe abertos: o dashboard de SLI, o canal do Discord e um terminal.

```bash
terraform apply -var simulate_db_failure=true      # remove a regra 5432 do sg db
```

Gere alguns erros na hora (o loadgen também gera sozinho):
```bash
curl -sS -o /dev/null -w 'status=%{http_code} tempo=%{time_total}s\n' \
  -X POST --data-urlencode 'texto=teste db_failure' \
  https://app.labdenuvemarquiteturavinicius.click/notas
# esperado: status=500 depois de ~5 s
```

Linha do tempo esperada:

| Depois de | O que acontece |
|---|---|
| ~0–30 s | `POST /notas` passa a responder 500 em ~5 s |
| ~1 min | Disponibilidade cai no dashboard |
| ~2 min | `DisponibilidadeAbaixoDoSLO` vai de *Pending* para **Firing** |
| ~2 min + 10 s | Mensagem **[FIRING]** no Discord |
| ~3–4 min | `LatenciaP95Alta` também dispara (cada erro leva ~5 s) |

**Print 6: SLI caindo + trace com erro**
- Dashboard com a disponibilidade abaixo da linha do SLO de 99,5%.
- Explore > Tempo: `{ status = error && span.http.route = "/notas" }`. Abra um trace: span em
  vermelho com o evento `exception` (`psycopg2.OperationalError`, timeout de conexão).
- Bônus para a Seção 7: EC2 > Target Groups > `tg-lab` com os targets **healthy**. O ALB não percebe
  a falha porque `/health` responde 200.

**Print 12: Alerta disparando + Discord**
- Alerting > Alert rules com `DisponibilidadeAbaixoDoSLO` em **Firing** (ou a aba do Alertmanager).
- A mensagem no canal do Discord.

Depois dos prints, **desfaça a falha**:
```bash
terraform apply -var simulate_db_failure=false
```
Em alguns minutos chega o **[RESOLVED]** no Discord (`send_resolved: true`). Vale um print extra.

> Não precisa repetir a falha se der errado: rode `false`, espere o SLI voltar a ~100% e repita.

---

## 4. Destruir (print 7 por último)

```bash
# o repositório da aplicação não apaga sozinho com imagens dentro
aws ecr batch-delete-image --repository-name labarquiteturanuvem \
  --image-ids "$(aws ecr list-images --repository-name labarquiteturanuvem --query imageIds --output json)"

terraform destroy
terraform state list      # deve sobrar no máximo data.aws_route53_zone.this
```

**Print 7: EC2 Terminated**
EC2 > Instances com `lab-obs-grafana` e `lab-obs-backend` em **Terminated**. O `destroy` já
remove os SGs `obs-grafana`/`obs-backend` e as roles `lab-obs-ec2`/`lab-obs-grafana`, que a
apostila pede para excluir. Se quiser, mostre também que eles sumiram de Security Groups e IAM > Roles.

---

## Problemas comuns

**Grafana não abre (timeout).** Seu IP mudou. Atualize `grafana_allowed_cidrs` e:
```bash
terraform apply -target='module.observability[0].aws_vpc_security_group_ingress_rule.grafana_ui'
```

**Alerta em Firing, mas nada no Discord.** No backend (Session Manager):
```bash
curl -s localhost:9093/metrics | grep 'alertmanager_notifications.*discord'
sudo docker logs --tail 20 alertmanager
```
- `notifications_total` subindo e `failed_total` em 0: a mensagem foi entregue (confira o canal certo).
- `context deadline exceeded`: o Alertmanager não alcança o squid. Na EC2 do Grafana:
  `systemctl status squid` e `grep 'acl backend' /etc/squid/squid.conf` (tem que ser `10.0.11.250`).
- Alertmanager não recebe nada: confira `curl -s localhost:9090/api/v1/alerts` no backend.

**Dashboard vazio / "No data".**
- Logo depois do deploy: espere 5 min (janela do `rate()`).
- Persistindo: `curl -s localhost:9090/api/v1/label/__name__/values | grep http_server` no backend.
  Se não houver nada, veja `sudo docker logs otel-collector` e se as tasks estão na revisão com
  `app-2.2.0`.

**Bootstrap das EC2 falhou.** `sudo tail -50 /var/log/obs-bootstrap.log` na instância.
No backend, o mais comum é imagem faltando no ECR: rode `scripts/mirror-images.sh`.

**`mirror-images.sh` reclama de arquitetura.** Uma tag ficou presa numa imagem que não é amd64
(repositório IMMUTABLE). O script mostra o `aws ecr batch-delete-image` exato; rode e repita.

**Mudei uma config e as EC2 foram recriadas.** Esperado: o `user_data` mudou. Prometheus, Tempo
e Loki voltam vazios; espere ~10 min antes dos prints de métricas.

**`apply` sem `-var simulate_db_failure=true` no meio do teste.** Ele volta a regra 5432
(o padrão é `false`). Rode de novo com `=true`.
