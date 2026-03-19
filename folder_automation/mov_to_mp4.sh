for f in "$@"; do
    # Process only .mov files
    if [[ "${f##*.}" != "mov" ]]; then
        echo "Skipping file: $f"
        continue
    fi

    output="/Users/eito/Documents/Folder Automation/MOV TO MP4/$(date +"%Y_%m_%d_%I_%M_%p_%s").mp4"
    echo "Converting '$f' to '$output'"
    /opt/homebrew/bin/ffmpeg -n -loglevel error -i "$f" -vcodec libx264 -crf 23 -preset ultrafast -tune film "$output"
    if [ $? -eq 0 ]; then
        echo "Conversion succeeded, deleting original."
        rm -f "$f"
    else
        echo "Conversion failed for '$f'"
    fi
done
