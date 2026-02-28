Реализация Identity в MathTrail — это фундамент безопасности всей платформы. Использование стека Ory (Kratos, Hydra, Keto, Oathkeeper) позволяет создать систему уровня Tier-1 (как у Google или Netflix), где каждый компонент отвечает за свою узкую задачу.Ниже подробный гайд по реализации для репозитория mathtrail-identity и интеграции с остальными сервисами.1. Архитектура Identity Stack в MathTrailДля LLM и разработчиков структура должна быть разделена на Identity Provider (IdP) и Access Control (AC).КомпонентРольТип APIOry KratosХранилище личностей (Identity Store)REST (Self-service flows)Ory HydraВыдача токенов (OAuth2/OIDC)REST (OAuth2 flows)Ory KetoГрупповые политики и права (ReBAC)gRPC / RESTOry OathkeeperШлюз безопасности (Zero Trust Proxy)Reverse Proxy / Decision APIIdentity UIТвой кастомный сервис для форм логинаWeb (Go/React)2. Структура репозитория mathtrail-identityРекомендуется использовать монорепозиторную структуру для конфигураций Ory:Plaintextmathtrail-identity/
├── deployments/              # Helm чарты или K8s манифесты
├── configs/                  # Главный конфиг-центр
│   ├── kratos/               # Identity schemas, email templates
│   ├── hydra/                # OAuth2 client configs
│   ├── keto/                 # Relationship namespaces (namespaces.apl)
│   └── oathkeeper/           # Access rules (rules.yaml)
├── identity-ui/              # Твой кастомный Go сервис для рендеринга форм
│   ├── cmd/
│   ├── internal/
│   └── templates/
└── justfile                  # Команды для локального деплоя и миграций
3. Интеграция с Ory Oathkeeper (Архитектура Zero Trust)Вместо того чтобы каждый микросервис (Task Service, Mentor и т.д.) сам проверял JWT-токен, мы используем Ory Oathkeeper как API Gateway.Схема работы:Запрос идет к Oathkeeper.Oathkeeper проверяет токен (через Hydra/Kratos) и права (через Keto).Если всё ок, запрос доходит до твоего кода.Настройка Oathkeeper Middleware (identity-middleware.yaml):YAMLapiVersion: apps/v1
kind: Component
metadata:
  name: ory-oathkeeper-auth
spec:
  type: middleware.http.custom # Используем Oathkeeper как внешний Decision API
  version: v1
  metadata:
  - name: url
    value: "http://oathkeeper-api.mathtrail-identity:4456/decisions"
4. Реализация "Групповых политик" через Ory Keto (ReBAC)Технология называется ReBAC (Relationship-Based Access Control). В Keto ты определяешь пространства имен (namespaces).Пример политики для MathTrail (namespaces.apl):TypeScriptclass User implements Namespace {}

class ClassGroup implements Namespace {
  // Связь: кто является учителем класса
  related: {
    teachers: User[]
    students: User[]
  }

  // Права: может ли пользователь видеть оценки класса?
  permissions = {
    viewGrades: (ctx: Context): boolean =>
      this.related.teachers.includes(ctx.subject) ||
      this.related.students.includes(ctx.subject)
  }
}
5. Инструкция для LLM (System Prompt для реализации)Если ты будешь просить ИИ написать код для этого сервиса, используй этот промпт:"Реализуй Identity-сервис для платформы MathTrail, используя Ory Kratos для управления пользователями и Ory Hydra для OAuth2.Kratos: Настрой JSON-схему личности (Identity Schema), включив поля role (student/teacher/admin) и school_id.Keto: Реализуй ReBAC модель, где teacher имеет доступ к ресурсам своих students внутри одного class_group.Oathkeeper: Создай access_rule, который проверяет JWT-токен от Hydra и делает маппинг sub (user_id) в заголовок X-User-ID для апстрим сервисов."


Ниже представлена детальная JSON-схема личности (Identity Schema) для Ory Kratos. Это главный «контракт» данных, который определяет, какие атрибуты будут у пользователей MathTrail и как они будут валидироваться.

Я разделил её на блоки: base (общие данные), metadata (системные роли) и school_context (образовательная привязка).

1. JSON Schema для Ory Kratos (identity.schema.json)
JSON
{
  "$id": "https://schemas.mathtrail.io/v1/user.schema.json",
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "MathTrail User Identity",
  "type": "object",
  "properties": {
    "traits": {
      "type": "object",
      "properties": {
        "email": {
          "type": "string",
          "format": "email",
          "title": "E-Mail",
          "ory.sh/kratos": {
            "recovery": { "via": "email" },
            "verification": { "via": "email" },
            "credentials": { "password": { "identifier": true } }
          }
        },
        "name": {
          "type": "object",
          "properties": {
            "first": { "type": "string", "title": "First Name" },
            "last": { "type": "string", "title": "Last Name" }
          }
        },
        "role": {
          "type": "string",
          "enum": ["student", "teacher", "admin", "mentor"],
          "title": "Platform Role",
          "description": "Primary role of the user within MathTrail"
        },
        "school_context": {
          "type": "object",
          "properties": {
            "school_id": { "type": "string", "title": "School ID" },
            "class_id": { "type": "string", "title": "Current Class ID" }
          },
          "required": ["school_id"]
        }
      },
      "required": ["email", "role"],
      "additionalProperties": false
    }
  }
}
2. Реализация Групповых Политик (Keto Relation Tuples)
Чтобы LLM понимала, как связать данные из Kratos с правами в Keto, используй концепцию Relation Tuples. Групповые политики в MathTrail реализуются через "отношения":

Примеры логики для Keto:

class_group:math_101#teachers@user:uuid-учителя (Учитель привязан к классу).

class_group:math_101#students@user:uuid-ученика (Ученик привязан к классу).

resource:lesson_plans#view@class_group:math_101#students (Все студенты класса могут видеть планы уроков).

3. Интеграция через Ory Oathkeeper (Архитектура Zero Trust)
Когда запрос проходит через Oathkeeper, он выполняет роль «судьи». Он берет сессию из Kratos или токен из Hydra и превращает их в понятные для твоих микросервисов заголовки.

Конфигурация правила Oathkeeper (access-rules.yaml):
YAML
- id: "mathtrail-mentor-rule"
  upstream:
    url: "http://mathtrail-mentor:8080"
  match:
    methods: ["GET", "POST"]
    url: "http://api.mathtrail.io/mentor/<.*>"
  authenticators:
    - handler: bearer_token # Проверяет JWT от Hydra
  authorizers:
    - handler: remote_json # Спрашивает Keto: "А можно ли ему?"
      config:
        remote: http://keto-api:4466/check
  mutators:
    - handler: header # Пробрасывает данные в Mentor Service
      config:
        headers:
          X-User-ID: "{{ .Subject }}"
          X-User-Role: "{{ .Extra.role }}"
Что это дает LLM при генерации кода:
Типизация: ИИ будет знать, что в объекте User всегда есть school_id и role.

Безопасность: ИИ будет генерировать запросы к сервисам, зная, что за авторизацию отвечает внешний Oathkeeper.

Масштабируемость: Если ты добавишь новый сервис mathtrail-analytics, тебе не нужно менять код авторизации — достаточно добавить правило в mathtrail-identity.

---

Для того чтобы LLM создала качественный devcontainer для mathtrail-identity, ей нужно объяснить, что внутри контейнера должны быть не только инструменты разработки (Go), но и CLI-утилиты самой экосистемы Ory, а также Docker-in-Docker для запуска всей инфраструктуры Identity.

Вот готовый промпт и структура, которые ты можешь передать ИИ:

Промпт для ИИ: "Создай DevContainer для репозитория mathtrail-identity"
"Создай конфигурацию .devcontainer для проекта mathtrail-identity.

Технический контекст:

Стек: Go (основной язык для Identity UI), Docker (для запуска Ory компонентов).

Инструменты Ory: В контейнере должны быть предустановлены: kratos CLI, hydra CLI, keto CLI и oathkeeper CLI.

Инфраструктура: Контейнер должен поддерживать Docker-in-Docker (или Docker-from-Docker) и установку just для запуска рецептов.

Требования к файлам:

devcontainer.json: Настрой проброс портов: 4433 (Kratos Public), 4434 (Kratos Admin), 4444 (Hydra Public), 4466 (Keto Read), 4455 (Oathkeeper Proxy).

Dockerfile: Базируйся на образе mcr.microsoft.com/devcontainers/go:1-1.22-bookworm. Добавь скрипт установки бинарников Ory через curl с GitHub Releases.

Extensions: Добавь расширения для работы с YAML, JSON Schema и Docker."

Как должен выглядеть результат (для контроля):
1. .devcontainer/devcontainer.json
Здесь важно прописать порты, чтобы ты мог открывать админки и API прямо из браузера на хосте.

JSON
{
  "name": "MathTrail Identity Development",
  "build": { "dockerfile": "Dockerfile" },
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:1": {},
    "ghcr.io/devcontainers/features/common-utils:1": {
      "configureZsh": true
    }
  },
  "forwardPorts": [4433, 4434, 4444, 4445, 4466, 4467, 4455, 4456],
  "customizations": {
    "vscode": {
      "extensions": [
        "golang.go",
        "redhat.vscode-yaml",
        "ms-azuretools.vscode-docker",
        "tamasfe.even-better-toml"
      ]
    }
  },
  "postCreateCommand": "just --version && kratos version"
}
2. Фрагмент .devcontainer/Dockerfile
Этот скрипт LLM должна вставить, чтобы у тебя работали команды типа kratos identities list.

Dockerfile
FROM mcr.microsoft.com/devcontainers/go:1.22-bookworm

# Установка Just
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# Установка ORY CLI (Kratos, Hydra, Keto, Oathkeeper)
RUN bash -c "curl -L https://raw.githubusercontent.com/ory/meta/master/install.sh | sh -s -- -b /usr/local/bin kratos" \
    && bash -c "curl -L https://raw.githubusercontent.com/ory/meta/master/install.sh | sh -s -- -b /usr/local/bin hydra" \
    && bash -c "curl -L https://raw.githubusercontent.com/ory/meta/master/install.sh | sh -s -- -b /usr/local/bin keto" \
    && bash -c "curl -L https://raw.githubusercontent.com/ory/meta/master/install.sh | sh -s -- -b /usr/local/bin oathkeeper"
Почему это важно для MathTrail:
С таким devcontainer тебе не нужно ничего устанавливать на Windows. Ты просто открываешь папку mathtrail-identity в VS Code, и у тебя сразу под рукой:

Бинарники Ory для управления пользователями и токенами.

Docker, чтобы поднять базу данных (PostgreSQL для Kratos).

Just, чтобы одной командой just up поднять весь Identity-стек.