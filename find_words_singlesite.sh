#!/bin/bash

# Define words to search for
SEARCH_WORDS=("word" "word2")
EXCEL_FILE="all_matched_urls.tsv"  # TSV file for Excel
PDF_DIR="/var/www/csurec.colostate.edu/htdocs/wp-content/uploads"
BASE_URL="https://csurec.colostate.edu/wp-content/uploads"

TEMP_FILE=$(mktemp)  # Temporary file to store results before sorting

echo "Starting search. Results will be saved in $EXCEL_FILE"

# Get the correct database table prefix
TABLE_PREFIX=$(wp db prefix --skip-column-names | tr -d '[:space:]')

if [ -z "$TABLE_PREFIX" ]; then
    echo "Error: Could not determine table prefix"
    exit 1
fi

echo "Using table prefix: $TABLE_PREFIX"

# Loop through each search word
for WORD in "${SEARCH_WORDS[@]}"; do
    echo "Searching for: $WORD"

    # Count occurrences in each post/page
    QUERY="SELECT ID, (LENGTH(LOWER(post_content)) - LENGTH(REPLACE(LOWER(post_content), '$(echo "$WORD" | tr '[:upper:]' '[:lower:]')', ''))) / LENGTH('$(echo "$WORD" | tr '[:upper:]' '[:lower:]')') AS count FROM ${TABLE_PREFIX}posts WHERE post_status='publish' AND post_type IN ('post', 'page') AND LOWER(post_content) LIKE '%$(echo "$WORD" | tr '[:upper:]' '[:lower:]')%';"

    wp db query "$QUERY" --skip-column-names | while read -r ID COUNT; do
        INTEGER_COUNT=${COUNT%.*}  # Convert float to integer by removing decimal
        if [[ -z "$ID" || -z "$COUNT" || ! "$INTEGER_COUNT" =~ ^[0-9]+$ || "$INTEGER_COUNT" -eq 0 ]]; then
            continue
        fi
        PAGE_URL=$(wp post url "$ID" --skip-themes)
        echo -e "$PAGE_URL\t$INTEGER_COUNT" >> "$TEMP_FILE"
    done
done

# 🔹 PDF Search
if [ -d "$PDF_DIR" ]; then
    echo "Searching PDFs in $PDF_DIR..."

    find "$PDF_DIR" -type f -name "*.pdf" | while read -r PDF_FILE; do
        PDF_URL="${PDF_FILE/$PDF_DIR/$BASE_URL}"

        for WORD in "${SEARCH_WORDS[@]}"; do
            # Count occurrences in PDF
            PDF_COUNT=$(pdfgrep -i -c "$WORD" "$PDF_FILE" || echo 0)
            
            # If no direct match, try extracting text
            if [[ ! "$PDF_COUNT" =~ ^[0-9]+$ || "$PDF_COUNT" -eq 0 ]]; then
                TEMP_TEXT_FILE=$(mktemp)
                pdftotext "$PDF_FILE" "$TEMP_TEXT_FILE"
                PDF_COUNT=$(grep -i -o "$WORD" "$TEMP_TEXT_FILE" | wc -l)
                rm -f "$TEMP_TEXT_FILE"
            fi

            if [[ ! -z "$PDF_COUNT" && "$PDF_COUNT" =~ ^[0-9]+$ && "$PDF_COUNT" -gt 0 ]]; then
                echo -e "$PDF_URL\t$PDF_COUNT" >> "$TEMP_FILE"
            fi
        done
    done
fi

# Sort results in descending order by number of hits and save in a TSV file
sort -nr -k2 "$TEMP_FILE" > "$EXCEL_FILE"

rm -f "$TEMP_FILE"  # Cleanup

echo "Search completed. Results saved in $EXCEL_FILE (Excel-ready)."
