#!/bin/bash
# Quick 빌드 + 실행 (백그라운드)
cd "$(dirname "$0")"
pkill -f "Quick.app" 2>/dev/null
sleep 0.3
bash build.sh direct 2>&1 | grep -E "error:|✅|❌"
if [ $? -eq 0 ]; then
    open build/Quick.app
    echo "Quick 실행됨"
fi
