cat >myscript.sh <<'EOF'
#!/usr/bin/env bash

clean() {
    local a=${1//[^[:alnum:]]/}
    echo "${a,,}"
}
EOF

clean '"kind-"-("controller") & echo "kind-"-(worker-1 worker-2)'
