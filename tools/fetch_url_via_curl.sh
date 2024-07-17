#!/usr/bin/env bash
set -e

# @describe Extract the content from a given URL.
# @meta require-tools pandoc
# @option --url! The URL to scrape.

main() {
    # span and div tags are dropped from the HTML https://pandoc.org/MANUAL.html#raw-htmltex and sed removes any inline SVG images in image tags from the Markdown content.
    curl -fsSL "$argc_url" | \
        pandoc -f html-native_divs-native_spans -t gfm-raw_html --wrap=none | \
        sed -E 's/!\[[^]]*\]\([^)]*\)//g' \
        >> "$LLM_OUTPUT"
}

eval "$(argc --argc-eval "$0" "$@")"
