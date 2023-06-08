config_file="$PWD/merge_config.json"
sleep_time=1

while getopts f:s: flag; do
    case "${flag}" in
    f) config_file=${OPTARG} ;;
    s) sleep_time=${OPTARG} ;;
    esac
done

merge_js_files() {
    local source_directory="$1"
    local output_file="$2"

    # Create a temporary file for the output
    temp_file=$(mktemp)

    # Copy the contents of JavaScript files to the temporary file
    find "$source_directory" -type f -name '*.js' -print0 | while IFS= read -r -d '' file; do
        echo "// File: $file" >>"$temp_file"
        printf '\n' >>"$temp_file"
        cat "$file" >>"$temp_file"
        printf '\n\n' >>"$temp_file"
    done

    # Replace the output file with the temporary file
    mv "$temp_file" "$output_file"
}

monitor_source_directories() {
    local source_directory="$1"
    local output_file="$2"

    echo "Monitoring '$source_directory' directory to write in '$output_file' file"

    # Create a hash of the source directory
    local directory_hash=$(find "$source_directory" -type f -name '*.js' -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}')

    merge_js_files "$source_directory" "$output_file"

    monitor=true
    trap 'monitor=false' 2
    while $monitor; do
        # Sleep for a short interval in seconds before checking again
        sleep $sleep_time

        # Check if the source directory has been modified
        local new_directory_hash=$(find "$source_directory" -type f -name '*.js' -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}')

        if [[ "$new_directory_hash" != "$directory_hash" ]]; then
            echo "JavaScript files in $source_directory have been modified."

            # Update the directory hash
            directory_hash="$new_directory_hash"

            # Clean the output file
            >"$output_file"

            # Copy the updated contents of JavaScript files to the output file
            merge_js_files "$source_directory" "$output_file"
        fi
    done

    echo "Stopped monitoring $source_directory"
}

launch_source_directories_monitors() {
    local -n local_monitorings_pids=$1

    local nbConfigs=$(($(jq -r '.Configurations | length' $config_file) - 1))
    for configId in $(seq 0 $nbConfigs); do
        local source_directory=$(jq -r ".Configurations[$configId].SourceDirectory" $config_file)
        local output_file=$(jq -r ".Configurations[$configId].OutputFilePath" $config_file)

        if [[ -d $source_directory ]]; then
            if [[ -f $output_file ]]; then
                monitor_source_directories "$source_directory" "$output_file" &

                # Register PID of previous command
                local_monitorings_pids+=($!)
            else
                echo "Invalid output file '$output_file'"
            fi
        else
            echo "Invalid source directory '$source_directory'"
        fi
    done
}

kill_processes() {
    local -n pids=$1

    for pid in "${pids[@]}"; do
        kill -INT "$pid"
        wait "$pid"
    done

    echo "All monitorings have been interrupted"
    pids=()
}

# Function to monitor config file for modifications
monitor_config_file() {
    # Create a hash of the config file
    local config_file_hash=$(md5sum "$config_file" | awk '{print $1}')

    local monitorings_pids=()
    launch_source_directories_monitors monitorings_pids

    while true; do
        # Sleep for a short interval in seconds before checking again
        sleep $sleep_time

        # Check if the config file has been modified
        local new_config_file_hash=$(md5sum "$config_file" | awk '{print $1}')

        if [[ "$new_config_file_hash" != "$config_file_hash" ]]; then
            echo "Config file has been modified."

            # Update the directory hash
            config_file_hash="$new_config_file_hash"

            kill_processes monitorings_pids
            launch_source_directories_monitors monitorings_pids
        fi
    done
}

if [[ -f "$config_file" ]]; then
    monitor_config_file
else
    echo "Unable to find config file $config_file"
fi

# Wait for any modification events to occur
wait
