## 4주차 정리 (자동화와 협업)

### 경로와 파일 찾기
- 절대 경로(`/`로 시작)와 상대 경로(`.`, `..`, `~` 기준)를 구분해서 사용
- `find . -type f -name "*.sh"` : 현재 디렉터리 아래에서 이름이 `.sh`로 끝나는 **파일**만 재귀적으로 탐색
  - `-type f`는 파일, `-type d`는 디렉터리만 걸러줌
- `grep -R -n "exit 1" week04 2>/dev/null` : week04 디렉터리 아래를 재귀적으로(`-R`) 뒤져서 `exit 1`이 들어간 줄을 줄 번호(`-n`)와 함께 출력
  - `2>/dev/null`로 권한 에러 같은 표준 에러 출력은 버림
- 파이프(`|`)는 앞 명령의 표준 출력을 뒤 명령의 표준 입력으로 그대로 이어주는 것
  - `grep -R "exit 1" week04 2>/dev/null | wc -l` 처럼 grep 결과를 `wc -l`로 넘겨 줄 수를 셀 수 있음

### 로그 필터링 (`server.log` 실습)
- `grep "ERROR" server.log` : ERROR가 들어간 줄만 출력
- `grep -i "error" server.log` : 대소문자 구분 없이 검색(`-i`)
- `grep -c "ERROR" server.log` : 개수만 출력(`-c`)
- `grep -v "INFO" server.log` : INFO가 **없는** 줄만 반전 출력(`-v`)
- `grep ERROR server.log > errors.txt` : 결과를 파일로 저장(리다이렉션) → [errors.txt](./errors.txt)
- `head -2`, `tail -1`, `wc -l`로 파일의 앞/뒤/전체 줄 수 확인

### 변수와 조건문
- `USERNAME="홍길동"`처럼 `=` 양옆에 공백 없이 변수 지정, `$USERNAME`으로 값 꺼내 쓰기
- `$(date +%Y%m%d)` 같은 **명령어 치환**으로 명령 실행 결과를 변수에 담을 수 있음
- `if [ $# -eq 0 ]; then ... fi` : 스크립트에 넘긴 인자 개수(`$#`)로 분기, `[ ]` 안쪽은 꼭 공백 필요
- `-f`(파일 존재), `-d`(디렉터리 존재), `-z`(문자열 길이 0), `-eq/-ne/-gt/-lt` 같은 조건 연산자로 파일/숫자 검사
- `for f in *.sh; do echo "$f"; done` 형태의 반복문으로 여러 파일을 순회

### 프로세스와 백업 스크립트
- 프로그램(디스크에 저장된 코드)과 프로세스(실행 중인 프로그램)의 차이 학습
- `ps aux`, `htop`으로 실행 중인 프로세스 확인, `kill <PID>`(SIGTERM, 정상 종료 요청) / `kill -9 <PID>`(SIGKILL, 강제 종료) 차이
- 위 내용을 묶어서 [backup.sh](./03_자동화와_협업_코드/backup.sh)를 작성
  - 인자로 받은 폴더(없으면 `test`)를 `tar -czf`로 압축해 `backups/`에 저장
  - 압축 성공 여부를 `$?`로 확인하고, 실패하면 `exit 1`
  - `backups/`, `restore-check/`처럼 실습 중 생기는 산출물은 `.gitignore`에 등록해 Git 추적에서 제외

### Git 협업 흐름 (브랜치 → 커밋/푸시 → PR → Merge)
같은 저장소를 여러 사람이 동시에 고칠 때 바로 main에 수정하지 않고 아래 순서로 진행:
1. `git switch -c feature/기능명` 으로 main에서 안전하게 분리된 새 브랜치 생성
2. 브랜치에서 작업하고 `git status`, `git diff`로 변경 내용을 확인한 뒤 `git add` → `git commit -m "메시지"`
3. `git push -u origin feature/기능명` 으로 원격 저장소에 브랜치 올리기
4. `gh pr create --base main --head feature/기능명` 으로 Pull Request 생성 → 코드 리뷰가 끝나면 `gh pr merge --squash --delete-branch`로 main에 합치고 브랜치 정리
5. 같은 파일을 여러 브랜치에서 동시에 고치면 **Conflict**가 발생할 수 있는데, 충돌 표시(`<<<<<<<`, `=======`, `>>>>>>>`)를 직접 보고 남길 내용을 정해 다시 커밋해야 함

이 흐름은 [week06](../week06/README.md)에서 다룬 Issue → 브랜치 → PR → Merge 실습(#1, #2)에 그대로 이어서 사용했다.
