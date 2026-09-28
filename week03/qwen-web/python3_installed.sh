cd "$(dirname "$0")" || exit 1

if ! command -v python3 > /dev/null 2>&1; then
# !는 조건의 결과를 반전시키는 연산자
# command -v python3는 python3라는 명령어가 현재 실행 가능한지 확인
# 위 명령어를 실행하면 python3가 어디에 있는지 출력됨
# 만약 없다면 아무것도 출력하지 않고 실패 상태를 반환함
# 하지만 ! 때문에 이 경우에는 python3 명령어를 찾을 수 없는 게 참
# > /dev/null: 표준 출력 버리기
# 2>&1: 표준 에러도 표준 출력과 같은 곳으로 보내기
# 결국 표준 출력과 표준 에러를 같이 버리는 코드
	eho "Python3를 먼저 설치하세요." >&2
	exit 1
fi
exec python3 chat.py
