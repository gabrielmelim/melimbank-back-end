# melimbank — doc

> Guia didático e completo para subir, testar e entender o melimbank no ambiente **100% local** usando **Docker + WSL2**, **LocalStack (AWS)** e **Kubernetes (kind)**. Inclui **matriz serviço × AWS** explicando *quem usa o quê e por quê*.

---

## 📌 Sumário
- [Visão Geral e Arquitetura](#-visão-geral-e-arquitetura)
- [Matriz serviço × AWS (o que usa e por quê)](#-matriz-serviço--aws-o-que-usa-e-por-quê)
- [Estrutura do Monorepo](#-estrutura-do-monorepo)
- [Pré-requisitos (Windows + WSL)](#-pré-requisitos-windows--wsl)
- [Instalação e Configuração do AWS CLI v2 (WSL)](#-instalação-e-configuração-do-aws-cli-v2-wsl)
- [Infra Local com Docker Compose](#-infra-local-com-docker-compose)
- [Banco de Dados (Flyway V1)](#-banco-de-dados-flyway-v1)
- [Serviços e Configuração (application-*.yml)](#-serviços-e-configuração-application-yml)
- [Rodando os Serviços (DEV)](#-rodando-os-serviços-dev)
- [🚀 Passo a passo de validação do melimbank](#-passo-a-passo-de-validação-do-melimbank)
- [Kubernetes (kind)](#-kubernetes-kind)
- [Build e Load de Imagens no kind](#-build-e-load-de-imagens-no-kind)
- [Ingress (Gateway)](#-ingress-gateway)
- [Dependências recomendadas (backend)](#-dependências-recomendadas-backend)
- [Observabilidade e Segurança (roadmap)](#-observabilidade-e-segurança-roadmap)
- [Troubleshooting](#-troubleshooting)
- [Guia Rápido de Comandos (Docker + K8s)](#-guia-rápido-de-comandos-docker--k8s)
- [Checklist inicial](#-checklist-inicial)

---

## 🧭 Visão Geral e Arquitetura

- **Apps Java 21 (Spring Boot)** — microserviços REST.
- **PostgreSQL 16** (Docker) para dados de domínio.
- **LocalStack 3** para simular **S3, SQS, SNS, DynamoDB, Secrets Manager** localmente.
- **Mensageria**: **SQS/SNS** (não usamos RabbitMQ).
- **Auditoria**: **DynamoDB**.
- **Gateway/BFF**: **Spring Cloud Gateway** roteando as chamadas para os microserviços.
- **Kubernetes local (kind)** para testes de deploy + readiness/liveness + Ingress.

Fluxo exemplo:
1. `customers-service` cadastra um cliente (Postgres).
2. `accounts-service` cria conta, publica **eventos SNS** (ex.: `AccountCreated`), armazena extratos/anexos no **S3**.
3. `transactions-service` registra transação (Postgres) e publica em **SQS** (`melimbank-transactions`) para processamento contábil; também pode publicar eventos de alto nível no **SNS**.
4. `ledger-service` consome **SQS**, aplica double-entry e grava **auditoria no DynamoDB**.
5. `notifications-service` assina o **SNS** via **SQS** e gera notificações (mock/log).
6. `gateway-service` expõe tudo via `http://localhost:8080/...`.

---

## 📊 Matriz serviço × AWS (o que usa e por quê)

| Serviço                | AWS usado                  | Como usa                                                                 | Por quê (benefício)                                                  |
|------------------------|----------------------------|--------------------------------------------------------------------------|-----------------------------------------------------------------------|
| **customers-service**  | —                          | —                                                                        | Não há integração direta necessária neste MVP.                        |
| **accounts-service**   | **S3**, **SNS**            | **S3** para extratos/anexos; **SNS (publisher)** de eventos: `AccountCreated`, `AccountUpdated`, `BalanceChanged`. | Fan-out desacoplado para outros serviços (ex.: notificações) e armazenamento de artefatos/documentos. |
| **transactions-service** | **SQS**, **SNS**         | **SQS (producer)** na fila `melimbank-transactions`; **SNS (publisher)** no tópico `melimbank-events`. | **SQS** para processamento assíncrono/robusto do **ledger**; **SNS** para fan-out de eventos. |
| **ledger-service**     | **SQS**, **DynamoDB**      | **SQS (consumer)**; persiste auditoria em **DynamoDB** (`audit_events`). | Processamento tolerante a falhas + trilha de auditoria imutável.     |
| **notifications-service** | **SNS + SQS**           | Assina o **SNS** via **SQS** para receber eventos e emitir notificações. | Entrega confiável, escalável e desacoplada.                           |
| **gateway-service**    | —                          | —                                                                        | Apenas roteamento HTTP.                                               |

> No LocalStack, os recursos acima são criados por `infra/docker/localstack-init/*.sh`.

---

## 🗂️ Estrutura do Monorepo

```
melimbank/
├─ backend/
│  ├─ services/
│  │  ├─ customers-service/
│  │  ├─ accounts-service/
│  │  ├─ transactions-service/
│  │  ├─ ledger-service/
│  │  ├─ notifications-service/
│  │  └─ gateway-service/
│  └─ libs/
├─ infra/
│  ├─ docker/
│  │  ├─ localstack-init/
│  │  └─ pg-init/
│  └─ k8s/
│     ├─ base/
│     └─ overlays/
├─ scripts/
├─ docs/
└─ README.md
```

> Dica performance WSL: se o repo estiver em `C:\GIT\melimbank`, crie link no WSL: `ln -s /mnt/c/GIT/melimbank ~/melimbank`.

---

## 📦 Pré-requisitos (Windows + WSL)

1) **WSL2 + Ubuntu 22.04** (PowerShell admin):
```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
```
No WSL:
```bash
sudo apt update && sudo apt upgrade -y
sudo tee /etc/wsl.conf <<'EOF'
[boot]
systemd=true
EOF
```
Reinicie o WSL (no Windows):
```powershell
wsl --shutdown
```

2) **Docker Engine no WSL** (Ubuntu):
```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```
Reinicie o WSL e teste:
```powershell
wsl --shutdown
```
```bash
docker run hello-world
```

3) **Java 21 (Temurin) no Windows**:
```powershell
winget install --id EclipseAdoptium.Temurin.21.JDK -e
java -version
setx JAVA_HOME "C:\Program Files\Eclipse Adoptium\jdk-21"
```

4) **Git**:
```powershell
winget install --id Git.Git -e
git --version
```

---

## 🛠 Instalação e Configuração do AWS CLI v2 (WSL)

Remova v1 (se existir):
```bash
sudo apt remove -y awscli || true
```
Instale v2:
```bash
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
aws --version
```
Profile local:
```bash
aws configure --profile melimbank-local
# AWS Access Key ID: lab
# AWS Secret Access Key: lab
# Default region name: us-east-1
# Default output format: json
```
Alias para LocalStack:
```bash
echo 'alias awslocal="aws --endpoint-url=http://localhost:4566 --profile melimbank-local"' >> ~/.bashrc
source ~/.bashrc
awslocal sts get-caller-identity
```

---

## 🧱 Infra Local com Docker Compose

`infra/docker/.env`
```env
POSTGRES_USER=lab
POSTGRES_PASSWORD=lab
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=lab
AWS_SECRET_ACCESS_KEY=lab
```

`infra/docker/pg-init/01-create-dbs.sql`
```sql
CREATE DATABASE customers_db;
CREATE DATABASE accounts_db;
CREATE DATABASE transactions_db;
CREATE DATABASE ledger_db;
ALTER DATABASE customers_db OWNER TO lab;
ALTER DATABASE accounts_db OWNER TO lab;
ALTER DATABASE transactions_db OWNER TO lab;
ALTER DATABASE ledger_db OWNER TO lab;
```

`infra/docker/localstack-init/01-init.sh`
```bash
#!/usr/bin/env bash
set -e
awslocal s3 mb s3://melimbank-bucket
awslocal sqs create-queue --queue-name melimbank-transactions
TOPIC_ARN=$(awslocal sns create-topic --name melimbank-events --query TopicArn --output text)
QUEUE_URL=$(awslocal sqs get-queue-url --queue-name melimbank-transactions --query QueueUrl --output text)
QUEUE_ARN=$(awslocal sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
awslocal sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$QUEUE_ARN"
awslocal dynamodb create-table \
  --table-name audit_events \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
echo "LocalStack pronto: S3, SQS, SNS e DynamoDB criados."
```

`infra/docker/docker-compose.yml`
```yaml
version: "3.9"
name: melimbank

services:
  postgres:
    image: postgres:16
    container_name: pg16
    env_file: .env
    environment:
      POSTGRES_DB: postgres
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./pg-init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER"]
      interval: 5s
      timeout: 3s
      retries: 10

  localstack:
    image: localstack/localstack:3
    container_name: localstack
    env_file: .env
    environment:
      - SERVICES=s3,sqs,sns,secretsmanager,dynamodb
      - DEBUG=1
      - AWS_DEFAULT_REGION=${AWS_REGION}
      - DOCKER_HOST=unix:///var/run/docker.sock
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./localstack-init:/etc/localstack/init/ready.d:ro"

volumes:
  pg_data:
```

Subir:
```bash
cd infra/docker
docker compose up -d
docker logs -f localstack
```

---

## 🗄️ Banco de Dados (Flyway V1)

**customers-service — `V1__init.sql`**
```sql
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY,
  document VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(120) UNIQUE NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
```

**accounts-service — `V1__init.sql`**
```sql
CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY,
  customer_id UUID NOT NULL,
  number VARCHAR(30) UNIQUE NOT NULL,
  branch VARCHAR(10) NOT NULL,
  balance NUMERIC(18,2) NOT NULL DEFAULT 0,
  currency VARCHAR(3) NOT NULL DEFAULT 'BRL',
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_accounts_customer ON accounts(customer_id);
```

**transactions-service — `V1__init.sql`**
```sql
CREATE TYPE IF NOT EXISTS tx_type AS ENUM ('DEBIT','CREDIT','TRANSFER');
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL,
  type tx_type NOT NULL,
  amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  description VARCHAR(200),
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);
```

**ledger-service — `V1__init.sql`**
```sql
CREATE TABLE IF NOT EXISTS ledger_accounts (
  id UUID PRIMARY KEY,
  code VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL
);
CREATE TABLE IF NOT EXISTS ledger_entries (
  id UUID PRIMARY KEY,
  tx_id UUID NOT NULL,
  debit_account UUID NOT NULL,
  credit_account UUID NOT NULL,
  amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_tx ON ledger_entries(tx_id);
```

---

## 🌐 Serviços e Configuração (`application-*.yml`)

**gateway-service** (`application-dev.yml`):
```yaml
server:
  port: 8080
spring:
  cloud:
    gateway:
      default-filters:
        - DedupeResponseHeader=Access-Control-Allow-Credentials Access-Control-Allow-Origin
      globalcors:
        corsConfigurations:
          '[/**]':
            allowedOrigins: "*"
            allowedHeaders: "*"
            allowedMethods: "*"
      routes:
        - id: customers
          uri: http://localhost:8081
          predicates: [ Path=/customers/** ]
          filters: [ StripPrefix=1 ]
        - id: accounts
          uri: http://localhost:8082
          predicates: [ Path=/accounts/** ]
          filters: [ StripPrefix=1 ]
        - id: transactions
          uri: http://localhost:8083
          predicates: [ Path=/transactions/** ]
          filters: [ StripPrefix=1 ]
        - id: ledger
          uri: http://localhost:8084
          predicates: [ Path=/ledger/** ]
          filters: [ StripPrefix=1 ]
        - id: notifications
          uri: http://localhost:8085
          predicates: [ Path=/notifications/** ]
          filters: [ StripPrefix=1 ]
management.endpoints.web.exposure.include: health,info
```

**accounts-service** (`application-dev.yml`):
```yaml
server:
  port: 8082
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/accounts_db
    username: ${POSTGRES_USER:lab}
    password: ${POSTGRES_PASSWORD:lab}
  jpa:
    hibernate:
      ddl-auto: validate
  flyway:
    enabled: true
    baseline-on-migrate: true
aws:
  region: ${AWS_REGION:us-east-1}
  s3:
    bucket: melimbank-bucket
  sns:
    topic: melimbank-events
```

**transactions-service** (`application-dev.yml`):
```yaml
server:
  port: 8083
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/transactions_db
    username: lab
    password: lab
  jpa:
    hibernate:
      ddl-auto: validate
  flyway:
    enabled: true
aws:
  region: us-east-1
  sqs:
    queue: melimbank-transactions
  sns:
    topic: melimbank-events
```

**ledger-service** (`application-dev.yml`):
```yaml
server:
  port: 8084
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/ledger_db
    username: lab
    password: lab
  jpa:
    hibernate:
      ddl-auto: validate
  flyway:
    enabled: true
aws:
  region: us-east-1
  dynamodb:
    table: audit_events
  sqs:
    queue: melimbank-transactions
```

**notifications-service** (`application-dev.yml`):
```yaml
server:
  port: 8085
aws:
  region: us-east-1
  sns:
    topic: melimbank-events
  sqs:
    queue: melimbank-transactions
```

> Segurança DEV (Gateway): permitir tudo durante DEV.
```java
@Configuration
public class SecurityConfig {
  @Bean
  SecurityWebFilterChain springSecurityFilterChain(ServerHttpSecurity http) {
    return http.csrf(ServerHttpSecurity.CsrfSpec::disable)
              .authorizeExchange(a -> a.anyExchange().permitAll())
              .build();
  }
}
```

---

## ▶️ Rodando os Serviços (DEV)

Abra um terminal por serviço:
```powershell
cd backend/services/customers-service;      .\mvnw spring-boot:run
cd backend/services/accounts-service;       .\mvnw spring-boot:run
cd backend/services/transactions-service;   .\mvnw spring-boot:run
cd backend/services/ledger-service;         .\mvnw spring-boot:run
cd backend/services/notifications-service;  .\mvnw spring-boot:run
cd backend/services/gateway-service;        .\mvnw spring-boot:run
```

---

## 🚀 Passo a passo de validação do melimbank

### 1) Subir a infraestrutura (Docker Compose)
```bash
cd infra/docker
docker compose up -d
docker ps
docker logs -f localstack   # criação do bucket/fila/tópico/tabela
```

### 2) Conferir Postgres
```bash
docker exec -it pg16 psql -U lab -d customers_db -c "\dt"
# repita p/ accounts_db, transactions_db, ledger_db
```

### 3) Conferir LocalStack
```bash
awslocal s3 ls
awslocal sqs list-queues
awslocal sns list-topics
awslocal dynamodb list-tables
```

### 4) Testes HTTP
Diretos:
```bash
curl http://localhost:8081/ping
curl http://localhost:8082/ping
```
Via Gateway:
```bash
curl http://localhost:8080/customers/ping
curl http://localhost:8080/accounts/ping
```

### 5) Testar SQS/DynamoDB
```bash
awslocal sqs send-message --queue-url $(awslocal sqs get-queue-url --queue-name melimbank-transactions --query QueueUrl --output text) --message-body 'hello-melimbank'
awslocal sqs receive-message --queue-url $(awslocal sqs get-queue-url --queue-name melimbank-transactions --query QueueUrl --output text)

awslocal dynamodb put-item --table-name audit_events --item '{"id":{"S":"test-1"}}'
awslocal dynamodb scan --table-name audit_events
```

---

## ☸️ Kubernetes (kind)

Instalar **kind** e criar cluster:
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
kind create cluster --name melimbank
kubectl get nodes
```
Namespace:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: melimbank
```
Aplicar:
```bash
kubectl apply -f infra/k8s/base/namespace.yaml
```

---

## 📦 Build e Load de Imagens no kind

Exemplo (accounts-service):
```bash
cd backend/services/accounts-service
./mvnw -q -DskipTests package
docker build -t accounts-service:local .
kind load docker-image accounts-service:local --name melimbank
kubectl apply -f infra/k8s/base/accounts/deployment.yaml
```

---

## 🌐 Ingress (Gateway)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gateway
  namespace: melimbank
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: melimbank.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gateway-service
                port: { number: 80 }
```

---

## 📦 Dependências recomendadas (backend)

```xml
<dependencies>
  <dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
  </dependency>
  <dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
  </dependency>
  <dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
  </dependency>

  <dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
  </dependency>
  <dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
  </dependency>
  <dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
  </dependency>

  <dependency>
    <groupId>io.awspring.cloud</groupId>
    <artifactId>spring-cloud-aws-starter-sqs</artifactId>
  </dependency>
  <dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>dynamodb</artifactId>
  </dependency>
  <dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>s3</artifactId>
  </dependency>
  <dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>sns</artifactId>
  </dependency>

  <dependency>
    <groupId>org.mapstruct</groupId>
    <artifactId>mapstruct</artifactId>
  </dependency>
  <dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <scope>provided</scope>
  </dependency>

  <dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
  </dependency>
</dependencies>
```

---

## 📈 Observabilidade e Segurança (roadmap)

- Actuator liveness/readiness em todos serviços.
- Micrometer → Prometheus + Grafana (overlays).
- Logs estruturados (JSON) + traceId.
- JWT (auth-service futuro) validado no gateway.
- Secrets: K8s Secrets + AWS Secrets Manager (LocalStack).

---

## 🛟 Troubleshooting

- `permission denied /var/run/docker.sock` → `sudo usermod -aG docker $USER` + reiniciar WSL.
- `pg_isready` falha → ver `.env` e volume `pg_data` (`docker compose down -v`).
- LocalStack sem recursos → confira `localstack-init` e `docker logs -f localstack`.
- `ImagePullBackOff` no kind → `kind load docker-image <img>:local --name melimbank`.
- Alias `awslocal` não encontrado → confira `~/.bashrc` ou use `aws --endpoint-url=http://localhost:4566 ...`.

---

## 🧾 Guia Rápido de Comandos (Docker + K8s)

**Docker**
```bash
docker ps
docker compose up -d
docker compose down -v
docker logs -f <container>
docker exec -it <container> bash
docker system prune -af --volumes
```

**Kubernetes**
```bash
kind create cluster --name melimbank
kubectl get pods -A
kubectl get all -n melimbank
kubectl logs -f deploy/gateway-service -n melimbank
kubectl rollout restart deploy/gateway-service -n melimbank
kubectl port-forward svc/gateway-service -n melimbank 18080:80
```

---

## ✅ Checklist inicial
- [ ] `docker compose up -d` (Postgres + LocalStack)
- [ ] `application-dev.yml` apontando para `localhost`
- [ ] **Flyway V1** aplicada em todos serviços com DB
- [ ] Gateway roteando `8081..8085`
- [ ] Endpoints `/actuator/health` OK
- [ ] kind criado e imagens carregadas via `kind load docker-image ...`

---

### Licença
Projeto didático. Use e modifique livremente no seu ambiente local.
