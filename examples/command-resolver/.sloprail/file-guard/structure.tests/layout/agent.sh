#!/usr/bin/env bash
# A scripted agent: writes files where the layout allows them and where it does not.
n=$(grep -c "\"tool_result\"" "$A10N_MOCK_SESSION_FILE" 2>/dev/null); n=${n:-0}
tu() { jq -nc --arg id "$1" --arg name "$2" --argjson input "$3" '{type:"assistant",uuid:("u-"+$id),message:{role:"assistant",stop_reason:null,content:[{type:"tool_use",id:$id,name:$name,input:$input}]}}'; }
write_() { tu "$1" Write "$(jq -nc --arg p "$2" --arg c "$3" '{file_path:$p,content:$c}')"; }
case $n in
  0) write_ ok-cmd cmd/resolve/main.go "package main" ;;
  1) write_ ok-code internal/words/split.go "package words" ;;
  2) write_ ok-test internal/words/split_test.go "package words" ;;
  3) write_ ok-module internal/words/module.yaml "concern: words" ;;
  4) write_ ok-nested internal/words/quote/quote.go "package quote" ;;
  5) write_ ok-gomod go.mod "module resolver" ;;
  6) write_ no-pkg pkg/words/split.go "package words" ;;
  7) write_ no-root main.go "package main" ;;
  8) write_ no-script scripts/build.sh "go build" ;;
  9) write_ no-testdata internal/words/testdata/cases.json "[]" ;;
  10) write_ no-case internal/Words/split.go "package words" ;;
  11) write_ no-doc docs/NOTES.md "notes" ;;
  12) write_ ok-cases internal/words/testdata/quoting.jsonl "{}" ;;
  13) write_ ok-e2e tests/command-strings/bash_c_test.go "package commandstrings" ;;
  14) write_ ok-e2e-cases tests/words/testdata/quoting.jsonl "{}" ;;
  15) write_ no-e2e-helper tests/words/helper.go "package words" ;;
  16) write_ no-e2e-root tests/all_test.go "package tests" ;;
  17) write_ no-root-testdata testdata/cases.jsonl "{}" ;;
  *) echo '{"type":"result","subtype":"success","result":"done","is_error":false}' ;;
esac
