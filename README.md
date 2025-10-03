# helm-charts

[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=fff)](#)
[![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=fff)](#)
[![YAML](https://img.shields.io/badge/YAML-CB171E?logo=yaml&logoColor=fff)](#)

Kubernetes manifests for deploying Book-em

## 1 Getting started

### 1.1 Installing the required tools

(All of these tools should be installed inside Linux)

You will need:

- [minikube](https://minikube.sigs.k8s.io/docs/start/?arch=%2Flinux%2Fx86-64%2Fstable%2Fbinary+download)
- [kubectl](https://kubernetes.io/releases/download/)
- [helm](https://helm.sh/docs/intro/quickstart/)

### 1.2 Installing recommended tools

- [helmfile](https://github.com/helmfile/helmfile):
```sh
helm plugin install https://github.com/databus23/helm-diff
curl -LO https://github.com/helmfile/helmfile/releases/download/v1.1.7/helmfile_1.1.7_linux_amd64.tar.gz
tar -xzf helmfile_1.1.7_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/
```

### 1.3 Installing tools if you're using WSL2

- [socat](https://www.baeldung.com/linux/socat-command):
```sh
sudo apt install socat
```

## 2 Deploying the infrastructure

1. Make sure to start the local cluster:

    ```sh
    minikube start

    # If you haven't, enable ingress.
    minikube addons enable ingress
    ```

2. The easiest way to deploy the whole infrastructure is using helmfile:

    ```sh
    helmfile apply
    ```

3. If you're using WSL2, establish a connection between your Windows host and the WSL guest:

    ```sh
    ./socat.sh
    ```

4. Add the hostname to your hosts file:

    - If you're on windows:
    ```yml
    # C:/Windows/System32/drivers/etc/hosts

    127.0.0.1 bookem.local
    127.0.0.1 api.bookem.local
    127.0.0.1 db.bookem.local
    127.0.0.1 jaeger.bookem.local
    127.0.0.1 grafana.bookem.local
    ```

    - If you're on Linux:
    ```yml
    # /etc/hosts

    127.0.0.1 bookem.local api.bookem.local db.bookem.local jaeger.bookem.local grafana.bookem.local
    ```