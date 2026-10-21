#!/bin/bash
# ============================================
# week07: web 서비스를 항상 3개로 유지하는 감시 스크립트
# 사용법: ./watch_web.sh
# ============================================

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
