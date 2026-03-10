#!/usr/bin/env zsh
# auto-forward-ports: Monitor a remote host for new listening ports
# and automatically set up SSH local port forwards.
#
# Usage: auto-forward-ports <host> [poll_interval]
#   host           SSH host to monitor (e.g. aspen, pika)
#   poll_interval  seconds between checks (default: 5)

setopt no_unset pipe_fail

if [[ $# -lt 1 ]]; then
    echo "Usage: auto-forward-ports <host> [poll_interval]"
    echo "  host           SSH host to monitor (e.g. aspen, pika)"
    echo "  poll_interval  seconds between checks (default: 5)"
    exit 1
fi

REMOTE_HOST="$1"
POLL_INTERVAL="${2:-5}"

STATE_DIR=$(mktemp -d "/tmp/auto-forward-ports.${REMOTE_HOST}.XXXXXX")

# Store port -> process description for display
typeset -A port_desc

# Event log (recent events)
typeset -a event_log

log_event() {
    local msg="$1"
    event_log+=("$(date '+%H:%M:%S') $msg")
    # Keep last 5 events
    if (( ${#event_log} > 5 )); then
        shift event_log
    fi
}

# Terminal formatting
bold=$'\e[1m'
dim=$'\e[2m'
green=$'\e[32m'
yellow=$'\e[33m'
red=$'\e[31m'
cyan=$'\e[36m'
reset=$'\e[0m'

cleanup() {
    # Show cursor, clear screen
    printf '\e[?25h'
    echo ""
    echo "${bold}Shutting down all forwards...${reset}"
    for f in "$STATE_DIR"/*(.N); do
        local port=$(basename "$f")
        local pid=$(cat "$f")
        kill "$pid" 2>/dev/null && echo "  ${red}Stopped${reset} port $port"
    done
    rm -rf "$STATE_DIR"
    exit 0
}
trap cleanup INT TERM

get_remote_ports() {
    ssh "$REMOTE_HOST" '
        summarize_cmd() {
            local cmd="$1"
            local exe=$(echo "$cmd" | awk "{print \$1}")
            local base=$(basename "$exe" 2>/dev/null)
            case "$base" in
                python|python3|python3.*)
                    local script=$(echo "$cmd" | awk "{for(i=2;i<=NF;i++){if(\$i !~ /^-/){print \$i;exit}}}")
                    if [ -n "$script" ]; then
                        base=$(basename "$script" .py)
                    fi
                    ;;
                java)
                    local jar=$(echo "$cmd" | grep -oP "(?<=-jar )\S+" | head -1)
                    if [ -n "$jar" ]; then
                        base="java:$(basename "$jar")"
                    fi
                    ;;
            esac
            local args=$(echo "$cmd" | tr " " "\n" | awk "
                NR==1 {next}
                grab_next {printf \" %s\", \$0; grab_next=0; next}
                /^(--logdir|--logdir_spec|--port)\$/ {printf \" %s\", \$0; grab_next=1; next}
                /^(--logdir|--logdir_spec|--port)=/ {printf \" %s\", \$0; next}
                /^(--bind_all|edit|--watch)\$/ {printf \" %s\", \$0; next}
                /^\// && !/^-/ && !/\\.cache/ && !/\\.venv/ && !/runfiles/ {
                    n=split(\$0,p,\"/\")
                    if(n>2) printf \" .../%s/%s\", p[n-1], p[n]
                    else printf \" %s\", \$0
                }
                /^~/ {printf \" %s\", \$0}
            ")
            printf "%s%s" "$base" "$args"
        }

        ss -tlnp 2>/dev/null | awk "/LISTEN/ {print}" | while IFS= read -r line; do
            addr=$(echo "$line" | awk "{split(\$4,a,\":\"); print a[length(a)]}")
            [ -z "$addr" ] && continue

            procs=""
            for pid in $(echo "$line" | grep -oP "pid=\K[0-9]+" 2>/dev/null); do
                cmd=$(tr "\0" " " < /proc/$pid/cmdline 2>/dev/null | sed "s/ *$//")
                if [ -n "$cmd" ]; then
                    short=$(summarize_cmd "$cmd")
                    [ -n "$procs" ] && procs="$procs, "
                    procs="${procs}${short}"
                fi
            done

            printf "%s\t%s\n" "$addr" "$procs"
        done
    ' 2>/dev/null | sort -t'	' -k1 -un
}

start_forward() {
    local port=$1
    local proc=$2
    if (( port < 1024 )); then
        return
    fi
    ssh -N -L "${port}:localhost:${port}" "$REMOTE_HOST" 2>/dev/null &
    local pid=$!
    echo "$pid" > "$STATE_DIR/$port"
    port_desc[$port]="$proc"
    log_event "${green}+${reset} port ${bold}${port}${reset} ${dim}${proc}${reset}"
}

stop_forward() {
    local port=$1
    local pid
    pid=$(cat "$STATE_DIR/$port" 2>/dev/null) || return
    if kill "$pid" 2>/dev/null; then
        log_event "${red}-${reset} port ${bold}${port}${reset} ${dim}${port_desc[$port]:-}${reset}"
    fi
    unset "port_desc[$port]"
    rm -f "$STATE_DIR/$port"
}

redraw() {
    local cols=$(tput cols 2>/dev/null || echo 80)
    local now=$(date '+%H:%M:%S')

    # Move to top and clear
    printf '\e[H\e[J'

    # Header
    printf "${bold}  auto-forward-ports${reset} ${dim}─${reset} ${cyan}%s${reset} ${dim}│${reset} %s ${dim}│${reset} polling every %ss\n" \
        "$REMOTE_HOST" "$now" "$POLL_INTERVAL"
    printf "${dim}"
    printf '─%.0s' {1..$cols}
    printf "${reset}\n"

    # Port table
    local count=0
    local sorted_ports=()
    for p in "${(@k)port_desc}"; do
        sorted_ports+=("$p")
    done
    sorted_ports=("${(@on)sorted_ports}")

    if (( ${#sorted_ports} == 0 )); then
        printf "  ${dim}No ports forwarded${reset}\n"
    else
        for port in "${sorted_ports[@]}"; do
            local desc="${port_desc[$port]}"
            local indicator="${green}●${reset}"
            # Check if tunnel is alive
            local spid=$(cat "$STATE_DIR/$port" 2>/dev/null)
            if [[ -n "$spid" ]] && ! kill -0 "$spid" 2>/dev/null; then
                indicator="${yellow}○${reset}"
            fi
            if [[ -n "$desc" ]]; then
                printf "  %s ${bold}%-6s${reset} ${dim}%s${reset}\n" "$indicator" "$port" "$desc"
            else
                printf "  %s ${bold}%-6s${reset}\n" "$indicator" "$port"
            fi
            (( count++ ))
        done
    fi

    # Separator
    printf "${dim}"
    printf '─%.0s' {1..$cols}
    printf "${reset}\n"

    # Event log
    if (( ${#event_log} > 0 )); then
        for evt in "${event_log[@]}"; do
            printf "  ${dim}%s${reset}\n" "$evt"
        done
    else
        printf "  ${dim}Waiting for ports...${reset}\n"
    fi

    # Footer
    printf "\n  ${dim}Ctrl-C to stop${reset}\n"
}

# Hide cursor for cleaner display
printf '\e[?25l'

# Initial draw
redraw

while true; do
    lines=("${(@f)$(get_remote_ports)}")
    current_port_list=()
    changed=0

    for line in "${lines[@]}"; do
        [[ -z "$line" ]] && continue
        local port="${line%%$'\t'*}"
        local proc="${line#*$'\t'}"
        [[ -z "$port" ]] && continue
        current_port_list+=("$port")

        if [[ ! -f "$STATE_DIR/$port" ]]; then
            start_forward "$port" "$proc"
            changed=1
        else
            # Update description in case it changed
            port_desc[$port]="$proc"
            pid=$(cat "$STATE_DIR/$port")
            if ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$STATE_DIR/$port"
                log_event "${yellow}↻${reset} port ${bold}${port}${reset} reconnecting"
                start_forward "$port" "$proc"
                changed=1
            fi
        fi
    done

    for f in "$STATE_DIR"/*(.N); do
        local port=$(basename "$f")
        local found=0
        for cp in "${current_port_list[@]}"; do
            [[ "$cp" = "$port" ]] && found=1 && break
        done
        if (( !found )); then
            stop_forward "$port"
            changed=1
        fi
    done

    redraw

    sleep "$POLL_INTERVAL"
done
