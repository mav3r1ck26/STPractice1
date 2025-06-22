#!/usr/bin/env bash
set -e

# @describe Perform a web search using SearXNG to get up-to-date information or additional context.
# Use this when you need current information or feel a search could provide a better answer.
# @env SEARXNG_URL The Sear  XNG instance URL
# @env LLM_OUTPUT=/dev/stdout The output path
# @env MAX_SEARXNG_RESULTS=16 The maximum number of results to process
# @env SEARXNG_RESULT_CHUNK_SIZE=1000 The approximate token size for each chunk (default 1000 tokens)

# @option --query! The query to search for.
# @option --searxng Optional searxng URL overriding the env var

validate_environment() {
    if [ -z "${argc_searxng}" ]; then
        if [ -z "$SEARXNG_URL" ]; then
          echo "SEARXNG_URL environment variable is not set and --searxng parameter was not passed, bailing!" >&2
          exit 1
        fi
    else
        SEARXNG_URL="${argc_searxng}"
    fi
    if [ -z "$LLM_OUTPUT" ]; then
        LLM_OUTPUT=/dev/stdout
    fi
    if [ -z "$MAX_SEARXNG_RESULTS" ]; then
        MAX_SEARXNG_RESULTS=16
    fi
}

# Function to estimate token size (approximation; use model-specific tools for accuracy)
estimate_token_size() {
    local text="$1"
    # Simple approximation: divide by average token size (about 0.75 bytes per token for English)
    #local byte_size=$(echo -n "$text" | wc -c)
    #echo "$((byte_size / 75))"  # Adjust divisor for better accuracy if needed
    local word_size=$(echo -n "$text" | wc -w)
    echo "$( word_size )"
}

# Process and chunk results respecting JSON boundaries
process_results() {
    local results="$1"
    local chunk_token_size=${SEARXNG_RESULT_CHUNK_SIZE:-2048}

    # If results are large, split into chunks based on token size
    if [ $(echo "$results" | jq '.results | length') -gt 0 ]; then
        echo "Processing $SEARXNG_RESULT_CHUNK_SIZE tokens per chunk" >&2
        # Split the JSON array into chunks using jq to avoid breaking objects
        echo "$results" | jq -c '.results | .[0:]' | while read -r chunk; do
            local chunk_size=$(estimate_token_size "$chunk")
            if [ $chunk_size -le $chunk_token_size ]; then
                echo "$chunk" >> "$LLM_OUTPUT"
            else
                # Split further if needed (recursive or iterative approach)
                echo "$chunk" | jq -c '.[]' | split_into_chunks "$chunk_token_size"
            fi
        done
    else
        echo "$results" >> "$LLM_OUTPUT"
    fi
}

split_into_chunks() {
    local chunk_token_size=$1
    local current_chunk=""
    local current_tokens=0

    while IFS= read -r line; do
        # Estimate tokens for this line
        local line_tokens=$(echo -n "$line" | estimate_token_size)
        if [ $(($current_tokens + $line_tokens)) -gt $chunk_token_size ]; then
            if [ -n "$current_chunk" ]; then
                echo "$current_chunk" >> "$LLM_OUTPUT"
                current_chunk=""
                current_tokens=0
            fi
        fi
        current_chunk="$current_chunk$line"
        current_tokens=$((current_tokens + line_tokens))
    done

    if [ -n "$current_chunk" ]; then
        echo "$current_chunk" >> "$LLM_OUTPUT"
    fi
}

main() {
    validate_environment

    # Perform the search and capture the output
    search_output=$(curl -sLX GET --data-urlencode q="$argc_query" -d format=json -d number_of_results=$MAX_SEARXNG_RESULTS "$SEARXNG_URL/search" || { echo "Failed to connect to SearXNG" >&2; exit 1; })
    # Validate and extract the results
    if ! jq -e '.results' <<< "$search_output" > /dev/null 2>&1; then
        echo "Invalid JSON response from SearXNG" >&2
        exit 1
    fi

    # Extract the results
    results=$(echo "$search_output" | jq -r '.results')

    # If MAX_SEARXNG_RESULTS is set, limit the number of results
    if [ -n "$MAX_SEARXNG_RESULTS" ]; then
        results=$(echo "$results" | jq --argjson max_results "$MAX_SEARXNG_RESULTS" 'if length > $max_results then .[:$max_results] else . end')
    fi

    # Process the results with chunking support
    process_results "$results"
}

eval "$(argc --argc-eval "$0" "$@")"

