#!/bin/bash

sudo apt update && sleep 5;

sudo apt install -y python-docker
sleep 3;
echo "python-docker installed"

sudo apt install -y ansible;
sleep 3;
echo "ansible installed"

echo "running playbook"
ansible-playbook -u ubuntu /tmp/playbook.yaml
