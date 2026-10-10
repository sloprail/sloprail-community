#!/usr/bin/env bash
# A scripted agent: commits a code file and ends the turn; told to run the checks, runs them and ends again.
n=$(grep -c "\"tool_result\"" "$A10N_MOCK_SESSION_FILE" 2>/dev/null); n=${n:-0}
tu() { jq -nc --arg id "$1" --arg c "$2" '{type:"assistant",uuid:("u-"+$id),message:{role:"assistant",stop_reason:null,content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'; }
done_() { echo '{"type":"result","subtype":"success","result":"done","is_error":false}'; }
case $n in
  0) tu commit 'mkdir -p internal/words && printf "package words\n" > internal/words/a.go && git add -A && git -c user.name=t -c user.email=t@t commit -q -m code' ;;
  1) if grep -q 'sr-checks run --base' "$A10N_MOCK_SESSION_FILE"; then tu run 'sr-checks run --base "$(git log -1 --format=%H -- .sloprail)" --head HEAD'; else done_; fi ;;
  *) done_ ;;
esac
