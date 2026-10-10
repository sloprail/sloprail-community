#!/usr/bin/env bash
# A scripted agent: tries to write each kind of given file, then a code file, then to delete an invariant.
n=$(grep -c "\"tool_result\"" "$A10N_MOCK_SESSION_FILE" 2>/dev/null); n=${n:-0}
tu() { jq -nc --arg id "$1" --arg name "$2" --argjson input "$3" '{type:"assistant",uuid:("u-"+$id),message:{role:"assistant",stop_reason:null,content:[{type:"tool_use",id:$id,name:$name,input:$input}]}}'; }
write_() { tu "$1" Write "$(jq -nc --arg p "$2" --arg c "$3" '{file_path:$p,content:$c}')"; }
case $n in
  0) write_ w-spec spec/words/invariants/a.yaml 'predicate: weaker' ;;
  1) write_ w-new spec/words/invariants/new.yaml 'predicate: new' ;;
  2) write_ w-adr adr/file-size/ADR.md 'limits: {go: 9999}' ;;
  3) write_ w-config config/builtin.yaml 'wrappers: []' ;;
  4) write_ w-claude CLAUDE.md 'anything goes' ;;
  5) write_ w-rule .sloprail/gate/givens-frozen/gate.yaml 'on: []' ;;
  6) write_ w-code internal/words/a.go 'package words' ;;
  7) write_ w-readme README.md 'notes' ;;
  8) tu d-spec Bash '{"command":"rm spec/words/invariants/a.yaml"}' ;;
  *) echo '{"type":"result","subtype":"success","result":"done","is_error":false}' ;;
esac
