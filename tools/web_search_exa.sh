#!/usr/bin/env bash
set -e

# @describe Perform a web search using Exa API to get up-to-date information or additional context.
# Use this when you need current information or feel a search could provide a better answer.
# Construct the query out of keywords, not human sentences, sorted by relevance - just like a good Google query.
# This returns text, then URL. Print that URL so that it's transparent where you got the info from.

# @option --query! The query to search for.

# @env EXA_API_KEY! The api key
# @env LLM_OUTPUT=/dev/stdout The output path The output path

main() {
curl -X POST 'https://api.exa.ai/search' \
  -H "x-api-key: $EXA_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": "'"$argc_query"'",
    "text": true,
    "type": "keyword",
    "numResults": 1
      }' | \
    jq -r '.results[0] | (.text, .url)' >> "$LLM_OUTPUT"
}

eval "$(argc --argc-eval "$0" "$@")"
