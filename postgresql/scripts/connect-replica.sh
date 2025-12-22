#!/bin/bash

# Check if container is running
if [ "$(docker ps -q -f name=postgresql-replica)" ]; then
    echo "Connecting to PostgreSQL replica..."
    docker exec -it postgresql-replica psql -U postgres -d learning_db
else
    echo "Error: postgresql-replica container is not running."
    echo "Ensure you have followed the setup steps in Increment 10."
fi
