#!/bin/bash
# Add login flow to all test files that don't already have it

cd /Users/rezivure/git/Grid-Mobile/.maestro

for file in *.yaml; do
    # Skip if already has login flow
    if grep -q "runFlow: flows/login_testuser1.yaml" "$file"; then
        echo "✓ $file already has login flow"
        continue
    fi
    
    # Skip if it's the login flow itself or other special files
    if [[ "$file" == "flows/"* ]] || [[ "$file" == "*simple*" ]] || [[ "$file" == "*fixed*" ]] || [[ "$file" == "*template*" ]]; then
        echo "↪ Skipping special file: $file"
        continue
    fi
    
    echo "📝 Adding login flow to $file..."
    
    # Create backup
    cp "$file" "$file.backup"
    
    # Find the line after the --- header
    awk '
    /^---$/ { 
        print
        print ""
        print "# Start with fresh login"
        print "- runFlow: flows/login_testuser1.yaml"
        print ""
        next 
    }
    { print }
    ' "$file.backup" > "$file"
    
    echo "✅ Added login flow to $file"
done

echo "Done! Added login flows to files."