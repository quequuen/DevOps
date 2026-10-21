## 7주차 정리 (Docker Compose) — "web=3을 항상 유지하려면?" 호기심 문제

### 구성

[docker-compose.yml](./docker-compose.yml)으로 `guestbook` 앱을 `web` 서비스로, `redis`를 저장소로 함께 띄운다.

```yaml
services:
  web:
    build: ../guestbook
    environment:
      - REDIS_HOST=redis
    expose:
      - "5000"
    restart: unless-stopped
    depends_on:
      - redis
    deploy:
      replicas: 3

  redis:
    image: redis:7-alpine
    restart: unless-stopped
```

- 여러 개를 동시에 띄워야 하므로 `web`에는 호스트 포트를 고정하는 `ports: "8080:5000"` 대신 컨테이너 간에만 노출하는 `expose`를 사용했다. (포트를 고정하면 2번째 컨테이너부터 포트 충돌로 못 뜸)
- 외부에서 접속하려면 앞단에 nginx 같은 리버스 프록시/로드밸런서를 추가해 `web` 3개로 요청을 분산시켜야 한다. (이 실습에서는 "3개 유지"에 집중하고 프록시는 생략)

### 방법 1 — `deploy.replicas` + `restart: unless-stopped`

```bash
docker compose up -d
docker compose ps web
```

직접 실행해서 확인한 결과:

```
NAME           IMAGE        SERVICE   STATUS
week07-web-1   week07-web   web       Up
week07-web-2   week07-web   web       Up
week07-web-3   week07-web   web       Up
```

- Compose v2는 Swarm 없이도 `deploy.replicas: 3`을 그대로 읽어서 `web` 컨테이너 3개를 만들어준다.
- `restart: unless-stopped`는 컨테이너 **안의 프로세스가 죽거나 컨테이너가 죽었을 때** 같은 컨테이너를 다시 살려준다.

### 방법 1의 한계를 직접 실험해서 확인

| 실험 | 명령 | 결과 |
| --- | --- | --- |
| 프로세스/컨테이너가 죽는 경우 | `docker kill week07-web-2` | 몇 초 뒤 `restart` 정책이 **같은 컨테이너**를 자동으로 재시작 → 계속 3개 |
| 컨테이너 자체가 삭제되는 경우 | `docker rm -f week07-web-3` | `restart` 정책이 적용될 컨테이너가 아예 없어짐 → **2개로 줄어든 채 복구되지 않음** |
| 다시 원하는 개수로 맞추기 | `docker compose up -d` | `deploy.replicas: 3` 기준으로 부족한 만큼(1개) 다시 생성 → 3개로 복구 |

→ **`restart` 정책만으로는 "항상 3개"를 보장하지 못한다.** 컨테이너가 죽는(died) 경우는 막아주지만, 컨테이너가 아예 제거되는 경우는 `docker compose up -d`를 다시 실행해줘야 개수가 맞춰진다.

### 방법 2 — 지금까지 배운 셸 스크립트로 직접 감시하기

4주차에 배운 `while`/조건문/`docker ps`와 5~6주차에 배운 docker 명령어를 조합해, 컨테이너가 통째로 사라지는 경우까지 자동으로 복구하는 감시 스크립트를 작성했다. → [watch_web.sh](./watch_web.sh)

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

`--no-recreate` 옵션으로 이미 멀쩡히 떠 있는 컨테이너는 건드리지 않고, 부족한 개수만 새로 만든다.

### 가산점 — 각 방법의 장단점과 한계

| 방법 | 장점 | 단점 / 한계 |
| --- | --- | --- |
| `restart: unless-stopped` | 설정 한 줄로 끝남, Compose 기본 기능이라 추가 코드 불필요 | 컨테이너 자체가 삭제되면 무력함(위 실험으로 확인). 노드(호스트)가 죽는 경우도 대응 못 함 |
| `deploy.replicas: 3` | "항상 3개"라는 의도를 선언적으로 표현 가능, `docker compose up -d`를 다시 실행하면 즉시 수량 재조정 | 선언만으로는 **계속 감시**해주지 않음 — 누군가/무언가 다시 `up`을 실행해줘야 반영됨. 포트를 고정해서 쓰던 습관(`ports:`)을 못 쓰게 되어 로드밸런서가 별도로 필요 |
| `watch_web.sh` 감시 스크립트 | 지금까지 배운 셸/도커 명령만으로 구현 가능, 컨테이너 삭제까지 자동 복구 | 사실상 미니 오케스트레이터를 직접 만드는 것 — 스크립트 자체가 죽으면 소용없고(스크립트를 감시할 것이 또 필요), 여러 요청을 3개 컨테이너에 고르게 분산해주는 기능(로드밸런싱)은 별도로 없음, 폴링 주기(10초) 동안의 공백은 못 막음 |

종합하면, 지금까지 배운 도구(Compose 옵션 + 셸 스크립트)로는 "짧은 공백을 감수한 자동 복구"까지는 가능하지만, 무중단으로 정확히 3개를 계속 유지하고 트래픽까지 분산해주는 것은 뒤에 배울 Kubernetes의 Deployment/ReplicaSet 같은 전용 오케스트레이터의 역할이라는 것을 실험을 통해 체감했다.
