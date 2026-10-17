#!/usr/bin/env bash
set -euo pipefail

backend_port=8080
frontend_port=8081
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backend_path="$repository_root/backend"
frontend_path="$repository_root/frontend"
log_dir="${TMPDIR:-/tmp}/stela-new-server-logs"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        if ! command -v powershell.exe >/dev/null 2>&1; then
            echo "PowerShell was not found. Run restart_servers.ps1 from Windows instead." >&2
            exit 1
        fi

        if command -v cygpath >/dev/null 2>&1; then
            windows_script="$(cygpath -w "$repository_root/restart_servers.ps1")"
        else
            windows_script="$repository_root/restart_servers.ps1"
        fi

        exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$windows_script"
        ;;
esac

if ! command -v lsof >/dev/null 2>&1; then
    echo "Required command 'lsof' was not found on PATH. Install lsof or run this on Windows through Git Bash so port cleanup can use PowerShell." >&2
    exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
    echo "Required command 'flutter' was not found on PATH." >&2
    exit 1
fi

if ! command -v nohup >/dev/null 2>&1; then
    echo "Required command 'nohup' was not found on PATH." >&2
    exit 1
fi

if command -v python3 >/dev/null 2>&1; then
    python_command="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    python_command="$(command -v python)"
else
    echo "Required command 'python3' or 'python' was not found on PATH." >&2
    exit 1
fi

for path in "$backend_path" "$frontend_path"; do
    if [[ ! -d "$path" ]]; then
        echo "Expected project directory was not found: $path" >&2
        exit 1
    fi
done

listener_pids() {
    lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
}

stop_port_listeners() {
    local port="$1"
    local pids
    local pid
    local attempt

    pids="$(listener_pids "$port")"
    if [[ -z "$pids" ]]; then
        return
    fi

    while IFS= read -r pid; do
        [[ -z "$pid" ]] && continue
        echo "Stopping PID $pid using port $port..."
        if ! kill -TERM "$pid"; then
            echo "Could not stop PID $pid using port $port; check permissions." >&2
            return 1
        fi
    done <<< "$pids"

    for ((attempt = 0; attempt < 20; attempt++)); do
        [[ -z "$(listener_pids "$port")" ]] && return
        sleep 0.25
    done

    pids="$(listener_pids "$port")"
    if [[ -n "$pids" ]]; then
        while IFS= read -r pid; do
            [[ -z "$pid" ]] && continue
            echo "Force-stopping PID $pid still using port $port..."
            if ! kill -KILL "$pid"; then
                echo "Could not stop PID $pid using port $port; check permissions." >&2
                return 1
            fi
        done <<< "$pids"
    fi

    sleep 0.25
    if [[ -n "$(listener_pids "$port")" ]]; then
        echo "Port $port is still in use; check permissions and retry." >&2
        return 1
    fi
}

stop_port_listeners "$backend_port"
stop_port_listeners "$frontend_port"
mkdir -p "$log_dir"

(
    cd "$backend_path"
    exec nohup "$python_command" -m flask run --host=127.0.0.1 --port="$backend_port"
) >"$log_dir/backend.log" 2>&1 </dev/null &
backend_pid=$!

(
    cd "$frontend_path"
    exec nohup flutter run -d web-server --web-hostname 127.0.0.1 \
        --web-port "$frontend_port" \
        --dart-define="CODE_EXEC_ENDPOINT=http://127.0.0.1:$backend_port/execute"
) >"$log_dir/frontend.log" 2>&1 </dev/null &
frontend_pid=$!

sleep 1
if ! kill -0 "$backend_pid" 2>/dev/null; then
    echo "Backend failed to start. See $log_dir/backend.log" >&2
    exit 1
fi
if ! kill -0 "$frontend_pid" 2>/dev/null; then
    echo "Frontend failed to start. See $log_dir/frontend.log" >&2
    exit 1
fi

echo "Backend starting at http://127.0.0.1:$backend_port (PID $backend_pid)"
echo "Frontend starting at http://127.0.0.1:$frontend_port (PID $frontend_pid)"
echo "Logs: $log_dir"
