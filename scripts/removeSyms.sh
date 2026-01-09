for name in catalog confs scripts; do
    if [ -L "$name" ]; then
        rm "$name"
        echo "Removed old symlink: $name"
    else
        echo "Skipping $name (not a symlink). If this should be a link, move or rename it manually."
    fi
done
