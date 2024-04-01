#!/bin/bash

ORIGIN_REMOTE_NAME="origin"  # Define origin remote name as a variable at the top

# Function to search for git repositories and pull
git_pull_recursive() {
    local dir="$1"
    local depth="$2"
    
    echo ""  # Added newline for spacing

    # If the depth is 0, return
    if ((depth == 0)); then
        echo "Max depth reached for $dir. Not searching further."
        return
    fi

    echo ""  # Added newline for spacing

    # Check if the directory is a git repository
    if [ -d "$dir/.git" ]; then

        # Fetch all branches and prune stale references
        echo "Fetching all branches from $ORIGIN_REMOTE_NAME and pruning stale references in $dir..."
        (cd "$dir" && git fetch $ORIGIN_REMOTE_NAME --prune) 2>&1

        echo ""  # Added newline for spacing

        # For each branch
	for branch in $(cd "$dir" && git branch -r | grep "$ORIGIN_REMOTE_NAME/" | grep -v -- "->" | sed 's/^ *//;s/* //;s/origin\///'); do
            echo "Working with branch $branch in $dir..."

	    if (cd "$dir" && git symbolic-ref -q HEAD); then
    		echo "Branch is valid. Continuing with operations."
	    else
    		echo "Detached HEAD or invalid branch detected. Skipping operations for this branch."
    		continue
	    fi

            echo ""  # Added newline for spacing

            # Check out the branch
            (cd "$dir" && git checkout $branch) 2>&1
            
            # Pull from origin
            echo "Pulling updates from $ORIGIN_REMOTE_NAME on branch $branch..."
            (cd "$dir" && git pull $ORIGIN_REMOTE_NAME $branch) 2>&1
            if [ $? -ne 0 ]; then
                echo "Error: Failed to pull updates for $dir from $ORIGIN_REMOTE_NAME on branch $branch"
                # Do not return; continue processing other branches
            else
                echo "Successfully pulled updates for $dir from $ORIGIN_REMOTE_NAME on branch $branch"
            fi

            echo ""  # Added newline for spacing

            # Push to other remotes
            for remote in $(cd "$dir" && git remote | grep -v "^$ORIGIN_REMOTE_NAME$"); do
                echo "Pushing updates to $remote in $dir on branch $branch..."
                (cd "$dir" && git push $remote --all) 2>&1
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to push updates for $dir to $remote on branch $branch"
                    # Do not return; continue processing other remotes
                else
                    echo "Successfully pushed updates for $dir to $remote on branch $branch"
                fi

                (cd "$dir" && git push $remote --tags) 2>&1
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to push updates for $dir to $remote for all tags"
                    # Do not return; continue processing other remotes
                else
                    echo "Successfully pushed updates for $dir to $remote on all tags"
                fi

                echo ""  # Added newline for spacing
            done
        done
    else
        echo "$dir is not a git repository. Searching its subdirectories..."
        
        echo ""  # Added newline for spacing

        # If not, look for subdirectories and search inside them
        local subdir
        for subdir in "$dir"/*/; do
            if [ -d "$subdir" ]; then
                git_pull_recursive "$subdir" $((depth - 1))
            fi
        done
    fi
}

# Define the list of root directories
root_directories=(
"/Users/taher/code/plug-vpn"
)

# Loop over the list of root directories and execute git pull recursively
for rootdir in "${root_directories[@]}"; do
    echo ""  # Added newline for spacing
    if [ -d "$rootdir" ]; then
        echo "Searching for git repositories in $rootdir..."
        git_pull_recursive "$rootdir" 4  # 1 for root + 3 levels deep
    else
        echo "Error: $rootdir is not a directory or does not exist"
        # Continue with the next root directory even if one fails
    fi
done

