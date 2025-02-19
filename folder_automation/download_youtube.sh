# Process each .webloc file
for f in "$@"; do
    echo "Processing file: $f"
    
    # Extract URL between <string> tags
    url=$(grep -o '<string>.*</string>' "$f" | sed 's/<string>\(.*\)<\/string>/\1/')
    echo "Extracted URL: $url"
    
    # Check if URL was found
    if [ -n "$url" ]; then
        echo "Attempting to download from: $url"
        
        # Download video using yt-dlp to the Downloads folder
        /opt/homebrew/bin/yt-dlp -P "~/Downloads" "$url"
        
        # Check if the download was successful
        if [ $? -eq 0 ]; then
            echo "Download successful, removing webloc file"
            rm -f "$f"
        else
            echo "Download failed"
        fi
    else
        echo "Error: No URL found in '$f'"
    fi

done
