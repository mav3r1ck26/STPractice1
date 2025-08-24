#!/usr/bin/env bash
set -e

# @describe Perform a web search using Exa API to get a list of links to fetch.
# Use this when you need current information or feel a search could provide a better answer.
# Construct the query out of keywords, not human sentences, sorted by relevance - just like a good Google query.
# This returns text, then URL for every result found. Judging by the title of the page, fetch relevant info.

# @option --query! The query to search for.

# @env EXA_API_KEY! The api key
# @env LLM_OUTPUT=/dev/stdout The output path The output path

main() {
curl -fsS -X POST 'https://api.exa.ai/search' \
  -H "x-api-key: $EXA_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": "'"$argc_query"'",
    "type": "keyword",
    "numResults": 20
      }' | \
    jq -r '.results[] | (.title, .url, "")' >> "$LLM_OUTPUT"
}

eval "$(argc --argc-eval "$0" "$@")"
