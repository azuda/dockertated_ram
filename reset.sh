#!/usr/bin/bash

docker compose down
rm -rf /home/opc/mc-server/data/world
docker compose up -d
