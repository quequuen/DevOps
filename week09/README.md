# 9주차 정리 (쿠버네티스 배포와 서비스) — Deployment / Service 직접 작성하고 배포하기

## 목표

- Deployment, ReplicaSet, Pod의 계층 관계를 이해한다.
- 서비스(Service)가 필요한 이유를 이해한다.
- 레이블과 셀렉터로 오브젝트들이 연결되는 원리를 이해한다.
- `deployment.yaml`, `service.yaml`을 직접 작성하고 배포한다.
- 스케일링, 롤링 업데이트, 롤백을 직접 수행한다.

지난주(8주차)까지는 `kubectl create`로 손으로 만드는 **명령형**이었다면, 이번 주는 원하는 상태를 YAML 파일에 적어두고 실행하는 **선언형**으로 넘어간다.

| | 명령형 (지난주) | 선언형 (이번 주) |
| --- | --- | --- |
| 만드는 법 | `kubectl create deployment ...` | `kubectl apply -f deployment.yaml` |
| 원하는 상태 저장 위치 | 내 머릿속, 터미널 기록 | 파일 (Git으로 관리) |
| 다른 클러스터에서 재현 | 다시 하나하나 입력 | `apply -f` 한 번 |

> 매니페스트는 PDF 슬라이드처럼 `guestbook/k8s/`가 아니라, 다른 주차와 같은 규칙으로 `week09/` 바로 아래 두었다. (`guestbook/`는 여러 주차가 공유하는 앱 소스라 건드리지 않음)

---

## 핵심 오브젝트 — 3층 구조

```
Deployment  "guestbook 앱을 2개 유지해줘, 이미지는 v1을 써"   ← 우리가 선언하는 것 (버전 관리, 롤링 업데이트)
  └─ ReplicaSet  "개수를 2개로 맞추기"                        ← Deployment가 자동 생성 (개수 유지 담당)
       └─ Pod, Pod  ...                                       ← 실제 컨테이너가 실행되는 단위
```

- Deployment 사장 / ReplicaSet 매니저 / Pod 직원 비유. 우리가 직접 만드는 건 **Deployment뿐**이고 나머지는 쿠버네티스가 알아서 만든다.
- 가장 실수가 잦은 곳: `spec.selector.matchLabels` = `spec.template.metadata.labels` (일치해야 함).

## 레이블과 셀렉터

- 레이블: IP나 이름을 몰라도 꼬리표(`app: guestbook`)만으로 Pod를 찾을 수 있게 해준다.
- 셀렉터: 레이블로 골라내는 조건. Deployment의 셀렉터는 **자기 Pod**를, Service의 셀렉터는 **트래픽을 보낼 Pod**를 찾는 데 쓰인다.
- 세 곳(`selector.matchLabels`, `template.metadata.labels`, Service의 `selector`)이 모두 `app: guestbook`으로 일치해야 사슬처럼 연결된다.

## 서비스(Service)가 필요한 이유

Pod는 죽었다 살아나면 IP가 바뀐다. 사용자가 접속할 고정 주소(대표 번호)가 필요해서 서비스를 둔다.

- `ClusterIP` (기본값): 클러스터 내부 전용. DB 등에 사용.
- `NodePort`: 노드의 특정 포트(30000~32767)로 외부 노출. 수업/개발용.
- `LoadBalancer`: 클라우드 로드밸런서 연결. 이 수업에서는 사용 안 함.

포트 세 개가 각각 다른 역할을 한다.

```
브라우저 → http://노드IP:30080
[Node]     nodePort: 30080   ← 클러스터 바깥에서 들어오는 문
[Service]  port: 80          ← 서비스 자신의 문 (클러스터 안에서는 guestbook:80)
[Pod]      targetPort: 5000  ← 컨테이너의 문 (app.py가 듣는 곳)
```

7주차 Docker Compose에서 nginx로 직접 만들었던 문지기 역할을, 쿠버네티스에서는 Service 설정 몇 줄이 대신해준다(오케스트레이션).

---

## 준비 — 이미지 두 개 만들기

실습에는 v1, v2 두 이미지가 필요하다. `guestbook/` 원본 소스는 다른 주차와 공유하므로 건드리지 않고, v1은 그대로 빌드하고 v2는 베이스 이미지의 `ENV`만 덮어써서 만들었다.

```bash
# v1 — guestbook/ 원본 그대로 빌드
$ docker build -t ghcr.io/quequuen/guestbook:v1 ./guestbook
```

[Dockerfile.v2](./Dockerfile.v2) — v1 이미지를 베이스로 제목만 바꾼 v2 (롤링 업데이트를 눈으로 확인하기 위한 용도)

```dockerfile
FROM ghcr.io/quequuen/guestbook:v1
ENV APP_TITLE="InhaTC DevOps 방명록 v2"
```

```bash
$ docker build -t ghcr.io/quequuen/guestbook:v2 -f week09/Dockerfile.v2 week09
```

클러스터에는 ghcr로 push하지 않고, 슬라이드가 안내하는 대로 로컬 이미지를 바로 minikube에 올려서 썼다.

```bash
$ minikube start --driver=docker
$ minikube image load ghcr.io/quequuen/guestbook:v1
$ minikube image load ghcr.io/quequuen/guestbook:v2
```

---

## 실습 1 — YAML로 배포하기

### 1-1. deployment.yaml

[deployment.yaml](./deployment.yaml)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guestbook
spec:
  replicas: 2
  selector:
    matchLabels:
      app: guestbook
  template:
    metadata:
      labels:
        app: guestbook
    spec:
      containers:
        - name: web
          image: ghcr.io/quequuen/guestbook:v1
          ports:
            - containerPort: 5000
```

실행 전 `--dry-run=server`로 문법만 먼저 검사했다.

```bash
$ kubectl apply -f deployment.yaml --dry-run=server
deployment.apps/guestbook created (server dry run)
```

### 1-2. 배포

```bash
$ kubectl apply -f deployment.yaml
deployment.apps/guestbook created

$ kubectl get deployments
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
guestbook   2/2     2            2           8s

$ kubectl get replicasets        # Deployment가 자동 생성
NAME                  DESIRED   CURRENT   READY   AGE
guestbook-74f4cd9bb   2         2         2       9s

$ kubectl get pods
NAME                        READY   STATUS    RESTARTS   AGE
guestbook-74f4cd9bb-76qkn   1/1     Running   0          11s
guestbook-74f4cd9bb-dlbqv   1/1     Running   0          11s
```

Pod 이름 규칙: `guestbook` (Deployment 이름) + `74f4cd9bb` (ReplicaSet 틀 번호 = 해시) + `76qkn` (무작위 5글자).

### 1-3. service.yaml

[service.yaml](./service.yaml)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: guestbook
spec:
  type: NodePort
  selector:
    app: guestbook
  ports:
    - port: 80
      targetPort: 5000
      nodePort: 30080
```

> Service는 `apps/v1`이 아니라 `v1`이고, `selector`에는 `matchLabels:` 없이 바로 레이블을 쓴다. Deployment와 형식이 달라서 실수하기 쉬운 부분.

```bash
$ kubectl apply -f service.yaml
service/guestbook created

$ kubectl get svc
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
guestbook    NodePort    10.111.198.141   <none>        80:30080/TCP   0s
kubernetes   ClusterIP   10.96.0.1        <none>        443/TCP        54s

$ kubectl describe svc guestbook
...
Endpoints:  10.244.0.4:5000,10.244.0.3:5000     # 셀렉터로 찾아낸 Pod 2개의 IP
```

### 접속 확인

macOS + docker 드라이버 조합에서는 `minikube ip`로 바로 접속이 안 돼서(터널이 필요), 클러스터 안에서 busybox로 서비스 이름(`http://guestbook/`)을 호출해 확인했다.

```bash
$ kubectl run lb-check --restart=Never --image=busybox:1.36 -- \
    sh -c 'wget -q -T 3 -O- http://guestbook/ | grep -oE "<title>[^<]+</title>|Pod/Host: [a-zA-Z0-9-]+"'
<title>InhaTC DevOps 방명록</title>
Pod/Host: guestbook-74f4cd9bb-76qkn
```

서비스 이름(`guestbook`)만으로 접속이 됐다 — 서비스 이름이 곧 클러스터 안의 DNS 주소.

---

## 실습 2 — 스케일링 & 로드밸런싱

### 2-1. 스케일링 + 로드밸런싱

```bash
$ kubectl scale deployment guestbook --replicas=4
deployment.apps/guestbook scaled

$ kubectl get pods
NAME                        READY   STATUS    RESTARTS   AGE
guestbook-74f4cd9bb-9dmht   1/1     Running   0          46s
guestbook-74f4cd9bb-dlbqv   1/1     Running   0          2m19s
guestbook-74f4cd9bb-hcltl   1/1     Running   0          5s
guestbook-74f4cd9bb-js7lv   1/1     Running   0          5s
```

서비스가 셀렉터로 찾은 Pod들에게 알아서 요청을 나눠준다. 별도로 로드밸런서를 설정하지 않았다 — 7주차엔 nginx 설정을 직접 작성해서 문지기를 붙였는데, 쿠버네티스는 이 과정이 자동이다(오케스트레이션).

busybox 루프로 10번 요청을 보내 실제로 여러 Pod에 분산되는지 확인:

```bash
$ kubectl run lb-check --restart=Never --image=busybox:1.36 -- \
    sh -c 'for i in 1 2 3 4 5 6 7 8 9 10; do wget -q -T 3 -O- http://guestbook/ | grep -oE "Pod/Host: [a-zA-Z0-9-]+"; sleep 0.3; done'
$ kubectl logs lb-check
Pod/Host: guestbook-74f4cd9bb-76qkn
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-76qkn
Pod/Host: guestbook-74f4cd9bb-dlbqv
Pod/Host: guestbook-74f4cd9bb-76qkn
```

축소도 순식간에 된다.

```bash
$ kubectl scale deployment guestbook --replicas=2
deployment.apps/guestbook scaled
```

### 자가 치유(self-healing) 확인

Pod 하나를 강제로 지워봤다.

```bash
$ kubectl get pods
NAME                        READY   STATUS    RESTARTS   AGE   IP           NODE
guestbook-74f4cd9bb-76qkn   1/1     Running   0          93s   10.244.0.4   minikube
guestbook-74f4cd9bb-dlbqv   1/1     Running   0          93s   10.244.0.3   minikube

$ kubectl delete pod guestbook-74f4cd9bb-76qkn
pod "guestbook-74f4cd9bb-76qkn" deleted

$ kubectl get pods
NAME                        READY   STATUS    RESTARTS   AGE
guestbook-74f4cd9bb-9dmht   1/1     Running   0          35s   # 새로 태어난 Pod
guestbook-74f4cd9bb-dlbqv   1/1     Running   0          2m8s
```

지운 Pod(`76qkn`)는 사라지고, ReplicaSet이 "2개를 유지해야 한다"는 선언대로 새 Pod(`9dmht`)를 자동으로 띄웠다. `kubectl create`로 손으로 만들었던 지난주와 달리, 이번엔 **내가 아무것도 안 했는데** 원래 개수로 복구된 게 핵심 차이.

### 2-2 / 2-3. 롤링 업데이트와 롤백

새벽 점검 없이 v1 → v2로 바꾸는 롤링 업데이트를 수행했다.

```bash
$ kubectl set image deployment/guestbook web=ghcr.io/quequuen/guestbook:v2
deployment.apps/guestbook image updated

$ kubectl rollout status deployment/guestbook
Waiting for deployment "guestbook" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "guestbook" rollout to finish: 1 old replicas are pending termination...
deployment "guestbook" successfully rolled out
```

ReplicaSet이 바뀌는 걸 확인:

```bash
$ kubectl get rs
NAME                   DESIRED   CURRENT   READY   AGE
guestbook-6c77b65f79   2         2         2       5s    # new (v2)
guestbook-74f4cd9bb    0         0         0       2m42s # old (v1), 0개로 남음
```

화면(제목)도 바뀐 것을 확인:

```bash
$ kubectl run lb-check2 --restart=Never --image=busybox:1.36 -- \
    sh -c 'wget -q -T 3 -O- http://guestbook/ | grep -oE "<title>[^<]+</title>|Pod/Host: [a-zA-Z0-9-]+"'
<title>InhaTC DevOps 방명록 v2</title>
Pod/Host: guestbook-6c77b65f79-hnwj4
```

**버그를 발견했다고 가정하고 롤백**:

```bash
$ kubectl rollout history deployment/guestbook
REVISION  CHANGE-CAUSE
1         <none>
2         <none>

$ kubectl rollout undo deployment/guestbook
deployment.apps/guestbook rolled back

$ kubectl rollout status deployment/guestbook
deployment "guestbook" successfully rolled out

$ kubectl get rs
NAME                   DESIRED   CURRENT   READY   AGE
guestbook-6c77b65f79   0         0         0       16s    # v2, 다시 0개로
guestbook-74f4cd9bb    2         2         2       2m53s  # v1, 되살아남
```

코드를 되돌리거나 다시 빌드·배포할 필요 없이, 쿠버네티스가 이전 ReplicaSet(v1)을 0개로 남겨두고 있다가 그대로 살려냈다. (단, 과거 모든 버전을 무제한 보관하는 건 아니라는 점 주의.)

변경 이유를 기록으로 남기기:

```bash
$ kubectl annotate deployment/guestbook kubernetes.io/change-cause="v1: 롤백 완료" --overwrite
deployment.apps/guestbook annotated

$ kubectl rollout history deployment/guestbook
REVISION  CHANGE-CAUSE
2         <none>
3         v1: 롤백 완료
```

롤백 직후 화면도 다시 v1로 돌아온 것을 확인:

```bash
$ kubectl run lb-check3 --restart=Never --image=busybox:1.36 -- \
    sh -c 'wget -q -T 3 -O- http://guestbook/ | grep -oE "<title>[^<]+</title>|Pod/Host: [a-zA-Z0-9-]+"'
<title>InhaTC DevOps 방명록</title>
Pod/Host: guestbook-74f4cd9bb-5p865
```

---

## 오브젝트 관계도 (요약)

```
kubectl apply -f week09/...
      │
      ├─▶ [Deployment: guestbook]        [Service: guestbook]
      │     replicas: 2, image: v1         type: NodePort
      │          │                         selector: app=guestbook
      │          ▼                              │ 레이블로 찾아서 요청 분배
      │     [ReplicaSet]                         │
      │     개수 유지                             │
      │          ▼                              │
      │     [Pod] app=guestbook   [Pod] app=guestbook ◀──┘
```

- 작성한 파일 2개: [deployment.yaml](./deployment.yaml), [service.yaml](./service.yaml)
- 확인한 핵심 오브젝트 5개: Deployment, ReplicaSet, Pod 2개, Service

---

## 고민거리 (다음 시간으로 이어짐)

- `deployment.yaml`에 DB 비밀번호 같은 값을 그대로 적어서 GitHub에 올리면 전 세계에 비밀번호를 공개하는 셈 → ConfigMap/Secret이 필요해 보인다.
- "앱은 살아있지만 응답을 못 하는 상태"(예: 커넥션 풀 고갈)는 쿠버네티스가 어떻게 알아챌 수 있을까 → 헬스체크(liveness/readiness probe)가 필요해 보인다.

## 환경 정리

실습이 끝난 뒤 생성한 리소스를 지우고 클러스터를 내렸다 (10주차 실습에 영향 없도록).

```bash
$ kubectl delete -f service.yaml -f deployment.yaml
$ minikube stop
```
