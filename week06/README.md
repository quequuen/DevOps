## 6주차 정리 (Dockerfile, 이미지 빌드)

실습 대상 앱: [guestbook/](../guestbook/) (방명록 Flask 앱)

### 내 이미지 주소

> TODO: `docker login ghcr.io` 후 아래 명령으로 올리고 실제 주소로 교체
> ```bash
> docker tag guestbook:v1 ghcr.io/quequuen/guestbook:v1
> docker push ghcr.io/quequuen/guestbook:v1
> ```
> 현재는 로컬에서만 `guestbook:v1`로 빌드·실행을 확인한 상태.

### 친구 이미지를 실행한 결과

> TODO: 친구의 `ghcr.io/.../guestbook:v1` 이미지를 `docker pull` 후 실행해서 화면 캡처 첨부

### Dockerfile 한 줄씩 설명 (내 언어로)

```dockerfile
FROM python:3.12-slim          # ① 베이스 이미지. Python 3.12가 이미 깔린 가벼운(slim) 리눅스 위에서 시작
WORKDIR /app                   # ② 컨테이너 안에서 이후 명령이 실행될 작업 폴더를 /app으로 고정
COPY requirements.txt .        # ③ 의존성 목록만 먼저 복사 (전체 코드를 복사하기 전 단계)
RUN pip install --no-cache-dir -r requirements.txt
                                # ④ requirements.txt에 적힌 패키지(Flask, redis 등) 설치. 레이어 캐시를 쓰려고 ③과 분리해둔 것
COPY . .                       # ⑤ 나머지 소스 코드 전체를 /app으로 복사
RUN useradd -m appuser         # ⑥ root가 아닌 일반 사용자(appuser) 생성 — 보안상 컨테이너를 root로 띄우지 않기 위함
USER appuser                   # ⑦ 이후 명령/컨테이너 실행을 appuser 권한으로 전환
ENV APP_TITLE="InhaTC DevOps 방명록" \
    THEME_COLOR="#0054A6"      # ⑧ 이미지에 기본값으로 박아둘 환경 변수 (코드 기본값보다 우선, docker run -e 보다는 후순위)
EXPOSE 5000                    # ⑨ 컨테이너가 5000번 포트를 쓴다는 "문서화" (실제 포트 연결은 docker run -p가 함)
CMD ["python", "app.py"]       # ⑩ 컨테이너가 시작될 때 실행할 기본 명령
```

- 순서를 **거의 안 바뀌는 것(FROM, WORKDIR, requirements 설치)** → **자주 바뀌는 것(COPY . .)** 순으로 둔 이유: Dockerfile은 위에서부터 한 줄씩 레이어를 쌓는데, 중간에 바뀐 줄부터는 캐시가 깨지고 그 아래 줄은 전부 다시 실행된다. 코드(`app.py`)는 자주 바뀌지만 `requirements.txt`는 거의 안 바뀌므로, 의존성 설치를 먼저 하고 코드 복사를 뒤에 둬야 코드만 고쳤을 때 `pip install`을 매번 새로 돌리지 않는다.

### 빌드 캐시가 동작한 로그 (CACHED)

처음 빌드(`docker build -t guestbook:v1 .`) 후 코드를 바꾸지 않고 다시 빌드하면, `requirements.txt`가 그대로이므로 설치 단계까지 전부 캐시에서 재사용된다.

```
#6 [3/6] COPY requirements.txt .
#6 CACHED

#7 [4/6] RUN pip install --no-cache-dir -r requirements.txt
#7 CACHED

#8 [5/6] COPY . .
#8 CACHED

#9 [2/6] WORKDIR /app
#9 CACHED

#10 [6/6] RUN useradd -m appuser
#10 CACHED
```

→ `docker run -d -p 8080:5000 --name guestbook guestbook:v1`로 실행해 `http://localhost:8080`에서 정상 동작(제목, 저장소: Memory, 방문 횟수 표시)까지 로컬에서 확인했다.

### 설정을 넣는 세 가지 방법 비교

| 방법 | 언제 확정되는가 | 바꾸려면 |
| --- | --- | --- |
| `app.py` 기본값 수정 (`os.environ.get("APP_TITLE", "DevOps 방명록")`의 기본값) | 코드 작성 시점 | 코드 수정 후 재빌드 필요 |
| `Dockerfile`의 `ENV` | 이미지 빌드 시점 | 이미지 재빌드 필요 |
| `docker run -e` | 컨테이너 실행 시점 | 컨테이너만 다시 실행하면 됨 (재빌드 불필요) |

우선순위는 `코드 기본값 < Dockerfile ENV < docker run -e` 순으로, 나중에 적용되는 설정이 앞의 값을 덮어쓴다. 이 구조는 이후 k8s의 ConfigMap과 같은 역할을 환경 변수 수준에서 미리 체험한 것이라고 이해했다.

### 기록 (git tag)

`guestbook/`은 이후 주차에서 계속 고쳐나갈 예정이라, 6주차 시점 상태를 `git tag week06`으로 남겨두고 문제가 생기면 `git restore --source=week06 guestbook/`으로 되돌릴 수 있게 했다.
