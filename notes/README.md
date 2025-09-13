Since this is the first time I'm using Kubernetes (k8s) and because k8s is orders of magnitude more complex
(relative to Docker and Docker Compose), I'll leave some notes and my thought process regarding k8s for this
project. Hopefully the rest of the team will also find this guide handy.

---

## Tools

- `minikube` - implementation of k8s that runs locally
- `kubectl` - CLI client tool for k8s
- `helm` - a package manager for k8s, but we'll use it for templates

## Helm chart

A helm chart is one "specification" of a "thing" ran inside of a k8s cluster.

What was a service in `infrastructure/compose.yml` will now get an entire chart.
 
Templating is used so we can extract all the configurable data for a chart (ports,
image name, docker image tag, reserved resources, ...) in a single `values.yml`, so
we don't have to read the actual templates themselves.

For each k8s resource (Pod, Deployment, Service, Volume Claim, Configmap) that we need
for a chart, we will have one yaml file.

Each of these is a standard k8s manifest, but the "variables" are not hardcoded there,
and instead they reference `values.yml`. It's a bit difficult to read templates at first,
but hopefully we won't need to do that all the time.

## K8s resources

In k8s, a resource is a thing managed by the k8s engine (in our case, minikube). Here's
a brief, and probably very wrong, description of some of the resources that we will probably
use:

- `Pod` is an abstraction of a docker container. It can have 1 or more
containers. We will probably use only 1 container per pod. Each pod is given a
unique IP address. Containers within the same pod can communicate with each
other using localhost.

- `Deployment` is when multiple pods are handled automatically. You set the
number of replicas (e.g. 3) and then the k8s engine makes sure to always have
exactly 3 instances of that pod. We will probably have 1 replica for each
deployment.

- `Service` is used to "combine" multiple pods under a single "thing". Imagine a
deployment with 3 DB servers. Each of those is in its own pod. The IP address of
these pods is dynamic, so you can't hardcode it in an app. The service basically
gives us a "stable" IP address that encapsulates multiple pods. Different pods
or services can then communicate using the service's IP and port.

- `Configmap` is useful for writing env variables. So a deployment can steal the
data from a configmap. The values in a configmap must be strings, never numbers, so
inside a configmap's template you'll see `FOO: {{ .Values.bar | quote }}` instead of `FOO: {{ .Values.bar }}`

- `Volume Claim` is used for handling volumes in k8s. Normally we would need
both a Persistent Volume and a Persistent Volume Claim, but we can probably get
away with just the claim under the right configurations.

- `Ingress` ...

When we write a helm chart, we will _at least_ write a deployment and a service. Pods
are "embedded" inside deployments.

## Process

Here's the process of creating helm charts.

1. We will create `user-service` first.

**1.1. Create a default helm chart:**

```sh
helm create user-service
```

There's a lot of files in the newly created `user-service/` folder.</br>
We can delete everything in `/templates/` and also clear `values.yaml`.

**1.2. Remove default templates and values (do this manually)**

**1.3. Create a basic deployment and service for user-service**

Deployment:
```yml
apiVersion: apps/v1

kind: Deployment

# Metadata should at least have name and namespace.
# We'll use the default namespace for now.
# labels is a special thing in k8s which we can use to "group"
# things. You'll see below a `selector` which refers to labels.
# Labels are arbitrary, but `app` is commonly used by everyone.
metadata:
  name: user-service
  namespace: default
  labels:
    app: user-service

# This is the actual specification of the deployment.
spec:
  replicas: 1

  # This is saying: "create 1 of anything that has a label called app
  # with the value user-service". In this case, it will check for that
  # "anything" inside of `template`. 
  selector:
    matchLabels:
      app: user-service

  template:
    # This is a single "thing" (Pod) which we create. Because it has
    # a label called app with the value user-serivce, the Deployment's
    # selector (see above) will match, and create `replicas`-many Pods
    # described by this template.
    metadata:
      labels:
        app: user-service

    # This also has a specification, since it's a Pod.
    spec:
      containers:
      - name: user-service
        image: magley/bookem-user-service:0.1.0
        ports:
        - containerPort: 8080
```

Service:
```yml
apiVersion: v1
kind: Service

# This has the same metadata as the Deployment. It doesn't have to, but
# if the namespaces don't match, you'll have problems. As for the name,
# we do this on purpose so it's easier for us. Same goes for the label.
metadata:
  name: user-service
  namespace: default
  labels:
    app: user-service

spec:
  # This is selecting against Pods (because Services combine Pods under a single
  # service), so the Pods (defined in deployment) must have this exact label.
  # The reason you don't write matchLabels like in the Deployment is because
  # only Deployments support multiple ways of matching labels (one of which is
  # matchLabels). Services _only_ support that.
  selector:
    app: user-service

  ports:
    - protocol: TCP     # TCP is the default, but no harm in being explicit.
      targetPort: 8080  # Port of the pods.
      port: 8080        # In infrastructure/compose.yml we used 9500.
```

