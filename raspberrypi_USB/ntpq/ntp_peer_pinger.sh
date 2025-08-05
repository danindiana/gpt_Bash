#!/bin/bash

# NTP Recursive Crawler Script - Fixed Version

# Discovers and queries NTP servers recursively to build a network map

# Colors for output

RED='\033[0;31m'

GREEN='\033[0;32m'

YELLOW='\033[1;33m'

BLUE='\033[0;34m'

CYAN='\033[0;36m'

NC='\033[0m' # No Color

# Configuration

MAX_DEPTH=4

MAX_SERVERS=100

TIMEOUT=1200

OUTPUT_FILE="ntp_crawl_results.txt"

VISITED_SERVERS="/tmp/ntp_visited_$$.txt"

SERVER_GRAPH="/tmp/ntp_graph_$$.txt"

# Initial seed servers

SEED_SERVERS=(
    "pool.ntp.org"
    "0.pool.ntp.org"
    "1.pool.ntp.org"
    "2.pool.ntp.org"
    "3.pool.ntp.org"
    "time.nist.gov"
    "time.windows.com"
)

# Check dependencies

check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    for cmd in ntpq ntpdate dig; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed. Please install it first.${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}All dependencies found.${NC}"
}

# Initialize files

initialize_files() {
    > "$VISITED_SERVERS"
    > "$SERVER_GRAPH"
    > "$OUTPUT_FILE"
    echo "NTP Recursive Crawl Results" > "$OUTPUT_FILE"
    echo "Started: $(date)" >> "$OUTPUT_FILE"
    echo "Max Depth: $MAX_DEPTH, Max Servers: $MAX_SERVERS" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
}

# Check if server was already visited

is_visited() {
    local server="$1"
    grep -F -x -q "$server" "$VISITED_SERVERS"
}

# Mark server as visited

mark_visited() {
    local server="$1"
    echo "$server" >> "$VISITED_SERVERS"
}

# Resolve hostname to IP

resolve_hostname() {
    local hostname="$1"
    dig +short "$hostname" | head -1
}

# Query NTP server using ntpdate

query_ntp_server() {
    local server="$1"
    echo -e "${CYAN}Querying NTP server: $server${NC}"
    local ip=$(resolve_hostname "$server")
    if [ -z "$ip" ]; then
        echo -e "${RED}Cannot resolve hostname: $server${NC}"
        return 1
    fi
    echo "Resolved $server -> $ip" >> "$OUTPUT_FILE"
    local result=$(timeout "$TIMEOUT" ntpdate -q "$server" 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Server $server ($ip) is responding${NC}"
        echo "Server: $server ($ip)" >> "$OUTPUT_FILE"
        echo "Query Result:" >> "$OUTPUT_FILE"
        echo "$result" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        local offset=$(echo "$result" | awk '/offset/{print $2}')
        local delay=$(echo "$result" | awk '/delay/{print $2}')
        if [ -n "$offset" ]; then
            echo -e "${BLUE}  Offset: $offset${NC}"
        fi
        if [ -n "$delay" ]; then
            echo -e "${BLUE}  Delay: $delay${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ Server $server ($ip) is not responding${NC}"
        echo "Server: $server ($ip) - FAILED" >> "$OUTPUT_FILE"
        echo "Error: $result" >> "$OUTPUT_FILE"
        echo "---" >> "$OUTPUT_FILE"
        return 1
    fi
}

# Get peer information using ntpq

get_ntp_peers() {
    local server="$1"
    local depth="$2"
    echo -e "${YELLOW}Getting peers from: $server (Depth: $depth)${NC}"
    local peers
    peers=$(timeout "$TIMEOUT" ntpq -p "$server" 2>&1) || {
        echo -e "${RED}Cannot get peer information from $server${NC}"
        return 1
    }
    echo -e "${CYAN}Peer information for $server:${NC}"
    echo "$peers" | head -20
    local peer_list
    peer_list=$(echo "$peers" | awk '
    NR > 2 && NF >= 1 {
        sub(/^[+*#-]/, "", $1)
        if ($1 != "LOCAL" && $1 != ".POOL") print $1
    }')
    echo "Peers found:" >> "$OUTPUT_FILE"
    echo "$peers" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    local new_peers=()
    for peer in $peer_list; do
        if [[ "$peer" =~ ^(127\.|::1|LOCAL|\.POOL)$ ]]; then
            continue
        fi
        echo "$server -> $peer" >> "$SERVER_GRAPH"
        if ! is_visited "$peer"; then
            new_peers+=("$peer")
            echo -e "${GREEN}  Discovered new peer: $peer${NC}"
        fi
    done
    printf '%s\n' "${new_peers[@]}"
}

# Recursive crawl function

crawl_ntp_servers() {
    local depth="$1"
    shift
    local servers=("$@")
    if [ $depth -gt $MAX_DEPTH ]; then
        echo -e "${YELLOW}Maximum depth reached. Stopping recursion.${NC}"
        return
    fi
    local server_count=$(wc -l < "$VISITED_SERVERS")
    if [ $server_count -ge $MAX_SERVERS ]; then
        echo -e "${YELLOW}Maximum server count reached. Stopping recursion.${NC}"
        return
    fi
    echo -e "${BLUE}=== Crawling at depth $depth ===${NC}"
    local next_level_peers=()
    for server in "${servers[@]}"; do
        if is_visited "$server"; then
            echo -e "${YELLOW}Skipping already visited server: $server${NC}"
            continue
        fi
        mark_visited "$server"
        if query_ntp_server "$server"; then
            local peers
            readarray -t peers < <(get_ntp_peers "$server" "$depth")
            for peer in "${peers[@]}"; do
                if [ -n "$peer" ] && ! is_visited "$peer"; then
                    next_level_peers+=("$peer")
                fi
            done
        fi
        sleep 1
    done
    if [ ${#next_level_peers[@]} -gt 0 ] && [ $depth -lt $MAX_DEPTH ]; then
        crawl_ntp_servers "$((depth + 1))" "${next_level_peers[@]}"
    fi
}

# Generate summary report

generate_summary() {
    echo -e "${YELLOW}=== Generating Summary Report ===${NC}"
    local total_servers
    total_servers=$(wc -l < "$VISITED_SERVERS")
    local responding_servers
    responding_servers=$(awk '/is responding/ {c++} END {print c+0}' "$OUTPUT_FILE")
    local failed_servers
    failed_servers=$(awk '/FAILED/ {c++} END {print c+0}' "$OUTPUT_FILE")
    echo -e "${GREEN}Summary:${NC}"
    echo -e "  Total servers discovered: ${CYAN}$total_servers${NC}"
    echo -e "  Responding servers: ${GREEN}$responding_servers${NC}"
    echo -e "  Failed servers: ${RED}$failed_servers${NC}"
    echo "" >> "$OUTPUT_FILE"
    echo "SUMMARY" >> "$OUTPUT_FILE"
    echo "=======" >> "$OUTPUT_FILE"
    echo "Total servers discovered: $total_servers" >> "$OUTPUT_FILE"
    echo "Responding servers: $responding_servers" >> "$OUTPUT_FILE"
    echo "Failed servers: $failed_servers" >> "$OUTPUT_FILE"
    echo "Completed: $(date)" >> "$OUTPUT_FILE"
    if [ -s "$SERVER_GRAPH" ]; then
        echo -e "${YELLOW}Server relationship graph saved to: $SERVER_GRAPH${NC}"
        echo -e "${BLUE}Graph preview (first 10 entries):${NC}"
        head -10 "$SERVER_GRAPH"
    fi
}

# Main function

main() {
    echo -e "${CYAN}NTP Recursive Crawler${NC}"
    echo -e "${YELLOW}=========================${NC}"
    echo "Max depth: $MAX_DEPTH"
    echo "Max servers: $MAX_SERVERS"
    echo "Timeout: ${TIMEOUT}s"
    echo ""
    check_dependencies
    initialize_files
    echo -e "${YELLOW}Starting recursive crawl...${NC}"
    crawl_ntp_servers 1 "${SEED_SERVERS[@]}"
    generate_summary
    echo -e "${GREEN}Crawl completed!${NC}"
    echo -e "${BLUE}Results saved to: $OUTPUT_FILE${NC}"
    echo -e "${BLUE}Visited servers list: $VISITED_SERVERS${NC}"
    trap "rm -f $VISITED_SERVERS $SERVER_GRAPH" EXIT
}

# Handle command line arguments

while getopts "d:s:t:h" opt; do
    case $opt in
        d) MAX_DEPTH="$OPTARG" ;;
        s) MAX_SERVERS="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -d MAX_DEPTH    Maximum recursion depth (default: 4)"
            echo "  -s MAX_SERVERS  Maximum number of servers to crawl (default: 100)"
            echo "  -t TIMEOUT      Query timeout in seconds (default: 1200)"
            echo "  -h              Show this help message"
            exit 0
            ;;
        *)
            echo "Invalid option. Use -h for help."
            exit 1
            ;;
    esac
done

# Run main function

main
