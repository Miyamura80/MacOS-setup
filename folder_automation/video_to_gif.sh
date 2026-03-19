for f in "$@"; do
    # Skip if already a GIF
    if [[ "${f##*.}" == "gif" ]]; then
        echo "Skipping gif file: $f"
        continue
    fi

    output="/Users/eito/Documents/Folder Automation/Video to GIF/$(date +"%Y_%m_%d_%I_%M_%p_%s").gif"
    palette="/tmp/palette_$(date +"%Y_%m_%d_%I_%M_%p_%s").png"
    
    echo "Generating palette for '$f'"
    /opt/homebrew/bin/ffmpeg -y -i "$f" -vf "fps=18,scale=3840:-1:flags=lanczos,palettegen" "$palette"
    if [ $? -ne 0 ]; then
        echo "Palette generation failed for '$f'"
        continue
    fi

    echo "Converting '$f' to gif using palette"
    /opt/homebrew/bin/ffmpeg -n -i "$f" -i "$palette" -filter_complex "fps=18,scale=3840:-1:flags=lanczos[x];[x][1:v]paletteuse" "$output"
    if [ $? -eq 0 ]; then
        echo "Conversion succeeded. Deleting original."
        rm -f "$f"
    else
        echo "Conversion failed for '$f'"
    fi
    
    rm -f "$palette"
done
