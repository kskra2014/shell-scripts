#!/bin/bash

GPG_RECIPIENT_EMAIL="mhosseintaher@gmail.com"

GITLAB_CONTAINER_NAME="tahersoft-gitlab-tahersoft-gitlab-1"
TARGET_PATH="/home/taher/gitlab-backups"
ARCHIVE_NAME="gitlab_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
SSH_TARGETS=("taher@51.15.159.37:/home/taher/gitlab-backups")

# Function to exit on error with a custom message
exit_on_error() {
    if [[ $? -ne 0 ]]; then
        echo "Error: $1"
        exit 1
    fi
}

# Ensure the backup directory exists on the host
echo "Ensuring backup directory exists on the host..."
mkdir -p $TARGET_PATH
exit_on_error "Failed to create backup directory on the host."

echo "Changing directory to $TARGET_PATH..."
cd $TARGET_PATH
exit_on_error "Failed to change directory to $TARGET_PATH."

echo "Cleaning up old backup files inside the container..."
docker exec $GITLAB_CONTAINER_NAME find /var/opt/gitlab/backups/ -name "*.tar" -delete
exit_on_error "Failed to clean up old backup tar files from the container."

echo "Cleaning up old backup files in $TARGET_PATH..."
find $TARGET_PATH -name "*.tar" -delete
exit_on_error "Failed to remove old tar files from $TARGET_PATH."

# Set permissions in the container for the GitLab backup directory
echo "Setting permissions inside the container..."
docker exec $GITLAB_CONTAINER_NAME chown git:git /var/opt/gitlab/backups
exit_on_error "Failed to set permissions inside the container."

# Create the backup inside the container
echo "Creating GitLab backup inside the container..."
docker exec $GITLAB_CONTAINER_NAME gitlab-backup create
exit_on_error "Failed to create GitLab backup inside the container."

# List all tar files in the backups directory inside the container
echo "Listing all tar files in the backups directory inside the container..."
TAR_FILES=$(docker exec $GITLAB_CONTAINER_NAME sh -c "ls /var/opt/gitlab/backups/*.tar")

# Exit if the command fails
exit_on_error "Failed to list tar files inside the container."

# Loop through each tar file and copy it to the host
echo "Copying all tar files from the container to the host..."
for TAR_FILE in $TAR_FILES; do
    docker cp $GITLAB_CONTAINER_NAME:$TAR_FILE .
    exit_on_error "Failed to copy $TAR_FILE from the container to the host."
done

echo "Copied all tar files from the container to the host."
docker cp $GITLAB_CONTAINER_NAME:/etc/gitlab/gitlab.rb .
exit_on_error "Failed to copy gitlab.rb from the container to the host."

echo "Copied gitlab.rb from the container to the host."
docker cp $GITLAB_CONTAINER_NAME:/etc/gitlab/gitlab-secrets.json .
exit_on_error "Failed to copy gitlab-secrets.json from the container to the host."

# Check if required files exist before creating the tarball
echo "Checking if required files exist before creating the tarball..."
if [[ ! -f gitlab.rb || ! -f gitlab-secrets.json || ! $(ls *.tar 2> /dev/null) ]]; then
    exit_on_error "One or more required files are missing. Cannot create the tarball."
fi

# Archive the backup tarball and the configuration files
echo "Archiving backup and configuration files..."
tar -czf $ARCHIVE_NAME *.tar gitlab.rb gitlab-secrets.json
exit_on_error "Failed to archive backup and configuration files."

# Encrypt the backup archive with GPG
echo "Encrypting the backup archive with GPG..."
gpg --encrypt --recipient $GPG_RECIPIENT_EMAIL --output $ARCHIVE_NAME.gpg $ARCHIVE_NAME
exit_on_error "Failed to encrypt the backup archive."

# Remove non-encrypted backup archive
echo "Removing non-encrypted backup archive..."
rm $ARCHIVE_NAME
exit_on_error "Failed to remove non-encrypted backup archive."

# Rsync the encrypted archive to each SSH target server
echo "Rsyncing the encrypted archive to each SSH target server..."
for SSH_TARGET in "${SSH_TARGETS[@]}"; do
    rsync -avzh --progress $ARCHIVE_NAME.gpg $SSH_TARGET
    exit_on_error "Failed to rsync the archive to $SSH_TARGET."
done


# Clean up individual backup and configuration files
echo "Cleaning up individual backup and configuration files..."
rm *.tar gitlab.rb gitlab-secrets.json
exit_on_error "Failed to clean up individual backup and configuration files."

# Remove backup tar files from the container
docker exec $GITLAB_CONTAINER_NAME find /var/opt/gitlab/backups/ -name "*.tar" -delete
exit_on_error "Failed to clean up backup tar files from the container."

# Remove the second-to-last backup archive
echo "Removing the second-to-last backup archive from $TARGET_PATH..."
find $TARGET_PATH -name "gitlab_backup_*.tar.gz.gpg" ! -name "$ARCHIVE_NAME.gpg" -delete
exit_on_error "Failed to remove previous backup archive."

echo "Removing the second-to-last backup archive from remote servers..."
for SSH_TARGET in "${SSH_TARGETS[@]}"; do
    # Split SSH target into user-host and path components
    USER_HOST="${SSH_TARGET%%:*}"
    REMOTE_PATH="${SSH_TARGET##*:}"
    
    # Use ssh to execute the find and delete command on the remote server
    ssh $USER_HOST "find $REMOTE_PATH -name 'gitlab_backup_*.tar.gz.gpg' ! -name '$ARCHIVE_NAME.gpg' -delete"
    
    exit_on_error "Failed to remove the second-to-last backup archive from $USER_HOST."
done

echo "Backup process completed!"
