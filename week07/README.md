## 7주차 정리 (Docker Compose)

guestbook 앱을 web 서비스로, redis를 캐시/저장소로, nginx를 문지기(리버스 프록시)로 묶어서 compose.yaml로 관리했다.

### 구성

```yaml
services:
  web:
    build: ../guestbook
    environment:
      APP_TITLE: "방명록"
      REDIS_HOST: "redis"
      REDIS_PORT: "6379"
      REDIS_PASSWORD: "${REDIS_PASSWORD:?비밀번호 설정 필요}"
    expose:
      - "5000"
    depends_on:
      redis:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "python", "-c",
        "import urllib.request; urllib.request.urlopen('http://localhost:5000/readyz')"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}", "--appendonly", "yes"]
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      web:
        condition: service_healthy
    restart: unless-stopped

volumes:
  redis-data:
```

- `web`은 여러 개로 띄울 거라 `ports` 대신 `expose`만 썼다. 바깥 포트(8080)는 `nginx`만 가진다.
- `REDIS_HOST: "redis"`처럼 **서비스 이름을 그대로 호스트명으로** 쓸 수 있다. 같은 네트워크 안에서는 컴포즈가 내부 DNS로 서비스 이름을 컨테이너 IP로 바꿔준다.
- `.env`에 `REDIS_PASSWORD`를 넣고 `compose.yaml`에는 `${REDIS_PASSWORD}`만 적었다. **`.env`는 `.gitignore`에 넣어서 Git에 올라가지 않게 했다** — 비밀번호를 코드에 그대로 적으면 저장소 기록(히스토리)에 영원히 남을 수 있기 때문이다. 팀원에게 "뭘 채워야 하는지"만 알려주려고 값 없는 `.env.example`은 커밋했다.
- `depends_on: condition: service_healthy` — redis가 "시작"만 해놓고 아직 준비가 안 됐을 때 web이 바로 연결을 시도하다 실패하는 걸 막으려고, healthcheck가 `healthy`가 될 때까지 다음 서비스를 기다리게 했다.

### nginx.conf

```nginx
server {
    listen 80;
    resolver 127.0.0.11 valid=5s;

    location / {
        set $backend http://web:5000;
        proxy_pass $backend;
    }
}
```

`web`을 여러 개 띄우면 도커 내부 DNS가 `web`이라는 이름에 여러 컨테이너 IP를 돌려준다. nginx가 요청이 올 때마다 그 이름을 다시 찾아서(=`resolver`) 그때그때 살아있는 web 중 하나에 넘겨준다.

### 혼자 해보기 — 실제로 확인한 내용

**1) `docker compose ps` 결과 (healthy 포함)**
```
NAME             IMAGE            SERVICE   STATUS
week07-nginx-1   nginx:alpine     nginx     Up
week07-redis-1   redis:7-alpine   redis     Up (healthy)
week07-web-1     week07-web       web       Up (healthy)
week07-web-2     week07-web       web       Up (healthy)
week07-web-3     week07-web       web       Up (healthy)
```

**2) scale 후 호스트명이 바뀌는 것 확인**

`docker compose up -d --scale web=3` 으로 web을 3개 띄운 뒤 `http://localhost:8080`을 새로고침하면, 화면의 `Pod/Host`가 새로고침마다 바뀐다 (nginx가 서로 다른 web 컨테이너로 요청을 보내는 것). 글 목록은 어느 web으로 가도 똑같이 보이는데, 데이터가 컨테이너 안이 아니라 공용 redis 한 곳에 있기 때문이다.

**3) `down` vs `down -v` 차이**

| 명령 | 컨테이너/네트워크 | 볼륨(redis 데이터) |
| --- | --- | --- |
| `docker compose down` | 삭제됨 | **남아있음** |
| `docker compose down -v` | 삭제됨 | **같이 삭제됨** |

직접 해보니 `down`만 했을 때는 다시 `up`해도 방명록 글이 그대로 남아있었고, `down -v`로 지운 뒤에는 글이 전부 사라졌다. `-v`는 볼륨까지 지우는 옵션이라, 운영 환경에서 실수로 쓰면 데이터가 통째로 날아갈 수 있어 조심해야 한다.

**4) `.env`를 Git에 올리지 않는 이유**

`.env`에는 `REDIS_PASSWORD` 같은 실제 비밀번호가 평문으로 들어있다. 이 파일을 커밋하면 비밀번호가 저장소 기록에 영구히 남고, 나중에 파일에서 지워도 Git 히스토리를 뒤지면 그대로 복구할 수 있다. 그래서 값이 든 `.env`는 `.gitignore`로 제외하고, 어떤 변수를 채워야 하는지만 보여주는 `.env.example`(값은 "비밀번호" 같은 더미)만 커밋했다.

---

## [07. 도커 컴포즈 호기심 문제] web=3을 항상 유지하는 방법

PDF 48쪽 "호기심 - web 하나를 멈추면?"에서 던진 질문을 그대로 가져왔다.

> 다시 3개로 돌리는 방법은? → 사람이 직접 `docker compose up -d --scale web=3` 입력
> 그런데 서버 자체가 고장 나거나, 원하는 컨테이너 수가 유지되지 않는 경우에는? → **다음 시간에**

"다음 시간에"로 미뤄둔 질문이지만, 아직 그 내용(아마 Kubernetes)을 배우기 전이라 지금까지 배운 것만으로 직접 풀어봤다.

### 방법 1 — `restart: unless-stopped`만 믿어보기 (직접 실험)

| 실험 | 명령 | 결과 |
| --- | --- | --- |
| 프로세스를 강제 종료 | `docker kill week07-web-2` | **자동으로 재시작되지 않음.** `docker events`로 확인해보니 kill → die 이후 재시작 이벤트가 전혀 없었다 |
| 컨테이너 자체를 삭제 | `docker rm -f week07-web-3` | 당연히 복구 안 됨 (컨테이너가 없어졌으니 되살릴 대상도 없음) |
| 다시 3개로 맞추기 | `docker compose up -d --scale web=3` | 그제서야 부족한 만큼 새로 만들어져서 3개로 복구 |

처음엔 `restart: unless-stopped`가 있으니 `docker kill`로 죽여도 알아서 살아날 거라 예상했는데, 실제로 두 번 다시 테스트해봐도 재시작되지 않았다. **"재시작 정책이 있다"는 것과 "항상 3개가 유지된다"는 것은 다른 이야기였다.** 결국 사람이 직접 `--scale web=3`을 다시 입력해줘야 했다.

### 방법 2 — 지금까지 배운 셸 스크립트로 직접 감시하기

4주차에 배운 `while`/조건문/`docker ps`류 명령을 조합해서, web 개수가 3개 밑으로 떨어지면 자동으로 다시 맞춰주는 감시 스크립트를 만들었다. → [watch_web.sh](./watch_web.sh)

```bash
#!/bin/bash
cd "$(dirname "$0")" || exit 1

DESIRED=3
INTERVAL=10

while true; do
  RUNNING=$(docker compose ps -q web | wc -l | tr -d ' ')

  if [ "$RUNNING" -lt "$DESIRED" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') web ${RUNNING}개 실행 중 (목표 ${DESIRED}개) → 재조정"
    docker compose up -d --scale web="$DESIRED" --no-recreate
  fi

  sleep "$INTERVAL"
done
```

의사코드로 요약하면:

```
반복(10초마다):
    현재 떠 있는 web 컨테이너 개수 = docker compose ps로 센다
    만약 현재 개수 < 3 이면:
        docker compose up -d --scale web=3 로 부족한 만큼 다시 생성
```

**실제로 테스트함**: 스크립트를 띄워두고 `docker kill week07-web-1`로 하나를 죽였더니, 아래처럼 10초 안에 스스로 감지하고 복구했다.

```
2026-10-22 21:13:17 web 2개 실행 중 (목표 3개) → 재조정
 Container week07-web-1 Starting
 Container week07-web-1 Started
 Container week07-web-1 Healthy
```

### 가산점 — 각 방법의 장단점과 한계

| 방법 | 장점 | 단점 / 한계 |
| --- | --- | --- |
| `restart: unless-stopped` | 설정 한 줄, Compose 기본 기능 | 이번 실험에서는 `kill`로 죽인 컨테이너조차 자동으로 살아나지 않았음. 컨테이너가 삭제되는 경우는 애초에 대응 불가 |
| `docker compose up -d --scale web=3` (사람이 직접) | 확실하게 원하는 개수로 맞춰짐 | **계속 감시해주는 게 아니라 그 순간 한 번만 맞춰줌.** 누군가 매번 들어와서 다시 입력해야 함 |
| `watch_web.sh` 감시 스크립트 | 지금까지 배운 셸·도커 명령만으로 구현 가능, 사람 없이도 자동 복구 | 사실상 미니 오케스트레이터를 직접 만든 것. 스크립트 자체가 죽으면 무용지물(감시하는 걸 또 감시해야 함), 로드밸런싱은 nginx가 하지만 "몇 개가 떠 있어야 하는지"는 스크립트가 따로 챙겨야 함, 폴링 주기(10초) 동안은 개수가 모자란 채로 방치됨

종합하면, 컴포즈 자체는 "지금 이 순간 몇 개를 띄울지"는 할 수 있어도 "항상 몇 개를 유지할지"는 계속 감시해주지 않는다는 걸 직접 실험으로 확인했다. 셸 스크립트로 그 감시 역할을 흉내 낼 수는 있지만, 스크립트 자체의 생존을 보장하거나 여러 서버에 걸쳐 관리하는 건 못 한다. PDF가 "다음 시간에"로 미뤄둔 이유가 바로 이 지점이고, 아마 Kubernetes의 ReplicaSet/Deployment가 "원하는 개수를 선언하면 계속 그 상태를 유지해주는" 전용 기능으로 이 문제를 해결해줄 거라고 예상한다.
