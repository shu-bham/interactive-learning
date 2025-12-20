#!/bin/bash

# Check if container is running
if [ "$(docker ps -q -f name=postgresql-primary)" ]; then
    echo "Connecting to PostgreSQL primary..."
    docker exec -it postgresql-primary psql -U postgres -d learning_db
else
    echo "Error: postgresql-primary container is not running."
    echo "Run 'docker-compose up -d' in the postgresql directory first."
fi
