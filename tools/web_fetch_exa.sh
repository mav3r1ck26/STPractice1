#!/usr/bin/env bash
set -e

# @describe Fetch contents of a URI using Exa API.
# Use this when you need to get contents of a link, where you think relevant info is to be found.
# If you have several sources for a subject to fetch, prioritize personal blogs, PDF files, official documentation, science articles.

# @option --url! The query to search for.

# @env EXA_API_KEY! The api key
# @env LLM_OUTPUT=/dev/stdout The output path The output path

main() {
curl -fsS -X POST 'https://api.exa.ai/contents' \
  -H "x-api-key: $EXA_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "urls": ["'"$argc_url"'"],
    "text": true
      }' | \
    jq -r '.results[0].text' >> "$LLM_OUTPUT"
}

eval "$(argc --argc-eval "$0" "$@")"
