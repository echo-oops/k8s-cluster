# Architecture

## Обзор
Этот каталог содержит документацию по архитектуре и компонентам кластера Kubernetes, который разворачивается с помощью Ansible/kubeadm и управляется Helm-чартами. Проект ориентирован на production‑ready on‑prem / small cloud deployment и включает:

- **Kubernetes (kubeadm)**: 3 узла — 1 control-plane, 2 worker (Ubuntu 22.04).
- **CNI**: Calico с поддержкой NetworkPolicy.
- **Ingress**: NGINX Ingress Controller (Helm).
- **Управление приложениями**: Helm v3, собственные чарты `frontend` и `backend`.
- **CI/CD**: GitLab CI (pipeline для сборки, пуша и деплоя через Helm).
- **Мониторинг**: Prometheus + Grafana (kube-prometheus-stack).
- **Логирование**: Loki + Promtail.
- **Безопасность**: RBAC, Network Policies (deny-by-default), Pod Security (контексты), Sealed Secrets.
- **Автоматизация**: Ansible роли для подготовки узлов и инициализации кластера; все манифесты идемпотентны.

## Компоненты и их роли
- **Control-plane (master)**  
  - kube-apiserver, etcd, kube-controller-manager, kube-scheduler, kube-proxy  
  - Хранит конфигурацию кластера и принимает API-запросы.
  - Рекомендуется иметь стабильный публичный/приватный IP (controlPlaneEndpoint в kubeadm-config).

- **Worker nodes**  
  - kubelet, containerd, calico-node, приложения (frontend/backend), node-exporter.
  - Запускают контейнеры и обеспечивают рабочую нагрузку.

- **Calico**  
  - CNI с поддержкой NetworkPolicy и возможностью использования BGP/IPPools.
  - Управляет маршрутизацией Pod‑сети и применяет политики безопасности.

- **NGINX Ingress Controller**  
  - Принимает внешний трафик (NodePort/LoadBalancer) и маршрутизирует в сервисы.
  - Устанавливается через Helm chart `ingress-nginx`.

- **Prometheus + Grafana (kube-prometheus-stack)**  
  - Prometheus собирает метрики, Alertmanager обрабатывает алерты, Grafana отображает дашборды.
  - ServiceMonitors для приложений (frontend/backend) и системных компонентов.

- **Loki + Promtail**  
  - Promtail собирает логи с узлов/подов и отправляет в Loki.
  - Grafana использует Loki как источник логов.

- **CI/CD (GitLab CI)**  
  - Сборка образов (Docker-in-Docker или Kaniko), пуш в registry, деплой через `helm upgrade --install`.
  - ServiceAccount `ci-deployer` с ограниченными правами для деплоя.

- **Sealed Secrets**  
  - Позволяет хранить зашифрованные секреты в Git; контроллер расшифровывает их в кластере.

## Сетевые диапазоны и адресация
- **Pod CIDR**: `10.244.0.0/16` (настраивается в kubeadm-config)
- **Service CIDR**: `10.96.0.0/12`
- **Calico IP Pool**: по умолчанию использует Pod CIDR; можно настроить IPIP/BGP в production.
- **NodePort**: `30000-32767` (Ingress NodePort в values.yaml: 30080/30443)

## Схема потоков трафика (ASCII)
Internet / Users
|
[NodePort / LB]
|
+-----------------+
|  NGINX Ingress  |
+-----------------+
|           |
frontend svc     backend svc
(ClusterIP)      (ClusterIP)
|                 |
frontend pods       backend pods
|                 |
Prometheus scrapes -> metrics endpoints
Promtail collects -> logs -> Loki
Grafana reads -> Prometheus + Loki




## Безопасность и политики
- **RBAC**
  - `ci-deployer` ServiceAccount в `default` namespace с Role, ограниченной ресурсами, необходимыми для деплоя.
  - `readonly` ClusterRole для аудиторов.

- **Network Policies**
  - `default-deny` в `default` namespace — блокирует весь ingress/egress по умолчанию.
  - `allow-dns` — разрешает egress на DNS (CoreDNS) и публичные DNS.
  - `allow-frontend-to-backend` — разрешает frontend -> backend по TCP:8080.

- **Pod Security**
  - В чартах заданы `podSecurityContext` и `securityContext` (runAsUser, fsGroup, drop capabilities, readOnlyRootFilesystem).
  - Рекомендуется включить Pod Security Admission (PSA) или OPA/Gatekeeper для enforcement.

- **Секреты**
  - Используйте Bitnami Sealed Secrets для хранения секретов в Git.
  - В production храните ключи SealedSecrets контроллера в безопасном месте.

## Хранилище и резервирование
- **etcd snapshot**: используйте `scripts/backup-etcd.sh` для регулярных снапшотов; храните в S3/облачном хранилище.
- **Persistent Volumes**: PVC для Prometheus, Grafana, Loki; убедитесь, что StorageClass поддерживает Retain/ReadWriteOnce.

## Масштабирование и HA
- **Control-plane**: для HA добавьте дополнительные control-plane узлы и используйте внешний балансировщик для `controlPlaneEndpoint`.
- **Loki**: для HA рекомендуется StatefulSet с 3 репликами и объектным хранилищем (S3/GCS).
- **Prometheus**: можно использовать Thanos или Cortex для масштабирования и долговременного хранения.

## Обновления
- **kubeadm upgrade** workflow:
  1. `kubeadm upgrade plan`
  2. `kubeadm upgrade apply vX.Y.Z` на control-plane
  3. Обновить пакеты kubelet/kubectl на всех узлах и перезапустить kubelet
  4. `kubeadm upgrade node` на воркерах при необходимости
- Тестируйте обновления на staging перед production.

## Рекомендации по мониторингу и алертингу
- Настройте базовые алерты: `InstanceDown`, `KubeAPIDown`, `HighErrorRate`, `HighCPU`, `HighMemory`.
- Интегрируйте Alertmanager с каналами оповещений (Slack, PagerDuty, Email) через секреты.
- Настройте retention и storage для Prometheus и Loki в соответствии с требованиями хранения логов/метрик.

## Примеры команд для быстрого доступа
- Проверка нод: `kubectl get nodes -o wide`
- Проверка подов: `kubectl get pods -A`
- Port-forward Grafana: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`
- Просмотр логов Loki через Grafana Explore

## Контакты и поддержка
- В репозитории добавлены скрипты и playbook’и для автоматизации. Для адаптации под конкретную инфраструктуру (bare-metal, cloud provider) потребуется корректировка Terraform/Ansible шаблонов и StorageClass.
