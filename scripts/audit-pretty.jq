# One coloured line per completed request: time  status  op  path  identity  policies
def c(code; s): "\u001b[\(code)m\(s)\u001b[0m";
(fromjson? // empty)
| select(.type == "response")
| (.error // (if .response.data.error then "request rejected (see raw log)" else "" end)) as $err
# The response record (not the request) carries the final outcome and the resolved identity.
| (.auth // {}) as $a
| ($a.metadata // {}) as $m
| (if $m.service_account_namespace then "\($m.service_account_namespace)/\($m.service_account_name)"
   elif $m.pod_name then "\($m.namespace)/\($m.pod_name) (pod)"
   else ($a.display_name // "-") end) as $who
# Denials, not errors, are the interesting signal for policy work, so they get their own colour.
| (if $err == "" then c("32"; "OK  ")
   elif ($err | test("permission denied")) then c("31"; "DENY")
   else c("33"; "ERR ") end) as $st
| "\(.time[11:19])  \($st)  \(.request.operation | .[0:6] | . + (" " * (6 - length)))  \(.request.path)  \(c("36"; $who))  \(c("2"; (($a.policies // []) | join(","))))"
  + (if $err != "" and ($err | test("permission denied") | not) then "  " + c("33"; ($err | gsub("\n|\t"; " ") | .[0:80])) else "" end)
