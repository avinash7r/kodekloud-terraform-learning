if [ -f "ssh_key" ]; then
    echo "SSH key already exists. Skipping generation."
else
    echo "Generating SSH key..."
    ssh-keygen -t rsa -f ssh_key 
    chmod 400 ssh_key

terraform init

