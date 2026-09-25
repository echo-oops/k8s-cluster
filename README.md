# k8s-cluster

Это мой рабочий репозиторий для поднятия небольшого production‑ready Kubernetes кластера на Ubuntu (kubeadm + containerd) с базовой инфраструктурой: Calico CNI, NGINX Ingress, Prometheus/Grafana, Loki, и CI/CD (GitLab CI / Jenkins). Я использую Terraform для провиженинга VM (опционально) и Ansible для конфигурации и bootstrap'а кластера. Репозиторий не идеален — это то, что я реально использую и дорабатываю по мере необходимости.

---

## Стек
- **Provisioning (опционально)**: Terraform
- **Конфигурация и bootstrap**: Ansible (kubeadm)
- **Container runtime**: containerd (или Docker, если нужно)
- **CNI**: Calico
- **Ingress**: NGINX Ingress Controller (Helm)
- **Мониторинг**: Prometheus + Grafana (kube-prometheus-stack)
- **Логирование**: Loki + Promtail
- **Пакетный менеджер**: Helm v3
- **CI/CD**: GitLab CI (Kaniko) и пример Jenkinsfile
- **Приложения**: локальные Helm-чарты (`helm-charts/`)

---

## Структура репозитория
k8s-cluster/
├── ansible/                # playbooks и роли (common, kubernetes, calico)
│   ├── inventory.yml
│   └── site.yml
├── terraform/              # опционально: провиженинг VM
├── helm-charts/            # локальные чарты приложений (frontend, backend)
├── infrastructure/         # values и манифесты для системных компонентов
├── ci-cd/                  # .gitlab-ci.yml, Jenkinsfile, скрипты CI
├── scripts/                # backup-etcd.sh, rotate-certs.sh, install-cluster.sh
├── docs/                   # architecture.md, troubleshooting.md
├── requirements.txt        # python deps для локальных утилит/ansible
└── README.md




## Что нужно перед запуском
- Доступ к 3+ VM (минимум 1 control-plane + 1 worker), Ubuntu 22.04.
- SSH‑доступ с ключом, sudo без пароля (или возможность передать `--ask-become-pass`).
- На машине управления: Python 3.10+, `ansible-core`, `kubectl`, `helm` (или роль установит helm на control-plane).
- (Опционально) Доступ к облачному провайдеру и настроенные credentials для Terraform.
- Registry для образов (GitLab Container Registry, Docker Hub или приватный registry).
- В CI: переменные (KUBE_CONFIG_DATA, CI_REGISTRY, CI_REGISTRY_USER, CI_REGISTRY_PASSWORD и т.д.) настроены и защищены.
