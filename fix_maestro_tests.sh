#!/bin/bash

# Script to fix common Maestro test issues
cd /Users/rezivure/git/Grid-Mobile

echo "Fixing Maestro test files..."

# Fix 1: Remove name and tags from header, keep only appId
for file in .maestro/*.yaml; do
    if [ -f "$file" ]; then
        # Check if file has name: or tags: fields
        if grep -q "^name:" "$file" || grep -q "^tags:" "$file"; then
            echo "Fixing header in $file"
            # Create temp file with fixed header
            temp_file=$(mktemp)
            
            # Extract appId line
            app_id_line=$(grep "^appId:" "$file")
            
            # Write fixed header
            echo "$app_id_line" > "$temp_file"
            echo "---" >> "$temp_file"
            
            # Skip original header and copy rest of file
            sed -n '/^---$/,$p' "$file" | tail -n +2 >> "$temp_file"
            
            # Replace original file
            mv "$temp_file" "$file"
        fi
    fi
done

echo "Fixed headers."

# Fix 2: Remove timeout parameters from waitForAnimationToEnd
echo "Fixing waitForAnimationToEnd syntax..."

for file in .maestro/*.yaml; do
    if [ -f "$file" ]; then
        if grep -q "waitForAnimationToEnd:" "$file"; then
            echo "Fixing waitForAnimationToEnd in $file"
            # Replace waitForAnimationToEnd with parameters with simple version
            sed -i '' 's/- waitForAnimationToEnd:.*$/- waitForAnimationToEnd/g' "$file"
            # Also remove any following timeout lines
            sed -i '' '/^[[:space:]]*timeout:[[:space:]]*[0-9]*$/d' "$file"
        fi
    fi
done

echo "Fixed waitForAnimationToEnd syntax."

echo "Done! Fixed common issues in Maestro test files."