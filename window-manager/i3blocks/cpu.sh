#!/bin/bash

# Define the path for the temporary file to store previous CPU stats
TEMP_FILE="/tmp/i3blocks_cpu_stats_sh"

# Function to get current CPU times
get_cpu_times() {
    # Read the first line of /proc/stat (overall CPU)
    # Example: cpu  2255 34 2289 2262556 6290 1 0 0 0 0
    # Fields: user nice system idle iowait irq softirq steal guest guest_nice
    read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat

    # Calculate total CPU time (sum of all fields)
    total_time=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))

    # Calculate idle CPU time (idle + iowait)
    idle_time=$((idle + iowait))

    echo "$total_time $idle_time"
}

# Read previous CPU stats from the temporary file
read_previous_stats() {
    if [[ -f "$TEMP_FILE" ]]; then
        read -r prev_total prev_idle < "$TEMP_FILE"
        echo "$prev_total $prev_idle"
    else
        echo "0 0" # Return 0s if file doesn't exist (first run)
    fi
}

# Main logic
main() {
    # Get current CPU times
    current_times=$(get_cpu_times)
    current_total=$(echo "$current_times" | awk '{print $1}')
    current_idle=$(echo "$current_times" | awk '{print $2}')

    # Read previous CPU times
    previous_times=$(read_previous_stats)
    prev_total=$(echo "$previous_times" | awk '{print $1}')
    prev_idle=$(echo "$previous_times" | awk '{print $2}')

    # Store current times for the next run
    echo "$current_total $current_idle" > "$TEMP_FILE"

    # Calculate differences
    total_diff=$((current_total - prev_total))
    idle_diff=$((current_idle - prev_idle))

    # Avoid division by zero on first run or if no activity
    if [[ "$total_diff" -eq 0 ]]; then
        cpu_percentage=0.0
    else
        # Calculate CPU usage (using bc for floating-point arithmetic)
        # (total_diff - idle_diff) is the "busy" time
        cpu_percentage=$(echo "scale=2; (($total_diff - $idle_diff) / $total_diff) * 100" | bc)
    fi

    # Ensure percentage is within 0-100 range
    if (( $(echo "$cpu_percentage < 0" | bc -l) )); then
        cpu_percentage=0.0
    elif (( $(echo "$cpu_percentage > 100" | bc -l) )); then
        cpu_percentage=100.0
    fi

    # Determine color based on usage
    color="#00FF00" # Green (low usage)
    if (( $(echo "$cpu_percentage > 80" | bc -l) )); then
        color="#FF0000" # Red (high usage)
    elif (( $(echo "$cpu_percentage > 50" | bc -l) )); then
        color="#FFFF00" # Yellow (medium usage)
    fi

    # i3blocks output format: Full text\nShort text\nColor
    full_text="CPU: $(printf "%.1f" "$cpu_percentage")%"
    echo "$full_text"
    echo "$full_text" # Short text can be the same
    echo "$color"
}

# Execute the main function
main
