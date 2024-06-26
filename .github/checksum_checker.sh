#!/bin/bash
set -euo pipefail
# This scripts needs yq and huggingface_hub to be installed
# to install hugingface_hub run pip install huggingface_hub

# Path to the input YAML file
input_yaml=$1

# Function to download file and check checksum using Python
function check_and_update_checksum() {
    model_name="$1"
    file_name="$2"
    uri="$3"
    old_checksum="$4"
    idx="$5"

    # Download the file and calculate new checksum using Python
    new_checksum=$(python3 -c "
import hashlib
from huggingface_hub import hf_hub_download
import requests
import sys
import os

uri = '$uri'
file_name = '$file_name'

# Function to parse the URI and determine download method
# Function to parse the URI and determine download method
def parse_uri(uri):
    if uri.startswith('huggingface://'):
        # Remove the protocol and extract repo id and filename
        repo_id = uri.split('://')[1]
        return 'huggingface', repo_id.rsplit('/', 1)[0]
    elif 'huggingface.co' in uri:
        # For full URLs to Hugging Face, extract repo and filename before '/resolve/'
        parts = uri.split('/resolve/')
        if len(parts) > 1:
            repo_path = parts[0].split('https://huggingface.co/')[-1]
            repo_id, file_part = repo_path.rsplit('/', 1)
            return 'huggingface', (repo_id, file_part)
    return 'direct', uri


def calculate_sha256(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for byte_block in iter(lambda: f.read(4096), b''):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

download_type, repo_id_or_url = parse_uri(uri)

# Decide download method based on URI type
if download_type == 'huggingface':
    file_path = hf_hub_download(repo_id=repo_id_or_url, filename=file_name, use_auth_token=False)
else:
    # Direct download for non-Hugging Face URLs
    response = requests.get(repo_id_or_url)
    if response.status_code == 200:
        with open(file_name, 'wb') as f:
            f.write(response.content)
        file_path = file_name
    else:
        print(f'Error downloading file: {response.status_code}', file=sys.stderr)
        sys.exit(1)

print(calculate_sha256(file_path))
# Clean up the downloaded file
os.remove(file_path)
")

    # Compare and update the YAML file if checksums do not match
    if [[ "$old_checksum" != "$new_checksum" ]]; then
        echo "Checksum mismatch for $file_name. Updating..."
        yq eval -i "del(.[$idx].files[] | select(.filename == \"$file_name\").sha256)" "$input_yaml"
        yq eval -i "(.[$idx].files[] | select(.filename == \"$file_name\")).sha256 = \"$new_checksum\"" "$input_yaml"
    else
        echo "Checksum match for $file_name. No update needed."
    fi
}

# Read the YAML and process each file
len=$(yq eval '. | length' "$input_yaml")
for ((i=0; i<$len; i++))
do
    name=$(yq eval ".[$i].name" "$input_yaml")
    files_len=$(yq eval ".[$i].files | length" "$input_yaml")
    for ((j=0; j<$files_len; j++))
    do
        filename=$(yq eval ".[$i].files[$j].filename" "$input_yaml")
        uri=$(yq eval ".[$i].files[$j].uri" "$input_yaml")
        checksum=$(yq eval ".[$i].files[$j].sha256" "$input_yaml")
        echo "Checking model $name, file $filename. URI = $uri, Checksum = $checksum"
        check_and_update_checksum "$name" "$filename" "$uri" "$checksum" "$i"
    done
done
