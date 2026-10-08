#!/bin/sh
cat > /dev/null
echo '{"reason":"SMOKE-NO-RM: do not delete with rm in this project. Use `git rm <path>` so the deletion is tracked."}'
exit 1
