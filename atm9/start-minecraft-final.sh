#!/bin/bash

# Your existing Minecraft server startup commands
echo "Starting Minecraft server..."
exec java -Xmx$MEMORY -Xms$MEMORY -jar /minecraft/server.jar
