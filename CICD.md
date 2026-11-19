# Pipeline de CI/CD da Notas da Nuvem

Implementação da apostila **CI/CD e Fitness Functions** (Aula 14) com a stack de CI/CD da AWS
(CodeConnections, CodePipeline, CodeBuild, ECR e ECS), adaptada a este repositório: aqui mora a
**infraestrutura** (Terraform) e a camada OpenTelemetry da imagem. O código da aplicação vem pronto na
imagem pública `rafaelserpa/notas-da-nuvem:1.0.0`, e o repositório da aplicação **não** foi trazido
para cá.

A cada push na `main`, o pipeline verifica segurança, IaC e observabilidade, constrói e publica a
imagem com a tag do commit, gera o `terraform plan`, espera a aprovação e aplica exatamente o plano
aprovado, conferindo no fim se o ECS estabilizou e se a aplicação responde pela URL pública.

## Visão geral

```
 GitHub (push na main)
   │  CodeConnections "notas-github" (GitHub App, só este repositório, sem token pessoal)
   ▼
 ┌─ Source ──────────────── Full clone (histórico completo para o gitleaks)
 │
 ├─ Validacao (em paralelo, os portões mais baratos primeiro: shift left)
 │    ├─ Seguranca ........ gitleaks · pip-audit · Bandit                 notas-seguranca
 │    ├─ IaC .............. terraform fmt/validate · tflint · Trivy config notas-iac
 │    └─ Observabilidade .. pytest + InMemorySpanExporter + PostgreSQL     notas-observabilidade
 │
 ├─ Imagem ................ build app/loadgen · não-root · Bandit e        notas-imagem
 │                          pip-audit no artefato · Trivy (CVE crítica
 │                          com correção) · push no ECR com tag = commit
 │                          → imagedefinitions.json
 │
 ├─ Plano ................. terraform plan com a imagem do commit          notas-plan
 │                          (role somente leitura) · bloqueia destruir
 │                          Aurora/ECR · resumo vai para a aprovação
 │
 ├─ Aprovacao ............. aprovação manual (e-mail via SNS)             opcional
 │
 └─ Deploy ................ espelho das imagens do backend no ECR ·        notas-deploy
                            terraform apply do plano aprovado · ECS
                            estável na revisão nova · GET /health pela
                            URL pública com banco ok
```

Qualquer portão vermelho interrompe o pipeline: nada é publicado no ECR nem aplicado na conta.

| Arquivo | Para quê |
|---|---|
| [buildspecs/](buildspecs/) | Os seis buildspecs (`seguranca`, `iac`, `observabilidade`, `imagem`, `plan`, `deploy`) |
| [tests/test_observabilidade.py](tests/test_observabilidade.py) | Fitness function de observabilidade (Seção 4 da apostila + "dica do professor") |
| [Dockerfile](Dockerfile) | Targets `test` (fitness function), `app` e `loadgen` (runtime sem pip) |
| [requirements.txt](requirements.txt) / [requirements-dev.txt](requirements-dev.txt) | Dependências fixadas, lidas pelo pip-audit |
| [ci/requirements-tools.txt](ci/requirements-tools.txt) | pip-audit e Bandit com hashes (`--require-hashes`) |
| [security/bandit-baseline.json](security/bandit-baseline.json) | Aceite consciente do B104 |
| [.trivyignore.yaml](.trivyignore.yaml) | Exceções do Trivy, com justificativa e prazo |
| [.tflint.hcl](.tflint.hcl) | Regras do tflint |
| [.github/CODEOWNERS](.github/CODEOWNERS) | Quem revisa buildspecs, testes e exceções |
| [cicd/](cicd/) + [modules/cicd/](modules/cicd/) | Stack Terraform do pipeline (estado próprio) |

## Mapa apostila → implementação

| Apostila | Aqui |
|---|---|
| Passo 3: conexão `notas-github` | `aws_codeconnections_connection` (nasce *Pending*; autorizar no console) |
| Passo 4: `notas-codebuild-role` com push só no repositório do lab | Quatro roles, uma por tipo de trabalho; só `notas-codebuild-imagem` faz push, e só em `labarquiteturanuvem` |
| Passo 5: `notas-pipeline`, Queued, Full clone, `notas-seguranca`, `standard:7.0` | Iguais, via Terraform (pipeline V2) |
| Passo 6: Observabilidade em paralelo (Privileged), Imagem (`BuildTrivyEcr`, `ECR_REPOSITORY_URI`, `CONTAINER_NAME`, `ImagemArtifact`), Deploy | Iguais. O deploy é o `terraform apply` (veja [Decisões](#decisões-e-diferenças-em-relação-ao-laboratório)) |
| Passo 7: Flask 3.1.3 e `# nosec B104` | `flask==3.1.3` em `requirements.txt`; B104 aceito em `security/bandit-baseline.json` |
| Passo 8: gitleaks + `.gitleaksignore` | `buildspecs/seguranca.yml` (testado com a chave falsa da apostila) |
| Passo 9: regressão com thread | Teste barra a regressão (testado: `o INSERT não está no mesmo trace da requisição`) |
| Passo 10: relatório e aprovação manual | Report group `notas-observabilidade-fitness`; etapa `Aprovacao` ligada por padrão |
| Seção 9: proteger o pipeline | [Segurança do próprio pipeline](#segurança-do-próprio-pipeline-sec11-bp07) |

## Portões (fitness functions)

| Etapa | Ferramenta | Falha quando | Onde |
|---|---|---|---|
| Validacao | gitleaks 8.30.1 | qualquer segredo em **todo** o histórico do Git | `seguranca.yml` |
| Validacao | pip-audit 2.10.1 | vulnerabilidade conhecida em `requirements*.txt` | `seguranca.yml` |
| Validacao | Bandit 1.9.4 | achado médio/alto (`-ll`) no Python do repositório | `seguranca.yml` |
| Validacao | terraform fmt/validate | código fora do padrão ou inválido (stack principal e `cicd/`) | `iac.yml` |
| Validacao | tflint 0.65.0 | regras `recommended` do Terraform | `iac.yml` |
| Validacao | Trivy config 0.76.1 | misconfiguração HIGH/CRITICAL sem exceção registrada | `iac.yml` |
| Validacao | pytest (OTel) | `POST /notas` sem span HTTP + span do `INSERT` no mesmo trace, sem `http.route`, ou com o texto da nota na telemetria | `observabilidade.yml` |
| Imagem | inspeção da imagem | imagem roda como root | `imagem.yml` |
| Imagem | Bandit | achado médio/alto **novo** no `app.py` empacotado | `imagem.yml` |
| Imagem | pip-audit `--path` | vulnerabilidade no ambiente Python inteiro da imagem (base + este repo) | `imagem.yml` |
| Imagem | Trivy image | CVE **crítica** que já tem correção (SO e bibliotecas) | `imagem.yml` |
| Plano | jq sobre o plano | o plano destrói/substitui `aws_rds_cluster` ou `aws_ecr_repository` | `plan.yml` |
| Deploy | AWS CLI | o service não estabiliza, ou estabiliza numa revisão diferente da aplicada (rollback do circuit breaker) | `deploy.yml` |
| Deploy | curl | `GET /health` pela URL pública não responde `status: up` e `database: ok` | `deploy.yml` |
| Produção | SLO (Aula 13) | disponibilidade < 99,5% ou p95 > 500 ms (Prometheus → Alertmanager → Discord) | já existente |

Todas foram executadas localmente antes da entrega, no mesmo formato do CodeBuild (containers
linux/amd64): segurança, observabilidade e imagem verdes; gitleaks barrando a chave falsa do Passo 8
e liberando com o `.gitleaksignore`; a fitness function barrando a regressão do Passo 9; pip-audit
barrando `flask==3.0.3`. Na primeira rodada, o próprio pip-audit pegou o `pytest==9.0.2`
(PYSEC-2026-1845), que foi atualizado.

### A imagem

O pipeline não constrói a aplicação do zero: o `Dockerfile` parte da imagem pública fixada por
**digest** (tags do Docker Hub são mutáveis) e acrescenta a camada OpenTelemetry da Aula 13. Na mesma
camada:

- **Flask 3.0.3 → 3.1.3** (achado do pip-audit da apostila, PYSEC-2026-2151);
- `apt-get upgrade` aplica as correções do Debian publicadas depois da base (o Trivy acusava
  `zlib1g`, CVE-2026-85091);
- as imagens de runtime **não têm pip**: ele não é usado em execução e carregava dependências próprias
  (`pip/_vendor`: urllib3, msgpack, setuptools) com CVEs HIGH. Resultado: zero vulnerabilidades
  corrigíveis MEDIUM ou acima no Trivy;
- o target `test` é a base da fitness function: o pytest roda contra o `app.py` e as bibliotecas que
  vão para produção, e não contra uma cópia do código.

## Segurança do próprio pipeline (SEC11-BP07)

- **Nenhuma access key.** CodePipeline e CodeBuild assumem roles de serviço com credenciais
  temporárias. As relações de confiança exigem `aws:SourceAccount` e `aws:SourceArn` (só os projetos
  e o pipeline certos podem assumi-las).
- **Menor privilégio por tipo de trabalho:**

  | Role | Pode |
  |---|---|
  | `notas-codebuild-checks` | logs, relatórios, artefatos, conexão (Segurança, IaC, Observabilidade) |
  | `notas-codebuild-imagem` | + push **só** em `labarquiteturanuvem` |
  | `notas-codebuild-plan` | + **ler** a conta, o estado e o tfvars. Não escreve nada |
  | `notas-codebuild-deploy` | + escrever nos serviços da stack, só em `us-east-1`; IAM só em `lab-*` e sempre com o boundary |
  | `notas-codepipeline` | artefatos, conexão, iniciar os seis projetos, avisar a aprovação. Escrita à mão, no lugar da role ampla que o console gera |

- **Permission boundary.** A role de deploy só cria ou altera roles `lab-*` se elas tiverem o boundary
  `notas-workload-boundary` (pull do ECR, logs, os segredos da stack, Session Manager), e não pode
  removê-lo. Mesmo que alguém altere o Terraform para criar uma role "admin", ela nunca passa desse
  teto. O pipeline também não alcança os próprios recursos (CodeBuild, CodePipeline, roles `notas-*`,
  buckets, chave KMS): eles ficam numa stack separada (`cicd/`), aplicada por um administrador.
- **Portões que não podem ser contornados.** Por padrão os buildspecs ficam **fixados nos projetos
  do CodeBuild** a cada `terraform apply` de `cicd/` (`buildspec_from_repository = false`): apagar a
  linha do Bandit num commit não muda o que o pipeline roda. Somado a isso, o `CODEOWNERS` cobre
  `buildspecs/`, `tests/`, `ci/`, `security/`, as exceções e o `Dockerfile`. Para o laboratório
  (editar buildspec e ver o efeito no próximo push), use `buildspec_from_repository = true`.
- **Cadeia de ferramentas fixada.** Terraform, gitleaks, tflint e Trivy com versão fixa **e SHA-256
  oficial** conferido antes de executar; pip-audit e Bandit com `--require-hashes`; versões com pelo
  menos duas semanas; imagem base por digest; PostgreSQL e base de CVEs do Trivy vindos do ECR Public.
- **Plano aprovado = plano aplicado.** O `tfplan` é um artefato; o deploy aplica esse arquivo, e não
  um plano novo. Se o estado mudou entre o plano e o apply, o Terraform recusa (*stale plan*). Plan e
  deploy têm `concurrent_build_limit = 1`, o estado usa lock nativo do S3 e o pipeline roda em modo
  Queued.
- **Dados sensíveis.** O tfvars (e-mails, IP do Grafana, webhook do Discord) fica no Secrets Manager
  e só vira arquivo durante o build, com `umask 077`, apagado no `post_build`. O `tfplan` carrega
  valores sensíveis: por isso artefatos, estado, logs, segredos e o tópico SNS são cifrados com a
  chave KMS do pipeline (rotação ligada), e os buckets bloqueiam acesso público e exigem TLS.
- **Rollback automático.** O service do ECS tem *deployment circuit breaker* com rollback; o deploy
  fica vermelho se o ECS voltar para a revisão anterior.
- **Auditoria.** O CloudTrail (histórico de eventos, 90 dias) registra quem alterou o pipeline, um
  projeto do CodeBuild ou uma role; os logs de cada build ficam no CloudWatch por 30 dias.

Falta configurar no GitHub (não dá para fazer pelo Terraform da AWS): em *Settings > Branches*, uma
regra para a `main` com **Require a pull request before merging** e **Require review from Code
Owners**, e acrescentar os integrantes do grupo no `CODEOWNERS`.

## Decisões e diferenças em relação ao laboratório

| Laboratório | Aqui | Por quê |
|---|---|---|
| Deploy pela ação **Amazon ECS** com `imagedefinitions.json` | `terraform apply` com `-var otel_image_tag=<commit>` (o `imagedefinitions.json` continua sendo gerado, como artefato) | Aqui a task definition é do Terraform. A ação do ECS registraria revisões fora do estado, e o próximo `apply` desfaria o deploy. O efeito é o mesmo da Figura 9: nova revisão só com a imagem trocada (as `OTEL_*` e os segredos do banco ficam) e rolling update |
| Teste importa o `app.py` do repositório da aplicação | Teste roda dentro do target `test`, sobre o `app.py` da imagem | O repositório da aplicação não foi trazido; o teste fica até mais fiel ao que vai para produção |
| `# nosec B104` na linha do `app.run` | Baseline do Bandit (`security/bandit-baseline.json`) | Não dá para editar o `app.py` da imagem base. O baseline aceita só aquele achado; qualquer outro médio/alto falha |
| Três buildspecs | Seis (+ IaC, Plano e Deploy) | O repositório entrega infraestrutura: ela também passa por portões, e o deploy é um `apply` revisado |
| Tag = commit | Tag = 7 primeiros caracteres do SHA (`a8244ab`); loadgen = `loadgen-a8244ab` | Repositório IMMUTABLE com duas imagens; reexecutar o mesmo commit reaproveita as imagens já publicadas |
| Pipeline e projetos pelo console | Terraform (`cicd/`), com estado próprio | Revisável, reproduzível e com IAM de menor privilégio desde o início |
| `standard:7.0` | Igual | Imagem gerenciada da apostila |

## Como subir (bootstrap, uma vez)

Pré-requisitos: credenciais de administrador da conta (só para o bootstrap), Terraform ≥ 1.10,
AWS CLI e a stack principal ainda **sem** estado relevante (ou o estado local que você já tem, que
será migrado).

```bash
# 1. Stack do pipeline
cd cicd
cp terraform.tfvars.example terraform.tfvars     # account_id, github_repository, e-mails
terraform init
terraform apply
```

2. **Conexão com o GitHub** (Passo 3 da apostila): *Developer Tools > Settings > Connections >
   notas-github > Update pending connection > Install a new app*, escolhendo **Only select
   repositories** e só este repositório. O status precisa ficar **Available**.
3. **Confirme a inscrição** no e-mail "AWS Notification - Subscription Confirmation" (pedidos de
   aprovação e resultado das execuções).

```bash
# 4. tfvars da stack principal no Secrets Manager (o mesmo arquivo que você usa localmente)
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw tfvars_secret_id)" \
  --secret-string file://../terraform.tfvars

# 4b. Opcional, recomendado: token do Docker Hub (só leitura) contra o limite de pulls anônimos
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw dockerhub_secret_id)" \
  --secret-string '{"username":"<usuario>","token":"<access token read-only>"}'

# 5. Stack principal no estado remoto (bucket criado no passo 1)
cd ..
terraform -chdir=cicd output -raw backend_config > backend.hcl
terraform init -migrate-state -backend-config=backend.hcl

# 6. Uma vez só: os repositórios ECR em que o pipeline publica
terraform apply -target=module.ecr -target=module.obs_image_repos

# 7. Dispare: push na main (ou "Release change" no console do CodePipeline)
git push origin main
```

A primeira execução cria o ambiente inteiro (o Aurora leva de 10 a 15 min). A partir daí, **o
pipeline é o único caminho de deploy** (SEC11-BP06): um `terraform apply` local usaria as tags
padrão das imagens (`app-2.2.0`) e desfaria o deploy do pipeline.

## Operação

- **Aprovar:** o e-mail traz o resumo (`Plano: N a criar, ...`) e o link do build do plano. Leia o
  plano no log do `TerraformPlan` e aprove em *CodePipeline > notas-pipeline > Aprovacao > Review*.
- **Mudar o tfvars** (seu IP do Grafana mudou, outro webhook): atualize o segredo como no passo 4 e
  clique em *Release change*.
- **Rollback:** `git revert` do commit e push; o pipeline publica de novo a versão anterior. Se o ECS
  não estabilizar, o circuit breaker já volta para a revisão anterior sozinho.
- **Simulação de falha do banco (Aula 13):** com `simulate_db_failure = true` no tfvars, o smoke
  test do deploy fica vermelho de propósito, porque `/health` passa a responder `database: erro`.
- **Relatórios:** *CodeBuild > Report groups*: `notas-observabilidade-fitness` (pytest),
  `notas-imagem-trivy` e `notas-iac-trivy`.
- **Implantação contínua:** `require_manual_approval = false` em `cicd/terraform.tfvars` remove a
  etapa de aprovação.

### Problemas comuns (dica do professor)

| Sintoma | Causa provável |
|---|---|
| Erro no clone logo no começo do build | Conexão ainda *Pending*, ou role sem `codeconnections:UseConnection` |
| `Cannot connect to the Docker daemon` | Projeto sem modo privilegiado |
| `toomanyrequests` ao puxar a imagem base | Limite anônimo do Docker Hub: preencha o segredo `notas/dockerhub` |
| `AccessDenied` no plan/deploy | Recurso novo fora da lista de serviços das policies `notas-workload-*` ([modules/cicd/iam.tf](modules/cicd/iam.tf)) |
| `Saved plan is stale` | Outra execução aplicou antes: rode *Release change* |
| Deploy vermelho em "estável em ..." | Tasks não sobem: veja o log group `/ecs/labarquiteturanuvem` |

## Evidências do laboratório (Tabela 3 da apostila)

A `main` é protegida: cada passo é **um PR mergeado**, e o merge dispara o pipeline. Antes de
mergear o próximo PR, aprove ou rejeite qualquer execução parada na **Aprovacao**. No modo Queued,
a execução seguinte espera atrás dela.

O código da aplicação vem na imagem base. Para reproduzir os passos 5, 7 e 9 da apostila, que
mexem no `app.py`, ele entra no repositório na Evidência 1 e passa a ser copiado para a imagem na
Evidência 2. O código é o mesmo da imagem.

| Nº | Passo | PR | Resultado esperado |
|---|---|---|---|
| 1 | 5 | `flask==3.0.3` + `app.py` da imagem na raiz | **Seguranca** vermelha: `PORTÕES REPROVADOS: pip-audit bandit` |
| 2 e 3 | 7 | `flask==3.1.3` + `# nosec B104` + `COPY app.py` | Tudo verde; nova revisão no ECS com a tag do commit |
| 4 | 8 | `config_local.py` com a chave falsa | **Seguranca** vermelha no gitleaks |
| 5 | 8 | remove o arquivo e depois cria o `.gitleaksignore` | vermelho, depois verde |
| 6 | 9 | `app.py` com a thread | **Observabilidade** vermelha; Imagem e Deploy sem execução |
| 7 | 10 | revert do PR da Evidência 6 | report group com a execução que falhou e a que passou |

### Evidência 1: pipeline vermelho com pip-audit e Bandit (Passo 5)

```bash
git checkout main && git pull && git checkout -b evidencia-1
docker create --name notas-tmp --platform linux/amd64 rafaelserpa/notas-da-nuvem:1.0.0
docker cp notas-tmp:/app/app.py app.py && docker rm notas-tmp
sed -i '' 's/^flask==3.1.3$/flask==3.0.3/' requirements.txt
git add app.py requirements.txt && git commit -m "evidencia 1: Flask 3.0.3 e app.py sem aceite do B104"
git push -u origin evidencia-1     # abra o PR e faça o merge
```

Na ação **Seguranca**, *View details > Logs*: o bloco do pip-audit mostra
`flask 3.0.3 PYSEC-2026-2151 3.1.3`, o do Bandit mostra `[B104:hardcoded_bind_all_interfaces]` em
`./app.py:151`, e o fim do log mostra `PORTÕES REPROVADOS: pip-audit bandit`. **Prints:** o pipeline
vermelho e os dois trechos do log.

### Evidências 2 e 3: pipeline verde e nova revisão no ECS (Passo 7)

```bash
git checkout main && git pull && git checkout -b evidencia-2
sed -i '' 's/^flask==3.0.3$/flask==3.1.3/' requirements.txt
```

No `app.py`, troque a última linha pelo aceite consciente, como na apostila:

```python
if __name__ == "__main__":
    # O container precisa escutar em todas as interfaces para o ALB alcançar a task.
    app.run(host="0.0.0.0", port=APP_PORT)  # nosec B104
```

No `Dockerfile`, no target `otel`, logo antes do primeiro `USER appuser`:

```dockerfile
COPY --chmod=644 app.py /app/app.py
```

No `.dockerignore`, acrescente a linha `!app.py`. Depois:

```bash
git add app.py requirements.txt Dockerfile .dockerignore
git commit -m "evidencia 2: Flask 3.1.3 e aceite consciente do B104"
git push -u origin evidencia-2     # PR + merge; aprove no e-mail quando chegar
```

- **Evidência 2:** o pipeline com todas as etapas verdes, depois da aprovação.
- **Evidência 3:** *ECS > lab-cluster > lab-service > Deployments* com a nova revisão `lab-test:N`;
  em *Task definitions > lab-test:N > Containers*, a imagem `...labarquiteturanuvem:<sha>`; em
  *ECR > labarquiteturanuvem*, a mesma tag. Mostre que ela é o início do SHA do merge
  (`git log -1 --format=%h origin/main` ou o commit na aba *Source* do pipeline).

### Evidência 4: gitleaks barrando a chave falsa (Passo 8)

```bash
git checkout main && git pull && git checkout -b evidencia-4
echo 'AWS_ACCESS_KEY_ID=AKIA''Q3EGRSTU7VWXYZ5A' > config_local.py   # chave FALSA da apostila
git add config_local.py && git commit -m "teste do gitleaks"
git push -u origin evidencia-4     # PR + merge
```

Se o GitHub bloquear o push (*push protection*), use o link da mensagem e marque "It's used in
tests". **Print:** o log da **Seguranca** com `Finding: AWS_ACCESS_KEY_ID=REDACTED`,
`RuleID: aws-access-token`, a linha `Fingerprint:` e `leaks found: 1`. **Copie o Fingerprint**,
que é usado na Evidência 5.

### Evidência 5: `.gitleaksignore` e pipeline verde (Passo 8)

```bash
git checkout main && git pull && git checkout -b evidencia-5a
git rm config_local.py && git commit -m "remove a chave falsa"
git push -u origin evidencia-5a    # PR + merge: CONTINUA vermelho (o segredo está no histórico)
```

```bash
git checkout main && git pull && git checkout -b evidencia-5b
cat > .gitleaksignore <<'EOF'
# Exceção: chave FALSA usada no teste do gitleaks da Aula 14 (nunca foi válida).
# Responsável: <nome do integrante>. Revisar em: <data>.
<cole aqui o Fingerprint do log da Evidência 4>
EOF
git add .gitleaksignore && git commit -m "excecao formal da chave falsa"
git push -u origin evidencia-5b    # PR + merge; aprove o deploy
```

**Prints:** o `.gitleaksignore` aberto no GitHub e o pipeline verde.

### Evidência 6: regressão barrada (Passo 9)

```bash
git checkout main && git pull && git checkout -b evidencia-6
```

No `app.py`, acrescente `import threading` junto dos outros imports e troque a rota `criar_nota`:

```python
def salvar_nota(texto):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO notas (texto) VALUES (%s);", (texto,))
        conn.commit()


@app.route("/notas", methods=["POST"])
def criar_nota():
    texto = request.form.get("texto", "").strip()
    if texto:
        threading.Thread(target=salvar_nota, args=(texto,)).start()
    return redirect(url_for("index"))
```

```bash
git add app.py && git commit -m "otimiza POST /notas com thread"
git push -u origin evidencia-6     # PR + merge
```

**Print:** **Observabilidade** vermelha com
`AssertionError: nenhum span do INSERT foi gerado: ['POST /notas']`, e Imagem, Plano, Aprovacao e
Deploy sem execução. O ECS continua na revisão da Evidência 5.

### Evidência 7: relatório da fitness function (Passo 10)

No GitHub, abra o PR da Evidência 6 e clique em **Revert**. Isso cria um PR de revert: mergeie e
aprove o deploy. Depois, em *CodeBuild > Report groups > notas-observabilidade-fitness*, aparecem
a execução que falhou (3 testes, 1 ou 2 com falha) e a que passou (3 de 3). **Print:** o relatório.
A etapa opcional de aprovação manual do Passo 10 já existe (**Aprovacao**); o e-mail e a tela de
*Review* servem de evidência extra.

## Registro de exceções

| Achado | Decisão | Onde |
|---|---|---|
| Bandit B104 (`app.run(host="0.0.0.0")`) | Aceite: o container precisa escutar em todas as interfaces para o ALB alcançar a task. No gunicorn o bind já é `0.0.0.0:8080` | `security/bandit-baseline.json` |
| Trivy AWS-0053 (ALB público) | Origem do CloudFront; o sg só aceita a prefix list do CloudFront | `.trivyignore.yaml` (vence em 2027-05-19) |
| Trivy AWS-0011 (CloudFront sem WAF) | Custo fora do orçamento do lab | idem |
| Trivy AWS-0079 (Aurora sem CMK) | Já cifrado com a chave gerenciada `aws/rds` | idem |
| Trivy AWS-0104 (saída 0.0.0.0/0) | Só em `app`, `obs-backend` e `obs-grafana`; sem NAT, as subnets privadas não saem para a internet. `alb`, `db` e `endpoint` ganharam saída mínima | idem |
| Trivy AWS-0342 (MEDIUM, `iam:PassRole`) | Fora do portão (só HIGH/CRITICAL). O PassRole é restrito a `lab-*` e a `ecs-tasks`/`ec2` | `modules/cicd/iam.tf` |
| Trivy AWS-0089 (LOW, log de acesso do S3) | Fora do portão; exigiria um terceiro bucket | — |

Cada exceção tem prazo. Quando ele vence, o achado volta a derrubar o pipeline e alguém precisa
decidir de novo: é a resposta deste repositório para "o que acontece com o alerta que ninguém
corrige?" da dinâmica.

## Custos e limpeza

O pipeline parado custa ~US$ 2/mês (chave KMS e dois segredos). Cada execução consome alguns minutos
de CodeBuild e de CodePipeline V2, poucos centavos de dólar, e o free tier cobre parte disso. O
ambiente que ele cria custa o mesmo de antes (veja o [README](README.md#custos-e-destroy)).

Limpeza (Passo 11), com credenciais de administrador:

```bash
# 1. Ambiente (como no README): esvazie o repositório da aplicação e destrua
aws ecr batch-delete-image --repository-name labarquiteturanuvem \
  --image-ids "$(aws ecr list-images --repository-name labarquiteturanuvem --query imageIds --output json)"
terraform destroy

# 2. Pipeline, buckets, roles, conexão e chave (a chave fica 7 dias agendada para exclusão)
terraform -chdir=cicd apply   -var state_bucket_force_destroy=true
terraform -chdir=cicd destroy -var state_bucket_force_destroy=true
```

Por fim, desinstale o app **AWS Connector for GitHub** em *GitHub > Settings > Applications*.
