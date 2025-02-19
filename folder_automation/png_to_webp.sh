for f in "$@"; do
    echo "Received file: $f"
    ext="${f##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ "$ext" != "jpg" && "$ext" != "jpeg" && "$ext" != "png" ]]; then
        echo "Skipping unsupported file: $f"
        continue
    fi
    output="/Users/eito/Documents/Folder Automation/Image to WEBP/$(date +"%Y_%m_%d_%I_%M_%p_%s").webp"
    echo "Converting '$f' to '$output'"
    /opt/homebrew/bin/cwebp -q 70 "$f" -o "$output"
    if [ $? -eq 0 ]; then
        echo "Conversion succeeded. Deleting original file."
        rm -f "$f"
    else
        echo "Conversion failed for '$f'"
    fi
done
