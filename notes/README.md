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

- `Secret` is a secret. We can use this to pass secret files like JWT keys to Deployments (Pods).

When we write a helm chart, we will _at least_ write a deployment and a service. Pods
are "embedded" inside deployments.

## Process

Here's the process of creating helm charts.

First of all, you need to start minikube `minikube start` and also it would be
a good idea to do `docker compose down` for the `infrastructure` repo so we don't
accidentally send requests to the docker containers instead of k8s pods later on.

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
      port: 8080        # In infrastructure/compose.yml we used 8500.
```

**1.4 Install the chart**

Installing a chart means to create it and run it.

```sh
helm install user-service ./user-service
```

It should output this:

```ts
NAME: user-service
LAST DEPLOYED: Sat Sep 13 14:48:31 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

Now we can check by using kubectl:

```sh
kubectl get all
```

It should output this:

```ts
NAME                                READY   STATUS             RESTARTS      AGE
pod/user-service-5697759744-qvxmp   0/1     CrashLoopBackOff   3 (38s ago)   82s

NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/kubernetes     ClusterIP   10.96.0.1       <none>        443/TCP    2d23h
service/user-service   ClusterIP   10.107.109.64   <none>        8080/TCP   83s

NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/user-service   0/1     1            0           83s

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/user-service-5697759744   1         1         0       83s
```

We have a single Pod, two Services (the `kubernetes` Service is handled by
minikube), one Deployment and one Replicaset (Replicasets are handleded by
Deployments, but it's the actual "collection" of Pods).

Take a look at the pod details:

```ts
NAME  READY   STATUS             RESTARTS      AGE
...   0/1     CrashLoopBackOff   3 (38s ago)   82s
```

The status is `CrashLoopBackOff`. That means it's starting, crashing, restarting,
crashing, ...

Let's see what's going on. This will print the logs.

```sh
kubectl logs pod/user-service-5697759744-qvxmp
```

If we add a `-f` flag, it will "attach" the terminal to the log output so you can
recieve logs in real time.

Anyway, here's the log output:

```ts
2025/09/13 12:51:40 Failed to open DB: failed to connect to `user=password= database=sslmode=disable`:
        hostname resolving error: lookup port=: no such host
        lookup port=: no such host

2025/09/13 12:51:40 /app/main.go:47
[error] failed to initialize database, got error failed to connect to `user=password= database=sslmode=disable`:
        hostname resolving error: lookup port=: no such host
        lookup port=: no such host
```

So the problem is that the connection string is incorrect. `user`, `password` and `database` are empty. That's because we didn't set the environment variables.

**1.5 Add a configmap**

We can put the env variables directly inside a Deployment, but Deployments can get
verbose very quickly, so it's better to extract them into a Configmap.

Configmap:
```yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-service
  namespace: default

# Notice that numbers are written as quotes. This is important.
# Also, this is all copied from `infrastructure/compose.yml`.
data:
  DB_HOST: user-db
  DB_PORT: "5432"
  DB_NAME: bookem_userdb_db
  DB_USER: bookem_userdb_user
  DB_PASSWORD: password123
  JWT_PRIVATE_KEY_PATH: /app/keys/private_key.key
  JWT_PUBLIC_KEY_PATH: /app/keys/public_key.pem
```

Now we "include" the configmap inside the deployment:

```yml
apiVersion: apps/v1
kind: Deployment
metadata: ...
spec:
  ...
  template:
    metadata: ...
    spec:
      containers:
      - name: ...

        # We add an environment from a ConfigMap reference.
        # This is added inside a container.
        # Name must match the name of the ConfigMap.
        envFrom:
        - configMapRef:
            name: user-service
```

**1.6 Update the chart**

We _install_ helm charts only once. If the chart by that name already exists,
we must _upgrade_ it:

```sh
helm upgrade user-service ./user-service
```

Since this is annoying (install or upgrade), we can use the `--install/-i` flag
to upgrade if chart exists or install if it doesn't:

```sh
helm upgrade -i user-service ./user-service
```

That's the command I'll be using from now on.

```sh
kubectl get all

NAME                                READY   STATUS             RESTARTS       AGE
pod/user-service-5697759744-qvxmp   0/1     CrashLoopBackOff   11 (25s ago)   27m
pod/user-service-84b5b8c74d-cdsg7   0/1     Error              3 (42s ago)    62s



kubectl logs pod/user-service-84b5b8c74d-cdsg7

2025/09/13 13:15:27 /app/main.go:47
[error] failed to initialize database, got error failed to connect to `user=bookem_userdb_user database=bookem_userdb_db`: hostname resolving error: lookup user-db on 10.96.0.10:53: server misbehaving
2025/09/13 13:15:27 Failed to open DB: failed to connect to `user=bookem_userdb_user database=bookem_userdb_db`: hostname resolving error: lookup user-db on 10.96.0.10:53: server misbehaving
```

Now the problem is that it can't connect to `user-db` because we don't have it ready yet. We need to create a helm chart for `user-db` as well.

**2. Create charts for user-db.**

The process is exactly the same:

```sh
helm create user-db
# And then delete the templates and contents of values.yaml...
```

```yml
# deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-db
  namespace: default
  labels:
    app: user-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: user-db
  template:
    metadata:
      labels:
        app: user-db
    spec:
      containers:
      - name: user-db
        image: postgres:15.9-alpine3.20
        ports:
        - containerPort: 5432

        envFrom:
        - configMapRef:
            name: user-db

        # This is new. We create a volume mount called `db-storage`
        # and have it mount /var/lib/postgresql/data.
        # Compare it to the volume mount in user-db in compose.yml.
        volumeMounts:
        - mountPath: /var/lib/postgresql/data
          name: db-storage

      # This is like the volumes resource in compose.yml at the very
      # bottom of the file. Notice how this is written inside `spec`
      # but outside `containers`. Similar to docker compose.
      # Make sure the claimName matches the name of the Persistent
      # Volume Claim (see below).
      volumes:
      - name: db-storage
        persistentVolumeClaim:
          claimName: user-db
```

```yml
# service.yml

apiVersion: v1
kind: Service
metadata:
  name: user-db
  namespace: default
  labels:
    app: user-db
spec:
  selector:
    app: user-db
  ports:
    - protocol: TCP
      targetPort: 5432
      port: 5432
```

```yml
# configmap.yml

apiVersion: v1
kind: ConfigMap
metadata:
  name: user-db
  namespace: default
data:
  POSTGRES_DB: bookem_userdb_db
  POSTGRES_USER: bookem_userdb_user
  POSTGRES_PASSWORD: password123
```

The new thing here is a PersistentVolumeClaim:

```yml
# pvc.yml

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: user-db
  namespace: default
spec:
  # Can be read by a single node (minikube = 1 node).
  accessModes:
    - ReadWriteOnce

  resources:
    requests:
      storage: 1Gi

  # Because this is set to `standard`, we don't have to create
  # a Persistent Volume itself. The kubernetes engine will take
  # care of that for us.
  storageClassName: standard
```

```sh
helm upgrade -i user-db ./user-db
```

```sh
kubectl get pods


NAME                            READY   STATUS             RESTARTS         AGE
user-db-695c48fbf5-zmmfm        1/1     Running            0                5s


kubectl logs user-db-695c48fbf5-zmmfm

PostgreSQL Database directory appears to contain a database; Skipping initialization

2025-09-13 13:40:52.499 UTC [1] LOG:  starting PostgreSQL 15.9 on x86_64-pc-linux-musl, compiled by gcc (Alpine 13.2.1_git20240309) 13.2.1 20240309, 64-bit
2025-09-13 13:40:52.499 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2025-09-13 13:40:52.499 UTC [1] LOG:  listening on IPv6 address "::", port 5432
2025-09-13 13:40:52.509 UTC [1] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
2025-09-13 13:40:52.527 UTC [29] LOG:  database system was shut down at 2025-09-13 12:48:25 UTC
2025-09-13 13:40:52.559 UTC [1] LOG:  database system is ready to accept connections
```

It works. Now to connect user-service to user-db.

**3 Fix user-serivce**

Sometimes you will need to force reset the chart (pod/deployment/service/...) because
doing `helm upgrade` won't fix it (especially if the helm chart hasn't updated).

```sh
kubectl rollout restart deployment user-service
```

```ts
kubectl get all

NAME                               READY   STATUS    RESTARTS   AGE
pod/user-db-695c48fbf5-zmmfm       1/1     Running   0          2m57s
pod/user-service-bb667b748-kgbck   1/1     Running   0          4s
```

```ts
kubectl logs service/user-service

2025/09/13 13:43:44 Connected to DB!
[GIN-debug] [WARNING] Creating an Engine instance with the Logger and Recovery middleware already attached.

[GIN-debug] [WARNING] Running in "debug" mode. Switch to "release" mode in production.
 - using env:   export GIN_MODE=release
 - using code:  gin.SetMode(gin.ReleaseMode)

[GIN-debug] GET    /healthz                  --> main.main.func1 (4 handlers)
[GIN-debug] POST   /api/register             --> bookem-user-service/api.(*Handler).registerUser-fm (5 handlers)
[GIN-debug] POST   /api/login                --> bookem-user-service/api.(*Handler).login-fm (5 handlers)
[GIN-debug] PUT    /api/update               --> bookem-user-service/api.(*Handler).update-fm (5 handlers)
[GIN-debug] PUT    /api/password             --> bookem-user-service/api.(*Handler).changePassword-fm (5 handlers)
[GIN-debug] GET    /api/:id                  --> bookem-user-service/api.(*Handler).findById-fm (5 handlers)
[GIN-debug] DELETE /api/:id                  --> bookem-user-service/api.(*Handler).deleteById-fm (5 handlers)
[GIN-debug] [WARNING] You trusted all proxies, this is NOT safe. We recommend you to set a value.
Please check https://pkg.go.dev/github.com/gin-gonic/gin#readme-don-t-trust-all-proxies for details.
[GIN-debug] Environment variable PORT is undefined. Using port :8080 by default
[GIN-debug] Listening and serving HTTP on :8080
```

It works now.

**4. Test user service inside of the pod**

```sh
curl -X GET http://localhost:8080/healthz
```

This will **fail**. It's because by default services are not available to the outside.

For this we would normally use something like Ingress or a NodePort service.
But for now, let's just forward ports:

```sh
kubectl port-forward service/user-service 8500:8080
```

This will basically open the port until you Ctrl+D.

So open the web browser and go to `http://localhost:8500/healthz` it should return `null`.

In fact, let's try using it through the web app. Run the web-app (npm run dev) and create a new user in the Register page.

This will **fail**, because if the user-service doesn't have access to the keys. If you check the logs of the user-service pod, you'll see this:

```ts
[GIN] 2025/09/13 - 13:52:08 | 400 |   83.263947ms |       127.0.0.1 | POST     "/api/login"
Error #01: invalid user or password
2025/09/13 13:52:08 could not open private key /app/keys/private_key.key: open /app/keys/private_key.key: no such file or directory
2025/09/13 13:52:08 [DEBUG] Error: invalid user or password
```

So we will need to mount the keys.

**5. Add JWT keys to user-service Pod**

For this, we will use a Secret resource:

```yml
# secret.yml

apiVersion: v1
kind: Secret
metadata:
  # We'll use a different name just in case we have multiple secrets.
  name: user-service-jwt-keys
  namespace: default
type: Opaque
data:
  # The data is in the format KEY: VALUE
  # In this case, we create two KEYs, matching the names of the files.
  # This is important because of the way these secrets are used (see below).
  #
  # As for the file, this is the first time we're using a Helm declaration.
  # It's anything between {{ }}
  # The inside is either some value or function calls.
  # In this case, we have .Files which is like a built in module, and we
  # use the method Get, followed by its parameter.
  #
  # So .Files.Get "secrets/keys/private_key.key" will basically load the
  # file "secrets/keys/private_key.key" (file paths are relative to the chart
  # directory) and PASTE its contents in-place.
  #
  # Then, we pipe that result (i.e. file contents) into the function b64enc
  # which encodes the file.
  #
  # So once the template supstitution is done, private_key.key will equal
  # the base64 encoded value of the private key. Note that this is all in
  # memory, no files have been created for this purpose.

  private_key.key: {{ .Files.Get "secrets/keys/private_key.key" | b64enc }}
  public_key.pem: {{ .Files.Get "secrets/keys/public_key.pem" | b64enc }}
```

Now we need to mount this:

```yml
# deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata: ...
spec:
  ...
  template:
    ...
    spec:
      containers:
      - name: user-service
        ...

        # We mount `jwt-keys` to /app/keys
        volumeMounts:
        - name: jwt-keys
          mountPath: /app/keys
          readOnly: true

      # `jwt-keys` is from a Secret called `user-service-jwt-keys`
      # This will basically create all the files from the Secret's
      # key-value pairs at runtime.
      volumes:
      - name: jwt-keys
        secret:
          secretName: user-service-jwt-keys
```

Finally, we must actually pass the keys.
I'll copy the `keys/` folder from the `user-service` git repo and put it in a `secrets/` folder (that's why `{{ .Files.Get "secrets/keys/private_key.key" | b64enc }}` uses that exact path).

You can check if it really works by running:

```
helm template ./user-service
```

This will print the final k8s manifest for this chart to stdout.
Find the keys and check if they're really hardcoded:

```yml
---
# Source: user-service/templates/secret.yml
apiVersion: v1
kind: Secret
metadata:
  name: user-service-jwt-keys
  namespace: default
type: Opaque
data:
  private_key.key: LS0tLS...LS0NCg==
  public_key.pem: LS0tLS...LS0NCg==
---
# Source: user-service/templates/configmap.yml
apiVersion: v1
kind: ConfigMap
...
```

Finally we can upgrade the user-service and now registering new users inside the web app should work.

**6. Templating the helm charts**

Example:

```yml
# deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  ...
spec:
  replicas: 1

  ...
```

If we want to make the number of replicas "variable", we would do:

```yml
# deployment.yml

apiVersion: apps/v1
kind: Deployment
metadata:
  ...
spec:
  replicas: {{ .Values.replicas }}
```

and then in `values.yaml`:

```yml
# values.yaml

replicas: 1
```

If we want to change it later, we modify `replicas` in `values.yaml` and then upgrade the helm chart. So the `.Values` variable is the main thing here.

Values can be nested:

```yml
---
# values.yaml

replicas: 1

image:
  name: magley/bookem-user-service
  tag: 0.1.0

---
# deployment.yml

spec:
  replicas: {{ .Values.replicas }}
  template:
    spec:
      containers:
      - image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
        # I add quotes just in case.
```

You can do fancy things like iterating over an array of elements, too, but we probably
won't need that just yet.

**7. Health check**

In Docker Compose we have healthcheck. In K8s, we have probes.
The two important probes are:
- livenessProbe = is the container inside the Pod alive (running)?
- readinessProbe = is the container inside the Pod ready (ready to accept connections)?

It's best to write both, with livenessProbe having a greater period.

```yml
# user-service/deplyment.yml

spec:
  containers:
    - ...
      readinessProbe:
        httpGet:
          path: /healthz
          port: {{ .Values.port }}
        initialDelaySeconds: 3
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 5

      livenessProbe:
        httpGet:
          path: /healthz
          port: {{ .Values.port }}
        initialDelaySeconds: 10
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 5

---
# user-db/deplyment.yml

spec:
  containers:
    - ...
      readinessProbe:
        exec:
          command:
            - /bin/sh
            - -c
            - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
        initialDelaySeconds: 3
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 5

      livenessProbe:
        exec:
          command:
            - /bin/sh
            - -c
            - pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
        initialDelaySeconds: 10
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 5
```

**8. Deploying Room service, DB and Nginx server**

**8.1** room-db is similar to user-db

**8.2** room-image-server is the "room-images" Nginx server.

We use a PVC to mount images.
Remember: this is local to the room-images pod.

But room service which is in a different chart, and therefore in a different
pod, will need to write to this directory, so the PVC `accessModes` must be
`ReadWriteMany` instead of `ReadWriteOnce`.

Furthermore, since the two charts use the same PVC, we must:
- give it a unique name like {{ .Values.sharedImagesPvc }}
- define it only once (since we use the same namespace)
- reference it in deployments of both the room-service and room-image-server 

We can see the list of images like so:

```sh
kubectl exec [pod name] -- ls -a /usr/share/nginx/html/images
```

**8.3** room-service is simple enough. Just be careful when copy-pasting stuff.

**8.4** Testing:

We can test if everything works by opening ports to all the servers:

```sh
kubectl port-forward svc/user-service 8500:8080
kubectl port-forward svc/room-service 8503:8080
kubectl port-forward svc/room-image-server 8505:80
```

Note that this requires 3 terminals since port-forward steals the shell.

**9. Deploying reservation db and reservation service**

This is pretty much the same as user service, but we don't need the private key
(like we didn't need it in the room service).

We can then test everything by opening ports of these services:

```sh
kubectl port-forward svc/user-service 8500:8080
kubectl port-forward svc/room-service 8503:8080
kubectl port-forward svc/room-image-server 8505:80
kubectl port-forward svc/reservation-service 8506:8080
```