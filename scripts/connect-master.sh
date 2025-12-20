#!/bin/bash
# Quick connect script for MySQL master

docker exec -it mysql-master mysql -uroot -prootpass learning_db
