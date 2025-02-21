#!/bin/bash

# Define words to search for
SEARCH_WORDS=("word" "word2")
EXCEL_FILE="all_matched_urls.tsv"  # Output file for Excel
TEMP_FILE=$(mktemp)  # Temporary file for storing results

echo "Starting search across multisite network. Results will be saved in $EXCEL_FILE"

# Loop through each active, non-deleted, non-archived site URL in the network
wp site list --field=url --status=active --archived=0 --deleted=0 | while read -r SITE_URL; do
    echo "Processing site: $SITE_URL"

    # Extract domain name from the site URL (e.g., health.colostate.edu)
    DOMAIN_NAME=$(echo "$SITE_URL" | awk -F[/:] '{print $4}')

    if [ -z "$DOMAIN_NAME" ]; then
        echo "Error: Could not extract domain from $SITE_URL"
        continue
    fi

    echo "Extracted domain: $DOMAIN_NAME"

    # Query the database for the site ID using the extracted domain
    SITE_ID=$(wp db query "SELECT blog_id FROM wp_blogs WHERE domain = '$DOMAIN_NAME'" --skip-column-names)

    if [ -z "$SITE_ID" ]; then
        echo "Error: Could not determine site ID for $SITE_URL"
        continue
    fi

    # Extract domain name from the site URL (e.g., health.colostate.edu)
    DOMAIN_NAME=$(echo "$SITE_URL" | awk -F[/:] '{print $4}')

    if [ -z "$DOMAIN_NAME" ]; then
        echo "Error: Could not extract domain from $SITE_URL"
        continue
    fi

    # Determine the correct table prefix for the current site
    TABLE_PREFIX=$(wp --url="$SITE_URL" db prefix --skip-column-names | tr -d '[:space:]')

    if [ -z "$TABLE_PREFIX" ]; then
        echo "Error: Could not determine table prefix for $SITE_URL"
        continue
    fi

    echo "Using table prefix: $TABLE_PREFIX"

    # Loop through each search word for posts/pages
    for WORD in "${SEARCH_WORDS[@]}"; do
        echo "Searching for: $WORD in site: $SITE_URL"

        QUERY="SELECT ID, (LENGTH(LOWER(post_content)) - LENGTH(REPLACE(LOWER(post_content), '$(echo "$WORD" | tr '[:upper:]' '[:lower:]')', ''))) / LENGTH('$(echo "$WORD" | tr '[:upper:]' '[:lower:]')') AS count FROM ${TABLE_PREFIX}posts WHERE post_status='publish' AND post_type IN ('post', 'page') AND LOWER(post_content) LIKE '%$(echo "$WORD" | tr '[:upper:]' '[:lower:]')%';"

        wp db query "$QUERY" --url="$SITE_URL" --skip-column-names | while read -r ID COUNT; do
            INTEGER_COUNT=${COUNT%.*}  # Convert float to integer by removing decimal
            if [[ -z "$ID" || -z "$COUNT" || ! "$INTEGER_COUNT" =~ ^[0-9]+$ || "$INTEGER_COUNT" -eq 0 ]]; then
                continue
            fi
            PAGE_URL=$(wp post url "$ID" --url="$SITE_URL")
            echo -e "$PAGE_URL\t$INTEGER_COUNT" >> "$TEMP_FILE"
        done
    done

    # 🔹 Dynamically determine the correct PDF directory for the site
    PDF_DIR="/var/www/health.colostate.edu/htdocs/wp-content/uploads/sites/$SITE_ID"
    
    # 🔹 Dynamically adjust BASE_URL to match the site's domain
    BASE_URL="${SITE_URL%/}/wp-content/uploads/sites/$SITE_ID"

    #echo "BASE_URL: $BASE_URL"

    if [ -d "$PDF_DIR" ]; then
        echo "Searching PDFs in $PDF_DIR for site: $SITE_URL"

        find "$PDF_DIR" -type f -name "*.pdf" | while read -r PDF_FILE; do
            PDF_URL="$BASE_URL/${PDF_FILE#$PDF_DIR/}"
            #echo "PDF_URL: $PDF_URL"

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
    else
        echo "⚠ No PDF directory found for site: $SITE_URL (Expected: $PDF_DIR)"
    fi

done

# Sort results in descending order by number of hits and save in a TSV file
sort -nr -k2 "$TEMP_FILE" > "$EXCEL_FILE"

rm -f "$TEMP_FILE"  # Cleanup

echo "Multisite search completed. Results saved in $EXCEL_FILE (Excel-ready)."
