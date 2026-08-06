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

---

## Быстрая инструкция по развёртыванию

### 1) Подготовка локально
```bash
git clone <repo>
cd k8s-cluster
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt


Подготовить inventory
Отредактируйте ansible/inventory.yml — укажите IP/hostnames и ansible_user. Пример:

yaml
masters:
  hosts:
    master-01.example.com:
      ansible_host: 10.0.0.10
workers:
  hosts:
    worker-01.example.com:
      ansible_host: 10.0.0.20



3) Запустить подготовку ОС (common)
ansible-playbook -i ansible/inventory.yml ansible/site.yml --tags common


4) Инициализация control-plane
Запускайте play только на мастере(ах). Пример:

ansible-playbook -i ansible/inventory.yml ansible/site.yml --limit masters \
  -e "is_control_plane=true control_plane_endpoint=k8s.example.com:6443 pod_network_cidr=10.244.0.0/16"


Присоединение воркеров

ansible-playbook -i ansible/inventory.yml ansible/site.yml --limit workers \
  -e "is_control_plane=false join_command='kubeadm join ...'"
Если join_command не передан, playbook попытается прочитать его с control-plane (если доступно через hostvars)


Установка системных компонентов (Helm)
На одном из мастеров

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace -f infrastructure/ingress-nginx/values.yaml
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f infrastructure/monitoring/values.yaml
helm upgrade --install loki grafana/loki -n logging --create-namespace -f infrastructure/logging/values.yaml
helm upgrade --install promtail grafana/promtail -n logging -f infrastructure/logging/values.yaml




О директориях (коротко)
ansible/ — inventory, site.yml, роли:

common/ — базовая подготовка ОС, docker/containerd, sysctl, swap off.

kubernetes/ — установка kubeadm/kubelet/kubectl, init/join, создание ci-deployer SA.

calico/ — установка Calico (manifest/helm).

terraform/ — примеры конфигураций для провиженинга VM (если используете облако).

helm-charts/ — локальные чарты приложений (frontend/backend).

infrastructure/ — values для ingress, monitoring, logging; network policies; rbac manifests.

ci-cd/ — .gitlab-ci.yml, Jenkinsfile, скрипты build-and-push.sh, deploy-helm.sh.

scripts/ — вспомогательные скрипты: backup-etcd.sh, rotate-certs.sh, install-cluster.sh.

docs/ — архитектура, troubleshooting.

Мониторинг и логирование
Метрики: Prometheus собирает метрики с kubelet, kube-proxy, kube-apiserver и приложений. Grafana содержит базовые дашборды (kube-system, node, pod).

Алерты: Alertmanager интегрируется с Slack/PagerDuty/Email — конфиг хранится в Helm values.

Логи: Promtail собирает логи с нод/подов и отправляет в Loki. Grafana Explore позволяет быстро искать по логам.

В infrastructure/ лежат значения для retention, storage и ресурсов — настройте их под ваши требования (особенно для Prometheus и Loki).

CI/CD
GitLab CI: .gitlab-ci.yml использует Kaniko для сборки образов и Helm для деплоя. В CI задайте KUBE_CONFIG_DATA (base64 kubeconfig) и registry credentials.

Jenkins: пример Jenkinsfile для multibranch pipeline, использует секретный файл kubeconfig и credentials для registry.

Скрипты ci-cd/scripts/build-and-push.sh и deploy-helm.sh — утилиты, которые можно вызывать локально или из CI.

Что можно улучшить / TODO (список для себя)
Вынести секреты в External Secrets / Vault вместо Ansible Vault или переменных CI.

Добавить автоматические тесты ролей (Molecule + Testinfra).

Сделать HA etcd с отдельными дисками и бэкапами в объектное хранилище (S3/GCS).

Интегрировать OPA/Gatekeeper для политики безопасности.

Настроить Thanos/Cortex для долговременного хранения метрик.

Автоматизировать ротацию сертификатов и ключей (cron + playbook).

CI: добавить Canary/Blue-Green деплойменты для frontend/backend.

Примечания по безопасности
Никогда не храните приватные ключи и kubeconfigs в репозитории. Используйте Ansible Vault или секреты CI.

Ограничьте доступ к control_plane_endpoint через firewall / security groups.

ServiceAccount для CI (ci-deployer) создаётся с минимальными правами — проверьте и сузьте правила под ваши нужды.